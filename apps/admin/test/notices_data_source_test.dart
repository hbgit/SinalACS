import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

final _agora = DateTime(2026, 10, 14, 12);

Matcher _recusa(String msg) =>
    throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', msg));

void main() {
  late MockAdminDataSource fonte;
  setUp(() => fonte = MockAdminDataSource(now: () => _agora));

  test('agendar a menos de 1 minuto recusa; a mais de 1 minuto entra como pending', () async {
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(seconds: 30))),
      _recusa('O horário do aviso deve ser pelo menos 1 minuto à frente.'),
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
    await expectLater(
        fonte.cancelScheduledNotice(id), _recusa('Só avisos pendentes podem ser cancelados.'));
    await expectLater(fonte.cancelScheduledNotice('nada'), _recusa('Aviso não encontrado.'));
  });

  test('termos: publicar sem revisão recusa; com revisão e 15 dias aceita; 14 dias recusa', () async {
    final t = await fonte.draftTermsVersion(
        version: '2099.1', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 15)));
    await expectLater(fonte.publishTermsVersion(t.id), _recusa('A versão ainda não foi revisada juridicamente.'));
    await fonte.markTermsReviewed(t.id);
    expect((await fonte.publishTermsVersion(t.id)).publishedAt, _agora);

    final fonte2 = MockAdminDataSource(now: () => _agora);
    final curto = await fonte2.draftTermsVersion(
        version: '2099.2', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 14)));
    await fonte2.markTermsReviewed(curto.id);
    await expectLater(fonte2.publishTermsVersion(curto.id), _recusa('A vigência exige 15 dias de antecedência.'));
  });

  test('bordas: 1 minuto exato aceita, 59 s recusa; microárea inexistente e limites de texto', () async {
    await fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(minutes: 1)));
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-12', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(seconds: 59))),
      _recusa('O horário do aviso deve ser pelo menos 1 minuto à frente.'),
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

  Future<String> agenda(String area, Duration em, {String titulo = 'T', String msg = 'M'}) =>
      fonte.scheduleNotice(
          microAreaId: area, audience: NoticeAudience.everyone, title: titulo, message: msg,
          scheduledFor: _agora.add(em));

  test('histórico: ordena por scheduledFor desc, filtra por microárea e pagina', () async {
    final a = await agenda('ma-12', const Duration(hours: 1));
    final b = await agenda('ma-07', const Duration(hours: 3));
    final c = await agenda('ma-12', const Duration(hours: 2));
    expect((await fonte.fetchNoticeHistory()).map((x) => x.id), [b, c, a]);
    expect((await fonte.fetchNoticeHistory(microAreaId: 'ma-12')).map((x) => x.id), [c, a]);
    expect((await fonte.fetchNoticeHistory(limit: 2)).map((x) => x.id), [b, c]);
    expect((await fonte.fetchNoticeHistory(limit: 2, offset: 1)).map((x) => x.id), [c, a]);
    expect((await fonte.fetchNoticeHistory(offset: 3)), isEmpty);
    expect((await fonte.fetchNoticeHistory(offset: 10)), isEmpty);
    expect((await fonte.fetchNoticeHistory(microAreaId: 'ma-03')), isEmpty);
  });

  test('limites do aviso: 60/240 aceitam, 61/241 recusam, só espaços recusa, trim aplicado', () async {
    await agenda('ma-12', const Duration(hours: 1), titulo: 'x' * 60, msg: 'y' * 240);
    await expectLater(agenda('ma-12', const Duration(hours: 1), titulo: 'x' * 61),
        _recusa('O título pode ter no máximo 60 caracteres.'));
    await expectLater(agenda('ma-12', const Duration(hours: 1), msg: 'y' * 241),
        _recusa('A mensagem pode ter no máximo 240 caracteres.'));
    await expectLater(agenda('ma-12', const Duration(hours: 1), titulo: '   '),
        _recusa('Informe o título e a mensagem do aviso.'));
    await expectLater(agenda('ma-12', const Duration(hours: 1), msg: '   '),
        _recusa('Informe o título e a mensagem do aviso.'));
    final id = await agenda('ma-07', const Duration(hours: 5), titulo: '  ${'x' * 60}  ');
    final h = await fonte.fetchNoticeHistory(microAreaId: 'ma-07');
    expect(h.single.id, id);
    expect(h.single.title, 'x' * 60);
  });

  test('rascunho de termos: resumo 280/281, versão vazia e vigência passada', () async {
    final futuro = _agora.add(const Duration(days: 20));
    await fonte.draftTermsVersion(version: 'a', summary: 'x' * 280, effectiveFrom: futuro);
    await expectLater(fonte.draftTermsVersion(version: 'b', summary: 'x' * 281, effectiveFrom: futuro),
        _recusa('O resumo deve ter de 1 a 280 caracteres.'));
    await expectLater(fonte.draftTermsVersion(version: '  ', summary: 'S', effectiveFrom: futuro),
        _recusa('Informe o número da versão.'));
    await expectLater(
        fonte.draftTermsVersion(version: 'c', summary: 'S', effectiveFrom: _agora.subtract(const Duration(days: 1))),
        _recusa('A vigência deve ser futura.'));
  });
}
