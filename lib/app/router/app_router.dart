import 'package:go_router/go_router.dart';

import '../screens/editor_screen.dart';
import '../screens/export_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/home_screen.dart';
import '../screens/music_screen.dart';
import '../screens/my_creation_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/gallery',
      builder: (context, state) => const GalleryScreen(),
    ),
    GoRoute(
      path: '/editor',
      builder: (context, state) => const EditorScreen(),
    ),
    GoRoute(
      path: '/music',
      builder: (context, state) => const MusicScreen(),
    ),
    GoRoute(
      path: '/export',
      builder: (context, state) => const ExportScreen(),
    ),
    GoRoute(
      path: '/creations',
      builder: (context, state) => const MyCreationScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
