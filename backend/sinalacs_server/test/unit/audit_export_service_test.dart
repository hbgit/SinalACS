import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/admin/audit_export_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_csv.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// `AuditExportService` (#45, Task 10; D5–D8) sem banco: papel (só admin),
/// período obrigatório, teto de linhas, ordem fixa
/// autoriza → valida → head → conta → lê → gera → transação → devolve, e a
/// transação que falha não devolve CSV nem deixa `audit_exports`.
/// Dados sintéticos.
const _segredo = 'segredo-sintetico-da-exportacao';
const _admin = '00000000-0000-4000-8000-00000000a001';
const _pacienteRecurso = '00000000-0000-4000-8000-0000000b18f0';
const _exportId = '00000000-0000-4000-8000-00000000e001';

final _agora = DateTime.utc(2026, 10, 13, 15, 30);
final _de = DateTime.utc(2026, 10, 1);
final _ate = DateTime.utc(2026, 10, 13);

AdminAuditFilter _filtro({DateTime? from, DateTime? to, String? result}) =>
    AdminAuditFilter(from: from ?? _de, to: to ?? _ate, result: result);

AuthenticatedUser _user(UserRole role, {String id = _admin}) =>
    AuthenticatedUser(
      id: id,
      role: role,
      microAreaId: role == UserRole.acs || role == UserRole.patient
          ? 'ma-1'
          : null,
      deviceId: 'sem-aparelho',
    );

/// Cadeia sintética e íntegra de [n] linhas, com o vizinho certo em cada uma.
List<AdminAuditRow> _cadeia(int n) {
  final chain = AuditChain(secret: _segredo);
  final linhas = <AdminAuditRow>[];
  var anterior = AuditChain.genesisHash;
  for (var seq = 1; seq <= n; seq++) {
    final campos = AuditChainFields(
      sequence: seq,
      previousHash: anterior,
      userId: seq.isEven ? _admin : '00000000-0000-4000-8000-0000000c0a7e',
      actionType: 'read',
      resourceType: seq == 2 ? 'patient_directory' : 'admin_audit_logs',
      resourceId: seq == 2 ? _pacienteRecurso : null,
      timestamp: DateTime.utc(2026, 10, 5, 10, seq),
      ipHash: 'ip-sintetico-$seq',
      result: 'success',
    );
    final hash = chain.computeEntryHash(campos);
    linhas.add(
      AdminAuditRow(
        entry: AdminAuditEntry(
          id: 'id-$seq',
          sequence: seq,
          userLabel: 'rotulo-da-tela',
          actionType: campos.actionType,
          resourceType: campos.resourceType,
          timestamp: campos.timestamp,
          result: campos.result,
        ),
        seal: AuditSealInput(
          row: AuditChainEntry(fields: campos, entryHash: hash),
          previousEntryHash: seq == 1 ? null : anterior,
        ),
        actorRole: seq.isEven ? 'admin' : 'patient',
        actorEnrollmentId: seq.isEven ? 'ADM-EXP-1' : null,
      ),
    );
    anterior = hash;
  }
  return linhas;
}

final _ordem = <String>[];

class _Audit extends AuditTrail {
  final eventos = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    _ordem.add('audit:${event.result}');
    if (falhar) throw StateError('trilha fora do ar');
    eventos.add(event);
  }
}

/// Store transacional falso: `commitExport` só "comita" (`exports` e
/// `eventosDaTransacao`) se o apêndice da auditoria dentro da transação passa.
class _Store implements AuditExportStore {
  _Store(this.linhas);

  final List<AdminAuditRow> linhas;
  int head = 0;
  int leituras = 0;
  bool falharLeitura = false;
  bool falharApendiceNaTransacao = false;
  int? contagemForcada;
  int? headPedido;

  final exports = <AuditExport>[];
  final eventosDaTransacao = <AuditEvent>[];

  @override
  Future<String?> ubsOf(String staffId) async => null;

  @override
  Future<int> headSequence() async {
    leituras++;
    _ordem.add('store:head');
    return head;
  }

  @override
  Future<int> countUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int cap,
  }) async {
    leituras++;
    _ordem.add('store:count');
    headPedido = headSequence;
    final n =
        contagemForcada ??
        linhas.where((l) => l.entry.sequence <= headSequence).length;
    return n > cap ? cap : n;
  }

  @override
  Future<List<AdminAuditRow>> readUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int limit,
  }) async {
    leituras++;
    _ordem.add('store:read');
    if (falharLeitura) {
      throw Exception('relation "audit_logs" texto-do-banco-secreto');
    }
    return linhas
        .where((l) => l.entry.sequence <= headSequence)
        .take(limit)
        .toList();
  }

  @override
  Future<void> commitExport(AuditExport registro, AuditEvent evento) async {
    _ordem.add('tx:export+audit');
    // Transação: os dois entram juntos ou nenhum.
    final pendenteExport = registro;
    if (falharApendiceNaTransacao) {
      throw StateError('falha no apêndice da cadeia');
    }
    exports.add(pendenteExport);
    eventosDaTransacao.add(evento);
  }
}

void main() {
  late _Audit audit;
  late _Store store;
  var estadoDaCadeia = AuditIntegrityState.verified;
  final falhasLogadas = <Object>[];
  final pedidosDeEstado = <DateTime>[];

  AuditExportService servico() => AuditExportService(
    store: store,
    audit: audit,
    auditChain: AuditChain(secret: _segredo),
    chainState: (notBefore) async {
      _ordem.add('chain:state');
      pedidosDeEstado.add(notBefore);
      return estadoDaCadeia;
    },
    clock: () => _agora,
    newId: () => _exportId,
    onFailure: falhasLogadas.add,
  );

  setUp(() {
    _ordem.clear();
    falhasLogadas.clear();
    pedidosDeEstado.clear();
    audit = _Audit();
    store = _Store(_cadeia(4))..head = 4;
    estadoDaCadeia = AuditIntegrityState.verified;
  });

  group('papel: só admin exporta', () {
    for (final role in [UserRole.acs, UserRole.patient, UserRole.coordinator]) {
      test(
        '$role ⇒ AlertPermissionException + denied, nenhuma leitura',
        () async {
          await expectLater(
            servico().export(_user(role, id: 'u-${role.name}'), _filtro()),
            throwsA(isA<AlertPermissionException>()),
          );
          expect(store.leituras, 0);
          expect(store.exports, isEmpty);
          expect(_ordem, ['audit:denied']);
          final e = audit.eventos.single;
          expect(e.actionType, 'export');
          expect(e.resourceType, 'admin_audit_export');
          expect(e.result, 'denied');
          expect(e.userId, 'u-${role.name}');
        },
      );
    }
  });

  group('filtro: período obrigatório, sem auditar', () {
    final invalidos = <String, AdminAuditFilter?>{
      'nulo': null,
      'sem from': AdminAuditFilter(to: _ate),
      'sem to': AdminAuditFilter(from: _de),
      'sem período': AdminAuditFilter(result: 'success'),
      'from == to': _filtro(from: _ate, to: _ate),
      'from > to': _filtro(from: _ate, to: _de),
      'janela > 366 d': _filtro(
        from: _de,
        to: _de.add(const Duration(days: 367)),
      ),
      'result inválido': _filtro(result: 'X;DROP'),
    };
    invalidos.forEach((nome, f) {
      test(
        '$nome ⇒ AdminInvalidRequestException, sem auditoria/leitura',
        () async {
          await expectLater(
            servico().export(_user(UserRole.admin), f),
            throwsA(isA<AdminInvalidRequestException>()),
          );
          expect(audit.eventos, isEmpty);
          expect(store.leituras, 0);
        },
      );
    });

    test('janela de exatamente 366 dias é aceita', () async {
      final r = await servico().export(
        _user(UserRole.admin),
        _filtro(from: _de, to: _de.add(const Duration(days: 366))),
      );
      expect(r.rowCount, 4);
    });
  });

  test(
    'recorte > maxRows ⇒ refused_limit e AdminInvalidRequestException; '
    'nada lido nem gerado',
    () async {
      store.contagemForcada = AuditExportService.maxRows + 1;
      await expectLater(
        servico().export(_user(UserRole.admin), _filtro()),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(_ordem, ['store:head', 'store:count', 'audit:refused_limit']);
      expect(store.exports, isEmpty);
      final e = audit.eventos.single;
      expect(e.actionType, 'export');
      expect(e.resourceType, 'admin_audit_export');
      expect(e.result, 'refused_limit');
    },
  );

  test('recorte == maxRows é aceito (o teto é inclusivo)', () async {
    store.contagemForcada = AuditExportService.maxRows;
    final r = await servico().export(_user(UserRole.admin), _filtro());
    expect(r.rowCount, 4);
  });

  test(
    'admin: ordem fixa head/count/read/chain/tx e resposta coerente',
    () async {
      final r = await servico().export(_user(UserRole.admin), _filtro());

      expect(_ordem, [
        'store:head',
        'store:count',
        'store:read',
        'chain:state',
        'tx:export+audit',
      ]);
      // O estado da cadeia é pedido FRESCO: verificação iniciada a partir do
      // início desta exportação, nunca um retrato anterior a ela.
      expect(pedidosDeEstado, [_agora]);
      // Sem linha de auditoria FORA da transação no caminho feliz.
      expect(audit.eventos, isEmpty);
      expect(store.headPedido, 4);

      expect(r.rowCount, 4);
      expect(r.firstSequence, 1);
      expect(r.lastSequence, 4);
      expect(r.contentSha256, sha256.convert(utf8.encode(r.csv)).toString());
      expect(r.chainState, AuditIntegrityState.verified);
      expect(r.generatedAt, _agora);
      expect(r.fileName, 'auditoria_20261001T000000Z_20261013T000000Z.csv');

      // CSV: cabeçalho fixo, ordem crescente, rótulos minimizados, selo.
      final linhas = r.csv.split('\r\n');
      expect(linhas.first, AuditCsv.columns.join(','));
      expect(linhas[1], startsWith('1,'));
      expect(linhas[4], startsWith('4,'));
      expect(linhas[1], contains(',Paciente #0A7E,patient,'));
      expect(linhas[2], contains(',ADM-EXP-1,admin,'));
      expect(linhas[2], contains(',patient_directory,#18F0,success,verified'));
      expect(linhas[1], endsWith(',admin_audit_logs,,success,verified'));
      expect(r.csv, isNot(contains(_pacienteRecurso)));
      expect(r.csv, isNot(contains('ip-sintetico')));
      expect(r.csv, isNot(contains(_admin)));
      expect(r.csv, isNot(contains('rotulo-da-tela')));

      // audit_exports e evento, na MESMA transação, ligados pelo id.
      final x = store.exports.single;
      final e = store.eventosDaTransacao.single;
      expect(x.id!.uuid, _exportId);
      expect(e.resourceId, _exportId);
      expect(e.actionType, 'export');
      expect(e.resourceType, 'admin_audit_logs');
      expect(e.result, 'success');
      expect(e.userId, _admin);
      expect(x.requestedBy.uuid, _admin);
      expect(x.requestedAt, _agora);
      expect(x.format, 'csv');
      expect(x.rowCount, 4);
      expect(x.firstSequence, 1);
      expect(x.lastSequence, 4);
      expect(x.contentSha256, r.contentSha256);
      expect(x.chainState, 'verified');

      // filtersJson: só o filtro.
      final f = jsonDecode(x.filtersJson) as Map<String, dynamic>;
      expect(f.keys.toSet(), {'from', 'to'});
      expect(x.filtersJson, isNot(contains('success')));
      expect(x.filtersJson, isNot(contains('ADM-EXP-1')));
    },
  );

  test('seleciona o vizinho: linha adulterada sai com selo invalid', () async {
    final linhas = _cadeia(3);
    final orig = linhas[1].seal.row;
    final campos = orig.fields;
    linhas[1] = AdminAuditRow(
      entry: linhas[1].entry,
      seal: AuditSealInput(
        row: AuditChainEntry(
          fields: AuditChainFields(
            sequence: campos.sequence,
            previousHash: campos.previousHash,
            userId: campos.userId,
            actionType: campos.actionType,
            resourceType: campos.resourceType,
            resourceId: campos.resourceId,
            timestamp: campos.timestamp,
            ipHash: campos.ipHash,
            result: 'adulterado',
          ),
          entryHash: orig.entryHash,
        ),
        previousEntryHash: linhas[1].seal.previousEntryHash,
      ),
      actorRole: linhas[1].actorRole,
      actorEnrollmentId: linhas[1].actorEnrollmentId,
    );
    store = _Store(linhas)..head = 3;
    final r = await servico().export(_user(UserRole.admin), _filtro());
    final csv = r.csv.split('\r\n');
    expect(csv[1], endsWith(',verified'));
    expect(csv[2], endsWith(',invalid'));
  });

  test('recorte vazio: CSV só com cabeçalho, sequences nulas, exportação '
      'registrada', () async {
    store = _Store(const [])..head = 7;
    final r = await servico().export(_user(UserRole.admin), _filtro());
    expect(r.rowCount, 0);
    expect(r.firstSequence, isNull);
    expect(r.lastSequence, isNull);
    expect(r.csv, '${AuditCsv.columns.join(',')}\r\n');
    expect(store.exports.single.rowCount, 0);
    expect(store.eventosDaTransacao, hasLength(1));
  });

  test(
    'estado da cadeia ≠ verified é registrado e devolvido como está',
    () async {
      for (final estado in [
        AuditIntegrityState.broken,
        AuditIntegrityState.unavailable,
        AuditIntegrityState.inconclusive,
      ]) {
        estadoDaCadeia = estado;
        store = _Store(_cadeia(2))..head = 2;
        final r = await servico().export(_user(UserRole.admin), _filtro());
        expect(r.chainState, estado);
        expect(store.exports.single.chainState, estado.name);
      }
    },
  );

  test(
    'falha do apêndice DENTRO da transação ⇒ nenhum CSV devolvido, nada em '
    'audit_exports, failed registrado e exceção genérica',
    () async {
      store.falharApendiceNaTransacao = true;
      Object? erro;
      AdminAuditExport? r;
      try {
        r = await servico().export(_user(UserRole.admin), _filtro());
      } catch (e) {
        erro = e;
      }
      expect(r, isNull);
      expect(store.exports, isEmpty);
      expect(store.eventosDaTransacao, isEmpty);
      expect(erro, isA<AuditExportFailedException>());
      expect(
        (erro! as AuditExportFailedException).message,
        AuditExportFailedException.mensagem,
      );
      expect(_ordem.last, 'audit:failed');
      expect(audit.eventos.single.result, 'failed');
      expect(audit.eventos.single.resourceType, 'admin_audit_export');
      expect(falhasLogadas, hasLength(1));
    },
  );

  test(
    'falha de leitura ⇒ failed fora da transação, mensagem fixa sem texto do '
    'banco, sem transação',
    () async {
      store.falharLeitura = true;
      await expectLater(
        servico().export(_user(UserRole.admin), _filtro()),
        throwsA(
          isA<AuditExportFailedException>()
              .having(
                (e) => e.message,
                'message',
                AuditExportFailedException.mensagem,
              )
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('texto-do-banco')),
              ),
        ),
      );
      expect(_ordem, [
        'store:head',
        'store:count',
        'store:read',
        'audit:failed',
      ]);
      expect(store.exports, isEmpty);
      expect(audit.eventos.single.actionType, 'export');
    },
  );

  test('falha de leitura com a trilha também fora do ar ⇒ ainda a exceção '
      'genérica (nunca o texto do banco)', () async {
    store.falharLeitura = true;
    audit.falhar = true;
    await expectLater(
      servico().export(_user(UserRole.admin), _filtro()),
      throwsA(isA<AuditExportFailedException>()),
    );
    expect(store.exports, isEmpty);
  });

  test(
    'trilha fora do ar na recusa de papel ⇒ exceção sobe, nada lido',
    () async {
      audit.falhar = true;
      await expectLater(
        servico().export(_user(UserRole.coordinator), _filtro()),
        throwsA(isA<StateError>()),
      );
      expect(store.leituras, 0);
    },
  );

  test('a resposta não carrega hash, ipHash nem segredo', () async {
    final r = await servico().export(_user(UserRole.admin), _filtro());
    final texto = jsonEncode(r.toJson());
    expect(texto, isNot(contains(_segredo)));
    expect(texto, isNot(contains('ip-sintetico')));
    for (final l in store.linhas) {
      expect(texto, isNot(contains(l.seal.row.entryHash)));
    }
  });
}
