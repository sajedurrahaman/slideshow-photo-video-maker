import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_ids.dart';

/// Preloads + shows interstitial. Failures are silent — export keeps running.
class InterstitialAdHelper {
  InterstitialAdHelper._();

  static InterstitialAd? _ad;
  static bool _loading = false;

  static bool get isReady => _ad != null;

  static void preload() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_ad != null || _loading) return;

    _loading = true;
    InterstitialAd.load(
      adUnitId: AdmobIds.interstitialAdUnitId(isAndroid: Platform.isAndroid),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _ad = null;
              preload();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Interstitial failed to show: $error');
              ad.dispose();
              _ad = null;
              preload();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: $error');
          _loading = false;
          _ad = null;
        },
      ),
    );
  }

  /// Shows a loaded interstitial if available. Never throws; no-op if not ready.
  static Future<void> showIfReady() async {
    final ad = _ad;
    if (ad == null) {
      preload();
      return;
    }
    _ad = null;
    try {
      await ad.show();
    } catch (e) {
      debugPrint('Interstitial show error: $e');
      ad.dispose();
      preload();
    }
  }
}
