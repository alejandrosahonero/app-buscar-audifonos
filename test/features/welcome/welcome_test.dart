import 'package:buscar_audifonos/features/welcome/presentation/screens/welcome_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_app.dart';

void main() {
  const Map<String, Object> firstLaunch = <String, Object>{
    'welcome_done': false,
    'app_locale': 'es',
  };

  testWidgets('the first launch opens on the welcome', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      scanService: FakeScanService(),
      preferences: firstLaunch,
    );

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Saltar'), findsOneWidget);
  });

  testWidgets('"Empezar" on the last page lands on the scanner and is '
      'remembered', (WidgetTester tester) async {
    await pumpApp(
      tester,
      scanService: FakeScanService(),
      preferences: firstLaunch,
    );

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Saltar').hitTestable(), findsNothing);

    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.text('Buscar Audífonos'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('welcome_done'), isTrue);
  });

  testWidgets('skipping also completes it', (WidgetTester tester) async {
    await pumpApp(
      tester,
      scanService: FakeScanService(),
      preferences: firstLaunch,
    );

    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('a second launch goes straight to the scanner', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      scanService: FakeScanService(),
      preferences: <String, Object>{'welcome_done': true},
    );

    expect(find.byType(WelcomeScreen), findsNothing);
  });
}
