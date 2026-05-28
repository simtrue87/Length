// 공유용 텍스트 포맷 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/features/result/domain/measurement_result.dart';
import 'package:length/features/result/presentation/result_text.dart';

void main() {
  test('거리: cm로 포맷', () {
    const r = MeasurementResult(
      kind: MeasureKind.distance,
      value: 85.6,
      modeLabel: '사진 — 신용카드',
      confidence: MeasurementConfidence.medium,
    );
    final text = formatResultForShare(r);
    expect(text, contains('거리'));
    expect(text, contains('8.56 cm'));
    expect(text, contains('사진 — 신용카드'));
  });

  test('각도: 도 단위 포맷', () {
    const r = MeasurementResult(
      kind: MeasureKind.angle,
      value: 90.0,
      modeLabel: 'test',
      confidence: MeasurementConfidence.high,
    );
    expect(formatResultForShare(r), contains('90.0°'));
  });

  test('면적: cm² 단위 포맷', () {
    const r = MeasurementResult(
      kind: MeasureKind.area,
      value: 10000.0, // 100cm² = 10000mm²
      modeLabel: 'test',
      confidence: MeasurementConfidence.medium,
    );
    expect(formatResultForShare(r), contains('100.00 cm²'));
  });
}
