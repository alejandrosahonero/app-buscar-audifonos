import 'package:buscar_audifonos/core/routing/app_routes.dart';
import 'package:buscar_audifonos/core/widgets/error_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/screens/radar_screen.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/screens/scanner_screen.dart';
import 'package:buscar_audifonos/features/premium/presentation/screens/paywall_screen.dart';
import 'package:buscar_audifonos/features/settings/presentation/screens/settings_screen.dart';
import 'package:buscar_audifonos/features/welcome/presentation/providers/welcome_controller.dart';
import 'package:buscar_audifonos/features/welcome/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Root navigator key.
///
/// Services that live outside the widget tree (ad callbacks, purchase stream)
/// need a context to show a dialog; they use this key instead of holding on to
/// a stale `BuildContext`.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// The application router.
///
/// Kept alive for the whole app lifetime on purpose: disposing it would reset
/// the navigation stack.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.homePath,
    debugLogDiagnostics: false,
    // First run: nothing is reachable before the welcome, deep links included.
    // The destination rides along in `from`, so a link opened on first launch
    // lands where it pointed once the welcome is done.
    redirect: (BuildContext context, GoRouterState state) {
      final bool done = ref.read(welcomeDoneProvider);
      final bool atWelcome = state.matchedLocation == AppRoutes.welcomePath;
      if (done) return atWelcome ? AppRoutes.homePath : null;
      if (atWelcome) return null;
      return Uri(
        path: AppRoutes.welcomePath,
        queryParameters: <String, String>{
          AppRoutes.welcomeFromParam: state.uri.toString(),
        },
      ).toString();
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.welcomePath,
        name: AppRoutes.welcomeName,
        builder: (BuildContext context, GoRouterState state) => WelcomeScreen(
          from: state.uri.queryParameters[AppRoutes.welcomeFromParam],
        ),
      ),
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const ScannerScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'settings',
            name: AppRoutes.settingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
          GoRoute(
            path: 'premium',
            name: AppRoutes.paywallName,
            builder: (BuildContext context, GoRouterState state) =>
                const PaywallScreen(),
          ),
          GoRoute(
            path: 'radar/:${AppRoutes.radarDeviceIdParam}',
            name: AppRoutes.radarName,
            builder: (BuildContext context, GoRouterState state) => RadarScreen(
              deviceId:
                  state.pathParameters[AppRoutes.radarDeviceIdParam] ?? '',
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        RouteErrorScreen(location: state.uri.toString()),
  );

  ref.onDispose(router.dispose);
  return router;
});
