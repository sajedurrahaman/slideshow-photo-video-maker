import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Splash styled like the marketing splash: white canvas, soft cyan
/// bubbles/wave (code-drawn), brand logo, "Slide"+"show" title, tagline.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  bool _navigated = false;

  static const _brandCyan = Color(0xFF00C2E8);

  static const _homeAssets = [
    'assets/images/home/slider/slide_1.png',
    'assets/images/home/slider/slide_2.png',
    'assets/images/home/slider/slide_3.jpg',
    'assets/images/home/slider/slide_4.png',
    'assets/images/slideshowbutton.png',
    'assets/images/slideshow.png',
    'assets/images/studiobutton.png',
    'assets/images/studio.png',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareAndGo());
  }

  Future<void> _prepareAndGo() async {
    if (!mounted || _navigated) return;
    final minWait = Future<void>.delayed(const Duration(milliseconds: 1400));
    try {
      await Future.wait([
        minWait,
        ..._homeAssets.map((path) => precacheImage(AssetImage(path), context)),
      ]);
    } catch (_) {
      // Still navigate if an asset fails; home has fallbacks.
    }
    if (!mounted || _navigated) return;
    _navigated = true;
    context.go('/home');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Match marketing splash logo size (~78% of screen width).
    final iconSize = 120.0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fade,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _SplashDecorPainter(color: _brandCyan)),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _BrandTitle(cyan: _brandCyan),
                    const Text(
                      'Turn Your Photos into Amazing Videos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.cyan});

  final Color cyan;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 28, height: 2, color: cyan),
        const SizedBox(width: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Slide',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: cyan,
                  letterSpacing: -0.4,
                ),
              ),
              const TextSpan(
                text: 'show',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 28, height: 2, color: cyan),
      ],
    );
  }
}

/// Soft bubbles + bottom-right layered waves matching the design curve.
class _SplashDecorPainter extends CustomPainter {
  const _SplashDecorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = color.withValues(alpha: 0.10);
    final softer = Paint()..color = color.withValues(alpha: 0.055);

    void bubble(Offset c, double r, Paint p) => canvas.drawCircle(c, r, p);

    bubble(Offset(size.width * 0.12, size.height * 0.10), 46, soft);
    bubble(Offset(size.width * 0.28, size.height * 0.06), 18, softer);
    bubble(Offset(size.width * 0.88, size.height * 0.14), 52, soft);
    bubble(Offset(size.width * 0.78, size.height * 0.08), 16, softer);
    bubble(Offset(size.width * 0.18, size.height * 0.70), 26, softer);
    bubble(Offset(size.width * 0.99, size.height * 0.78), 44, softer);
    bubble(Offset(size.width * 0.12, size.height * 0.99), 48, softer);

    // Path cornerWave({
    //   required double startX,
    //   required double midY,
    //   required double endY,
    //   required double lift,
    // }) {
    //   return Path()
    //     ..moveTo(startX, size.height)
    //     ..cubicTo(
    //       startX + size.width * 0.18,
    //       size.height * 0.995,
    //       size.width * 0.38,
    //       size.height * midY,
    //       size.width * 0.58,
    //       size.height * (midY - 0.02),
    //     )
    //     ..cubicTo(
    //       size.width * 0.78,
    //       size.height * (midY - 0.06),
    //       size.width * 0.90,
    //       size.height * endY,
    //       size.width * 1.05,
    //       size.height * (endY - lift),
    //     )
    //     ..lineTo(size.width * 1.05, size.height * 1.05)
    //     ..lineTo(startX, size.height * 1.05)
    //     ..close();
    // }

    // Faintest wide wash (extends furthest left).
    // canvas.drawPath(
    //   cornerWave(
    //     startX: size.width * -0.05,
    //     midY: 0.92,
    //     endY: 0.78,
    //     lift: 0.12,
    //   ),
    //   Paint()..color = color.withValues(alpha: 0.10),
    // );

    // // Soft translucent middle wave.
    // canvas.drawPath(
    //   cornerWave(startX: size.width * 0.05, midY: 0.91, endY: 0.74, lift: 0.14),
    //   Paint()
    //     ..shader =
    //         LinearGradient(
    //           begin: Alignment.bottomLeft,
    //           end: Alignment.topRight,
    //           colors: [
    //             color.withValues(alpha: 0.12),
    //             color.withValues(alpha: 0.28),
    //             color.withValues(alpha: 0.42),
    //           ],
    //         ).createShader(
    //           Rect.fromLTWH(
    //             0,
    //             size.height * 0.55,
    //             size.width,
    //             size.height * 0.45,
    //           ),
    //         ),
    // );

    // // Solid cyan front wave — bottom-right corner.
    // canvas.drawPath(
    //   cornerWave(startX: size.width * 0.22, midY: 0.99, endY: 0.86, lift: 0.01),
    //   Paint()
    //     ..shader =
    //         LinearGradient(
    //           begin: Alignment.bottomCenter,
    //           end: Alignment.topRight,
    //           colors: [
    //             color,
    //             color.withValues(alpha: 0.92),
    //             color.withValues(alpha: 0.72),
    //           ],
    //         ).createShader(
    //           Rect.fromLTWH(
    //             size.width * 0.2,
    //             size.height * 0.55,
    //             size.width * 0.85,
    //             size.height * 0.45,
    //           ),
    //         ),
    // );
  }

  @override
  bool shouldRepaint(covariant _SplashDecorPainter oldDelegate) =>
      oldDelegate.color != color;
}
