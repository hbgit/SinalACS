import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_backend/src/domain/enums/user_role.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.role,
    required this.microAreaId,
    required this.deviceId,
  });

  final String id;
  final UserRole role;
  final String? microAreaId;
  final String deviceId;
}

class DevelopmentAuthService {
  DevelopmentAuthService({required String secret}) : _secret = utf8.encode(secret);

  final List<int> _secret;

  String issueToken(AuthenticatedUser user, {Duration lifetime = const Duration(minutes: 15), DateTime? now}) {
    final issuedAt = now ?? DateTime.now().toUtc();
    final header = _encode({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _encode({
      'sub': user.id,
      'role': user.role.name,
      'micro_area_id': user.microAreaId,
      'device_id': user.deviceId,
      'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': issuedAt.add(lifetime).millisecondsSinceEpoch ~/ 1000,
    });
    final unsignedToken = '$header.$payload';
    return '$unsignedToken.${_sign(unsignedToken)}';
  }

  AuthenticatedUser? verifyToken(String token, {DateTime? now}) {
    final sections = token.split('.');
    if (sections.length != 3 || !_matchesSignature('${sections[0]}.${sections[1]}', sections[2])) return null;

    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(sections[1])))) as Map<String, dynamic>;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch((payload['exp'] as int) * 1000, isUtc: true);
      if (!expiresAt.isAfter(now ?? DateTime.now().toUtc())) return null;
      return AuthenticatedUser(
        id: payload['sub'] as String,
        role: UserRole.values.byName(payload['role'] as String),
        microAreaId: payload['micro_area_id'] as String?,
        deviceId: payload['device_id'] as String,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  String _encode(Map<String, dynamic> value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  String _sign(String value) => base64Url.encode(Hmac(sha256, _secret).convert(utf8.encode(value)).bytes).replaceAll('=', '');

  bool _matchesSignature(String value, String signature) {
    final expected = _sign(value);
    if (expected.length != signature.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ signature.codeUnitAt(index);
    }
    return difference == 0;
  }
}