import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/ads/admob_bootstrap.dart';
import 'app/core/responsive/app_responsive.dart';
import 'app/core/theme/app_theme.dart';
import 'app/router/app_router.dart';
import 'app/services/firebase_bootstrap.dart';
import 'app/services/slideshow_project.dart';
import 'app/utils/force_update_upgrader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.init();
  await initializeMobileAds();
  runApp(const ClipCraftApp());
}

class ClipCraftApp extends StatelessWidget {
  const ClipCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SlideshowProject(),
      child: MaterialApp.router(
        title: 'Slideshows',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
        builder: (context, child) {
          return ResponsiveApp(
            child: wrapWithForceUpdateAlert(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
