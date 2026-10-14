import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

final _agora = DateTime(2026, 10, 14, 12);

void main() {
  late MockAdminDataSource fonte;
  setUp(() => fonte = MockAdminDataSource(now: () => _agora));

  test('agendar a menos de 1 minuto recusa; a mais de 1 minuto entra como pending', () async {
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(seconds: 30))),
      throwsA(isA<AdminValidationFailure>()),
    );
    final id = await fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.chronic,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(hours: 2)));
    final h = await fonte.fetchNoticeHistory();
    expect(h.single.id, id);
    expect(h.single.status, NoticeStatus.pending);
  });

  test('cancelar só vale para pending', () async {
    final id = await fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(hours: 2)));
    await fonte.cancelScheduledNotice(id);
    expect((await fonte.fetchNoticeHistory()).single.status, NoticeStatus.cancelled);
    await expectLater(fonte.cancelScheduledNotice(id), throwsA(isA<AdminValidationFailure>()));
  });

  test('termos: publicar sem revisão recusa; com revisão e 15 dias aceita; 14 dias recusa', () async {
    final t = await fonte.draftTermsVersion(
        version: '2099.1', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 15)));
    await expectLater(fonte.publishTermsVersion(t.id), throwsA(isA<AdminValidationFailure>()));
    await fonte.markTermsReviewed(t.id);
    expect((await fonte.publishTermsVersion(t.id)).publishedAt, _agora);

    final curto = await fonte.draftTermsVersion(
        version: '2099.2', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 14)));
    await fonte.markTermsReviewed(curto.id);
    await expectLater(fonte.publishTermsVersion(curto.id), throwsA(isA<AdminValidationFailure>()));
  });

  test('bordas: 1 minuto exato aceita, 59 s recusa; microárea inexistente e limites de texto', () async {
    await fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(minutes: 1)));
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(seconds: 59))),
      throwsA(isA<AdminValidationFailure>()),
    );
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'nao-existe', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(hours: 1))),
      throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', 'Microárea não encontrada.')),
    );
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'x' * 61, message: 'M', scheduledFor: _agora.add(const Duration(hours: 1))),
      throwsA(isA<AdminValidationFailure>()),
    );
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'T', message: ' ', scheduledFor: _agora.add(const Duration(hours: 1))),
      throwsA(isA<AdminValidationFailure>()),
    );
  });

  test('termos: versão única, revisão única, publicação única', () async {
    final t = await fonte.draftTermsVersion(
        version: '2099.1', summary: 'S', effectiveFrom: _agora.add(const Duration(days: 20)));
    await expectLater(
      fonte.draftTermsVersion(version: '2099.1', summary: 'S', effectiveFrom: _agora.add(const Duration(days: 20))),
      throwsA(isA<AdminValidationFailure>()),
    );
    await fonte.markTermsReviewed(t.id);
    await expectLater(fonte.markTermsReviewed(t.id), throwsA(isA<AdminValidationFailure>()));
    await fonte.publishTermsVersion(t.id);
    await expectLater(fonte.publishTermsVersion(t.id), throwsA(isA<AdminValidationFailure>()));
    expect((await fonte.fetchTermsVersions()).single.state, TermsVersionState.published);
  });
}
