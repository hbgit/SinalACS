import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';

Future<void> _loginTo(WidgetTester tester, FailingAdminDataSource dataSource, String destination) async {
  await tester.pumpWidget(SinalAdminApp(dataSource: dataSource));
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
  if (destination != 'Indicadores') {
    await tester.tap(find.text(destination).last);
    await tester.pumpAndSettle();
  }
}

void main() {
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
