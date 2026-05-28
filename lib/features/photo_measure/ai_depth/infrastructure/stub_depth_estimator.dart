// 실제 Depth Anything V2 모델 통합 전까지 사용하는 임시 추정기.
// 가정: 이미지 상단(작은 v)은 멀리, 하단(큰 v)은 가까이. 평균 깊이는 사용자가 지정한 기본값.
// 결과는 isMetric=false(상대). 측정 결과 신뢰도는 항상 low로 표기해야 함.
import 'dart:typed_data';

import '../domain/depth_estimator.dart';

class StubDepthEstimator implements DepthEstimator {
  const StubDepthEstimator({
    this.width = 256,
    this.height = 192,
    this.nearMm = 300,
    this.farMm = 2000,
  });

  final int width;
  final int height;
  final double nearMm;
  final double farMm;

  @override
  Future<DepthMap> estimate(String imagePath) async {
    final data = Float32List(width * height);
    for (var y = 0; y < height; y++) {
      // y가 작을수록(이미지 상단) 멀리, 클수록 가까이.
      final t = y / (height - 1);
      final depth = farMm - (farMm - nearMm) * t;
      for (var x = 0; x < width; x++) {
        data[y * width + x] = depth;
      }
    }
    return DepthMap(
      depths: data,
      width: width,
      height: height,
      isMetric: false,
    );
  }
}
