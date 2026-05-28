// 공통 측정 엔진. 순수 Dart. 거리·픽셀-mm 변환·참조물 스케일 계산.
import 'dart:math' as math;
import 'dart:ui';

class MeasurementEngine {
  const MeasurementEngine._();

  /// 두 2D 점 사이의 유클리디안 거리(픽셀).
  static double distance2D(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 두 3D 점 사이의 유클리디안 거리.
  static double distance3D(
    ({double x, double y, double z}) a,
    ({double x, double y, double z}) b,
  ) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// 픽셀 거리에 mm/픽셀 스케일을 곱해 실제 길이(mm) 반환.
  static double pixelToMm({
    required double pixelDistance,
    required double mmPerPixel,
  }) =>
      pixelDistance * mmPerPixel;

  /// 참조물의 픽셀 길이와 실제 mm 길이로 mm/픽셀 스케일 계산.
  /// refPixelLength가 0이면 ArgumentError.
  static double computeScale(double refPixelLength, double refRealMm) {
    if (refPixelLength <= 0) {
      throw ArgumentError.value(
        refPixelLength,
        'refPixelLength',
        '0 이하일 수 없음',
      );
    }
    return refRealMm / refPixelLength;
  }

  /// 폴리라인(열림) 픽셀 총 길이.
  static double polylineLengthPx(List<Offset> points) {
    if (points.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += distance2D(points[i - 1], points[i]);
    }
    return sum;
  }

  /// 폴리곤 픽셀² 면적. Shoelace 공식. 꼭짓점은 자동으로 닫힌 것으로 간주.
  /// 3점 미만이면 0.
  static double polygonAreaPx2(List<Offset> points) {
    if (points.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// 픽셀² 면적에 (mm/px)² 곱해 mm² 반환.
  static double pixelArea2ToMm2({
    required double pixelArea,
    required double mmPerPixel,
  }) =>
      pixelArea * mmPerPixel * mmPerPixel;

  /// 평면 위 수직 촬영 가정 시 위젯 픽셀 → 평면 mm 스케일.
  /// 카메라 높이 h(mm), 세로 시야각 FOV(degree), 위젯 표시 높이(px) 입력.
  /// 가정: 단말이 평면과 평행, 광축이 평면에 수직, 이미지가 위젯에 letterbox 없이 표시됨.
  static double computeMmPerPixelFromHeight({
    required double heightMm,
    required double verticalFovDegrees,
    required double widgetHeightPx,
  }) {
    if (widgetHeightPx <= 0) {
      throw ArgumentError.value(widgetHeightPx, 'widgetHeightPx');
    }
    if (heightMm <= 0) {
      throw ArgumentError.value(heightMm, 'heightMm');
    }
    final fovRad = verticalFovDegrees * math.pi / 180;
    final groundHeightMm = 2 * heightMm * math.tan(fovRad / 2);
    return groundHeightMm / widgetHeightPx;
  }

  /// vertex에서 a-vertex-b 각도(degree). 0 < θ < 180.
  static double angleAtVertexDegrees(Offset a, Offset vertex, Offset b) {
    final v1 = a - vertex;
    final v2 = b - vertex;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final m1 = v1.distance;
    final m2 = v2.distance;
    if (m1 == 0 || m2 == 0) {
      throw ArgumentError('vertex와 일치하는 점이 있음');
    }
    final cos = (dot / (m1 * m2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }
}
