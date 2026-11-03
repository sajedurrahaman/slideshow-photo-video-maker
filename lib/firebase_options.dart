// File generated manually from Firebase project
// Project: clipcraft-image-slider-maker
//
// Android values come from android/app/google-services.json.
// iOS values come from ios/Runner/GoogleService-Info.plist — replace that
// plist (and update ios below) after adding the iOS app in Firebase Console.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCucxz5CQG9fHglSAQPLCH9SojfonA2XHI',
    appId: '1:167487194042:android:60ed2e2dbaac2ece8f5383',
    messagingSenderId: '167487194042',
    projectId: 'clipcraft-image-slider-maker',
    storageBucket: 'clipcraft-image-slider-maker.firebasestorage.app',
  );

  /// Update [appId] / [iosBundleId] after registering the iOS app in Firebase
  /// and downloading GoogleService-Info.plist into ios/Runner/.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCucxz5CQG9fHglSAQPLCH9SojfonA2XHI',
    appId: 'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '167487194042',
    projectId: 'clipcraft-image-slider-maker',
    storageBucket: 'clipcraft-image-slider-maker.firebasestorage.app',
    iosBundleId: 'app.graphics_cycle.clipCraft',
  );
}
