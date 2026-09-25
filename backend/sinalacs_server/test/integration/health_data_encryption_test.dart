import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_patient_directory_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_triage_session_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_visit_store.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, a decisão §6 (RNF03, INV-04): os três campos
/// clínicos chegam ao disco CIFRADOS.
///
/// A asserção que sustenta tudo é a leitura por SQL cru
/// (`session.db.unsafeQuery`): passar pelo ORM não provaria nada, porque o
/// store decifra na volta. A coluna bruta é lida como texto e comparada
/// contra cada palavra do texto claro — nenhuma pode aparecer, nem inteira nem
/// como substring.
///
/// Dados sintéticos apenas (LGPD): os termos clínicos abaixo são rótulos de
/// teste, não prontuário de ninguém.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _patientId = '00000000-0000-4000-8000-000000000005';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _localId = '00000000-0000-4000-8000-0000000000b1';

/// Termos que NÃO podem aparecer em lugar nenhum da coluna bruta.
const _condicoes = ['diabetes tipo 2', 'hipertensão arterial'];
const _notaChave = 'observacaoClinica';
const _notaValor = 'paciente relatou tontura ao levantar';

const _acs = AuthenticatedUser(
  id: _acsId,
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

const _paciente = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

class _SilentAuditTrail extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final agora = DateTime.utc(2026, 1, 1);
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient-05',
      name: 'Fulano de Tal',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: agora,
      updatedAt: agora,
    ),
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: agora,
      updatedAt: agora,
    ),
  ]);
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: true,
      chronicConditions: _condicoes,
    ),
  );
}

/// Lê a coluna como texto puro, sem passar pelo ORM — é o que garante que a
/// asserção olha para o BYTE gravado, e não para o valor já decifrado.
Future<String> _colunaBruta(
  Session session, {
  required String table,
  required String column,
}) async {
  final rows = await session.db.unsafeQuery('SELECT "$column"::text FROM "$table";');
  expect(rows, hasLength(1), reason: 'o seed deve ter gravado exatamente 1 linha');
  return rows.single.first.toString();
}

/// Falha se QUALQUER palavra do texto claro aparecer na coluna bruta.
///
/// Comparar a string inteira seria fraco demais: um JSON parcialmente cifrado,
/// ou um escape diferente, ainda deixaria `diabetes` legível para quem tem
/// acesso direto ao Postgres — que é exatamente a ameaça que RNF03 endereça.
///
/// A checagem roda DUAS vezes: na coluna como está e nos bytes que ela
/// decodifica. Sem a segunda, um valor apenas codificado em base64 — que não é
/// cifragem nenhuma, só ofuscação reversível por qualquer um — passaria, já
/// que o base64 de `diabetes` também não contém a substring `diabetes`.
void expectSemTextoClaro(String bruto, List<String> textosClaros) {
  final superficies = <String>[bruto.toLowerCase()];
  try {
    superficies.add(
      String.fromCharCodes(base64.decode(bruto)).toLowerCase(),
    );
  } on FormatException {
    fail('a coluna deveria guardar base64 (nonce+ciphertext+tag); veio: $bruto');
  }

  for (final texto in textosClaros) {
    for (final palavra in texto.toLowerCase().split(' ')) {
      if (palavra.length < 4) continue; // 'de', 'ao' etc. não identificam nada.
      for (final superficie in superficies) {
        expect(
          superficie.contains(palavra),
          isFalse,
          reason: 'nem a coluna bruta nem os bytes decodificados podem conter '
              '"$palavra"; valor: $bruto',
        );
      }
    }
  }
}

void main() {
  withServerpod('Dado os campos clínicos cifrados em repouso',
      (sessionBuilder, endpoints) {
    test('patients.chronicConditionsEncrypted não guarda o texto claro, e o '
        'store devolve as condições intactas', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final bruto = await _colunaBruta(
        session,
        table: 'patients',
        column: 'chronicConditionsEncrypted',
      );
      expect(bruto, isNotEmpty);
      expectSemTextoClaro(bruto, _condicoes);

      final versao = await _colunaBruta(
        session,
        table: 'patients',
        column: 'chronicConditionsKeyVersion',
      );
      expect(versao, '1');

      // Ida e volta: o que o ACS lê continua sendo o texto claro original.
      final store = OrmPatientDirectoryStore(
        session: () => session,
        cipher: testHealthDataCipher(),
      );
      final entries = await store.listByMicroArea(_microAreaId);
      expect(entries, hasLength(1));
      expect(entries.single.chronicConditions, _condicoes);
    });

    test('triage_sessions.answersEncrypted não guarda as respostas em claro, e '
        'a triagem volta legível', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(
          session: () => session,
          cipher: testHealthDataCipher(),
        ),
        audit: _SilentAuditTrail(),
      );

      final risco = await service.evaluateAndRecord(
        user: _paciente,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      expect(risco, RiskLevel.red);

      final bruto = await _colunaBruta(
        session,
        table: 'triage_sessions',
        column: 'answersEncrypted',
      );
      expect(bruto, isNotEmpty);
      // Os nomes das perguntas e as respostas são o conteúdo clínico aqui.
      expectSemTextoClaro(bruto, const [
        'chestPain',
        'difficultyBreathing',
        'persistentVomiting',
        'severeWeakness',
        'question',
        'answer',
      ]);

      final versao = await _colunaBruta(
        session,
        table: 'triage_sessions',
        column: 'answersKeyVersion',
      );
      expect(versao, '1');

      // Ida e volta pela cifra: as seis respostas continuam lá.
      final gravada = await TriageSession.db.findFirstRow(session);
      final respostas = await decryptedTriageAnswers(gravada!);
      expect(respostas, hasLength(6));
      expect(
        {for (final r in respostas) r.question: r.answer}['chestPain'],
        'sim',
      );
    });

    test('visits.notesEncrypted não guarda as notas em claro, e o pull do ACS '
        'as devolve legíveis', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final relogio = DateTime.utc(2026, 9, 17, 12);
      final store = OrmVisitStore(
        session: () => session,
        cipher: testHealthDataCipher(),
      );
      final service = VisitSyncService(
        store: store,
        audit: _SilentAuditTrail(),
        clock: () => relogio,
      );

      final results = await service.sync(
        user: _acs,
        entries: [
          VisitSyncEntry(
            localId: _localId,
            patientId: _patientId,
            scheduledAt: DateTime.utc(2026, 9, 17, 9),
            completedAt: DateTime.utc(2026, 9, 17, 10),
            status: 'realizada',
            riskLevelBefore: RiskLevel.yellow,
            riskLevelAfter: RiskLevel.green,
            notes: const {_notaChave: _notaValor},
            version: 1,
            arrivalMethod: ArrivalMethod.manual,
          ),
        ],
      );
      expect(results.single.syncStatus, SyncStatus.synced);

      final bruto = await _colunaBruta(
        session,
        table: 'visits',
        column: 'notesEncrypted',
      );
      expect(bruto, isNotEmpty);
      expectSemTextoClaro(bruto, const [_notaValor, _notaChave]);

      final versao = await _colunaBruta(
        session,
        table: 'visits',
        column: 'notesKeyVersion',
      );
      expect(versao, '1');

      // Ida e volta pelo caminho real do app do ACS (`visits.pull`).
      final puxadas = await service.pull(
        user: _acs,
        since: relogio.subtract(const Duration(days: 1)),
      );
      expect(puxadas, hasLength(1));
      expect(puxadas.single.notes, const {_notaChave: _notaValor});
    });
  });
}
