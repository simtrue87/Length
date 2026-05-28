// 핀홀 카메라 내부 파라미터. pixel → 3D 역투영 함수.
class CameraIntrinsics {
  const CameraIntrinsics({
    required this.fxPx,
    required this.fyPx,
    required this.cxPx,
    required this.cyPx,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  final double fxPx;
  final double fyPx;
  final double cxPx;
  final double cyPx;
  final int imageWidthPx;
  final int imageHeightPx;

  /// 35mm 환산 초점거리(mm)와 이미지 해상도만으로 근사 intrinsics 생성.
  /// fx = (focal35mm / 36mm) * widthPx, fy = (focal35mm / 24mm) * heightPx.
  /// 주점은 이미지 중심으로 가정.
  factory CameraIntrinsics.fromFocal35mm({
    required double focal35mm,
    required int imageWidthPx,
    required int imageHeightPx,
  }) {
    final fx = (focal35mm / 36.0) * imageWidthPx;
    final fy = (focal35mm / 24.0) * imageHeightPx;
    return CameraIntrinsics(
      fxPx: fx,
      fyPx: fy,
      cxPx: imageWidthPx / 2,
      cyPx: imageHeightPx / 2,
      imageWidthPx: imageWidthPx,
      imageHeightPx: imageHeightPx,
    );
  }
}

/// 픽셀(u, v) + depth(Z) → 카메라 좌표계 3D 점(X, Y, Z). 단위는 depth와 동일.
({double x, double y, double z}) unproject({
  required double u,
  required double v,
  required double depth,
  required CameraIntrinsics intrinsics,
}) {
  final x = (u - intrinsics.cxPx) * depth / intrinsics.fxPx;
  final y = (v - intrinsics.cyPx) * depth / intrinsics.fyPx;
  return (x: x, y: y, z: depth);
}
