// 측정 결과를 공유용 텍스트로 포맷. 길이/면적/각도 모두 처리.
import '../../../core/units/unit_converter.dart';
import '../domain/measurement_result.dart';

String formatResultForShare(MeasurementResult r) {
  final value = switch (r.kind) {
    MeasureKind.distance ||
    MeasureKind.perimeter =>
      UnitConverter.format(r.value, LengthUnit.cm, digits: 2),
    MeasureKind.area => UnitConverter.formatArea(r.value, LengthUnit.cm, digits: 2),
    MeasureKind.angle => '${r.value.toStringAsFixed(1)}°',
  };
  final lines = <String>[
    '[Length] ${r.kind.label} 측정 결과',
    value,
    r.modeLabel,
    '신뢰도 — ${r.confidence.label}',
    if (r.note != null) r.note!,
  ];
  return lines.join('\n');
}
