import 'package:app_template/app.dart';
import 'package:app_template/services/billing/premium_controller.dart';
import 'package:app_template/services/billing/premium_state.dart';
import 'package:app_template/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replaces the real controller so the test never touches Google Play Billing.
/// Overriding `build` is enough: no platform channel is opened.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: false, storeAvailable: false);
}

void main() {
  testWidgets('home screen renders the main sections', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App Template'), findsOneWidget);
    expect(find.text('Completed actions: 0'), findsOneWidget);
    expect(find.text('Available credits: 0'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
  });

  testWidgets('completing a task increments the counter', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete task'));
    await tester.pumpAndSettle();

    expect(find.text('Completed actions: 1'), findsOneWidget);
  });
}
