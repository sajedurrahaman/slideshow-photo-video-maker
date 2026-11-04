import 'package:flutter/material.dart';

import '../core/responsive/app_responsive.dart';
import '../core/theme/app_theme.dart';

class TealPillButton extends StatelessWidget {
  const TealPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final radius = BorderRadius.circular(rs.r(8));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled ? AppColors.primaryGradient : null,
            color: enabled
                ? null
                : AppColors.primaryStart.withValues(alpha: 0.35),
            borderRadius: radius,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: rs.h(34)),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rs.w(16),
                vertical: rs.h(2),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: rs.sp(12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EditorToolIcon extends StatelessWidget {
  const EditorToolIcon({
    super.key,
    this.icon,
    this.assetPath,
    required this.label,
    required this.selected,
    required this.onTap,
  }) : assert(icon != null || assetPath != null);

  final IconData? icon;
  final String? assetPath;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final muted = AppColors.iconNormal;
    final iconSize = rs.r(24);
    Widget iconWidget;
    if (assetPath != null) {
      iconWidget = Image.asset(
        assetPath!,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        color: selected ? Colors.white : muted,
        errorBuilder: (_, _, _) => Icon(
          icon ?? Icons.extension_outlined,
          color: selected ? Colors.white : muted,
          size: iconSize,
        ),
      );
    } else {
      iconWidget = Icon(
        icon!,
        color: selected ? Colors.white : muted,
        size: iconSize,
      );
    }
    if (selected) {
      iconWidget = PrimaryGradientMask(child: iconWidget);
    }

    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: rs.sp(11),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : muted,
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(rs.r(10)),
      child: SizedBox(
        width: rs.w(64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            SizedBox(height: rs.h(4)),
            if (selected)
              PrimaryGradientMask(child: labelWidget)
            else
              labelWidget,
          ],
        ),
      ),
    );
  }
}

/// Centered sheet title: textDark with a short underline.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 36,
          height: 2.5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}

class SectionSheet extends StatelessWidget {
  const SectionSheet({
    super.key,
    required this.title,
    required this.child,
    this.height = 168,
    this.headerRow,
    this.onClose,
    this.onConfirm,
    this.beforeConfirm,
    this.compactHeader = false,
    this.showTopDivider = true,
    this.center,
  });

  final String title;
  final Widget child;
  final double height;
  final Widget? center;

  /// Optional row shown at the top of the sheet (e.g. preview controls).
  /// Built by the parent so this widget stays free of project/state logic.
  final Widget? headerRow;
  final VoidCallback? onClose;
  final VoidCallback? onConfirm;
  final Widget? beforeConfirm;
  final bool compactHeader;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: showTopDivider
            ? const Border(top: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (headerRow != null)
            Padding(
              // Match editor idle timeline header inset (play/pause Y stable).
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: headerRow!,
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(8, compactHeader ? 0 : 0, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: compactHeader
                      ? const BoxConstraints(minWidth: 32, minHeight: 20)
                      : null,
                  icon: const Icon(Icons.close, color: AppColors.textDark),
                ),
                center ?? SheetTitle(title),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?beforeConfirm,
                    IconButton(
                      onPressed: onConfirm,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: compactHeader
                          ? const BoxConstraints(minWidth: 32, minHeight: 20)
                          : null,
                      icon: const Icon(Icons.check, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
