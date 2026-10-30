import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Shared overlay for [SlideshowProject.isPreparingPreview].
/// Same Lottie as native Photo-Slideshow-Maker (`video_theme_loading.json`).
class PreparingPreviewOverlay extends StatelessWidget {
  const PreparingPreviewOverlay({
    super.key,
    this.dimColor = const Color(0x73000000),
    this.size = 72,
  });

  final Color dimColor;
  final double size;

  static const assetPath = 'assets/lottie/video_theme_loading.json';

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dimColor,
      child: Center(
        child: Lottie.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
        ),
      ),
    );
  }
}
