import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';

const _fcmChannelId = 'high_importance_channel';
const _fcmChannelName = 'Push notifications';

/// Background FCM handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _ready = false;
  static bool get isReady => _ready;

  /// Latest FCM registration token (for Firebase Console test message).
  static String? fcmToken;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (_ready) return;
    try {
      final options = DefaultFirebaseOptions.currentPlatform;
      if (options.appId.contains('REPLACE_WITH')) {
        debugPrint(
          'FirebaseBootstrap: iOS GoogleService-Info.plist / appId '
          'not configured yet — skipping Firebase init.',
        );
        return;
      }
      await Firebase.initializeApp(options: options);

      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );

      await _initLocalNotifications();

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _configureMessaging();

      _ready = true;
    } catch (e, st) {
      debugPrint('FirebaseBootstrap.init failed: $e\n$st');
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _fcmChannelId,
        _fcmChannelName,
        description: 'Slideshow Maker alerts',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    await _localNotifications.show(
      id: notification.hashCode ^ message.messageId.hashCode,
      title: title ?? 'Slideshow Maker',
      body: body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _fcmChannelId,
          _fcmChannelName,
          channelDescription: 'Slideshow Maker alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.isEmpty ? null : message.data.toString(),
    );
  }

  static Future<String?> refreshFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        if (apns == null) return null;
      }
      // ignore: deprecated_member_use — needed for Firebase Console test message
      final token = await messaging.getToken();
      fcmToken = token;
      if (token != null) {
        debugPrint('======== FCM TOKEN (copy for Console test) ========');
        debugPrint(token);
        debugPrint('===================================================');
      }
      return token;
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }

  static Future<void> _configureMessaging() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      String? apns = await messaging.getAPNSToken();
      for (var i = 0; apns == null && i < 5; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        apns = await messaging.getAPNSToken();
      }
      if (apns == null) {
        debugPrint('FCM: APNs token not ready yet');
        return;
      }
    }

    await refreshFcmToken();
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((token) {
      fcmToken = token;
      debugPrint('======== FCM TOKEN REFRESH ========');
      debugPrint(token);
      debugPrint('===================================');
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        'FCM foreground: ${message.notification?.title} '
        '${message.notification?.body}',
      );
      unawaited(_showForegroundNotification(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('FCM opened from background: ${message.messageId}');
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('FCM opened from terminated: ${initial.messageId}');
    }
  }
}
