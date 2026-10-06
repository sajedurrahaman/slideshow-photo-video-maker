import 'package:flutter/material.dart';

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
    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: enabled
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 34),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
    final color = selected ? AppColors.primary : AppColors.iconNormal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (assetPath != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                child: Image.asset(
                  assetPath!,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    icon ?? Icons.extension_outlined,
                    color: color,
                    size: 24,
                  ),
                ),
              )
            else
              Icon(icon!, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
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
  });

  final String title;
  final Widget child;
  final double height;

  /// Optional row shown at the top of the sheet (e.g. preview controls).
  /// Built by the parent so this widget stays free of project/state logic.
  final Widget? headerRow;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (headerRow != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: headerRow!,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.close, color: AppColors.textDark),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    // decorationColor: AppColors.primary,
                    // decorationThickness: 2,
                    // decorationStyle: TextDecorationStyle.solid,
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.check, color: AppColors.primary),
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
