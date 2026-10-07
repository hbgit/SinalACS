import 'dart:convert';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';

/// Fakes compartilhados pelos testes unitários do login institucional com MFA
/// (`institutional_auth_mfa_test.dart` e `institutional_auth_staff_test.dart`).
///
/// Cofre de teste: base64 reversível. Quem prova a cifra real é
/// `health_data_cipher_test.dart`.
class FakeTotpVault implements TotpSecretVault {
  @override
  Future<SealedSecret> seal(Uint8List secret) async =>
      SealedSecret(ciphertextBase64: base64Encode(secret), keyVersion: 1);

  @override
  Future<Uint8List> open(SealedSecret sealed) async => base64Decode(sealed.ciphertextBase64);
}

/// Store em memória de uma única credencial, encontrada pela [matricula].
class FakeCredentialStore implements AcsCredentialStore, TotpStore {
  FakeCredentialStore(this.record, {this.matricula = 'ACS-001'});

  AcsCredentialRecord record;
  final String matricula;
  int enabledCalls = 0;
  int? lastRegisteredStep;
  int successfulLogins = 0;

  /// Simula a requisição concorrente que gravou antes: o `UPDATE` condicional
  /// do store real não altera linha nenhuma e devolve `false`.
  bool perdeCorrida = false;

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async =>
      enrollmentId == matricula ? record : null;

  @override
  Future<void> registerFailedAttempt(String acsId,
      {required bool restartCounter,
      required int maxFailedAttempts,
      required DateTime lockUntil,
      required DateTime at}) async {
    final anterior = record.failedAttempts;
    final proximo = restartCounter ? 1 : anterior + 1;
    record = _copia(failedAttempts: proximo, lockedUntil: proximo >= maxFailedAttempts ? lockUntil : null);
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    successfulLogins++;
    record = _copia(failedAttempts: 0, lockedUntil: null);
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {}

  @override
  Future<bool> saveSecret(String acsId, SealedSecret s, DateTime at) async {
    if (perdeCorrida) return false;
    record = _copia(totp: TotpEnrollment(sealed: s, enabled: false, lastStep: null));
    return true;
  }

  @override
  Future<bool> enable(String acsId, SealedSecret pending, int step, DateTime at) async {
    if (perdeCorrida) return false;
    enabledCalls++;
    final t = record.totp!;
    record = _copia(totp: TotpEnrollment(sealed: t.sealed, enabled: true, lastStep: step));
    return true;
  }

  @override
  Future<bool> registerStep(String acsId, int step) async {
    if (perdeCorrida) return false;
    lastRegisteredStep = step;
    final t = record.totp!;
    record = _copia(totp: TotpEnrollment(sealed: t.sealed, enabled: t.enabled, lastStep: step));
    return true;
  }

  /// Copia a linha preservando papel e sequência de bloqueios: um fake que
  /// perdesse o papel faria uma conta de staff "virar" ACS no meio do teste.
  AcsCredentialRecord _copia({int? failedAttempts, DateTime? lockedUntil, TotpEnrollment? totp}) =>
      AcsCredentialRecord(
        acsId: record.acsId,
        microAreaId: record.microAreaId,
        active: record.active,
        role: record.role,
        digest: record.digest,
        failedAttempts: failedAttempts ?? record.failedAttempts,
        lockedUntil: failedAttempts != null ? lockedUntil : record.lockedUntil,
        lockStreak: record.lockStreak,
        totp: totp ?? record.totp,
      );
}

/// Trilha que guarda os eventos, para o teste conferir o desfecho auditado.
class RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  List<String> get results => [for (final e in events) e.result];

  List<String> get resourceTypes => [for (final e in events) e.resourceType];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}
