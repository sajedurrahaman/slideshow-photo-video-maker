import 'package:go_router/go_router.dart';

import '../core/app_navigator_key.dart';
import '../screens/crop_screen.dart';
import '../screens/drafts_screen.dart';
import '../screens/editor_screen.dart';
import '../screens/export_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/home_screen.dart';
import '../screens/music_screen.dart';
import '../screens/my_creation_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/video_editor_screen.dart';

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
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
      builder: (context, state) {
        final insert =
            state.uri.queryParameters['insert'] == '1' ||
            state.uri.queryParameters['insert'] == 'true';
        final at = int.tryParse(state.uri.queryParameters['at'] ?? '') ?? 0;
        final video =
            state.uri.queryParameters['type'] == 'video' ||
            state.uri.queryParameters['video'] == '1';
        return GalleryScreen(
          insertMode: insert,
          insertIndex: at,
          videoMode: video,
        );
      },
    ),
    GoRoute(
      path: '/editor',
      builder: (context, state) => const EditorScreen(),
    ),
    GoRoute(
      path: '/video-editor',
      builder: (context, state) {
        final extra = state.extra;
        final paths = extra is List<String>
            ? extra
            : extra is List
                ? extra.whereType<String>().toList()
                : <String>[];
        return VideoEditorScreen(videoPaths: paths);
      },
    ),
    GoRoute(
      path: '/crop',
      builder: (context, state) => const CropScreen(),
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
      path: '/drafts',
      builder: (context, state) => const DraftsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
