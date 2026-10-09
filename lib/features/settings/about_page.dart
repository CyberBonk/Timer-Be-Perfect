import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/localization/app_locale.dart';
import 'developer_info_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appName = 'Be Perfect';
  String _version = '2.0.0';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appName = info.appName.isNotEmpty ? info.appName : 'Be Perfect';
        _version = info.version;
      });
    } catch (_) {}
  }

  Future<void> _launchDeveloperUrl() async {
    final url = Uri.parse('https://github.com/CyberBonk');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('About', 'حول التطبيق')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _appName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Version $_version',
                  'الإصدار $_version',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.titleMedium,
                  children: [
                    TextSpan(
                      text: context.tr(
                        'Developed for Be Perfect by ',
                        'طُوّر لصالح Be Perfect بواسطة ',
                      ),
                    ),
                    TextSpan(
                      text: 'Abanoub Samy (CyberBonk)',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = _launchDeveloperUrl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeveloperInfoPage()),
                  );
                },
                icon: const Icon(Icons.person_pin_circle_outlined, size: 18),
                label: Text(
                  context.tr(
                    'Developer Information (@CyberBonk)',
                    'معلومات المطوّر (@CyberBonk)',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
