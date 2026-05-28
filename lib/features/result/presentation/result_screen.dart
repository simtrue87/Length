// 측정 결과 화면. 측정 종류별 단위 토글 + 신뢰도 배지 + 저장 + 모드·메모 표시.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/settings/preferred_unit.dart';
import '../../../core/units/unit_converter.dart';
import '../domain/measurement_result.dart';
import 'result_text.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.result});

  final MeasurementResult result;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _saved = false;
  bool _saving = false;

  Future<void> _share(MeasurementResult r) async {
    final text = formatResultForShare(r);
    final path = r.imagePath;
    if (path != null && File(path).existsSync()) {
      await SharePlus.instance.share(
        ShareParams(text: text, files: [XFile(path)]),
      );
    } else {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(measurementRepositoryProvider).save(widget.result);
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이력에 저장되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formattedValue(MeasurementResult r, LengthUnit unit) {
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

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final scheme = Theme.of(context).colorScheme;
    final showsUnitToggle = r.kind != MeasureKind.angle;
    final unit = ref.watch(preferredUnitProvider).valueOrNull ?? LengthUnit.cm;
    return Scaffold(
      appBar: AppBar(
        title: Text('측정 결과 — ${r.kind.label}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(r),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.imagePath != null && File(r.imagePath!).existsSync()) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(r.imagePath!)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 16),
            Text(
              r.modeLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Center(child: _ConfidenceBadge(confidence: r.confidence)),
            const SizedBox(height: 32),
            Center(
              child: Text(
                _formattedValue(r, unit),
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(color: scheme.primary),
              ),
            ),
            const SizedBox(height: 24),
            if (showsUnitToggle)
              Center(
                child: SegmentedButton<LengthUnit>(
                  segments: const [
                    ButtonSegment(value: LengthUnit.mm, label: Text('mm')),
                    ButtonSegment(value: LengthUnit.cm, label: Text('cm')),
                    ButtonSegment(value: LengthUnit.inch, label: Text('inch')),
                  ],
                  selected: {unit},
                  onSelectionChanged: (s) =>
                      ref.read(preferredUnitProvider.notifier).set(s.first),
                ),
              ),
            if (r.note != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  r.note!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: (_saved || _saving) ? null : _save,
              icon: Icon(_saved ? Icons.check : Icons.bookmark_add_outlined),
              label: Text(_saved ? '저장됨' : '이력에 저장'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('새 측정'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final MeasurementConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (confidence) {
      MeasurementConfidence.high => (scheme.primaryContainer, scheme.onPrimaryContainer),
      MeasurementConfidence.medium => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      MeasurementConfidence.low => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '신뢰도 — ${confidence.label}',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
