import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/backend_admin_data_source.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/fake_admin_auth.dart';

/// Avisos e termos (#46) sobre o `EndpointAdmin` gerado, com chamador falso.
/// Dados sintéticos.
BackendAdminDataSource _fonte(
  FakeEndpointCaller caller, {
  DateTime? expiresAt,
  DateTime Function()? now,
}) => BackendAdminDataSource(
  api.EndpointAdmin(caller),
  accessToken: 'token-de-teste',
  expiresAt: expiresAt,
  now: now,
);

api.TermsVersionEntry _termo({DateTime? revisado, DateTime? publicado}) =>
    api.TermsVersionEntry(
      id: 't1',
      version: '2026.2',
      summary: 'Resumo sintético',
      effectiveFrom: DateTime.utc(2026, 11, 1),
      createdAt: DateTime.utc(2026, 10, 1),
      legallyReviewedAt: revisado,
      publishedAt: publicado,
    );

void main() {
  test('histórico: mapeia status e público por nome e repassa o filtro', () async {
    final caller = FakeEndpointCaller(
      result: api.NoticeHistoryPage(entries: [
        api.NoticeHistoryEntry(
          id: 'n1',
          microAreaId: 'ma-1',
          microAreaName: 'Microárea A',
          audience: 'chronic',
          title: 'T',
          status: api.ScheduledNoticeStatus.sent,
          scheduledFor: DateTime.utc(2026, 10, 14, 15),
          createdByLabel: 'ADM-001',
          sentAt: DateTime.utc(2026, 10, 14, 15, 1),
          recipients: 3,
          accepted: 2,
        ),
      ]),
    );
    final r = await _fonte(caller).fetchNoticeHistory(
      microAreaId: 'ma-1',
      limit: 10,
      offset: 20,
    );
    expect(r.single.status, NoticeStatus.sent);
    expect(r.single.audience, NoticeAudience.chronic);
    expect(r.single.accepted, 2);
    expect(r.single.recipients, 3);
    expect(caller.lastArgs, containsPair('accessToken', 'token-de-teste'));
    expect(caller.lastArgs, containsPair('microAreaId', 'ma-1'));
    expect(caller.lastArgs, containsPair('limit', 10));
    expect(caller.lastArgs, containsPair('offset', 20));
  });

  test('histórico sem argumentos envia limit 50 e offset 0', () async {
    final caller = FakeEndpointCaller(result: api.NoticeHistoryPage(entries: []));
    await _fonte(caller).fetchNoticeHistory();
    expect(caller.lastArgs, containsPair('limit', 50));
    expect(caller.lastArgs, containsPair('offset', 0));
  });

  test('scheduleNotice envia o público pelo nome e a data em UTC', () async {
    final caller = FakeEndpointCaller(result: 'novo-id');
    final local = DateTime(2026, 10, 20, 9, 30);
    final id = await _fonte(caller).scheduleNotice(
      microAreaId: 'ma-1',
      audience: NoticeAudience.everyone,
      title: 'Título',
      message: 'Texto',
      scheduledFor: local,
    );
    expect(id, 'novo-id');
    expect(caller.lastArgs, containsPair('audience', 'everyone'));
    final enviada = caller.lastArgs!['scheduledFor'] as DateTime;
    expect(enviada.isUtc, isTrue);
    expect(enviada, local.toUtc());
  });

  test('draftTermsVersion envia a vigência em UTC e mapeia o termo', () async {
    final caller = FakeEndpointCaller(result: _termo());
    final t = await _fonte(caller).draftTermsVersion(
      version: '2026.2',
      summary: 'Resumo',
      effectiveFrom: DateTime(2026, 11, 1, 8),
    );
    expect((caller.lastArgs!['effectiveFrom'] as DateTime).isUtc, isTrue);
    expect(t.state, TermsVersionState.draft);
  });

  test('termos: mapeia revisão, publicação e o estado', () async {
    final rev = DateTime.utc(2026, 10, 5);
    final pub = DateTime.utc(2026, 10, 6);
    final caller = FakeEndpointCaller(
      result: [_termo(), _termo(revisado: rev), _termo(revisado: rev, publicado: pub)],
    );
    final r = await _fonte(caller).fetchTermsVersions();
    expect(r.map((t) => t.state), [
      TermsVersionState.draft,
      TermsVersionState.reviewed,
      TermsVersionState.published,
    ]);
    expect(r[1].legallyReviewedAt, rev);
    expect(r[2].publishedAt, pub);
  });

  test('markTermsReviewed e publishTermsVersion mapeiam o termo', () async {
    final rev = DateTime.utc(2026, 10, 5);
    final c1 = FakeEndpointCaller(result: _termo(revisado: rev));
    expect((await _fonte(c1).markTermsReviewed('t1')).state, TermsVersionState.reviewed);
    expect(c1.lastArgs, containsPair('id', 't1'));
    final c2 = FakeEndpointCaller(result: _termo(revisado: rev, publicado: rev));
    expect((await _fonte(c2).publishTermsVersion('t1')).state, TermsVersionState.published);
  });

  group('recusa de validação vira AdminValidationFailure com a mensagem', () {
    final erro = api.AdminInvalidRequestException(message: 'A versão ainda não foi revisada juridicamente.');
    final Map<String, Future<Object?> Function(BackendAdminDataSource)> escritas = {
      'scheduleNotice': (f) => f.scheduleNotice(
        microAreaId: 'm',
        audience: NoticeAudience.chronic,
        title: 't',
        message: 'x',
        scheduledFor: DateTime.utc(2026, 12, 1),
      ),
      'cancelScheduledNotice': (f) => f.cancelScheduledNotice('n1'),
      'draftTermsVersion': (f) => f.draftTermsVersion(
        version: 'v',
        summary: 's',
        effectiveFrom: DateTime.utc(2026, 12, 1),
      ),
      'markTermsReviewed': (f) => f.markTermsReviewed('t1'),
      'publishTermsVersion': (f) => f.publishTermsVersion('t1'),
    };
    escritas.forEach((nome, chamar) {
      test(nome, () async {
        await expectLater(
          chamar(_fonte(FakeEndpointCaller(error: erro))),
          throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', contains('revisada'))),
        );
      });
    });
  });

  test('recusa por papel vira AdminDataFailure em leitura e escrita', () async {
    final erro = api.AlertPermissionException(message: 'x');
    await expectLater(
      _fonte(FakeEndpointCaller(error: erro)).fetchTermsVersions(),
      throwsA(isA<AdminDataFailure>().having((e) => e, 'tipo', isNot(isA<AdminValidationFailure>()))),
    );
    await expectLater(
      _fonte(FakeEndpointCaller(error: erro)).fetchNoticeHistory(),
      throwsA(isA<AdminDataFailure>()),
    );
    await expectLater(
      _fonte(FakeEndpointCaller(error: erro)).publishTermsVersion('t1'),
      throwsA(isA<AdminDataFailure>().having((e) => e, 'tipo', isNot(isA<AdminValidationFailure>()))),
    );
  });

  test('sessão vencida vira AdminSessionExpired em leitura e escrita', () async {
    final erro = api.AlertPermissionException(message: 'token inválido ou expirado');
    BackendAdminDataSource vencida() => _fonte(
      FakeEndpointCaller(error: erro),
      expiresAt: DateTime.utc(2026, 1, 1, 12),
      now: () => DateTime.utc(2026, 1, 1, 12, 0, 1),
    );
    await expectLater(vencida().fetchNoticeHistory(), throwsA(isA<AdminSessionExpired>()));
    await expectLater(vencida().cancelScheduledNotice('n1'), throwsA(isA<AdminSessionExpired>()));
  });
}
