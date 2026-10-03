import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Splash matches native SplashActivity feel: brand + brief delay then home.
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
    final minWait = Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      await Future.wait([
        minWait,
        ..._homeAssets.map(
          (path) => precacheImage(AssetImage(path), context),
        ),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.slideshow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Slideshows',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Photo Video Maker',
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
