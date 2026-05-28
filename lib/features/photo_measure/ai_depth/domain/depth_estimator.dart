// 단안 깊이 추정 인터페이스 + DepthMap 모델. 실제 모델 추론은 인프라 레이어가 담당.
import 'dart:typed_data';

class DepthMap {
  const DepthMap({
    required this.depths,
    required this.width,
    required this.height,
    required this.isMetric,
  });

  final Float32List depths;
  final int width;
  final int height;

  /// 깊이가 절대값(mm)인지, 상대 스케일인지. 상대일 경우 별도 캘리브레이션 필요.
  final bool isMetric;

  double depthAtPixel(int u, int v) {
    final uu = u.clamp(0, width - 1);
    final vv = v.clamp(0, height - 1);
    return depths[vv * width + uu];
  }
}

abstract class DepthEstimator {
  Future<DepthMap> estimate(String imagePath);
}
