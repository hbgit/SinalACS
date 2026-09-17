import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Ajudantes para os testes que precisam SEMEAR linhas cifradas.
///
/// `patients.chronicConditions` virou `chronicConditionsEncrypted` (Track E,
/// RNF03/INV-04), e não existe caminho Dart de produção que escreva essa
/// coluna — só leitura. Os testes de integração, porém, precisam montar o
/// prontuário de partida, e é isso que estas funções fazem: cifram com a
/// MESMA chave de desenvolvimento que o `AlertRuntime` usa nos testes, para
/// que o store consiga decifrar de volta.
///
/// Nunca dado real de paciente aqui — só rótulos sintéticos (regra do
/// repositório, LGPD).
HealthDataCipher testHealthDataCipher() => HealthDataCipher(
      keyHex: AppConfig.developmentHealthDataEncryptionKey,
      keyVersion: 1,
    );

/// Um `Patient` pronto para `insertRow`, com as condições crônicas já
/// cifradas.
Future<Patient> encryptedPatient({
  required String id,
  required String emergencyContact,
  required bool isChronic,
  List<String> chronicConditions = const [],
}) async {
  final encrypted = await testHealthDataCipher().encryptJson(chronicConditions);
  return Patient(
    id: UuidValue.fromString(id),
    emergencyContact: emergencyContact,
    isChronic: isChronic,
    chronicConditionsEncrypted: encrypted.ciphertextBase64,
    chronicConditionsKeyVersion: encrypted.keyVersion,
  );
}

/// Cifra um mapa de notas de visita, devolvendo o par que a coluna guarda.
Future<EncryptedValue> encryptedVisitNotes(Map<String, String> notes) =>
    testHealthDataCipher().encryptJson(notes);

/// Decifra as respostas de uma sessão de triagem lida pelo ORM.
///
/// Não existe caminho de LEITURA de triagem em produção (nenhum endpoint
/// devolve o prontuário da triagem ainda), então este ajudante vive no teste —
/// não em `infrastructure/` — para não criar uma API de produção que ninguém
/// chama.
Future<List<TriageAnswer>> decryptedTriageAnswers(TriageSession session) async {
  final decoded = await testHealthDataCipher()
      .decryptJson(session.answersEncrypted, session.answersKeyVersion);
  if (decoded == null) return const [];
  return [
    for (final json in decoded as List)
      TriageAnswer.fromJson(json as Map<String, dynamic>),
  ];
}
