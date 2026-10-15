import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class UbsContactRecord {
  const UbsContactRecord({required this.name, required this.phone});

  final String name;
  final String? phone;
}

abstract interface class UbsContactStore {
  /// UBS do ACS `acsId`, ou `null` se o ACS ou a UBS não existirem.
  Future<UbsContactRecord?> findForAcs(String acsId);
}

/// Contato da UBS para o botão de escalonamento do ACS (RF13).
///
/// A UBS vem do **token** (`user.id` é o id do ACS), nunca de parâmetro — mesma
/// regra de território das outras consultas do ACS.
class UbsContactService {
  UbsContactService({required this.store});

  final UbsContactStore store;

  Future<UbsContact> contactFor(AuthenticatedUser user) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () => StateError('Somente ACS consultam o contato da UBS.'),
    );

    final record = await store.findForAcs(user.id);
    if (record == null) {
      throw StateError('UBS do ACS não encontrada.');
    }
    final phone = record.phone?.trim();
    return UbsContact(
      name: record.name,
      phone: (phone == null || phone.isEmpty) ? null : phone,
    );
  }
}
