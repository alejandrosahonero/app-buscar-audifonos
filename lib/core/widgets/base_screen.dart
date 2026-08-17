import 'package:buscar_audifonos/core/widgets/adaptive_banner_ad.dart';
import 'package:flutter/material.dart';

/// Standard screen shell for the app.
///
/// Every screen should be built on top of this instead of a bare [Scaffold] so
/// the banner placement policy lives in exactly one place.
///
/// The banner is laid out **below** the content, never stacked on top of it.
/// Content therefore shrinks by the banner height instead of being covered,
/// which is what keeps accidental clicks — and AdMob suspensions — away.
///
/// It travels in `bottomNavigationBar` rather than in a [Column] under the body
/// for one specific reason: a [FloatingActionButton] is positioned from the
/// scaffold's own geometry, which only accounts for the bottom bar. With the
/// banner inside the body the FAB floated *over* it — hiding the ad behind the
/// button and putting the button one thumb-slip away from an accidental click.
///
/// Set `showBanner: false` on screens with dense controls, forms, onboarding,
/// or any destructive action near the bottom edge. The project guide only
/// recommends banners on list/consultation screens.
class BaseScreen extends StatelessWidget {
  const BaseScreen({
    required this.body,
    super.key,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
    this.showBanner = true,
    this.padding = EdgeInsets.zero,
    this.leading,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;

  /// Navigation bar, rendered under the banner.
  final Widget? bottomBar;

  final bool showBanner;
  final EdgeInsetsGeometry padding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions, leading: leading),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: Padding(padding: padding, child: body),
      ),
      bottomNavigationBar: _bottom(),
    );
  }

  /// Banner first, navigation bar under it. Returns `null` when there is
  /// neither, so the scaffold reserves no space at all.
  Widget? _bottom() {
    final Widget? bar = bottomBar;
    if (!showBanner) return bar;
    if (bar == null) return const AdaptiveBannerAd();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[const AdaptiveBannerAd(), bar],
    );
  }
}
