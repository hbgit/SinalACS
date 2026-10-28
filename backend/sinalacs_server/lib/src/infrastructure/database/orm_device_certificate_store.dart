import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart'
    show AuditAppender;

/// Certificados de aparelho e o contador da CRL sobre Postgres (#94).
///
/// As revogações são um `UPDATE … RETURNING` com parâmetros nomeados (nada é
/// concatenado no texto da consulta) e aceitam a transação de quem chama — a
/// limpeza remota e a gestão de contas revogam dentro das próprias transações.
class OrmDeviceCertificateStore implements DeviceCertificateStore {
  OrmDeviceCertificateStore({
    required Session Function() session,
    AuditAppender? appendAudit,
  }) : _session = session,
            _appendAudit = appendAudit;

  final Session Function() _session;

  /// A trilha dentro da transação da emissão (`OrmAuditTrail.recordInTransaction`).
  /// Só [issueReplacing] a usa; sem ela, a emissão é recusada.
  final AuditAppender? _appendAudit;

  /// Primeiro `CRL Number` publicado pelo backend.
  static const firstCrlNumber = 1000;

  static const _colunas =
      'id, "userId", "deviceId", "microAreaId", serial, "fingerprintSha256", '
      '"notBefore", "notAfter", "issuedAt", "revokedAt", "revocationReason"';

  @override
  Future<DeviceCertificate> insert(
    DeviceCertificate c, {
    Transaction? transaction,
  }) => DeviceCertificate.db.insertRow(_session(), c, transaction: transaction);

  @override
  Future<List<DeviceCertificate>> activeFor(String deviceId) =>
      DeviceCertificate.db.find(
        _session(),
        where: (t) => t.deviceId.equals(deviceId) & t.revokedAt.equals(null),
        orderBy: (t) => t.issuedAt,
      );

  @override
  Future<int> issuedSince(String deviceId, DateTime since) =>
      DeviceCertificate.db.count(
        _session(),
        where: (t) =>
            t.deviceId.equals(deviceId) & (t.issuedAt >= since.toUtc()),
      );

  @override
  Future<List<DeviceCertificate>> revoke({
    required String deviceId,
    required DeviceCertRevocationReason reason,
    required DateTime at,
    Transaction? transaction,
  }) => _revogar(
    '"deviceId" = @alvo',
    deviceId,
    reason,
    at,
    transaction,
  );

  @override
  Future<List<DeviceCertificate>> revokeForUser({
    required String userId,
    required DeviceCertRevocationReason reason,
    required DateTime at,
    Transaction? transaction,
  }) async {
    if (!_uuidValido(userId)) return const [];
    return _revogar('"userId" = @alvo::uuid', userId, reason, at, transaction);
  }

  Future<List<DeviceCertificate>> _revogar(
    String predicado,
    String alvo,
    DeviceCertRevocationReason reason,
    DateTime at,
    Transaction? transaction,
  ) async {
    final rows = await _session().db.unsafeQuery(
      'UPDATE device_certificates '
      'SET "revokedAt" = @at, "revocationReason" = @motivo '
      'WHERE $predicado AND "revokedAt" IS NULL '
      'RETURNING $_colunas',
      parameters: QueryParameters.named({
        'at': at.toUtc(),
        'motivo': reason.name,
        'alvo': alvo,
      }),
      transaction: transaction,
    );
    return [for (final r in rows) _linha(r)];
  }

  @override
  Future<List<DeviceCertificate>> revokedWith({
    required DeviceCertRevocationReason reason,
    required DateTime at,
    String? userId,
    String? deviceId,
  }) async {
    if (userId != null && !_uuidValido(userId)) return const [];
    return DeviceCertificate.db.find(
      _session(),
      where: (t) {
        var w =
            t.revocationReason.equals(reason) & t.revokedAt.equals(at.toUtc());
        if (userId != null) {
          w = w & t.userId.equals(UuidValue.fromString(userId));
        }
        if (deviceId != null) w = w & t.deviceId.equals(deviceId);
        return w;
      },
      orderBy: (t) => t.serial,
    );
  }

  @override
  Future<List<DeviceCertificate>> issueReplacing(
    DeviceCertificate certificate, {
    required AuditEvent issuedAudit,
    required AuditEvent Function(DeviceCertificate revoked) revokedAudit,
  }) {
    final appendAudit = _appendAudit;
    if (appendAudit == null) {
      throw StateError('emissão sem trilha de auditoria na transação');
    }
    final session = _session();
    return session.db.transaction((transaction) async {
      final renovados = await revoke(
        deviceId: certificate.deviceId,
        reason: DeviceCertRevocationReason.renewed,
        at: certificate.issuedAt,
        transaction: transaction,
      );
      for (final c in renovados) {
        await appendAudit(session, transaction, revokedAudit(c));
      }
      await insert(certificate, transaction: transaction);
      await appendAudit(session, transaction, issuedAudit);
      return renovados;
    });
  }

  @override
  Future<List<DeviceCertificate>> revokedUnexpired(DateTime now) =>
      DeviceCertificate.db.find(
        _session(),
        where: (t) =>
            t.revokedAt.notEquals(null) & (t.notAfter > now.toUtc()),
        orderBy: (t) => t.serial,
      );

  /// Uma linha só (`id = 1`): o `INSERT … ON CONFLICT DO UPDATE` cria com
  /// [firstCrlNumber] ou incrementa, atômico sob concorrência.
  @override
  Future<BigInt> nextCrlNumber() async {
    final rows = await _session().db.unsafeQuery(
      'INSERT INTO device_crl_counters (id, "lastNumber") VALUES (1, @primeiro) '
      'ON CONFLICT (id) DO UPDATE '
      'SET "lastNumber" = device_crl_counters."lastNumber" + 1 '
      'RETURNING "lastNumber"',
      parameters: QueryParameters.named({'primeiro': firstCrlNumber}),
    );
    return BigInt.from(rows.single[0]! as int);
  }

  static DeviceCertificate _linha(List<Object?> r) => DeviceCertificate(
    id: _uuid(r[0]),
    userId: _uuid(r[1]),
    deviceId: r[2]! as String,
    microAreaId: _uuid(r[3]),
    serial: r[4]! as String,
    fingerprintSha256: r[5]! as String,
    notBefore: (r[6]! as DateTime).toUtc(),
    notAfter: (r[7]! as DateTime).toUtc(),
    issuedAt: (r[8]! as DateTime).toUtc(),
    revokedAt: (r[9] as DateTime?)?.toUtc(),
    revocationReason: r[10] == null
        ? null
        : DeviceCertRevocationReason.fromJson(r[10]! as String),
  );

  /// O driver devolve `uuid` como texto ou valor próprio, conforme o tipo
  /// inferido; os dois viram [UuidValue] pela forma textual.
  static UuidValue _uuid(Object? v) => UuidValue.fromString(v.toString());

  static bool _uuidValido(String id) {
    try {
      UuidValue.withFormatValidation(id);
      return true;
    } on FormatException {
      return false;
    }
  }
}
