import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/core/theme/app_theme.dart';
import 'app/router/app_router.dart';
import 'app/services/slideshow_project.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      ),
    );
  }
}
