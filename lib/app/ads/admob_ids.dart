import 'package:flutter/foundation.dart';

/// AdMob app + banner unit IDs (Slideshow Maker).
abstract final class AdmobIds {
  AdmobIds._();

  static const androidAppId = 'ca-app-pub-9877635475483541~8716324031';
  static const iosAppId = 'ca-app-pub-9877635475483541~8716324031';

  /// Production banner — Export / Studio screens.
  static const androidBanner = 'ca-app-pub-9877635475483541/7898028397';
  static const iosBanner = 'ca-app-pub-9877635475483541/7898028397';

  /// Production interstitial — shown after Start Export.
  static const androidInterstitial = 'ca-app-pub-9877635475483541/3000924930';
  static const iosInterstitial = 'ca-app-pub-9877635475483541/3000924930';

  /// Google sample banner (debug loads).
  static const _sampleBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _sampleBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  /// Google sample interstitial (debug loads).
  static const _sampleInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _sampleInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static String bannerAdUnitId({required bool isAndroid}) {
    if (kDebugMode) {
      return isAndroid ? _sampleBannerAndroid : _sampleBannerIos;
    }
    return isAndroid ? androidBanner : iosBanner;
  }

  static String interstitialAdUnitId({required bool isAndroid}) {
    if (kDebugMode) {
      return isAndroid ? _sampleInterstitialAndroid : _sampleInterstitialIos;
    }
    return isAndroid ? androidInterstitial : iosInterstitial;
  }
}
