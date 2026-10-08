import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

Future<void> _loginTo(WidgetTester tester, FailingAdminDataSource dataSource, String destination) async {
  await tester.pumpWidget(SinalAdminApp(dataSource: dataSource, auth: FakeAdminAuth()));
  await entrarComCredenciais(tester);
  if (destination != 'Indicadores') {
    await tester.tap(find.text(destination).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('falhas do backend (#41): texto próprio e sessão vencida', () {
    testWidgets('AdminDataFailure: a tela mostra a mensagem da falha e o retry recupera', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())
        ..nextError = const AdminDataFailure('Não foi possível conectar ao servidor.');
      await _loginTo(tester, dataSource, 'Indicadores');

      expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);
      expect(find.text('Não foi possível carregar os indicadores.'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Painel de Indicadores'), findsOneWidget);
    });

    testWidgets('segunda falha seguida continua mostrando o erro, sem spinner', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())
        ..nextError = const AdminDataFailure('Acesso restrito ao backoffice.');
      await _loginTo(tester, dataSource, 'Indicadores');
      dataSource.nextError = const AdminDataFailure('Acesso restrito ao backoffice.');

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.text('Acesso restrito ao backoffice.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('AdminSessionExpired: volta ao login com o aviso, sem oferecer retry', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())
        ..nextError = const AdminSessionExpired();
      await _loginTo(tester, dataSource, 'Indicadores');

      expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);
    });

    testWidgets('AdminSessionExpired na auditoria também volta ao login', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource());
      await _loginTo(tester, dataSource, 'Indicadores');
      dataSource.nextError = const AdminSessionExpired();

      await tester.tap(find.text('Auditoria').last);
      await tester.pumpAndSettle();

      expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    });
  });

  group('erro e retry, por tela (achado da revisão do PR: erro não pode parecer vazio ou travar em spinner)', () {
    testWidgets('Indicadores: mostra erro (não spinner infinito) e retry recupera', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextIndicators = true;
      await _loginTo(tester, dataSource, 'Indicadores');

      expect(find.text('Não foi possível carregar os indicadores.'), findsOneWidget);
      expect(find.text('Painel de Indicadores'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.text('Painel de Indicadores'), findsOneWidget);
      expect(find.text('Não foi possível carregar os indicadores.'), findsNothing);
    });

    testWidgets('Microáreas: recordAccess falhando não deve expor a lista sem auditar o acesso', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextRecordAccess = true;
      await _loginTo(tester, dataSource, 'Microáreas');

      expect(find.text('Não foi possível carregar as microáreas.'), findsOneWidget);
      expect(find.textContaining('Microárea 12'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Microárea 12'), findsOneWidget);
    });

    testWidgets('Alertas: erro no carregamento não deve aparecer como "nenhum alerta"', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextAlerts = true;
      await _loginTo(tester, dataSource, 'Alertas');

      expect(find.text('Não foi possível carregar os alertas.'), findsOneWidget);
      expect(find.text('Nenhum alerta para o filtro selecionado.'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
    });

    testWidgets('Auditoria: erro no carregamento não deve aparecer como "nenhum acesso registrado"', (tester) async {
      final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextAuditLogs = true;
      await _loginTo(tester, dataSource, 'Auditoria');

      expect(find.text('Não foi possível carregar os logs de auditoria.'), findsOneWidget);
      expect(find.text('Nenhum acesso registrado ainda.'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('view • audit_logs'), findsOneWidget);
    });
  });

  testWidgets('filtros de Alertas mostram "Todas"/"Todos" fechados, não em branco (achado da revisão do PR)', (tester) async {
    final dataSource = FailingAdminDataSource(inner: MockAdminDataSource());
    await _loginTo(tester, dataSource, 'Alertas');

    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
  });
}
