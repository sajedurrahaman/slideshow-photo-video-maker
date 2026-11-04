import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'interstitial_ad_helper.dart';

Future<void> initializeMobileAds() async {
  try {
    await MobileAds.instance.initialize();
    if (kDebugMode) {
      debugPrint('MobileAds initialized');
    }
    InterstitialAdHelper.preload();
  } catch (e, st) {
    debugPrint('MobileAds.initialize failed: $e\n$st');
  }
}
