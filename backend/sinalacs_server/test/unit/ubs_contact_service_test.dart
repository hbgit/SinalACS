import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/ubs/ubs_contact_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';

class _FakeStore implements UbsContactStore {
  _FakeStore(this.record);
  UbsContactRecord? record;
  final consultados = <String>[];

  @override
  Future<UbsContactRecord?> findForAcs(String acsId) async {
    consultados.add(acsId);
    return record;
  }
}

AuthenticatedUser _usuario(UserRole role) => AuthenticatedUser(
  id: _acsId,
  role: role,
  microAreaId: '00000000-0000-4000-8000-000000000003',
  deviceId: 'dispositivo-teste',
);

void main() {
  test('devolve nome e telefone da UBS do ACS', () async {
    final service = UbsContactService(
      store: _FakeStore(
        const UbsContactRecord(name: 'UBS Teste', phone: '+55 11 5550-0100'),
      ),
    );

    final contato = await service.contactFor(_usuario(UserRole.acs));

    expect(contato.name, 'UBS Teste');
    expect(contato.phone, '+55 11 5550-0100');
  });

  test('UBS sem telefone cadastrado devolve phone nulo, sem falhar', () async {
    final service = UbsContactService(
      store: _FakeStore(
        const UbsContactRecord(name: 'UBS Sem Fone', phone: null),
      ),
    );
    final contato = await service.contactFor(_usuario(UserRole.acs));
    expect(contato.phone, isNull);
  });

  test('telefone só com espaços vale como não cadastrado', () async {
    final service = UbsContactService(
      store: _FakeStore(const UbsContactRecord(name: 'UBS', phone: '   ')),
    );
    expect((await service.contactFor(_usuario(UserRole.acs))).phone, isNull);
  });

  test('paciente não consulta o contato (nem toca no banco)', () async {
    final store = _FakeStore(const UbsContactRecord(name: 'UBS', phone: '1'));
    final service = UbsContactService(store: store);

    expect(
      () => service.contactFor(_usuario(UserRole.patient)),
      throwsA(isA<StateError>()),
    );
    expect(store.consultados, isEmpty);
  });

  test('ACS sem linha na tabela acs é erro, não contato vazio', () async {
    final service = UbsContactService(store: _FakeStore(null));
    expect(
      () => service.contactFor(_usuario(UserRole.acs)),
      throwsA(isA<StateError>()),
    );
  });
}
