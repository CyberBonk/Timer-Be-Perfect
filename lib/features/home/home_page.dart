import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/localization/app_locale.dart';
import '../rooms/join_room_dialog.dart';
import '../settings/settings_page.dart';
import '../settings/about_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isCreating = false;

  Future<void> _createRoom() async {
    setState(() => _isCreating = true);
    try {
      final repo = ref.read(roomRepositoryProvider);
      final res = await repo.createRoom();

      await ref.read(activeRoomPinProvider.notifier).update(res['pin']);
      await ref.read(activeRoomIdProvider.notifier).update(res['roomId']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('Error creating room', 'تعذر إنشاء الغرفة')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showJoinRoomDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const JoinRoomDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final double screenWidth = mediaQuery.size.width;
    final double screenHeight = mediaQuery.size.height;

    final double logoSize = (screenWidth * 0.42).clamp(140.0, 190.0);
    final double verticalSpacing = (screenHeight * 0.025).clamp(12.0, 32.0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: context.tr('Settings', 'الإعدادات'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: context.tr(
              'About Timer Be Perfect',
              'حول Timer Be Perfect',
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: (screenWidth * 0.06).clamp(16.0, 32.0),
            vertical: 20.0,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(logoSize * 0.18),
                ),
                child: Image.asset(
                  'assets/branding/logo-transparent.png',
                  fit: BoxFit.contain,
                  semanticLabel: context.tr(
                    'Be Perfect logo',
                    'شعار كنوا كاملين',
                  ),
                ),
              ),
              SizedBox(height: verticalSpacing * 0.7),
              Text(
                'Timer Be Perfect',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                  'Church Event Timer & Round Coordinator',
                  'مؤقت ومنسّق جولات للفعاليات الكنسية',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: verticalSpacing),

              // 1-Tap Direct Create Room Button (No modal redundancy)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  key: const ValueKey('create-room-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _isCreating ? null : _createRoom,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.add_circle_outline, size: 24),
                  label: Text(
                    _isCreating
                        ? context.tr('Creating Room...', 'جارٍ إنشاء الغرفة...')
                        : context.tr('Create Room', 'إنشاء غرفة'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Participant entry button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  key: const ValueKey('join-room-button'),
                  style: OutlinedButton.styleFrom(
                    side:
                        BorderSide(color: theme.colorScheme.primary, width: 2),
                    foregroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _showJoinRoomDialog(context),
                  icon: const Icon(Icons.login, size: 24),
                  label: Text(
                    context.tr('Join as Participant', 'الانضمام كمشارك'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
