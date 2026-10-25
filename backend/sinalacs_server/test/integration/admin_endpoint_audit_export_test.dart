import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/audit_export_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_csv.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_export_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'support/privileged_tamper.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `admin.exportAuditLogs` (#45, Task 10) pelo endpoint, com tokens reais e
/// Postgres real (banco do harness, desfeito a cada caso). Dados sintéticos;
/// ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000047a1';
const _maA = '00000000-0000-4000-8000-0000000047a3';
const _acsA = '00000000-0000-4000-8000-0000000047a5';
const _admin = '00000000-0000-4000-8000-0000000047a7';
const _coordA = '00000000-0000-4000-8000-0000000047a8';
const _paciente = '00000000-0000-4000-8000-0000000047a9';

/// `resourceId` sintético de uma linha (rótulo esperado: `#B18F`).
const _recurso = '00000000-0000-4000-8000-00000000b18f';

/// Matrícula sintética do autor: não pode aparecer no log do processo.
const _matriculaAcs = 'ACS-EXPORTA-A';

const _segredo = AppConfig.developmentAuditChainSecret;

final _t = DateTime.utc(2026, 10, 13, 12);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
  jwtSecret: 'test-secret',
  auditChainSecret: _segredo,
  healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
  cpfHashPepper: AppConfig.developmentCpfHashPepper,
  smsGateway: 'log',
  mqttUsername: null,
  mqttPassword: null,
  mqttUseTls: false,
  mqttCaCertificatePath: null,
  appEnv: 'development',
  enableDevLogin: true,
);

Future<void> _usuario(Session s, String id, UserRole role, {String? ma}) => User
    .db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'audit-export-ep-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

Future<void> _seed(Session s) async {
  await Ubs.db.insertRow(
    s,
    Ubs(
      id: UuidValue.fromString(_ubsA),
      name: 'UBS A',
      address: 'Endereço sintético',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    s,
    MicroArea(
      id: UuidValue.fromString(_maA),
      name: 'Microárea A',
      ubsId: UuidValue.fromString(_ubsA),
      geoJsonBoundary: '{}',
    ),
  );
  await _usuario(s, _acsA, UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acsA),
      enrollmentId: _matriculaAcs,
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _usuario(s, _paciente, UserRole.patient, ma: _maA);
  await _usuario(s, _admin, UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-EXPORTA-1',
      active: true,
    ),
  );
  await _usuario(s, _coordA, UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-EXPORTA-A',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
}

String _token(String id, UserRole role, {String? ma}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: id,
        role: role,
        microAreaId: ma,
        deviceId: 'sem-aparelho',
      ),
    );

/// Janela que cobre o "agora" das linhas gravadas pela trilha de produção.
AdminAuditFilter _janela({String? resourceType}) {
  final agora = DateTime.now().toUtc();
  return AdminAuditFilter(
    from: agora.subtract(const Duration(days: 1)),
    to: agora.add(const Duration(days: 1)),
    resourceType: resourceType,
  );
}

/// Captura tudo o que o processo escreve em stdout/stderr (e `print`)
/// enquanto [corpo] roda.
class _Captura implements StreamConsumer<List<int>> {
  final texto = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach((b) => texto.write(utf8.decode(b, allowMalformed: true)));

  @override
  Future<void> close() async {}
}

Future<T> _capturandoLog<T>(StringBuffer saida, Future<T> Function() corpo) {
  final out = _Captura();
  final err = _Captura();
  final fakeOut = IOSink(out);
  final fakeErr = IOSink(err);
  return IOOverrides.runZoned(
    () => runZoned(
      corpo,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, linha) => saida.writeln(linha),
      ),
    ),
    stdout: () => _Stdout(fakeOut),
    stderr: () => _Stdout(fakeErr),
  ).whenComplete(() async {
    await fakeOut.flush();
    await fakeErr.flush();
    saida
      ..write(out.texto)
      ..write(err.texto);
  });
}

/// `Stdout` mínimo sobre um [IOSink] (o que `IOOverrides` exige).
class _Stdout implements Stdout {
  _Stdout(this._sink);
  final IOSink _sink;

  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      _sink.writeAll(objects, sep);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> get done => _sink.done;
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding e) {}
  @override
  bool get hasTerminal => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  String get lineTerminator => '\n';
  @override
  set lineTerminator(String t) {}
}

void main() {
  withServerpod('Dado admin.exportAuditLogs (#45, Task 10)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      AlertRuntime.instance.resetAuditChainStatusCache();
      await _seed(session);
    });
    tearDown(() {
      AlertRuntime.instance.overrideConfig(null);
      AlertRuntime.instance.resetAuditChainStatusCache();
    });

    Future<void> linha(
      String autor,
      String resourceType, {
      String? resourceId,
      String result = 'success',
    }) => OrmAuditTrail(session: () => session, chainSecret: _segredo).record(
      AuditEvent(
        userId: autor,
        actionType: 'read',
        resourceType: resourceType,
        resourceId: resourceId,
        result: result,
      ),
    );

    Future<int> head() async =>
        (await AuditLog.db.findFirstRow(
          session,
          orderBy: (t) => t.sequence,
          orderDescending: true,
        ))?.sequence ??
        0;

    Future<List<AuditLog>> exports() => AuditLog.db.find(
      session,
      where: (t) => t.actionType.equals('export'),
      orderBy: (t) => t.sequence,
    );

    Future<AdminAuditExport> exportar(AdminAuditFilter filtro) =>
        endpoints.admin.exportAuditLogs(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
          filter: filtro,
        );

    test(
      'admin exporta o recorte: contagem, sequences e sha256 coerentes; o CSV '
      'não contém o próprio export; 1 linha export ligada a 1 audit_exports; '
      'cadeia continua verified; log sem trecho do CSV',
      () async {
        await linha(_acsA, 'patient_directory', resourceId: _recurso);
        await linha(_paciente, 'triage_session', result: '=CMD()');
        await linha(_admin, 'admin_indicators');
        final headAntes = await head();

        final log = StringBuffer();
        final r = await _capturandoLog(log, () async {
          // Sentinelas: provam que a captura vê stdout, stderr e print.
          stdout.writeln('sentinela-stdout');
          stderr.writeln('sentinela-stderr');
          // ignore: avoid_print
          print('sentinela-print');
          return exportar(_janela());
        });
        expect(
          log.toString(),
          allOf(
            contains('sentinela-stdout'),
            contains('sentinela-stderr'),
            contains('sentinela-print'),
          ),
        );

        // Recorte = tudo até o head capturado antes.
        expect(r.rowCount, headAntes);
        expect(r.firstSequence, 1);
        expect(r.lastSequence, headAntes);
        expect(
          r.contentSha256,
          sha256.convert(utf8.encode(r.csv)).toString(),
        );
        expect(r.chainState, AuditIntegrityState.verified);
        expect(r.fileName, startsWith('auditoria_'));
        expect(r.fileName, endsWith('.csv'));
        expect(r.fileName, isNot(contains(_matriculaAcs)));

        final linhasCsv = r.csv.split('\r\n')..removeLast();
        expect(linhasCsv.first, AuditCsv.columns.join(','));
        expect(linhasCsv, hasLength(headAntes + 1));
        expect(
          linhasCsv.skip(1).map((l) => int.parse(l.split(',').first)),
          [for (var i = 1; i <= headAntes; i++) i],
        );
        // Minimização (D6) e defesa de fórmula (Task 9).
        expect(
          r.csv,
          contains(
            ',$_matriculaAcs,acs,read,patient_directory,'
            '#B18F,success,verified',
          ),
        );
        expect(r.csv, contains(',Paciente #47A9,patient,'));
        expect(r.csv, contains(",'=CMD(),"));
        for (final proibido in [_recurso, _acsA, _paciente, _admin, _segredo]) {
          expect(r.csv, isNot(contains(proibido)));
        }

        // Exatamente um evento export, depois do recorte, ligado ao registro.
        final evs = await exports();
        expect(evs, hasLength(1));
        final ev = evs.single;
        expect(ev.sequence, greaterThan(r.lastSequence!));
        expect(ev.sequence, headAntes + 1);
        expect(ev.resourceType, 'admin_audit_logs');
        expect(ev.result, 'success');
        expect(ev.userId.uuid, _admin);
        expect(r.csv, isNot(contains(',export,')));

        final regs = await AuditExport.db.find(session);
        expect(regs, hasLength(1));
        final reg = regs.single;
        expect(ev.resourceId, reg.id);
        expect(reg.requestedBy.uuid, _admin);
        expect(reg.format, 'csv');
        expect(reg.rowCount, r.rowCount);
        expect(reg.firstSequence, r.firstSequence);
        expect(reg.lastSequence, r.lastSequence);
        expect(reg.contentSha256, r.contentSha256);
        expect(reg.chainState, 'verified');
        final filtros = jsonDecode(reg.filtersJson) as Map<String, dynamic>;
        expect(filtros.keys.toSet(), {'from', 'to'});
        for (final l in linhasCsv.skip(1)) {
          expect(reg.filtersJson, isNot(contains(l)));
        }
        expect(reg.filtersJson, isNot(contains(_matriculaAcs)));

        // A resposta não carrega hash nem segredo.
        final todas = await AuditLog.db.find(session);
        final resposta = jsonEncode(r.toJson());
        for (final l in todas) {
          expect(resposta, isNot(contains(l.entryHash)));
          expect(resposta, isNot(contains(l.ipHash)));
        }
        expect(resposta, isNot(contains(_segredo)));

        // A cadeia segue íntegra depois do apêndice transacional.
        final v = await AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: _segredo,
        ).verify();
        expect(v.ok, isTrue);
        expect(v.checked, headAntes + 1);

        // Nenhum trecho do CSV no log do processo.
        final texto = log.toString();
        expect(texto, isNot(contains(_matriculaAcs)));
        expect(texto, isNot(contains(AuditCsv.columns.join(','))));
        expect(texto, isNot(contains('#B18F')));
        expect(texto, isNot(contains(r.contentSha256)));
      },
    );

    test(
      'exportar duas vezes ⇒ +1 export por chamada; o 2º CSV contém o 1º '
      'export (esperado) e não o próprio',
      () async {
        await linha(_acsA, 'patient_directory');
        final primeiro = await exportar(_janela());
        expect((await exports()), hasLength(1));
        final segundo = await exportar(_janela());
        final evs = await exports();
        expect(evs, hasLength(2));
        expect(await AuditExport.db.count(session), 2);

        expect(primeiro.csv, isNot(contains(',export,')));
        // O 2º recorte vai até a linha do 1º export, e só ela é export.
        expect(segundo.lastSequence, evs.first.sequence);
        expect(RegExp(',export,').allMatches(segundo.csv), hasLength(1));
        expect(evs.last.sequence, greaterThan(segundo.lastSequence!));
        final regs = await AuditExport.db.find(
          session,
          orderBy: (t) => t.requestedAt,
        );
        expect(
          evs.map((e) => e.resourceId).toSet(),
          regs.map((r) => r.id).toSet(),
        );
        final v = await AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: _segredo,
        ).verify();
        expect(v.ok, isTrue);
      },
    );

    test(
      'filtro restringe o recorte (resourceType) e continua sem o export',
      () async {
        await linha(_acsA, 'patient_directory');
        await linha(_acsA, 'triage_session');
        await linha(_acsA, 'patient_directory');
        final r = await exportar(_janela(resourceType: 'patient_directory'));
        expect(r.rowCount, 2);
        expect(r.firstSequence, 1);
        expect(r.lastSequence, 3);
        expect(r.csv, isNot(contains('triage_session')));
      },
    );

    Future<void> verificarECachear() async {
      final s = await endpoints.admin.verifyAuditChain(
        sessionBuilder,
        accessToken: _token(_admin, UserRole.admin),
      );
      expect(s.state, AuditIntegrityState.verified);
    }

    test(
      'cache verified + UPDATE direto numa linha + exportar dentro dos 60 s '
      '⇒ chainState gravado e devolvido é broken (verificação fresca)',
      () async {
        await linha(_acsA, 'patient_directory');
        await linha(_acsA, 'triage_session');
        await linha(_acsA, 'patient_directory');
        await verificarECachear();
        await adulterarComoSuperusuario(
          session,
          "UPDATE audit_logs SET result = 'x' WHERE sequence = 2",
        );

        final r = await exportar(_janela());
        expect(r.chainState, AuditIntegrityState.broken);
        final reg = (await AuditExport.db.find(session)).single;
        expect(reg.chainState, 'broken');
      },
    );

    test(
      'cache verified (com checkpoint) + cauda apagada + exportar dentro dos '
      '60 s ⇒ chainState broken (tailTruncated), nunca verified',
      () async {
        for (var i = 0; i < 4; i++) {
          await linha(_acsA, 'patient_directory');
        }
        // A verificação grava o checkpoint na cabeça (a linha `read` dela).
        await verificarECachear();
        final cabeca = (await AuditLog.db.findFirstRow(
          session,
          orderBy: (t) => t.sequence,
          orderDescending: true,
        ))!.sequence;
        await adulterarComoSuperusuario(
          session,
          'DELETE FROM audit_logs WHERE sequence >= @s',
          parameters: QueryParameters.named({'s': cabeca - 1}),
        );

        final r = await exportar(_janela());
        expect(r.chainState, AuditIntegrityState.broken);
        expect(
          (await AuditExport.db.find(session)).single.chainState,
          'broken',
        );
        final status = await endpoints.admin.verifyAuditChain(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
        );
        expect(status.reasonCode, AuditChainReason.tailTruncated);
      },
    );

    test(
      'coordenador, ACS e paciente ⇒ AlertPermissionException, denied '
      'auditado, nada exportado',
      () async {
        await linha(_acsA, 'patient_directory');
        for (final (id, role, ma) in [
          (_coordA, UserRole.coordinator, null),
          (_acsA, UserRole.acs, _maA),
          (_paciente, UserRole.patient, _maA),
        ]) {
          await expectLater(
            endpoints.admin.exportAuditLogs(
              sessionBuilder,
              accessToken: _token(id, role, ma: ma),
              filter: _janela(),
            ),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        final negadas = await AuditLog.db.find(
          session,
          where: (t) => t.resourceType.equals('admin_audit_export'),
          orderBy: (t) => t.sequence,
        );
        expect(negadas.map((l) => l.result), ['denied', 'denied', 'denied']);
        expect(negadas.map((l) => l.actionType).toSet(), {'export'});
        expect(await AuditExport.db.count(session), 0);
        expect(
          await AuditLog.db.count(
            session,
            where: (t) =>
                t.result.equals('success') & t.actionType.equals('export'),
          ),
          0,
        );
      },
    );

    test('sem período (ou só from) ⇒ AdminInvalidRequestException, sem '
        'nenhuma linha nova', () async {
      await linha(_acsA, 'patient_directory');
      final antes = await AuditLog.db.count(session);
      for (final f in [
        AdminAuditFilter(),
        AdminAuditFilter(from: DateTime.now().toUtc()),
        AdminAuditFilter(to: DateTime.now().toUtc()),
      ]) {
        await expectLater(
          exportar(f),
          throwsA(isA<AdminInvalidRequestException>()),
        );
      }
      expect(await AuditLog.db.count(session), antes);
      expect(await AuditExport.db.count(session), 0);
    });

    test(
      'recorte acima de maxRows ⇒ refused_limit e AdminInvalidRequestException; '
      'nenhuma exportação',
      () async {
        await linha(_acsA, 'patient_directory');
        // Linhas sintéticas em massa (hash fictício): só a contagem importa.
        await session.db.unsafeExecute(
          '''
          INSERT INTO audit_logs ("userId", "actionType", "resourceType",
            "timestamp", "ipHash", result, sequence, "previousHash", "entryHash")
          SELECT @u::uuid, 'read', 'massa_sintetica', now() at time zone 'utc',
                 'ip', 'success', 1 + g, 'p', 'e'
          FROM generate_series(1, @n) g
          ''',
          parameters: QueryParameters.named({
            'u': _acsA,
            'n': AuditExportService.maxRows,
          }),
        );
        await expectLater(
          exportar(_janela()),
          throwsA(isA<AdminInvalidRequestException>()),
        );
        final recusa = await AuditLog.db.findFirstRow(
          session,
          where: (t) => t.resourceType.equals('admin_audit_export'),
        );
        expect(recusa!.result, 'refused_limit');
        expect(recusa.actionType, 'export');
        expect(await AuditExport.db.count(session), 0);
        expect((await exports()).where((e) => e.result == 'success'), isEmpty);
      },
    );

    test(
      'store: head, contagem limitada a cap e leitura presa a sequence <= head '
      '(linhas gravadas depois do head ficam fora: concorrência)',
      () async {
        for (var i = 0; i < 5; i++) {
          await linha(_acsA, 'patient_directory');
        }
        final store = OrmAuditExportStore(
          session: () => session,
          appendAudit: OrmAuditTrail(
            session: () => session,
            chainSecret: _segredo,
          ).recordInTransaction,
        );
        expect(await store.headSequence(), 5);
        final f = _janela();
        expect(await store.countUpTo(f, headSequence: 3, cap: 100), 3);
        expect(await store.countUpTo(f, headSequence: 5, cap: 2), 2);
        final lidas = await store.readUpTo(f, headSequence: 3, limit: 100);
        expect(lidas.map((l) => l.entry.sequence), [1, 2, 3]);
        expect(lidas.first.actorRole, 'acs');
        expect(lidas.first.actorEnrollmentId, _matriculaAcs);
        final limitadas = await store.readUpTo(f, headSequence: 5, limit: 2);
        // Limite com head: as `limit` mais recentes até o head, em ordem
        // crescente (o serviço só lê depois de a contagem caber no teto).
        expect(limitadas.map((l) => l.entry.sequence), [4, 5]);
      },
    );

    test(
      'falha do apêndice dentro da transação ⇒ rollback: nada em '
      'audit_exports, nenhum export success, nenhum CSV',
      () async {
        await linha(_acsA, 'patient_directory');
        final servico = AuditExportService(
          store: OrmAuditExportStore(
            session: () => session,
            appendAudit: (s, tx, e) async {
              // Grava a linha (a transação já tem o INSERT de audit_exports)
              // e então falha: os dois têm de sumir.
              await OrmAuditTrail(
                session: () => s,
                chainSecret: _segredo,
              ).recordInTransaction(s, tx, e);
              throw StateError('falha simulada depois do apêndice');
            },
          ),
          audit: OrmAuditTrail(session: () => session, chainSecret: _segredo),
          auditChain: AuditChain(secret: _segredo),
          chainState: (_) async => AuditIntegrityState.verified,
        );
        await expectLater(
          servico.export(
            AuthenticatedUser(
              id: _admin,
              role: UserRole.admin,
              microAreaId: null,
              deviceId: 'sem-aparelho',
            ),
            _janela(),
          ),
          throwsA(isA<AuditExportFailedException>()),
        );
        expect(await AuditExport.db.count(session), 0);
        final evs = await exports();
        expect(evs.where((e) => e.result == 'success'), isEmpty);
        final falhas = await AuditLog.db.find(
          session,
          where: (t) => t.resourceType.equals('admin_audit_export'),
        );
        expect(falhas.map((l) => l.result), ['failed']);
        final v = await AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: _segredo,
        ).verify();
        expect(v.ok, isTrue);
      },
    );

    test(
      'resposta perdida depois do commit (Review Focus 8): o evento export e '
      'o registro ficam; nada a desfazer — aceito, erra para auditar a mais',
      () async {
        await linha(_acsA, 'patient_directory');
        // Simula a conexão caindo DEPOIS do commit: o servidor concluiu, o
        // cliente nunca recebe o arquivo.
        Object? perdida;
        try {
          await exportar(_janela());
          throw const SocketException('resposta perdida (simulada)');
        } on SocketException catch (e) {
          perdida = e;
        }
        expect(perdida, isNotNull);
        final evs = await exports();
        expect(evs, hasLength(1));
        expect(evs.single.result, 'success');
        final reg = await AuditExport.db.find(session);
        expect(reg, hasLength(1));
        expect(evs.single.resourceId, reg.single.id);
        // Nenhum mecanismo desfaz: o registro diz "exportado", e o operador
        // pede de novo (outro export, outra linha).
      },
    );
  });
}
