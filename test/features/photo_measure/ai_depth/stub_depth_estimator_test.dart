// StubDepthEstimator 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/features/photo_measure/ai_depth/infrastructure/stub_depth_estimator.dart';

void main() {
  const e = StubDepthEstimator(width: 10, height: 10, nearMm: 100, farMm: 500);

  test('상단 픽셀은 farMm', () async {
    final m = await e.estimate('ignored');
    expect(m.depthAtPixel(5, 0), 500.0);
  });

  test('하단 픽셀은 nearMm', () async {
    final m = await e.estimate('ignored');
    expect(m.depthAtPixel(5, 9), 100.0);
  });

  test('isMetric=false', () async {
    final m = await e.estimate('ignored');
    expect(m.isMetric, isFalse);
  });
}
