// 측정 이력 화면. Kind 필터 + 날짜 그룹(오늘/어제/이번주/이전) + 썸네일 + 스와이프 삭제.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/measurement_repository.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/settings/preferred_unit.dart';
import '../../../core/units/unit_converter.dart';
import '../../result/domain/measurement_result.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  MeasureKind? _filter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(measurementsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('이력')),
      body: Column(
        children: [
          _buildFilterChips(),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              data: (items) {
                final filtered = _filter == null
                    ? items
                    : items.where((e) => e.result.kind == _filter).toList();
                if (filtered.isEmpty) return _buildEmpty();
                return _buildGroupedList(filtered);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('로드 실패: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _chip(label: '전체', selected: _filter == null, onTap: () => setState(() => _filter = null)),
          for (final k in MeasureKind.values) ...[
            const SizedBox(width: 8),
            _chip(
              label: k.label,
              selected: _filter == k,
              onTap: () => setState(() => _filter = k),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            _filter == null
                ? '저장된 측정이 없습니다.'
                : '${_filter!.label} 측정이 없습니다.',
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<MeasurementEntry> items) {
    final groups = _groupByDate(items);
    return ListView.builder(
      itemCount: groups.fold<int>(0, (sum, g) => sum + g.items.length + 1),
      itemBuilder: (context, index) {
        var i = 0;
        for (final g in groups) {
          if (index == i) return _SectionHeader(label: g.label);
          i++;
          if (index < i + g.items.length) {
            return _HistoryTile(entry: g.items[index - i]);
          }
          i += g.items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  List<_DateGroup> _groupByDate(List<MeasurementEntry> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final buckets = <String, List<MeasurementEntry>>{
      '오늘': [],
      '어제': [],
      '이번 주': [],
      '이전': [],
    };
    for (final e in items) {
      final d = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      if (d == today) {
        buckets['오늘']!.add(e);
      } else if (d == yesterday) {
        buckets['어제']!.add(e);
      } else if (d.isAfter(weekStart.subtract(const Duration(days: 1)))) {
        buckets['이번 주']!.add(e);
      } else {
        buckets['이전']!.add(e);
      }
    }
    return buckets.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => _DateGroup(label: e.key, items: e.value))
        .toList();
  }
}

class _DateGroup {
  const _DateGroup({required this.label, required this.items});
  final String label;
  final List<MeasurementEntry> items;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final MeasurementEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(preferredUnitProvider).valueOrNull ?? LengthUnit.cm;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) {
        ref.read(measurementRepositoryProvider).delete(entry.id);
      },
      child: ListTile(
        leading: _Thumb(path: entry.imagePath, kind: entry.result.kind),
        title: Text(
          _formatValue(entry.result, unit),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          '${entry.result.kind.label} · ${entry.result.modeLabel} · ${_formatTime(entry.createdAt)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/result', extra: entry.result),
      ),
    );
  }

  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  String _formatValue(MeasurementResult r, LengthUnit unit) {
    switch (r.kind) {
      case MeasureKind.distance:
      case MeasureKind.perimeter:
        return UnitConverter.format(r.value, unit, digits: 2);
      case MeasureKind.area:
        return UnitConverter.formatArea(r.value, unit, digits: 2);
      case MeasureKind.angle:
        return '${r.value.toStringAsFixed(1)}°';
    }
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.kind});
  final String? path;
  final MeasureKind kind;

  @override
  Widget build(BuildContext context) {
    final exists = path != null && File(path!).existsSync();
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: exists
            ? Image.file(File(path!), fit: BoxFit.cover)
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                alignment: Alignment.center,
                child: Icon(_iconFor(kind), size: 22),
              ),
      ),
    );
  }

  IconData _iconFor(MeasureKind k) {
    switch (k) {
      case MeasureKind.distance:
        return Icons.straighten;
      case MeasureKind.perimeter:
        return Icons.timeline;
      case MeasureKind.area:
        return Icons.crop_square;
      case MeasureKind.angle:
        return Icons.architecture;
    }
  }
}
