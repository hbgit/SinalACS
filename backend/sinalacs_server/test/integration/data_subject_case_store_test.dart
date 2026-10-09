import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/patients/push_token_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_otp_challenge_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_push_token_store.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Atendimento de pedidos do titular (#42) contra Postgres real: escopo por UBS,
/// ordem por prazo, decifração só no detalhe, anonimização transacional, corrida
/// entre dois analistas e rollback quando a auditoria falha. Dados sintéticos;
/// ids próprios (sufixo `42xx`) para não colidir com outros arquivos.
const _ubsA = '00000000-0000-4000-8000-000000004201';
const _ubsB = '00000000-0000-4000-8000-000000004202';
const _maA = '00000000-0000-4000-8000-000000004203';
const _maB = '00000000-0000-4000-8000-000000004204';
const _pacA = '00000000-0000-4000-8000-000000004211';
const _pacB = '00000000-0000-4000-8000-000000004212';
const _semArea = '00000000-0000-4000-8000-000000004213';
const _acsId = '00000000-0000-4000-8000-000000004214';
const _adminId = '00000000-0000-4000-8000-000000004215';
const _ubsCorrida = '00000000-0000-4000-8000-0000000043f1';
const _maCorrida = '00000000-0000-4000-8000-0000000043f2';
const _pedA1 = '00000000-0000-4000-8000-000000004221';
const _pedA2 = '00000000-0000-4000-8000-000000004222';
const _pedA3 = '00000000-0000-4000-8000-000000004223';
const _pedB1 = '00000000-0000-4000-8000-000000004224';
const _pedSemArea = '00000000-0000-4000-8000-000000004225';

const _nomeA = 'Joana Sintética Pereira';
const _detalheA2 = 'Corrigir telefone sintético para 0000-0000';
const _resolucao = 'Pedido atendido conforme LGPD (texto sintético)';

/// CPF sintético e válido, usado só aqui (nunca um CPF real).
const _cpfSintetico = '52998224725';

final _t = DateTime.utc(2026, 10, 8, 12);

const _segredoConsentimento = 'segredo-consentimento-sintetico';

final _hasher = HmacCpfHasher(pepper: AppConfig.developmentCpfHashPepper);

/// Grava o evento numa lista em vez de `audit_logs`: usado onde a linha real
/// da cadeia não pode ser commitada (grupo sem rollback) ou onde a falha é
/// injetada de propósito.
class _AuditoriaGravada {
  final eventos = <AuditEvent>[];
  bool falhar = false;

  Future<void> call(Session s, Transaction t, AuditEvent e) async {
    if (falhar) throw StateError('falha injetada na auditoria (só em teste)');
    eventos.add(e);
  }
}

/// Trilha sem efeito para o serviço de OTP (a auditoria dele não é o que se mede).
class _SemAuditoria extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

Future<void> _usuario(
  Session s,
  String id,
  String nome,
  UserRole role, {
  String? ma,
  String? cpfHash,
}) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: cpfHash ?? 'case-store-$id',
        name: nome,
        birthDate: DateTime.utc(1985, 3, 4),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

Future<void> _pedido(
  Session s,
  String id,
  String userId, {
  required DataSubjectRequestType tipo,
  required DateTime dueAt,
  DataSubjectRequestStatus status = DataSubjectRequestStatus.open,
  String? detalhe,
}) async {
  final cifrado = await testHealthDataCipher().encryptJson(detalhe);
  await DataSubjectRequest.db.insertRow(
    s,
    DataSubjectRequest(
      id: UuidValue.fromString(id),
      userId: UuidValue.fromString(userId),
      requestType: tipo,
      detailsEncrypted: cifrado.ciphertextBase64,
      detailsKeyVersion: cifrado.keyVersion,
      status: status,
      createdAt: dueAt.subtract(const Duration(days: 15)),
      dueAt: dueAt,
    ),
  );
}

Future<void> _territorio(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A 42'), (_ubsB, 'UBS B 42')]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(id),
        name: nome,
        address: 'Endereço sintético',
        city: 'São Paulo',
        state: 'SP',
      ),
    );
  }
  for (final (id, ubs) in [(_maA, _ubsA), (_maB, _ubsB)]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: 'Microárea $id',
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
}

/// Paciente A (UBS A) com prontuário completo, paciente B (UBS B), um titular
/// sem microárea, um ACS e um administrador. Pedidos:
/// - A1: exclusão de A, vence em _t-1d (vencido);
/// - A2: correção de A, com details, vence em _t+5d;
/// - A3: exclusão de A, em análise, vence em _t+10d;
/// - B1: correção de B, vence em _t+2d;
/// - SemArea: correção do titular sem microárea, vence em _t+3d.
Future<void> _seed(Session s) async {
  await _territorio(s);
  await _usuario(s, _acsId, 'ACS Sintético 42', UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-42-1',
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _usuario(s, _adminId, 'Admin Sintético 42', UserRole.admin);
  await _usuario(
    s,
    _pacA,
    _nomeA,
    UserRole.patient,
    ma: _maA,
    cpfHash: _hasher.hash(Cpf.tryParse(_cpfSintetico)!),
  );
  final pacienteA = await encryptedPatient(
    id: _pacA,
    emergencyContact: 'contato sintético',
    isChronic: true,
    chronicConditions: ['condição sintética'],
  );
  await Patient.db.insertRow(s, pacienteA.copyWith(lastLocationHash: 'loc-sintetica'));
  await _usuario(s, _pacB, 'Paciente B Sintético', UserRole.patient, ma: _maB);
  await Patient.db.insertRow(
    s,
    await encryptedPatient(id: _pacB, emergencyContact: 'x', isChronic: false),
  );
  await _usuario(s, _semArea, 'Sem Área Sintético', UserRole.patient);

  await _pedido(s, _pedA1, _pacA,
      tipo: DataSubjectRequestType.deletion, dueAt: _t.subtract(const Duration(days: 1)));
  await _pedido(s, _pedA2, _pacA,
      tipo: DataSubjectRequestType.correction,
      dueAt: _t.add(const Duration(days: 5)),
      detalhe: _detalheA2);
  await _pedido(s, _pedA3, _pacA,
      tipo: DataSubjectRequestType.deletion,
      dueAt: _t.add(const Duration(days: 10)),
      status: DataSubjectRequestStatus.inReview);
  await _pedido(s, _pedB1, _pacB,
      tipo: DataSubjectRequestType.correction,
      dueAt: _t.add(const Duration(days: 2)),
      detalhe: 'texto B sintético');
  await _pedido(s, _pedSemArea, _semArea,
      tipo: DataSubjectRequestType.correction,
      dueAt: _t.add(const Duration(days: 3)),
      detalhe: 'texto sem área sintético');
}

/// O "prontuário" acessório do paciente A: token de push, desafio OTP,
/// credencial, triagem, alerta, visita e consentimento.
Future<void> _prontuarioA(Session s) async {
  final a = UuidValue.fromString(_pacA);
  await PushToken.db.insertRow(
    s,
    PushToken(
      userId: a,
      microAreaId: UuidValue.fromString(_maA),
      token: 'tok-42-a',
      platform: 'android',
      createdAt: _t,
      updatedAt: _t,
    ),
  );
  await OtpChallenge.db.insertRow(
    s,
    OtpChallenge(
      userId: a,
      codeHash: 'hash-sintetico',
      attempts: 0,
      createdAt: _t,
      expiresAt: _t.add(const Duration(minutes: 5)),
    ),
  );
  await UserCredential.db.insertRow(
    s,
    UserCredential(
      userId: a,
      passwordHash: 'x',
      passwordSalt: 'y',
      memoryKb: 1,
      iterations: 1,
      parallelism: 1,
      failedAttempts: 0,
      createdAt: _t,
      updatedAt: _t,
    ),
  );
  final respostas = await testHealthDataCipher().encryptJson([
    TriageAnswer(question: 'fever', answer: 'sim').toJson(),
  ]);
  await TriageSession.db.insertRow(
    s,
    TriageSession(
      patientId: a,
      answersEncrypted: respostas.ciphertextBase64,
      answersKeyVersion: respostas.keyVersion,
      resultRisk: RiskLevel.yellow,
      resultDisplay: 'Amarelo',
      createdAt: _t,
      deviceId: 'device-sintetico',
    ),
  );
  await Alert.db.insertRow(
    s,
    Alert(
      patientId: a,
      microAreaId: UuidValue.fromString(_maA),
      triggeredAt: _t,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-sintetico',
      status: AlertStatus.pending,
      mqttTopic: 'sinalacs/v1/microareas/$_maA/alerts',
      deviceId: 'device-sintetico',
      retryCount: 0,
      version: 0,
    ),
  );
  await Visit.db.insertRow(
    s,
    Visit(
      patientId: a,
      acsId: UuidValue.fromString(_acsId),
      scheduledAt: _t,
      status: 'realizada',
      riskLevelBefore: RiskLevel.green,
      syncStatus: SyncStatus.synced,
      localId: UuidValue.fromString('00000000-0000-4000-8000-000000004231'),
      version: 1,
    ),
  );
  await ConsentLog.db.insertRow(
    s,
    ConsentLog(
      userId: a,
      purpose: ConsentPurpose.segmentedPush.name,
      action: 'granted',
      version: '2026.1',
      timestamp: _t,
      ipHash: 'nao-aplicavel-teste',
      userAgent: 'nao-aplicavel-teste',
      signature: 'assinatura-de-teste',
    ),
  );
}

AuditEvent _evento(String id, String result) => AuditEvent(
  userId: _adminId,
  actionType: 'write',
  resourceType: 'data_subject_request',
  resourceId: id,
  result: result,
);

void main() {
  withServerpod('Dado o atendimento de pedidos do titular (#42)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late _AuditoriaGravada auditoria;
    late OrmDataSubjectCaseStore store;
    const sistema = AdminScope.system();

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      auditoria = _AuditoriaGravada();
      store = OrmDataSubjectCaseStore(
        session,
        testHealthDataCipher(),
        chainSecret: _segredoConsentimento,
        appendAudit: auditoria.call,
      );
    });

    Future<DataSubjectRequest> pedido(String id) async =>
        (await DataSubjectRequest.db.findById(session, UuidValue.fromString(id)))!;

    Future<User> usuario(String id) async =>
        (await User.db.findById(session, UuidValue.fromString(id)))!;

    Future<bool> excluir(String id, {OrmDataSubjectCaseStore? via}) =>
        (via ?? store).decide(
          sistema,
          id,
          from: const {DataSubjectRequestStatus.open, DataSubjectRequestStatus.inReview},
          to: DataSubjectRequestStatus.completed,
          resolution: null,
          decidedBy: _adminId,
          anonymize: true,
          audit: _evento(id, 'completed'),
          now: _t,
        );

    test('list ordena por dueAt crescente e traz vencidos primeiro', () async {
      final p = await store.list(sistema, limit: 50, offset: 0, now: _t);
      expect(p.items.map((i) => i.id).toList(), [_pedA1, _pedB1, _pedSemArea, _pedA2, _pedA3]);
      expect(p.items.first.overdue, isTrue);
      expect(p.items.skip(1).every((i) => !i.overdue), isTrue);
      expect(p.nextOffset, isNull);

      final p1 = await store.list(sistema, limit: 2, offset: 0, now: _t);
      expect(p1.items.map((i) => i.id), [_pedA1, _pedB1]);
      expect(p1.nextOffset, 2);
      final p3 = await store.list(sistema, limit: 2, offset: 4, now: _t);
      expect(p3.items.map((i) => i.id), [_pedA3]);
      expect(p3.nextOffset, isNull);

      final emAnalise = await store.list(
        sistema,
        status: DataSubjectRequestStatus.inReview,
        limit: 50,
        offset: 0,
        now: _t,
      );
      expect(emAnalise.items.map((i) => i.id), [_pedA3]);
      expect(emAnalise.items.single.patientLabel, matches(RegExp(r'^#[0-9A-F]{4}$')));
    });

    test('escopo de UBS: coordenador só vê pacientes da própria UBS', () async {
      final soA = await store.list(const AdminScope.ubs(_ubsA), limit: 50, offset: 0, now: _t);
      expect(soA.items.map((i) => i.id).toSet(), {_pedA1, _pedA2, _pedA3});
      final soB = await store.list(const AdminScope.ubs(_ubsB), limit: 50, offset: 0, now: _t);
      expect(soB.items.map((i) => i.id), [_pedB1]);

      // Fora do escopo e inexistente são indistinguíveis: os dois devolvem null.
      expect(await store.find(const AdminScope.ubs(_ubsA), _pedB1, now: _t), isNull);
      expect(await store.find(const AdminScope.ubs(_ubsA), _pedSemArea, now: _t), isNull);
      expect(
        await store.find(sistema, '00000000-0000-4000-8000-0000000042ff', now: _t),
        isNull,
      );
      expect(await store.find(sistema, 'nao-e-uuid', now: _t), isNull);
      expect(await store.find(sistema, _pedSemArea, now: _t), isNotNull);

      // Decidir fora do escopo também não acontece.
      final ok = await store.decide(
        const AdminScope.ubs(_ubsA),
        _pedB1,
        from: const {DataSubjectRequestStatus.open},
        to: DataSubjectRequestStatus.rejected,
        resolution: 'motivo sintético',
        decidedBy: _adminId,
        anonymize: false,
        audit: _evento(_pedB1, 'rejected'),
        now: _t,
      );
      expect(ok, isFalse);
      expect((await pedido(_pedB1)).status, DataSubjectRequestStatus.open);
      expect(auditoria.eventos, isEmpty);
    });

    test('find decifra details só no detalhe; a lista não tem details', () async {
      final lista = await store.list(sistema, limit: 50, offset: 0, now: _t);
      final json = jsonEncode(lista.toJson());
      expect(json, isNot(contains(_detalheA2)));
      expect(json, isNot(contains(_nomeA)));
      expect(json, isNot(contains(_pacA)));

      final d = await store.find(sistema, _pedA2, now: _t);
      expect(d, isNotNull);
      expect(d!.details, _detalheA2);
      expect(d.type, DataSubjectRequestType.correction);
      expect(d.resolution, isNull);
      expect(d.decidedAt, isNull);
      expect(d.patientLabel, matches(RegExp(r'^#[0-9A-F]{4}$')));

      // Correção atendida com nota: a nota é cifrada e volta no detalhe.
      final ok = await store.decide(
        sistema,
        _pedA2,
        from: const {DataSubjectRequestStatus.open},
        to: DataSubjectRequestStatus.completed,
        resolution: _resolucao,
        decidedBy: _adminId,
        anonymize: false,
        audit: _evento(_pedA2, 'completed'),
        now: _t,
      );
      expect(ok, isTrue);
      final linha = await pedido(_pedA2);
      expect(linha.resolutionEncrypted, isNot(contains(_resolucao)));
      expect(linha.resolutionKeyVersion, linha.detailsKeyVersion);
      expect(linha.decidedBy, UuidValue.fromString(_adminId));
      expect(linha.decidedAt, _t);
      final depois = await store.find(sistema, _pedA2, now: _t);
      expect(depois!.resolution, _resolucao);
      expect(depois.status, DataSubjectRequestStatus.completed);
      expect(depois.decidedAt, _t);
      // Correção não anonimiza ninguém.
      expect((await usuario(_pacA)).name, _nomeA);
      expect(auditoria.eventos.single.result, 'completed');
    });

    test(
      'decide(exclusão) anonimiza user/patient, apaga push_tokens/otp/credential/triage answers e mantém alerts, visits, audit_logs, consent_logs',
      () async {
        await _prontuarioA(session);
        // Uma linha real na cadeia antes: ela tem de sobreviver à anonimização.
        await OrmAuditTrail(session: () => session, chainSecret: 'segredo-sintetico')
            .record(AuditEvent(
          userId: _pacA,
          actionType: 'read',
          resourceType: 'patient_data',
          result: 'success',
        ));
        final cpfAntes = (await usuario(_pacA)).cpfHash;
        final a = UuidValue.fromString(_pacA);

        expect(await excluir(_pedA1), isTrue);

        final u = await usuario(_pacA);
        expect(u.name, 'Titular removido');
        expect(u.cpfHash, startsWith('removed:'));
        expect(u.cpfHash, isNot(cpfAntes));
        expect(u.role, UserRole.patient);
        final p = (await Patient.db.findById(session, a))!;
        expect(p.chronicConditionsEncrypted, '');
        expect(p.lastLocationHash, isNull);
        expect(p.emergencyContact, '');
        expect(u.birthDate, DateTime.utc(1900, 1, 1));

        expect(await PushToken.db.count(session, where: (t) => t.userId.equals(a)), 0);
        expect(await OtpChallenge.db.count(session, where: (t) => t.userId.equals(a)), 0);
        expect(await UserCredential.db.count(session, where: (t) => t.userId.equals(a)), 0);
        final triagens = await TriageSession.db.find(session, where: (t) => t.patientId.equals(a));
        expect(triagens, hasLength(1), reason: 'a sessão fica para estatística');
        expect(await decryptedTriageAnswers(triagens.single), isEmpty);
        expect(triagens.single.resultRisk, RiskLevel.yellow);

        expect(await Alert.db.count(session, where: (t) => t.patientId.equals(a)), 1);
        expect(await Visit.db.count(session, where: (t) => t.patientId.equals(a)), 1);
        // O consentimento original fica intocado (append-only); entra um
        // `denied` de segmentedPush, assinado como os do painel do titular.
        final consentimentos = await ConsentLog.db.find(
          session,
          where: (t) => t.userId.equals(a),
          orderBy: (t) => t.timestamp,
        );
        expect(consentimentos, hasLength(2));
        expect(consentimentos.first.action, 'granted');
        final negado = consentimentos.last;
        expect(negado.purpose, ConsentPurpose.segmentedPush.name);
        expect(negado.action, 'denied');
        expect(negado.timestamp, _t.add(const Duration(microseconds: 1)));
        expect(
          negado.signature,
          ConsentSignature(secret: _segredoConsentimento).compute(
            userId: _pacA,
            purpose: negado.purpose,
            action: negado.action,
            version: negado.version,
            timestamp: negado.timestamp,
          ),
        );
        expect(await AuditLog.db.count(session, where: (t) => t.userId.equals(a)), 1);

        final linha = await pedido(_pedA1);
        expect(linha.status, DataSubjectRequestStatus.completed);
        expect(linha.decidedBy, UuidValue.fromString(_adminId));
        expect(linha.decidedAt, _t);
        expect(auditoria.eventos.map((e) => e.resourceId), [_pedA1, _pedA3]);

        // O paciente B não é tocado.
        expect((await usuario(_pacB)).name, 'Paciente B Sintético');
      },
    );

    test('decide(exclusão) fecha também um segundo pedido de exclusão aberto do mesmo titular', () async {
      expect(await excluir(_pedA1), isTrue);

      final a3 = await pedido(_pedA3);
      expect(a3.status, DataSubjectRequestStatus.completed);
      expect(a3.decidedAt, _t);
      expect(a3.decidedBy, UuidValue.fromString(_adminId));
      // A correção aberta do mesmo titular continua aberta: só exclusões fecham.
      expect((await pedido(_pedA2)).status, DataSubjectRequestStatus.open);
      // Uma linha de auditoria por pedido fechado: o decidido e o irmão.
      expect(auditoria.eventos, hasLength(2));
      final irmao = auditoria.eventos.last;
      expect(irmao.resourceId, _pedA3);
      expect(irmao.userId, _adminId);
      expect(irmao.actionType, 'write');
      expect(irmao.resourceType, 'data_subject_request');
      expect(irmao.result, 'completed');
      // O pedido fechado junto não pode ser decidido de novo.
      expect(await excluir(_pedA3), isFalse);
    });

    test('depois da anonimização, a sessão viva do titular não registra token de push', () async {
      // Consentimento `granted` vigente antes: sem o `denied` da anonimização,
      // o registro passaria.
      await _prontuarioA(session);
      expect(await excluir(_pedA1), isTrue);

      final r = await OrmPushTokenStore(session: () => session).registerIfConsented(
        userId: _pacA,
        microAreaId: _maA,
        token: 'tok-42-depois',
        platform: 'android',
        now: _t.add(const Duration(minutes: 1)),
      );

      expect(r.outcome, PushRegistration.refused);
      expect(
        await PushToken.db.count(
          session,
          where: (t) => t.userId.equals(UuidValue.fromString(_pacA)),
        ),
        0,
      );
    });

    test('decide em titular sem linha em patients não quebra', () async {
      const pedido42 = '00000000-0000-4000-8000-000000004226';
      await _pedido(session, pedido42, _semArea,
          tipo: DataSubjectRequestType.deletion, dueAt: _t.add(const Duration(days: 1)));

      expect(await excluir(pedido42), isTrue);

      final u = await usuario(_semArea);
      expect(u.name, 'Titular removido');
      expect(u.cpfHash, startsWith('removed:'));
      expect((await pedido(pedido42)).status, DataSubjectRequestStatus.completed);
    });

    test('exclusão de quem não é paciente é recusada e nada muda', () async {
      const pedidoAcs = '00000000-0000-4000-8000-000000004227';
      await _pedido(session, pedidoAcs, _acsId,
          tipo: DataSubjectRequestType.deletion, dueAt: _t.add(const Duration(days: 1)));

      await expectLater(excluir(pedidoAcs), throwsA(isA<StateError>()));

      expect((await usuario(_acsId)).name, 'ACS Sintético 42');
      expect((await pedido(pedidoAcs)).status, DataSubjectRequestStatus.open);
      expect(auditoria.eventos, isEmpty);
    });

    test('estado fora de `from` devolve false sem gravar nada', () async {
      final ok = await store.decide(
        sistema,
        _pedA3, // inReview
        from: const {DataSubjectRequestStatus.open},
        to: DataSubjectRequestStatus.inReview,
        resolution: null,
        decidedBy: _adminId,
        anonymize: false,
        audit: _evento(_pedA3, 'in_review'),
        now: _t,
      );
      expect(ok, isFalse);
      expect(auditoria.eventos, isEmpty);
      expect((await pedido(_pedA3)).decidedAt, isNull);
    });

    test('falha na auditoria desfaz a mudança de status (rollback)', () async {
      await _prontuarioA(session);
      final cpfAntes = (await usuario(_pacA)).cpfHash;
      auditoria.falhar = true;

      await expectLater(excluir(_pedA1), throwsA(isA<StateError>()));

      final linha = await pedido(_pedA1);
      expect(linha.status, DataSubjectRequestStatus.open);
      expect(linha.decidedAt, isNull);
      expect(linha.decidedBy, isNull);
      expect((await pedido(_pedA3)).status, DataSubjectRequestStatus.inReview);
      final u = await usuario(_pacA);
      expect(u.name, _nomeA);
      expect(u.cpfHash, cpfAntes);
      final a = UuidValue.fromString(_pacA);
      expect(await PushToken.db.count(session, where: (t) => t.userId.equals(a)), 1);
      expect(await UserCredential.db.count(session, where: (t) => t.userId.equals(a)), 1);
    });

    test('com a trilha real, a linha de auditoria entra na cadeia na mesma transação', () async {
      final trilha = OrmAuditTrail(session: () => session, chainSecret: 'segredo-sintetico');
      final real = OrmDataSubjectCaseStore(
        session,
        testHealthDataCipher(),
        chainSecret: _segredoConsentimento,
        appendAudit: trilha.recordInTransaction,
      );
      expect(await excluir(_pedA1, via: real), isTrue);
      final irmas = await AuditLog.db.find(
        session,
        where: (t) => t.resourceId.equals(UuidValue.fromString(_pedA3)),
      );
      expect(irmas.single.result, 'completed', reason: 'o pedido irmão também é auditado');
      final linhas = await AuditLog.db.find(
        session,
        where: (t) => t.resourceId.equals(UuidValue.fromString(_pedA1)),
      );
      expect(linhas, hasLength(1));
      expect(linhas.single.actionType, 'write');
      expect(linhas.single.resourceType, 'data_subject_request');
      expect(linhas.single.result, 'completed');
      expect(linhas.single.userId, UuidValue.fromString(_adminId));
    });

    test('depois da anonimização, requestOtp/verifyOtp do titular recusam com a mensagem genérica de sempre', () async {
      final cpf = Cpf.tryParse(_cpfSintetico)!;
      final naoCadastrado = Cpf.tryParse('98765432100')!;
      final sms = RecordingSmsGateway();
      final otp = PasswordlessAuthService(
        store: OrmOtpChallengeStore(session: () => session),
        hasher: _hasher,
        sms: sms,
        audit: _SemAuditoria(),
        codeGenerator: () => '123456',
      );
      final nascimento = DateTime.utc(1985, 3, 4);

      // Controle positivo: antes da exclusão o CPF acha o titular e recebe código.
      await otp.requestOtp(cpf: cpf, birthDate: nascimento, now: _t);
      expect(sms.sent, hasLength(1));

      expect(await excluir(_pedA1), isTrue);

      await otp.requestOtp(cpf: cpf, birthDate: nascimento, now: _t.add(const Duration(minutes: 2)));
      expect(sms.sent, hasLength(1), reason: 'nenhum código novo para o titular removido');
      expect(
        await OtpChallenge.db.count(
          session,
          where: (t) => t.userId.equals(UuidValue.fromString(_pacA)),
        ),
        0,
      );

      Future<String> recusa(Cpf c) async {
        try {
          await otp.verifyOtp(cpf: c, code: '123456', now: _t.add(const Duration(minutes: 3)));
        } on OtpRequestException catch (e) {
          return e.message;
        }
        fail('verifyOtp deveria recusar');
      }

      final removido = await recusa(cpf);
      expect(removido, await recusa(naoCadastrado));
      expect(removido, 'Código inválido ou expirado. Peça um novo.');
      // Nenhuma conta recriada com o hash do CPF.
      expect(
        await User.db.count(session, where: (t) => t.cpfHash.equals(_hasher.hash(cpf))),
        0,
      );
    });

    test('subjectOf devolve o titular do pedido e null para id inexistente ou malformado', () async {
      expect(await store.subjectOf(_pedA1), _pacA);
      expect(await store.subjectOf('00000000-0000-4000-8000-0000000042ff'), isNull);
      expect(await store.subjectOf('nao-e-uuid'), isNull);
    });

    test('ubsOf devolve a UBS do coordenador e null para quem não tem', () async {
      const coord = '00000000-0000-4000-8000-000000004216';
      await _usuario(session, coord, 'Coord Sintético 42', UserRole.coordinator);
      await StaffAccount.db.insertRow(
        session,
        StaffAccount(
          id: UuidValue.fromString(coord),
          enrollmentId: 'COO-42-1',
          active: true,
          ubsId: UuidValue.fromString(_ubsA),
        ),
      );
      expect(await store.ubsOf(coord), _ubsA);
      expect(await store.ubsOf(_adminId), isNull);
      expect(await store.ubsOf('nao-e-uuid'), isNull);
    });
  });

  // Sem rollback automático: com ele, sessões concorrentes do harness colidem no
  // savepoint compartilhado (ver `institutional_login_test.dart`). A auditoria
  // aqui é a lista em memória e não `audit_logs`: uma linha commitada na cadeia
  // seria vista por suítes paralelas que contam `AuditLog` sem filtro. O que a
  // lista prova é o que importa — o perdedor da corrida sai ANTES de chegar à
  // auditoria e à anonimização, que ficam dentro da mesma transação.
  withServerpod(
    'Dado o atendimento de pedidos do titular (#42), sem rollback (corrida)',
    (sessionBuilder, endpoints) {
      const rodadas = 5;
      String idDe(int base, int i) =>
          '00000000-0000-4000-8000-0000000043${(base + i).toRadixString(16).padLeft(2, '0')}';

      Future<void> limpar(Session s) async {
        for (var i = 0; i < rodadas; i++) {
          final user = UuidValue.fromString(idDe(0x10, i));
          await DataSubjectRequest.db.deleteWhere(s, where: (t) => t.userId.equals(user));
          await ConsentLog.db.deleteWhere(s, where: (t) => t.userId.equals(user));
          await Patient.db.deleteWhere(s, where: (t) => t.id.equals(user));
          await User.db.deleteWhere(s, where: (t) => t.id.equals(user));
        }
        await User.db.deleteWhere(
          s,
          where: (t) =>
              t.id.equals(UuidValue.fromString(idDe(0x01, 0))) |
              t.id.equals(UuidValue.fromString(idDe(0x02, 0))),
        );
        await MicroArea.db.deleteWhere(s, where: (t) => t.id.equals(UuidValue.fromString(_maCorrida)));
        await Ubs.db.deleteWhere(s, where: (t) => t.id.equals(UuidValue.fromString(_ubsCorrida)));
      }

      test('duas decisões simultâneas: uma true, outra false; uma só anonimização', () async {
        final s = sessionBuilder.build();
        final analista1 = idDe(0x01, 0);
        final analista2 = idDe(0x02, 0);
        await limpar(s);
        try {
          await Ubs.db.insertRow(
            s,
            Ubs(
              id: UuidValue.fromString(_ubsCorrida),
              name: 'UBS Corrida 42',
              address: 'Endereço sintético',
              city: 'São Paulo',
              state: 'SP',
            ),
          );
          await MicroArea.db.insertRow(
            s,
            MicroArea(
              id: UuidValue.fromString(_maCorrida),
              name: 'Microárea Corrida 42',
              ubsId: UuidValue.fromString(_ubsCorrida),
              geoJsonBoundary: '{}',
            ),
          );
          await _usuario(s, analista1, 'Analista 1 Sintético', UserRole.admin);
          await _usuario(s, analista2, 'Analista 2 Sintético', UserRole.admin);

          for (var i = 0; i < rodadas; i++) {
            final titular = idDe(0x10, i);
            final pedidoId = idDe(0x20, i);
            await _usuario(s, titular, 'Titular Corrida $i', UserRole.patient, ma: _maCorrida);
            await Patient.db.insertRow(
              s,
              await encryptedPatient(id: titular, emergencyContact: 'x', isChronic: false),
            );
            await _pedido(s, pedidoId, titular,
                tipo: DataSubjectRequestType.deletion, dueAt: _t);

            final auditoria = _AuditoriaGravada();
            Future<bool> decidir(String analista) => OrmDataSubjectCaseStore(
              sessionBuilder.build(),
              testHealthDataCipher(),
              chainSecret: _segredoConsentimento,
              appendAudit: auditoria.call,
            ).decide(
              const AdminScope.system(),
              pedidoId,
              from: const {DataSubjectRequestStatus.open, DataSubjectRequestStatus.inReview},
              to: DataSubjectRequestStatus.completed,
              resolution: null,
              decidedBy: analista,
              anonymize: true,
              audit: AuditEvent(
                userId: analista,
                actionType: 'write',
                resourceType: 'data_subject_request',
                resourceId: pedidoId,
                result: 'completed',
              ),
              now: _t,
            );

            final r = await Future.wait([decidir(analista1), decidir(analista2)]);
            expect(r.where((x) => x).length, 1, reason: 'rodada $i');
            expect(auditoria.eventos, hasLength(1), reason: 'rodada $i: uma só auditoria');
            final vencedor = r[0] ? analista1 : analista2;
            expect(auditoria.eventos.single.userId, vencedor);

            final linha = (await DataSubjectRequest.db.findById(s, UuidValue.fromString(pedidoId)))!;
            expect(linha.status, DataSubjectRequestStatus.completed);
            expect(linha.decidedBy, UuidValue.fromString(vencedor), reason: 'o perdedor não sobrescreve');
            final u = (await User.db.findById(s, UuidValue.fromString(titular)))!;
            expect(u.name, 'Titular removido');
            // Uma anonimização só, medida no banco: um único `denied` gravado.
            expect(
              await ConsentLog.db.count(
                s,
                where: (t) => t.userId.equals(UuidValue.fromString(titular)),
              ),
              1,
              reason: 'rodada $i',
            );
          }
        } finally {
          await limpar(s);
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
