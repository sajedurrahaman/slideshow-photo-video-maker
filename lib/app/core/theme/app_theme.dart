import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand tokens — primary CTAs use [primaryGradient].
class AppColors {
  static const primaryStart = Color(0xFF26EBD7);
  static const primaryEnd = Color(0xFF33B5F1);

  /// Solid fallback for icons / accents (gradient start).
  static const primary = primaryStart;
  static const primaryDark = primaryEnd;
  static const primarySoft = Color(0xFFE6FBFF);
  static const accent = primaryEnd;
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF5F6F8);
  static const textDark = Color(0xFF1C1C1E);
  static const textMuted = Color(0xFF8E8E93);
  static const border = Color(0xFFE5E5EA);
  static const danger = Color(0xFFFF3B30);
  static const iconActive = primary;
  static const iconNormal = Color(0xFF8E8E93);

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryStart, primaryEnd],
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.border,
      // Solid fallback; gradient CTAs use [TealPillButton] / [PrimaryGradientButton].
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: AppColors.primarySoft,
        backgroundColor: AppColors.surfaceAlt,
        side: BorderSide.none,
        labelStyle: const TextStyle(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primary,
        inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
      ),
    );
  }
}

/// Primary filled CTA with brand linear gradient.
class PrimaryGradientButton extends StatelessWidget {
  const PrimaryGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.height = 48,
    this.borderRadius = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
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
          child: Container(
            height: height,
            padding: padding,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
