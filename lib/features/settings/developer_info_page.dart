import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/localization/app_locale.dart';

class DeveloperInfoPage extends StatelessWidget {
  const DeveloperInfoPage({super.key});

  static const String developerName = 'Abanoub Samy';
  static const String githubUsername = 'CyberBonk';
  static const String githubUrl = 'https://github.com/CyberBonk';
  static const String repoUrl = 'https://github.com/CyberBonk/Timer-Be-Perfect';

  Future<void> _openUrl(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Could not open link: $urlString',
                  'تعذر فتح الرابط: $urlString',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Failed to launch URL: $e',
                'فشل في فتح الرابط: $e',
              ),
            ),
          ),
        );
      }
    }
  }

  void _copyGamertag(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: githubUsername));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'Copied @$githubUsername to clipboard!',
            'تم نسخ @$githubUsername إلى الحافظة!',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('Developer Information', 'معلومات المطوّر'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        children: [
          // Hero Profile Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary,
                          colorScheme.tertiary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'CB',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    developerName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _copyGamertag(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.alternate_email,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            githubUsername,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      context.tr(
                        'Lead Architect & Creator',
                        'المعماري والمطوّر الرئيسي',
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.tr(
                      'Timer Be Perfect was designed and developed by CyberBonk as a resilient, multi-device event coordination and timing solution for church youth activities.',
                      'تم تصميم وتطوير تطبيق Timer Be Perfect بالكامل بواسطة CyberBonk كنظام متكامل لتنسيق الأوقات وإدارة الفعاليات الشبابية الكنسية مع دقة التزامن والعمل دون اتصال.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openUrl(context, githubUrl),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(
                            context.tr('GitHub Profile', 'ملف GitHub'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _copyGamertag(context),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(context.tr('Copy Tag', 'نسخ الحساب')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Project Architecture & Credits Section
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.engineering_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        context.tr(
                          'Engineering Highlights',
                          'أبرز الخصائص الهندسية',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildHighlightTile(
                    context: context,
                    icon: Icons.timer_outlined,
                    title: context.tr(
                      'Offline Schedule Calculation',
                      'حساب الجدول الزمني دون اتصال',
                    ),
                    description: context.tr(
                      'Pure Dart deterministic schedule engine that prevents per-second network thrashing and survives temporary outages.',
                      'محرك زمني بدارت الخالصة يحسب الحالات محليًا دون استهلاك للشبكة ويعمل أثناء الانقطاع.',
                    ),
                  ),
                  const Divider(height: 24),
                  _buildHighlightTile(
                    context: context,
                    icon: Icons.cloud_done_outlined,
                    title: context.tr(
                      'Dual-Path Firebase Backend',
                      'بنية فايربيس ثنائية المسار',
                    ),
                    description: context.tr(
                      'Automated Cloud Functions v2 deployment with a secure, atomic direct-Firestore fallback path.',
                      'دوال سحابية مع مسار احتياطي مباشر مشفر ومحمي بقواعد الأمان الصارمة.',
                    ),
                  ),
                  const Divider(height: 24),
                  _buildHighlightTile(
                    context: context,
                    icon: Icons.volume_up_outlined,
                    title: context.tr(
                      'OEM & Huawei EMUI Audio Protection',
                      'حماية الصوت وأجهزة هواوي EMUI',
                    ),
                    description: context.tr(
                      'Volume elevation across audio streams, DND bypass management, and persistent boundary alarms.',
                      'رفع مستوى الصوت عبر القنوات الصوتية وتفادي كتم التنبيهات في واجهات النظام المختلفة.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Repository / Source Tile
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.code_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              title: Text(
                context.tr('Source Repository', 'مستودع الكود'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                context.tr(
                  'Explore the open code and release history',
                  'استعرض الكود المصدري وسجل الإصدارات',
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _openUrl(context, repoUrl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
