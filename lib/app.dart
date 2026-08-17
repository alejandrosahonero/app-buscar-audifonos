import 'package:buscar_audifonos/core/l10n/locale_controller.dart';
import 'package:buscar_audifonos/core/routing/app_router.dart';
import 'package:buscar_audifonos/core/theme/app_theme.dart';
import 'package:buscar_audifonos/core/theme/theme_controller.dart';
import 'package:buscar_audifonos/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Root widget. Holds no logic beyond wiring theme, routing and localization.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Locale? locale = ref.watch(localeProvider);

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // `null` hands the decision back to the platform resolution, which is
      // what "follow the phone" has to mean.
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
