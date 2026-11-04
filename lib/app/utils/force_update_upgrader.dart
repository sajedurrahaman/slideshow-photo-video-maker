import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import '../core/app_navigator_key.dart';

/// Reused across [MaterialApp] builder rebuilds so version checks are not reset.
final Upgrader _forceUpdateUpgrader = createForceUpdateUpgrader();

/// Soft update when a newer store build exists.
/// User can tap "SKIP NOW" and keep using the current version.
/// Hard force update (no skip) applies when store listing sets a min app version
/// (upgrader reads it from the store description / version info).
Upgrader createForceUpdateUpgrader() {
  return Upgrader(
    debugLogging: kDebugMode,
    // After skip, don't show again until this duration passes.
    durationUntilAlertAgain: const Duration(days: 1),
    messages: _SkipNowUpgraderMessages(),
  );
}

/// Wraps [child] so an upgrade dialog can show when a newer version exists.
Widget wrapWithForceUpdateAlert({required Widget child}) {
  return _SafeForceUpdateAlert(
    upgrader: _forceUpdateUpgrader,
    navigatorKey: rootNavigatorKey,
    barrierDismissible: false,
    shouldPopScope: () => true,
    showIgnore: false,
    showLater: true,
    dialogStyle: Platform.isIOS
        ? UpgradeDialogStyle.cupertino
        : UpgradeDialogStyle.material,
    child: child,
  );
}

/// [UpgradeAlert] in [MaterialApp.builder] sits *above* the [Navigator].
/// Showing the dialog with that context can hit a null navigator — use the root
/// [rootNavigatorKey] context, and skip until it is ready.
class _SafeForceUpdateAlert extends UpgradeAlert {
  _SafeForceUpdateAlert({
    required super.upgrader,
    super.navigatorKey,
    super.barrierDismissible,
    super.shouldPopScope,
    super.showIgnore,
    super.showLater,
    super.dialogStyle,
    super.child,
  });

  @override
  UpgradeAlertState createState() => _SafeForceUpdateAlertState();
}

class _SafeForceUpdateAlertState extends UpgradeAlertState {
  @override
  void showTheDialog({
    Key? key,
    required BuildContext context,
    required String? title,
    required String message,
    required String? releaseNotes,
    required bool barrierDismissible,
    required UpgraderMessages messages,
  }) {
    final dialogContext = _dialogContext(context);
    if (dialogContext == null) {
      // Navigator is not in the tree yet (splash / first frames). Retry.
      displayed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    super.showTheDialog(
      key: key,
      context: dialogContext,
      title: title,
      message: message,
      releaseNotes: releaseNotes,
      barrierDismissible: barrierDismissible,
      messages: messages,
    );
  }

  BuildContext? _dialogContext(BuildContext fallback) {
    final fromKey = widget.navigatorKey?.currentContext;
    if (_canShowDialog(fromKey)) return fromKey;
    if (_canShowDialog(fallback)) return fallback;
    return null;
  }

  bool _canShowDialog(BuildContext? ctx) {
    if (ctx == null || !ctx.mounted) return false;
    return Navigator.maybeOf(ctx, rootNavigator: true) != null;
  }
}

class _SkipNowUpgraderMessages extends UpgraderMessages {
  @override
  String get buttonTitleLater => 'SKIP NOW';

  @override
  String get buttonTitleUpdate => 'UPDATE NOW';
}
