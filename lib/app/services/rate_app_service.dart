import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';

/// Google Play / App Store in-app review (the native "Rate this app" sheet).
///
/// Notes:
/// - Dialog is controlled by the store (quota / eligibility). It may not appear
///   every tap, especially on debug / sideloaded builds.
/// - If the plugin is missing (hot-reload after `pub add`) or unavailable,
///   falls back to opening the Play Store URL via [url_launcher].
class RateAppService {
  RateAppService._();

  static final InAppReview _api = InAppReview.instance;

  static Uri get _playStoreUri => Uri.parse(
        'https://play.google.com/store/apps/details?id=${AppConstants.packageId}',
      );

  /// Prefer in-app review UI; otherwise open Play Store / App Store page.
  static Future<void> rateUs({String? appStoreId}) async {
    try {
      if (await _api.isAvailable()) {
        await _api.requestReview();
        return;
      }
    } on MissingPluginException {
      // Native channel not linked yet (needs full restart after adding plugin).
    } catch (_) {
      // Fall through to store listing.
    }
    await openStore(appStoreId: appStoreId);
  }

  /// After a successful export — in-app review sheet only (never leaves the app).
  /// Google/Apple may suppress the dialog based on quota; that is expected.
  static Future<void> promptAfterExportSuccess() async {
    try {
      if (await _api.isAvailable()) {
        await _api.requestReview();
      }
    } on MissingPluginException {
      // Needs full app restart after adding the plugin.
    } catch (_) {
      // Ignore — export success UI must not break.
    }
  }

  /// Opens the store listing. Uses plugin when linked; else [url_launcher].
  static Future<void> openStore({String? appStoreId}) async {
    try {
      await _api.openStoreListing(appStoreId: appStoreId);
      return;
    } on MissingPluginException {
      // Fall through.
    } catch (_) {
      // Fall through.
    }
    await launchUrl(_playStoreUri, mode: LaunchMode.externalApplication);
  }
}
