// 결과 화면 — MeasureKind별 값 포맷, 단위 토글, 신뢰도 배지.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:length/features/result/domain/measurement_result.dart';
import 'package:length/features/result/presentation/result_screen.dart';

Future<void> _pump(WidgetTester tester, MeasurementResult r) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: ResultScreen(result: r)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('거리: cm로 기본 표시 + mm/cm/inch 토글', (tester) async {
    await _pump(
      tester,
      const MeasurementResult(
        kind: MeasureKind.distance,
        value: 85.6,
        modeLabel: '사진 — 신용카드',
        confidence: MeasurementConfidence.medium,
      ),
    );
    expect(find.text('8.56 cm'), findsOneWidget);

    await tester.tap(find.text('mm'));
    await tester.pumpAndSettle();
    expect(find.text('85.60 mm'), findsOneWidget);

    await tester.tap(find.text('inch'));
    await tester.pumpAndSettle();
    expect(find.text('3.37 in'), findsOneWidget);
  });

  testWidgets('각도: 단위 토글 숨김 + ° 표시', (tester) async {
    await _pump(
      tester,
      const MeasurementResult(
        kind: MeasureKind.angle,
        value: 90.0,
        modeLabel: 'test',
        confidence: MeasurementConfidence.high,
      ),
    );
    expect(find.text('90.0°'), findsOneWidget);
    expect(find.text('mm'), findsNothing);
  });

  testWidgets('면적: cm² 표시', (tester) async {
    await _pump(
      tester,
      const MeasurementResult(
        kind: MeasureKind.area,
        value: 10000.0,
        modeLabel: 'test',
        confidence: MeasurementConfidence.medium,
      ),
    );
    expect(find.text('100.00 cm²'), findsOneWidget);
  });

  testWidgets('신뢰도 배지가 표시된다', (tester) async {
    await _pump(
      tester,
      const MeasurementResult(
        kind: MeasureKind.distance,
        value: 100,
        modeLabel: 'test',
        confidence: MeasurementConfidence.low,
      ),
    );
    expect(find.text('신뢰도 — 낮음'), findsOneWidget);
  });
}
