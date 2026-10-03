import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _tile(
            Icons.star_outline,
            'Rate Us',
            () => _openUrl(
              'https://play.google.com/store/apps/details?id=${AppConstants.packageId}',
            ),
          ),
          _tile(
            Icons.share_outlined,
            'Share App',
            () {
              SharePlus.instance.share(
                ShareParams(
                  text:
                      'Check out ${AppConstants.appName} — make photo slideshows easily!',
                ),
              );
            },
          ),
          _tile(
            Icons.privacy_tip_outlined,
            'Privacy Policy',
            () => _openUrl('https://sites.google.com/view/graphicscycle/home'),
          ),
          _tile(
            Icons.description_outlined,
            'Terms of Service',
            () => _openUrl('https://sites.google.com/view/graphicscycle/home'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.iconNormal),
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '…' : _version),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
