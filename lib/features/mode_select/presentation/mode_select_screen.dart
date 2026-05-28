// 측정 모드 선택 화면. AR / 사진 섹션 + 카드별 아이콘·배지. Capability에 따라 AR 안내 분기.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capability/measurement_mode.dart';
import '../../../core/capability/providers.dart';
import '../../../core/settings/last_used_mode.dart';
import '../../../core/settings/theme_mode_pref.dart';

class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capAsync = ref.watch(deviceCapabilityProvider);
    final arAvailable = capAsync.maybeWhen(
      data: (cap) =>
          selectAvailableModes(cap).contains(MeasurementMode.arTwoPoint),
      orElse: () => true,
    );
    final lastUsed = ref.watch(lastUsedModeProvider).valueOrNull;
    void go(String route) {
      ref.read(lastUsedModeProvider.notifier).set(route);
      context.go(route);
    }
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Length'),
        actions: [
          PopupMenuButton<ThemeMode>(
            icon: Icon(_iconFor(themeMode)),
            tooltip: '테마',
            onSelected: (m) =>
                ref.read(themeModeProvider.notifier).set(m),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: ThemeMode.system,
                child: Row(children: [
                  Icon(Icons.brightness_auto),
                  SizedBox(width: 12),
                  Text('시스템 따라가기'),
                ]),
              ),
              PopupMenuItem(
                value: ThemeMode.light,
                child: Row(children: [
                  Icon(Icons.light_mode),
                  SizedBox(width: 12),
                  Text('라이트'),
                ]),
              ),
              PopupMenuItem(
                value: ThemeMode.dark,
                child: Row(children: [
                  Icon(Icons.dark_mode),
                  SizedBox(width: 12),
                  Text('다크'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('AR'),
          _ModeCard(
            icon: Icons.view_in_ar,
            title: 'AR 두 점 측정',
            subtitle: arAvailable
                ? '실시간 카메라로 두 점 사이 거리.'
                : '이 기기는 AR 미지원 — 진입 시 사진 모드 안내.',
            enabled: arAvailable,
            badge: lastUsed == '/ar' ? '최근' : null,
            onTap: () => go('/ar'),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('사진'),
          _ModeCard(
            icon: Icons.credit_card,
            title: '참조 객체',
            subtitle: '신용카드 4점을 맞춰 측정. 빠르고 안정적.',
            recommended: lastUsed == null || lastUsed == '/photo/reference',
            badge: lastUsed == '/photo/reference' ? '최근' : null,
            onTap: () => go('/photo/reference'),
          ),
          _ModeCard(
            icon: Icons.qr_code_2,
            title: 'QR/마커',
            subtitle: 'QR을 자동 감지해 4점 보정.',
            badge: lastUsed == '/photo/marker' ? '최근' : '자동',
            onTap: () => go('/photo/marker'),
          ),
          _ModeCard(
            icon: Icons.set_meal,
            title: '물고기',
            subtitle: '카드 + 박스 한 번으로 직선 길이 자동.',
            badge: lastUsed == '/photo/fish' ? '최근' : '베타',
            onTap: () => go('/photo/fish'),
          ),
          _ModeCard(
            icon: Icons.straighten,
            title: '캘리브레이션 + 평면',
            subtitle: '단말 높이·FOV 입력 후 수직 촬영.',
            badge: lastUsed == '/photo/calibration' ? '최근' : null,
            onTap: () => go('/photo/calibration'),
          ),
          _ModeCard(
            icon: Icons.auto_awesome,
            title: 'AI 깊이 추정',
            subtitle: '단안 깊이 모델로 추정.',
            badge: lastUsed == '/photo/ai-depth' ? '최근' : '베타',
            onTap: () => go('/photo/ai-depth'),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('도구'),
          _ModeCard(
            icon: Icons.history,
            title: '이력 보기',
            subtitle: '저장한 측정 기록.',
            onTap: () => context.go('/history'),
            // 이력은 측정 모드가 아니므로 "최근" 대상에서 제외.
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

IconData _iconFor(ThemeMode m) {
  switch (m) {
    case ThemeMode.system:
      return Icons.brightness_auto;
    case ThemeMode.light:
      return Icons.light_mode;
    case ThemeMode.dark:
      return Icons.dark_mode;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.recommended = false,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool recommended;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = enabled
        ? (recommended ? scheme.onPrimary : scheme.primary)
        : scheme.outline;
    final iconBg = enabled
        ? (recommended ? scheme.primary : scheme.primaryContainer)
        : scheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        color: recommended ? scheme.primaryContainer : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: iconBg,
            child: Icon(icon, color: iconColor),
          ),
          title: Row(
            children: [
              Expanded(child: Text(title)),
              if (badge != null) ...[
                const SizedBox(width: 8),
                _Badge(text: badge!),
              ],
            ],
          ),
          subtitle: Text(subtitle),
          trailing: Icon(enabled ? Icons.chevron_right : Icons.info_outline),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
