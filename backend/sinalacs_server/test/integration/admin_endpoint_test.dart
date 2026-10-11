import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `admin.*` (#40) pelo endpoint, com tokens reais e Postgres real: papel,
/// escopo por UBS, auditoria de cada leitura e minimização de PII.
/// Dados sintéticos; ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000000d1';
const _ubsB = '00000000-0000-4000-8000-0000000000d2';
const _maA = '00000000-0000-4000-8000-0000000000d3';
const _maB = '00000000-0000-4000-8000-0000000000d4';
const _admin = '00000000-0000-4000-8000-0000000000d5';
const _coordA = '00000000-0000-4000-8000-0000000000d6';
const _coordSemUbs = '00000000-0000-4000-8000-0000000000d7';
const _acs = '00000000-0000-4000-8000-0000000000d8';
const _paciente = '00000000-0000-4000-8000-0000000000d9';
const _coordB = '00000000-0000-4000-8000-0000000000da';
const _nomePaciente = 'Joana Sintética Pereira';

final _agora = DateTime.now().toUtc();

Future<void> _usuario(
  Session s,
  String id,
  String nome,
  UserRole role, {
  String? ma,
}) async {
  await User.db.insertRow(
    s,
    User(
      id: UuidValue.fromString(id),
      cpfHash: 'admin-ep-$id',
      name: nome,
      birthDate: DateTime.utc(1980),
      role: role,
      microAreaId: ma == null ? null : UuidValue.fromString(ma),
      createdAt: _agora,
      updatedAt: _agora,
    ),
  );
}

Future<void> _alerta(
  Session s,
  String ma,
  RiskLevel risco,
  AlertStatus status,
  Duration atras,
) async {
  await Alert.db.insertRow(
    s,
    Alert(
      patientId: UuidValue.fromString(_paciente),
      microAreaId: UuidValue.fromString(ma),
      triggeredAt: _agora.subtract(atras),
      riskLevel: risco,
      locationHash: 'hash-sintetico',
      status: status,
      mqttTopic: 'sinalacs/v1/microareas/$ma/alerts',
      deviceId: 'device-sintetico',
      retryCount: 0,
      version: 0,
    ),
  );
}

Future<void> _seed(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A'), (_ubsB, 'UBS B')]) {
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
  for (final (id, nome, ubs) in [
    (_maA, 'Microárea A', _ubsA),
    (_maB, 'Microárea B', _ubsB),
  ]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: nome,
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  await _usuario(s, _acs, 'ACS Sintético', UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acs),
      enrollmentId: 'ACS-EP-1',
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _usuario(s, _paciente, _nomePaciente, UserRole.patient, ma: _maA);
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _paciente,
      emergencyContact: 'x',
      isChronic: false,
    ),
  );
  await _usuario(s, _admin, 'Admin Sintético', UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-EP-1',
      active: true,
    ),
  );
  await _usuario(s, _coordA, 'Coord A Sintético', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-EP-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
  await _usuario(s, _coordSemUbs, 'Coord Sem UBS', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordSemUbs),
      enrollmentId: 'COO-EP-2',
      active: true,
    ),
  );

  await _alerta(
    s,
    _maA,
    RiskLevel.red,
    AlertStatus.pending,
    const Duration(minutes: 10),
  );
  await _alerta(
    s,
    _maA,
    RiskLevel.green,
    AlertStatus.pending,
    const Duration(minutes: 20),
  );
  await _alerta(
    s,
    _maB,
    RiskLevel.red,
    AlertStatus.pending,
    const Duration(minutes: 5),
  );
}

String _token(String id, UserRole role, {String? ma, DateTime? now}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: id,
        role: role,
        microAreaId: ma,
        deviceId: 'sem-aparelho',
      ),
      now: now,
    );

Future<int> _auditoriasAdmin(Session s, String resultado) async {
  final linhas = await s.db.unsafeQuery(
    'SELECT count(*) FROM audit_logs WHERE "resourceType" LIKE \'admin_%\' AND result = @r',
    parameters: QueryParameters.named({'r': resultado}),
  );
  return linhas.single[0] as int;
}

void main() {
  withServerpod('Dado o endpoint admin do backoffice (#40)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
    });

    test(
      'admin lê os quatro endpoints e cada leitura vira uma linha read/success em audit_logs',
      () async {
        final t = _token(_admin, UserRole.admin);
        final ind = await endpoints.admin.indicators(
          sessionBuilder,
          accessToken: t,
        );
        expect(ind.red, 2);
        expect(ind.green, 1);
        expect(ind.tmravSeconds, isNull);
        expect(
          (await endpoints.admin.microAreas(
            sessionBuilder,
            accessToken: t,
          )).map((m) => m.name),
          containsAll(['Microárea A', 'Microárea B']),
        );
        expect(
          (await endpoints.admin.alerts(
            sessionBuilder,
            accessToken: t,
            limit: 50,
            offset: 0,
          )).items,
          hasLength(3),
        );
        await endpoints.admin.auditLogs(
          sessionBuilder,
          accessToken: t,
          limit: 50,
        );
        expect(await _auditoriasAdmin(session, 'success'), 4);
      },
    );

    test(
      'coordenador da UBS A não vê a UBS B (indicators, microAreas, alerts)',
      () async {
        final t = _token(_coordA, UserRole.coordinator);
        expect(
          (await endpoints.admin.indicators(
            sessionBuilder,
            accessToken: t,
          )).red,
          1,
        );
        expect(
          (await endpoints.admin.microAreas(
            sessionBuilder,
            accessToken: t,
          )).map((m) => m.name),
          ['Microárea A'],
        );
        final alertas = await endpoints.admin.alerts(
          sessionBuilder,
          accessToken: t,
          limit: 50,
          offset: 0,
        );
        expect(alertas.items, hasLength(2));
        expect(alertas.items.map((a) => a.microAreaName).toSet(), {
          'Microárea A',
        });
        final filtrandoB = await endpoints.admin.alerts(
          sessionBuilder,
          accessToken: t,
          microAreaId: _maB,
          limit: 50,
          offset: 0,
        );
        expect(
          filtrandoB.items,
          isEmpty,
          reason: 'filtro de outra UBS não fura o escopo',
        );
      },
    );

    test(
      'coordenador lê a auditoria escopada à UBS dele; linha de staff fica invisível',
      () async {
        // Linhas reais: a leitura do diretório pelo ACS (ator com microárea da
        // UBS A) e a leitura de indicadores pelo administrador (staff, sem
        // microárea). A do coordenador é a própria chamada abaixo.
        await endpoints.patients.listMicroArea(
          sessionBuilder,
          accessToken: _token(_acs, UserRole.acs, ma: _maA),
        );
        await endpoints.admin.indicators(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
        );

        final doCoordenador = await endpoints.admin.auditLogs(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          limit: 50,
        );
        expect(
          doCoordenador.items.map((e) => e.userLabel),
          contains('ACS-EP-1 (ACS)'),
        );
        expect(
          doCoordenador.items.map((e) => e.userLabel),
          isNot(contains('ADM-EP-1 (Administrador)')),
          reason: 'linha de staff não tem microárea: fora do escopo da UBS',
        );
        expect(
          doCoordenador.items.map((e) => e.userLabel),
          isNot(contains('COO-EP-1 (Coordenador)')),
          reason: 'a própria leitura do coordenador também é linha de staff',
        );

        final doAdmin = await endpoints.admin.auditLogs(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
          limit: 50,
        );
        expect(
          doAdmin.items.map((e) => e.userLabel),
          containsAll(
            <String>[
              'ACS-EP-1 (ACS)',
              'ADM-EP-1 (Administrador)',
              'COO-EP-1 (Coordenador)',
            ],
          ),
          reason: 'o administrador continua vendo o sistema inteiro',
        );
      },
    );

    test(
      'coordenador sem UBS recebe AlertPermissionException nos quatro',
      () async {
        final t = _token(_coordSemUbs, UserRole.coordinator);
        for (final chamada in <Future<Object?> Function()>[
          () => endpoints.admin.indicators(sessionBuilder, accessToken: t),
          () => endpoints.admin.microAreas(sessionBuilder, accessToken: t),
          () => endpoints.admin.alerts(
            sessionBuilder,
            accessToken: t,
            limit: 50,
            offset: 0,
          ),
          () => endpoints.admin.auditLogs(
            sessionBuilder,
            accessToken: t,
            limit: 50,
          ),
        ]) {
          await expectLater(
            chamada(),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(await _auditoriasAdmin(session, 'denied'), 4);
      },
    );

    test(
      'acs (com microárea) e patient com token válido recebem AlertPermissionException nos quatro',
      () async {
        for (final (id, role, ma) in [
          (_acs, UserRole.acs, _maA),
          (_paciente, UserRole.patient, _maA),
        ]) {
          final t = _token(id, role, ma: ma);
          for (final chamada in <Future<Object?> Function()>[
            () => endpoints.admin.indicators(sessionBuilder, accessToken: t),
            () => endpoints.admin.microAreas(sessionBuilder, accessToken: t),
            () => endpoints.admin.alerts(
              sessionBuilder,
              accessToken: t,
              limit: 50,
              offset: 0,
            ),
            () => endpoints.admin.auditLogs(
              sessionBuilder,
              accessToken: t,
              limit: 50,
            ),
          ]) {
            await expectLater(
              chamada(),
              throwsA(isA<AlertPermissionException>()),
            );
          }
        }
        expect(await _auditoriasAdmin(session, 'denied'), 8);
      },
    );

    test(
      'token adulterado e token expirado são recusados e não auditam leitura',
      () async {
        final bom = _token(_admin, UserRole.admin);
        final expirado = _token(
          _admin,
          UserRole.admin,
          now: DateTime.utc(2020),
        );
        for (final t in ['${bom}x', expirado, '', 'lixo']) {
          await expectLater(
            endpoints.admin.indicators(sessionBuilder, accessToken: t),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(await _auditoriasAdmin(session, 'success'), 0);
      },
    );

    test('a auditoria não devolve hash nem IP', () async {
      final t = _token(_admin, UserRole.admin);
      await endpoints.admin.indicators(sessionBuilder, accessToken: t);
      final json = jsonEncode(
        (await endpoints.admin.auditLogs(
          sessionBuilder,
          accessToken: t,
          limit: 50,
        )).toJson(),
      );
      expect(json, isNot(contains('Hash')));
      expect(json, isNot(contains('ip')));
      expect(json, contains('ADM-EP-1 (Administrador)'));
    });

    test(
      'a resposta de alertas não contém nome nem UUID do paciente',
      () async {
        final json = jsonEncode(
          (await endpoints.admin.alerts(
            sessionBuilder,
            accessToken: _token(_admin, UserRole.admin),
            limit: 50,
            offset: 0,
          )).toJson(),
        );
        expect(json, isNot(contains(_nomePaciente)));
        expect(json, isNot(contains(_paciente)));
      },
    );

    test(
      'limit fora de 1..100 vira AdminInvalidRequestException e não é auditado como leitura',
      () async {
        final t = _token(_admin, UserRole.admin);
        await expectLater(
          endpoints.admin.alerts(
            sessionBuilder,
            accessToken: t,
            limit: 0,
            offset: 0,
          ),
          throwsA(isA<AdminInvalidRequestException>()),
        );
        await expectLater(
          endpoints.admin.alerts(
            sessionBuilder,
            accessToken: t,
            limit: 101,
            offset: 0,
          ),
          throwsA(isA<AdminInvalidRequestException>()),
        );
        expect(await _auditoriasAdmin(session, 'success'), 0);
      },
    );

    group('pedidos do titular (#42), ponta a ponta pelo endpoint', () {
      String tPaciente() => _token(_paciente, UserRole.patient, ma: _maA);
      String tCoordA() => _token(_coordA, UserRole.coordinator);

      Future<void> coordenadorB() async {
        await _usuario(
          session,
          _coordB,
          'Coord B Sintético',
          UserRole.coordinator,
        );
        await StaffAccount.db.insertRow(
          session,
          StaffAccount(
            id: UuidValue.fromString(_coordB),
            enrollmentId: 'COO-EP-3',
            active: true,
            ubsId: UuidValue.fromString(_ubsB),
          ),
        );
      }

      Future<String> idDoPedido() async => (await DataSubjectRequest.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_paciente)),
      )).single.id!.uuid;

      test(
        'correção: paciente pede, coordenador lista (rótulo), abre, analisa e '
        'atende; o paciente vê completed e a nota em myData',
        () async {
          await endpoints.patients.requestDataCorrection(
            sessionBuilder,
            accessToken: tPaciente(),
            details: 'Meu contato de emergência sintético mudou.',
          );
          final id = await idDoPedido();

          final pagina = await endpoints.admin.dataSubjectRequests(
            sessionBuilder,
            accessToken: tCoordA(),
            limit: 50,
            offset: 0,
          );
          expect(pagina.items, hasLength(1));
          final item = pagina.items.single;
          expect(item.id, id);
          expect(item.type, DataSubjectRequestType.correction);
          expect(item.status, DataSubjectRequestStatus.open);
          expect(item.patientLabel, startsWith('#'));
          final jsonLista = jsonEncode(pagina.toJson());
          expect(jsonLista, isNot(contains(_nomePaciente)));
          expect(jsonLista, isNot(contains(_paciente)));
          expect(jsonLista, isNot(contains('contato de emergência')));

          final detalhe = await endpoints.admin.dataSubjectRequest(
            sessionBuilder,
            accessToken: tCoordA(),
            id: id,
          );
          expect(detalhe.details, 'Meu contato de emergência sintético mudou.');
          expect(jsonEncode(detalhe.toJson()), isNot(contains(_nomePaciente)));

          await endpoints.admin.startDataSubjectReview(
            sessionBuilder,
            accessToken: tCoordA(),
            id: id,
          );
          expect(
            (await endpoints.admin.dataSubjectRequest(
              sessionBuilder,
              accessToken: tCoordA(),
              id: id,
            )).status,
            DataSubjectRequestStatus.inReview,
          );

          await endpoints.admin.completeDataSubjectRequest(
            sessionBuilder,
            accessToken: tCoordA(),
            id: id,
            note: 'Contato atualizado pela equipe.',
          );

          final dados = await endpoints.patients.myData(
            sessionBuilder,
            accessToken: tPaciente(),
          );
          final pedido = dados.requests.single;
          expect(pedido.status, DataSubjectRequestStatus.completed);
          expect(pedido.resolution, 'Contato atualizado pela equipe.');

          final decisoes = await AuditLog.db.find(
            session,
            where: (t) =>
                t.resourceType.equals('data_subject_request') &
                t.resourceId.equals(UuidValue.fromString(id)) &
                t.actionType.equals('write') &
                t.userId.equals(UuidValue.fromString(_coordA)),
          );
          expect(
            decisoes.map((e) => e.result).toSet(),
            {'in_review', 'completed'},
          );
        },
      );

      test('recusa: o paciente vê rejected e o motivo', () async {
        await endpoints.patients.requestDataCorrection(
          sessionBuilder,
          accessToken: tPaciente(),
          details: 'Pedido sintético a recusar.',
        );
        final id = await idDoPedido();
        await endpoints.admin.rejectDataSubjectRequest(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
          id: id,
          reason: 'Dado já está correto.',
        );
        final pedido = (await endpoints.patients.myData(
          sessionBuilder,
          accessToken: tPaciente(),
        )).requests.single;
        expect(pedido.status, DataSubjectRequestStatus.rejected);
        expect(pedido.resolution, 'Dado já está correto.');
      });

      test(
        'acs e patient com token válido recebem AlertPermissionException nos cinco',
        () async {
          await endpoints.patients.requestDataDeletion(
            sessionBuilder,
            accessToken: tPaciente(),
          );
          final id = await idDoPedido();
          for (final t in [
            _token(_acs, UserRole.acs, ma: _maA),
            tPaciente(),
          ]) {
            for (final chamada in <Future<Object?> Function()>[
              () => endpoints.admin.dataSubjectRequests(
                sessionBuilder,
                accessToken: t,
                limit: 50,
                offset: 0,
              ),
              () => endpoints.admin.dataSubjectRequest(
                sessionBuilder,
                accessToken: t,
                id: id,
              ),
              () => endpoints.admin.startDataSubjectReview(
                sessionBuilder,
                accessToken: t,
                id: id,
              ),
              () => endpoints.admin.completeDataSubjectRequest(
                sessionBuilder,
                accessToken: t,
                id: id,
              ),
              () => endpoints.admin.rejectDataSubjectRequest(
                sessionBuilder,
                accessToken: t,
                id: id,
                reason: 'motivo sintético',
              ),
            ]) {
              await expectLater(
                chamada(),
                throwsA(isA<AlertPermissionException>()),
              );
            }
          }
          for (final t in ['', 'lixo']) {
            await expectLater(
              endpoints.admin.dataSubjectRequests(
                sessionBuilder,
                accessToken: t,
                limit: 50,
                offset: 0,
              ),
              throwsA(isA<AlertPermissionException>()),
            );
          }
          final pedido = (await DataSubjectRequest.db.find(
            session,
            where: (t) => t.userId.equals(UuidValue.fromString(_paciente)),
          )).single;
          expect(pedido.status, DataSubjectRequestStatus.open);
        },
      );

      test(
        'coordenador de outra UBS não vê nem decide o pedido, e a resposta é a '
        'mesma de um id inexistente',
        () async {
          await coordenadorB();
          await endpoints.patients.requestDataDeletion(
            sessionBuilder,
            accessToken: tPaciente(),
          );
          final id = await idDoPedido();
          final tB = _token(_coordB, UserRole.coordinator);

          expect(
            (await endpoints.admin.dataSubjectRequests(
              sessionBuilder,
              accessToken: tB,
              limit: 50,
              offset: 0,
            )).items,
            isEmpty,
          );

          Future<String> mensagem(Future<Object?> Function() chamada) async {
            try {
              await chamada();
            } on AdminInvalidRequestException catch (e) {
              return e.message;
            }
            fail('deveria ter lançado AdminInvalidRequestException');
          }

          const inexistente = '00000000-0000-4000-8000-0000000000ff';
          for (final (alvo, outro) in [
            (
              () => endpoints.admin.startDataSubjectReview(
                sessionBuilder,
                accessToken: tB,
                id: id,
              ),
              () => endpoints.admin.startDataSubjectReview(
                sessionBuilder,
                accessToken: tB,
                id: inexistente,
              ),
            ),
            (
              () => endpoints.admin.dataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: id,
              ),
              () => endpoints.admin.dataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: inexistente,
              ),
            ),
            (
              () => endpoints.admin.completeDataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: id,
              ),
              () => endpoints.admin.completeDataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: inexistente,
              ),
            ),
            (
              () => endpoints.admin.rejectDataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: id,
                reason: 'motivo sintético',
              ),
              () => endpoints.admin.rejectDataSubjectRequest(
                sessionBuilder,
                accessToken: tB,
                id: inexistente,
                reason: 'motivo sintético',
              ),
            ),
          ]) {
            expect(await mensagem(alvo), await mensagem(outro));
          }

          final pedido = (await DataSubjectRequest.db.find(
            session,
            where: (t) => t.userId.equals(UuidValue.fromString(_paciente)),
          )).single;
          expect(pedido.status, DataSubjectRequestStatus.open);
          final usuario = await User.db.findById(
            session,
            UuidValue.fromString(_paciente),
          );
          expect(usuario!.name, _nomePaciente);
        },
      );

      test(
        'exclusão atendida anonimiza o titular, myData mostra completed e o '
        'JWT ainda vivo não abre pedido novo nem registra push',
        () async {
          await endpoints.patients.requestDataDeletion(
            sessionBuilder,
            accessToken: tPaciente(),
          );
          final id = await idDoPedido();
          await endpoints.admin.completeDataSubjectRequest(
            sessionBuilder,
            accessToken: tCoordA(),
            id: id,
          );

          final usuario = await User.db.findById(
            session,
            UuidValue.fromString(_paciente),
          );
          expect(usuario!.name, isNot(_nomePaciente));
          expect(usuario.name, 'Titular removido');
          expect(usuario.cpfHash, startsWith('removed:'));

          final dados = await endpoints.patients.myData(
            sessionBuilder,
            accessToken: tPaciente(),
          );
          expect(
            dados.requests.single.status,
            DataSubjectRequestStatus.completed,
          );
          expect(dados.requests.single.resolution, isNull);

          await expectLater(
            endpoints.patients.requestDataCorrection(
              sessionBuilder,
              accessToken: tPaciente(),
              details: 'texto sintético depois da exclusão',
            ),
            throwsA(isA<AlertPermissionException>()),
          );
          await expectLater(
            endpoints.patients.updateConsent(
              sessionBuilder,
              accessToken: tPaciente(),
              purpose: ConsentPurpose.segmentedPush,
              granted: true,
            ),
            throwsA(isA<AlertPermissionException>()),
          );
          await expectLater(
            endpoints.devices.registerPushToken(
              sessionBuilder,
              accessToken: tPaciente(),
              token: 'token-sintetico-pos-exclusao',
              platform: 'android',
            ),
            throwsA(isA<DataRightsException>()),
          );
          expect(
            await PushToken.db.count(
              session,
              where: (t) => t.userId.equals(UuidValue.fromString(_paciente)),
            ),
            0,
          );
          expect(
            await DataSubjectRequest.db.count(
              session,
              where: (t) => t.userId.equals(UuidValue.fromString(_paciente)),
            ),
            1,
          );
        },
      );
    });

    test('página além do fim: items vazio e nextOffset nulo', () async {
      final p = await endpoints.admin.alerts(
        sessionBuilder,
        accessToken: _token(_admin, UserRole.admin),
        offset: 50,
        limit: 50,
      );
      expect(p.items, isEmpty);
      expect(p.nextOffset, isNull);
    });
  });
}
