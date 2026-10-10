import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/routing/app_routes.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/theme/app_theme.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/features/welcome/presentation/providers/welcome_controller.dart';
import 'package:buscar_audifonos/features/welcome/presentation/widgets/ondas_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First-run welcome: what the app is, how it is used, and what it will ask
/// for. Seen once.
///
/// Always on the brand dark, whatever the theme: it continues the splash,
/// which is Marea too, so launch → splash → welcome is one surface.
///
/// No permission is requested here — they are asked the moment the user first
/// scans, where the reason is obvious. Android remembers a "no", and a "no"
/// given here, out of context, would cost the app its only feature.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({this.from, super.key});

  /// Where the user was going when the welcome intercepted them (a deep link
  /// opened on first launch). Restored on finish so the link is not lost.
  final String? from;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  static const int _pageCount = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pageCount - 1;

  Future<void> _finish() async {
    await ref.read(welcomeDoneProvider.notifier).complete();
    if (!mounted) return;
    final String? from = widget.from;
    // Only an in-app path is honoured: `from` arrives in a URL, and anything
    // else in it is not ours to navigate to.
    context.go(
      from != null && from.startsWith('/') && from != AppRoutes.welcomePath
          ? from
          : AppRoutes.homePath,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Builder(
        builder: (BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: BaseScreen(
            showBanner: false,
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    // Nothing on these pages has to be accepted, so skipping
                    // is allowed; on the last page the main button already
                    // does the same thing.
                    child: Visibility(
                      visible: !_isLast,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(context.l10n.welcomeSkip),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (int page) => setState(() => _page = page),
                      children: const <Widget>[
                        _IntroPage(),
                        _HowToPage(),
                        _BeforePage(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Row(
                      children: <Widget>[
                        _Dots(count: _pageCount, current: _page),
                        const Spacer(),
                        SizedBox(
                          width: 160,
                          child: FilledButton(
                            onPressed: _next,
                            child: Text(
                              _isLast
                                  ? context.l10n.welcomeStart
                                  : context.l10n.welcomeNext,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each page scrolls on its own: a small phone with large text must never
/// overflow, and the footer stays put while it does.
class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: <Widget>[
        const Center(child: OndasLogo(size: 176)),
        const SizedBox(height: AppSpacing.xl),
        Text(context.l10n.appTitle, style: context.texts.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.welcomeTagline,
          style: context.texts.titleLarge?.copyWith(
            color: context.colors.primary,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.welcomeTaglineBody,
          style: context.texts.bodyLarge?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HowToPage extends StatelessWidget {
  const _HowToPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: <Widget>[
        Text(context.l10n.welcomeHowTitle, style: context.texts.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        _Step(
          number: 1,
          icon: Icons.bluetooth_searching,
          text: context.l10n.welcomeStepScan,
        ),
        _Step(
          number: 2,
          icon: Icons.touch_app_outlined,
          text: context.l10n.welcomeStepOpen,
        ),
        _Step(
          number: 3,
          icon: Icons.directions_walk,
          text: context.l10n.welcomeStepWalk,
        ),
        _Step(
          number: 4,
          icon: Icons.star_border,
          text: context.l10n.welcomeStepFavorite,
        ),
      ],
    );
  }
}

class _BeforePage extends StatelessWidget {
  const _BeforePage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: <Widget>[
        Text(
          context.l10n.welcomeReadyTitle,
          style: context.texts.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Notice(
          icon: Icons.lock_outline,
          title: context.l10n.welcomePermissionsTitle,
          body: context.l10n.welcomePermissionsBody,
        ),
        const SizedBox(height: AppSpacing.md),
        _Notice(
          icon: Icons.radar,
          title: context.l10n.welcomeLimitsTitle,
          body: context.l10n.welcomeLimitsBody,
        ),
      ],
    );
  }
}

/// A numbered step: the order is the real order of a search.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text});

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Icon(icon, color: context.colors.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          // Fixed width: the digits differ in width and the text beside them
          // has to start on one line.
          SizedBox(
            width: 20,
            child: Text(
              '$number',
              style: context.texts.titleLarge?.copyWith(
                fontWeight: FontWeight.w300,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.texts.bodyLarge)),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: context.texts.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(right: AppSpacing.xs + 2),
            width: index == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index == current
                  ? context.colors.primary
                  : context.colors.outlineVariant,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.pill),
              ),
            ),
          ),
      ],
    );
  }
}
