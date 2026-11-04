import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Design canvas matched to typical phone mockups (≈ iPhone 14 / Figma 390×844).
class AppResponsive {
  AppResponsive._(this.size, this.viewPadding);

  final Size size;
  final EdgeInsets viewPadding;

  static const designWidth = 390.0;
  static const designHeight = 844.0;
  static const tabletBreakpoint = 600.0;
  static const largeTabletBreakpoint = 900.0;

  /// Soft clamp so tiny/huge phones don't explode layout.
  static const minScale = 0.82;
  static const maxScale = 1.30;

  double get width => size.width;
  double get height => size.height;
  double get shortest => math.min(width, height);
  double get longest => math.max(width, height);

  double get scaleW => (width / designWidth).clamp(minScale, maxScale);
  double get scaleH => (height / designHeight).clamp(minScale, maxScale);
  double get scale => math.min(scaleW, scaleH);

  bool get isPhone => width < tabletBreakpoint;
  bool get isTablet => width >= tabletBreakpoint;
  bool get isLargeTablet => width >= largeTabletBreakpoint;
  bool get isLandscape => width > height;

  /// Horizontal page inset (scaled).
  double get pagePad => w(16);

  /// Max readable content width on tablets / landscape.
  double get maxContentWidth {
    if (isLargeTablet) return 840;
    if (isTablet) return 720;
    return width;
  }

  /// Scale by width (paddings, horizontal sizes).
  double w(double design) => design * scaleW;

  /// Scale by height (vertical gaps, sheet heights).
  double h(double design) => design * scaleH;

  /// Uniform scale (icons, radius, shared chrome).
  double r(double design) => design * scale;

  /// Font size — width-based, slightly softer clamp.
  double sp(double design) =>
      design * scaleW.clamp(minScale, 1.22);

  int gridCrossAxisCount({
    int phone = 3,
    int tablet = 4,
    int largeTablet = 5,
  }) {
    if (isLargeTablet) return largeTablet;
    if (isTablet) return tablet;
    return phone;
  }

  EdgeInsets pageInsets({
    double horizontal = 16,
    double top = 0,
    double bottom = 0,
  }) =>
      EdgeInsets.fromLTRB(w(horizontal), h(top), w(horizontal), h(bottom));

  static AppResponsive of(BuildContext context) {
    final scope = ResponsiveScope.maybeOf(context);
    if (scope != null) return scope;
    final mq = MediaQuery.of(context);
    return AppResponsive._(mq.size, mq.padding);
  }

  static AppResponsive fromMediaQuery(MediaQueryData mq) =>
      AppResponsive._(mq.size, mq.padding);
}

/// Inherited scale + optional content-width centering for the whole app.
class ResponsiveScope extends InheritedWidget {
  const ResponsiveScope({
    super.key,
    required this.data,
    required super.child,
  });

  final AppResponsive data;

  static AppResponsive? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ResponsiveScope>()
        ?.data;
  }

  static AppResponsive of(BuildContext context) {
    final found = maybeOf(context);
    assert(found != null, 'ResponsiveScope not found in context');
    return found ?? AppResponsive.of(context);
  }

  @override
  bool updateShouldNotify(ResponsiveScope oldWidget) {
    return oldWidget.data.width != data.width ||
        oldWidget.data.height != data.height;
  }
}

/// Centers children and caps width on tablet / landscape.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final r = AppResponsive.of(context);
    if (!r.isTablet && !r.isLandscape) return child;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.maxContentWidth),
        child: child,
      ),
    );
  }
}

/// Wraps [MaterialApp] child: init scale, clamp system text scale, expose scope.
class ResponsiveApp extends StatelessWidget {
  const ResponsiveApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final data = AppResponsive.fromMediaQuery(mq);
    final userScale = mq.textScaler.scale(1.0);
    final clamped = userScale.clamp(0.88, 1.18);

    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(clamped)),
      child: ResponsiveScope(data: data, child: child),
    );
  }
}

extension AppResponsiveContext on BuildContext {
  AppResponsive get resp => AppResponsive.of(this);
}

extension AppResponsiveNum on num {
  double w(BuildContext context) => AppResponsive.of(context).w(toDouble());
  double h(BuildContext context) => AppResponsive.of(context).h(toDouble());
  double r(BuildContext context) => AppResponsive.of(context).r(toDouble());
  double sp(BuildContext context) => AppResponsive.of(context).sp(toDouble());
}
