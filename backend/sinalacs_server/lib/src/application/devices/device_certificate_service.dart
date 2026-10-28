import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart' show Transaction, UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/pki/openssl_device_ca.dart';

/// O que a CRL dos aparelhos lê do banco (#94): as revogadas ainda não
/// vencidas e o próximo número da extensão `CRL Number`.
abstract interface class DeviceCrlSource {
  /// Certificados revogados cujo `notAfter` ainda não passou de [now]. Um
  /// vencido não precisa estar na CRL: o broker já o recusa pela validade.
  Future<List<DeviceCertificate>> revokedUnexpired(DateTime now);

  /// O próximo `CRL Number`, persistido e estritamente crescente; o primeiro é
  /// 1000 (acima do `01` da CRL inicial do `init.sh`).
  Future<BigInt> nextCrlNumber();
}

/// Certificados de aparelho sobre o banco (#94). Interface à parte do ORM, no
/// espírito de `DeviceWipeStore`.
///
/// As revogações devolvem as linhas revogadas (a serial vai para a trilha e o
/// `deviceId`/`userId` para a derrubada de sessão), e aceitam a [Transaction]
/// de quem chama para valerem junto com a mudança que as motivou.
abstract interface class DeviceCertificateStore implements DeviceCrlSource {
  Future<DeviceCertificate> insert(
    DeviceCertificate c, {
    Transaction? transaction,
  });

  /// Os certificados vigentes (não revogados) do aparelho.
  Future<List<DeviceCertificate>> activeFor(String deviceId);

  /// Quantas emissões o aparelho teve desde [since] (para o limite por hora).
  Future<int> issuedSince(String deviceId, DateTime since);

  /// Revoga os vigentes do aparelho, carimbando [at] e [reason].
  Future<List<DeviceCertificate>> revoke({
    required String deviceId,
    required DeviceCertRevocationReason reason,
    required DateTime at,
    Transaction? transaction,
  });

  /// Revoga os vigentes de todos os aparelhos do ACS [userId].
  Future<List<DeviceCertificate>> revokeForUser({
    required String userId,
    required DeviceCertRevocationReason reason,
    required DateTime at,
    Transaction? transaction,
  });

  /// As linhas revogadas com exatamente este [reason] e este carimbo [at] —
  /// as de UMA chamada, porque o carimbo é o instante (em microssegundos) que
  /// a própria chamada escolheu. É como a gestão de contas descobre, depois do
  /// commit, o que a transação dela revogou, sem que o `AdminAccountStore`
  /// precise devolvê-lo.
  Future<List<DeviceCertificate>> revokedWith({
    required DeviceCertRevocationReason reason,
    required DateTime at,
    String? userId,
    String? deviceId,
  });

  /// Revoga os vigentes do aparelho como `renewed`, insere [certificate] e
  /// grava as linhas de auditoria — tudo numa **única transação**: não existe
  /// instante com dois certificados vigentes no aparelho, nem um certificado
  /// sem a linha `device_cert_issued`.
  Future<List<DeviceCertificate>> issueReplacing(
    DeviceCertificate certificate, {
    required AuditEvent issuedAudit,
    required AuditEvent Function(DeviceCertificate revoked) revokedAudit,
  });
}

/// Publicação da CRL depois de uma revogação. Implementada por
/// `DeviceCrlPublisher`; nunca lança (uma falha agenda nova tentativa).
abstract interface class CrlPublication {
  Future<void> publish({DateTime? now});
}

/// Derrubada da sessão MQTT aberta de um client id. Implementada por
/// `MqttSessionKicker`; melhor esforço, nunca lança.
abstract interface class SessionKicker {
  Future<void> kick(String clientId, {Duration timeout});
}

/// Client id MQTT do aparelho do ACS (#94). **O app usa a mesma string**
/// (`deviceClientId` em `apps/acs`), e o teste de lá fixa a igualdade.
String deviceMqttClientId({required String acsId, required String deviceId}) =>
    'sinalacs-acs-$acsId-$deviceId';

/// O resultado de auditoria de uma revogação: `device_cert_revoked:<motivo>`,
/// com o motivo em snake_case (o filtro da Auditoria aceita `[a-z0-9_:]`).
String deviceCertRevokedResult(DeviceCertRevocationReason reason) =>
    'device_cert_revoked:${switch (reason) {
      DeviceCertRevocationReason.wipe => 'wipe',
      DeviceCertRevocationReason.deactivated => 'deactivated',
      DeviceCertRevocationReason.microAreaChanged => 'micro_area_changed',
      DeviceCertRevocationReason.renewed => 'renewed',
    }}';

/// A linha `device_certificate` da trilha para [certificate].
AuditEvent deviceCertAudit(
  DeviceCertificate certificate, {
  required String actorId,
  required String result,
}) => AuditEvent(
  userId: actorId,
  actionType: 'write',
  resourceType: 'device_certificate',
  resourceId: DeviceCertificateService.serialAsResourceId(certificate.serial),
  result: result,
);

/// O que vem depois do commit de uma revogação (#94): auditar (quando a
/// transação não o fez), publicar a CRL e derrubar a sessão MQTT de cada
/// aparelho revogado.
///
/// A CRL é o corte duro, mas só vale no PRÓXIMO handshake (I2): a sessão já
/// aberta seguiria recebendo — inclusive o território antigo, na troca de
/// microárea — até cair sozinha. Daí a derrubada.
class DeviceRevocationEffects {
  DeviceRevocationEffects({
    required this.store,
    required this.crl,
    required this.kicker,
  });

  final DeviceCertificateStore store;
  final CrlPublication? crl;
  final SessionKicker? kicker;

  /// Lê o que a chamada revogou ([reason] + [at]), publica a CRL, derruba as
  /// sessões e então audita cada um com [audit], quando dado. Sem nada
  /// revogado, não faz nada.
  Future<List<DeviceCertificate>> afterCommit({
    required DeviceCertRevocationReason reason,
    required DateTime at,
    String? userId,
    String? deviceId,
    ({AuditTrail trail, String actorId})? audit,
  }) async {
    final revogados = await store.revokedWith(
      reason: reason,
      at: at,
      userId: userId,
      deviceId: deviceId,
    );
    if (revogados.isEmpty) return revogados;
    // CRL e derrubada antes da trilha: a revogação já foi confirmada, e uma
    // falha da auditoria (que sobe, fail-closed) não pode deixar o aparelho
    // revogado conectado nem a CRL sem a serial.
    await crl?.publish();
    final ids = {
      for (final c in revogados)
        deviceMqttClientId(acsId: c.userId.toString(), deviceId: c.deviceId),
    };
    final k = kicker;
    if (k != null) {
      await Future.wait([for (final id in ids) k.kick(id)]);
    }
    if (audit != null) {
      for (final c in revogados) {
        await audit.trail.record(
          deviceCertAudit(
            c,
            actorId: audit.actorId,
            result: deviceCertRevokedResult(reason),
          ),
        );
      }
    }
    return revogados;
  }
}

/// Emissão do certificado de cliente MQTT do aparelho do ACS (#94).
///
/// O aparelho manda um CSR com chave EC P-256 gerada nele (a chave nunca sai
/// do aparelho); o backend confere a política e assina com a CA de aparelhos.
/// O CN é a microárea do token (o ACL do broker deriva o tópico dela) e os SANs
/// identificam o aparelho e o ACS.
///
/// Recusas: [StateError] para quem não pode pedir (papel ≠ `acs`, sem
/// microárea, token sem aparelho, aparelho com pedido de limpeza, CA não
/// configurada) e [ArgumentError] para um pedido malformado (CSR inválido,
/// chave fora de EC prime256v1, CN ≠ microárea do token, mais de
/// [maxIssuesPerHour] emissões do aparelho na última hora).
class DeviceCertificateService {
  DeviceCertificateService({
    required this.store,
    required this.ca,
    required this.certDays,
    required this.ensureDeviceNotMarked,
    this.crl,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final DeviceCertificateStore store;

  /// `null` = o ambiente não tem CA de aparelhos (Render): a emissão é recusada
  /// com [unavailableMessage].
  final OpensslDeviceCa? ca;
  final int certDays;

  /// `DeviceWipeService.ensureDeviceNotMarked`: lança
  /// `DeviceWipeRequiredException` para um aparelho com pedido de limpeza.
  final Future<void> Function(String? deviceId) ensureDeviceNotMarked;

  final CrlPublication? crl;
  final DateTime Function() _clock;
  final Random _random;

  static const unavailableMessage =
      'emissão de certificado indisponível neste ambiente';
  static const maxIssuesPerHour = 5;

  /// A serial (32 dígitos hex) no formato de UUID, para `audit_logs.resourceId`
  /// (coluna `uuid`): são os mesmos 128 bits, só com os hífens. Vale porque a
  /// serial nasce com os bits de um UUID v4 (ver [_novaSerial]).
  static String serialAsResourceId(String serial) {
    final h = serial.toLowerCase().padLeft(32, '0');
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<DeviceCertificateIssueResult> issue(
    AuthenticatedUser user,
    String csrPem, {
    DateTime? now,
  }) async {
    if (user.role != UserRole.acs) {
      throw StateError('somente o ACS pede certificado de aparelho');
    }
    final microArea = user.microAreaId;
    if (microArea == null) {
      throw StateError('ACS sem microárea vinculada');
    }
    final deviceId = user.deviceId;
    if (deviceId.trim().isEmpty ||
        deviceId == InstitutionalAuthService.deviceIdAbsent) {
      throw StateError('sessão sem aparelho identificado');
    }
    final autoridade = ca;
    if (autoridade == null) throw StateError(unavailableMessage);
    try {
      await ensureDeviceNotMarked(deviceId);
    } on DeviceWipeRequiredException {
      throw StateError('aparelho com pedido de limpeza remota');
    }

    // Truncado ao segundo: é a precisão do certificado, e a linha gravada
    // descreve exatamente a folha emitida.
    final t = (now ?? _clock()).toUtc();
    final agora = DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
    final emitidas = await store.issuedSince(
      deviceId,
      agora.subtract(const Duration(hours: 1)),
    );
    if (emitidas >= maxIssuesPerHour) {
      throw ArgumentError('limite de emissões deste aparelho atingido; tente mais tarde');
    }

    final CsrInfo info;
    try {
      info = await autoridade.inspectCsr(csrPem);
    } on FormatException {
      throw ArgumentError('CSR inválido');
    }
    if (info.keyAlgorithm != 'id-ecPublicKey' || info.curve != 'prime256v1') {
      throw ArgumentError('a chave do aparelho precisa ser EC prime256v1');
    }
    if (info.commonName != microArea) {
      throw ArgumentError('o CN do CSR difere da microárea da sessão');
    }

    final serial = _novaSerial();
    final notBefore = agora.subtract(const Duration(hours: 1));
    final notAfter = agora.add(Duration(days: certDays));
    final String pem;
    try {
      pem = await autoridade.sign(
        csrPem: csrPem,
        serial: serial,
        commonName: microArea,
        sanUris: [
          'urn:sinalacs:device:$deviceId',
          'urn:sinalacs:acs:${user.id}',
        ],
        notBefore: notBefore,
        notAfter: notAfter,
      );
    } on FormatException {
      throw ArgumentError('CSR inválido');
    }

    final serialHex = serial.toRadixString(16).padLeft(32, '0');
    final novo = DeviceCertificate(
      userId: UuidValue.fromString(user.id),
      deviceId: deviceId,
      microAreaId: UuidValue.fromString(microArea),
      serial: serialHex,
      fingerprintSha256: _fingerprint(pem),
      notBefore: notBefore,
      notAfter: notAfter,
      issuedAt: agora,
    );
    await store.issueReplacing(
      novo,
      issuedAudit: deviceCertAudit(
        novo,
        actorId: user.id,
        result: 'device_cert_issued',
      ),
      revokedAudit: (c) => deviceCertAudit(
        c,
        actorId: user.id,
        result: deviceCertRevokedResult(DeviceCertRevocationReason.renewed),
      ),
    );
    await crl?.publish();
    return DeviceCertificateIssueResult(
      certificatePem: pem,
      serial: serialHex,
      notAfter: notAfter,
      serverNow: agora,
    );
  }

  /// 16 bytes de `Random.secure()` com os bits de versão (4) e variante
  /// (RFC 4122) fixados: a serial é, bit a bit, um UUID v4. Assim ela entra
  /// tal qual em `audit_logs.resourceId` (coluna `uuid`, que o Serverpod relê
  /// validando versão e variante) e a trilha nomeia a serial, não um id
  /// derivado. Sobram 122 bits aleatórios — o CA/Browser Forum pede ≥ 64. O
  /// nibble de versão garante serial > 0.
  BigInt _novaSerial() {
    final b = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    var n = BigInt.zero;
    for (final x in b) {
      n = (n << 8) | BigInt.from(x);
    }
    return n;
  }

  /// SHA-256 do DER da folha, em hex minúsculo.
  static String _fingerprint(String pem) {
    final corpo = pem
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return sha256.convert(base64.decode(corpo)).toString();
  }
}
