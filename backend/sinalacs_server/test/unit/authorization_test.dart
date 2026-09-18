import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
// `TriageAuthorizationException` é uma classe Dart escrita à mão (não gerada),
// declarada em `application/triage/triage_session_service.dart:15` — é o único
// ponto do backend que recusa com exceção tipada em vez de `StateError`.
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

AuthenticatedUser _user(UserRole role, {String? microAreaId = 'micro-area-1'}) =>
    AuthenticatedUser(
      id: '00000000-0000-4000-8000-000000000002',
      role: role,
      microAreaId: microAreaId,
      deviceId: 'test-device',
    );

void main() {
  group('Authorization.require', () {
    test('aceita o papel permitido e devolve o controle ao chamador', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs),
          roles: {UserRole.acs},
          onDenied: () => StateError('não deveria ser lançada'),
        ),
        returnsNormally,
      );
    });

    test('recusa outro papel lançando o que o chamador passou', () {
      expect(
        () => Authorization.require(
          _user(UserRole.patient),
          roles: {UserRole.acs},
          onDenied: () => StateError('Somente ACS podem fazer isto.'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Somente ACS podem fazer isto.',
          ),
        ),
      );
    });

    // O tipo da exceção é decisão do chamador, não da guarda: a triagem lança
    // TriageAuthorizationException e os serviços territoriais lançam StateError.
    // Unificar aqui quebraria a tradução dos endpoints.
    test('preserva o tipo da exceção do chamador', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs),
          roles: {UserRole.patient},
          onDenied: () => const TriageAuthorizationException('x'),
        ),
        throwsA(isA<TriageAuthorizationException>()),
      );
    });

    test('recusa papel permitido sem território quando exigido', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs, microAreaId: null),
          roles: {UserRole.acs},
          onDenied: () => StateError('sem território'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // statusFor (RF05) é escopado ao próprio paciente e não depende de
    // território: exigir microárea ali recusaria todo paciente que o seed cria
    // com microárea — e passaria despercebido, porque o teste de hoje usa um
    // paciente que tem uma.
    test('não exige território quando requireMicroArea é false', () {
      expect(
        () => Authorization.require(
          _user(UserRole.patient, microAreaId: null),
          roles: {UserRole.patient},
          onDenied: () => StateError('não deveria ser lançada'),
          requireMicroArea: false,
        ),
        returnsNormally,
      );
    });

    test('recusa papéis ainda não emitidos pelo backend', () {
      for (final role in [UserRole.admin, UserRole.coordinator]) {
        expect(
          () => Authorization.require(
            _user(role),
            roles: {UserRole.acs, UserRole.patient},
            onDenied: () => StateError('papel não autorizado'),
          ),
          throwsA(isA<StateError>()),
          reason: '$role não pode passar numa regra de ACS/paciente',
        );
      }
    });
  });
}
