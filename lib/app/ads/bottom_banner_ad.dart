import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_ids.dart';

/// Bottom banner slot.
///
/// [reserveSpace]: when true (Export / Studio), keeps an empty white box at
/// banner height while loading / after failure. When false (Home), the widget
/// collapses to zero height until the ad loads, and stays hidden on failure.
class BottomBannerAd extends StatefulWidget {
  const BottomBannerAd({super.key, this.reserveSpace = true});

  final bool reserveSpace;

  @override
  State<BottomBannerAd> createState() => _BottomBannerAdState();
}

class _BottomBannerAdState extends State<BottomBannerAd> {
  BannerAd? _bannerAd;
  bool _loaded = false;
  bool _disposed = false;

  static double get _bannerHeight => AdSize.banner.height.toDouble();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _load();
    }
  }

  void _load() {
    if (_disposed) return;

    _bannerAd?.dispose();
    _bannerAd = null;
    _loaded = false;

    final ad = BannerAd(
      adUnitId: AdmobIds.bannerAdUnitId(isAndroid: Platform.isAndroid),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || _disposed) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BottomBannerAd failed: $error');
          ad.dispose();
          if (!mounted || _disposed) return;
          setState(() {
            _bannerAd = null;
            _loaded = false;
          });
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _disposed = true;
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAd = _loaded && _bannerAd != null;

    if (!widget.reserveSpace) {
      if (!showAd) return const SizedBox.shrink();
      return ColoredBox(
        color: Colors.white,
        child: SizedBox(
          width: double.infinity,
          height: _bannerHeight,
          child: Center(child: AdWidget(ad: _bannerAd!)),
        ),
      );
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      return SizedBox(height: _bannerHeight, width: double.infinity);
    }

    // Always reserve space — empty white box when not loaded / failed.
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: _bannerHeight,
        child: showAd
            ? Center(child: AdWidget(ad: _bannerAd!))
            : const SizedBox.expand(),
      ),
    );
  }
}
