import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Fonte que só muda o TMRAV do mock: o resto do painel segue igual.
class _ComTmrav extends MockAdminDataSource {
  _ComTmrav(this.tmrav);
  final int? tmrav;

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    final base = await super.fetchDashboardIndicators();
    return DashboardIndicators(
      countsByRisk: base.countsByRisk,
      openRedAlerts: base.openRedAlerts,
      acknowledgedRedAlerts: base.acknowledgedRedAlerts,
      tmravSeconds: tmrav,
    );
  }
}

/// TMRAV nulo (nenhum alerta vermelho reconhecido na janela) aparece como traço,
/// nunca como "0s": zero seria uma resposta instantânea que nunca aconteceu.
void main() {
  testWidgets('TMRAV sem amostra mostra "—" e não "0s"', (tester) async {
    await tester.pumpWidget(
      SinalAdminApp(dataSource: _ComTmrav(null), auth: FakeAdminAuth()),
    );
    await entrarComCredenciais(tester);

    expect(find.text('TMRAV (tempo médio de resposta)'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0s'), findsNothing);
    expect(find.text('null s'), findsNothing);
    expect(find.text('nulls'), findsNothing);
  });

  testWidgets('TMRAV com amostra mostra os segundos', (tester) async {
    await tester.pumpWidget(
      SinalAdminApp(dataSource: _ComTmrav(60), auth: FakeAdminAuth()),
    );
    await entrarComCredenciais(tester);

    expect(find.text('60s'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });
}
