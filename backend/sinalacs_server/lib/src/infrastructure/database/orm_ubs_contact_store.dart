import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/ubs/ubs_contact_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class OrmUbsContactStore implements UbsContactStore {
  OrmUbsContactStore(this._session);

  final Session _session;

  @override
  Future<UbsContactRecord?> findForAcs(String acsId) async {
    final acs = await Acs.db.findById(_session, UuidValue.fromString(acsId));
    if (acs == null) return null;
    final ubs = await Ubs.db.findById(_session, acs.ubsId);
    if (ubs == null) return null;
    return UbsContactRecord(name: ubs.name, phone: ubs.contactPhone);
  }
}
