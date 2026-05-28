// 카드/QR 4점(위젯 좌표) → 같은 평면의 mm 좌표 변환기.
// cv.findHomography로 H 계산 후 Dart 측에서 3x3 행렬로 보관해 가벼운 perspective transform.
import 'dart:math' as math;
import 'dart:ui';

import 'package:opencv_dart/opencv.dart' as cv;

class PlanarRectifier {
  PlanarRectifier._(this._h);

  /// 3x3 호모그래피 행렬 (row-major).
  final List<List<double>> _h;

  /// [cornersWidgetPx]: TL, TR, BR, BL 순. [widthMm], [heightMm]: 참조물의 실제 가로·세로.
  /// 쿼드의 TL→TR 변이 TR→BR보다 짧으면 참조물이 회전(세로)된 것으로 보고 가로/세로를 스왑.
  /// 점이 일직선이거나 변환 실패면 null.
  static PlanarRectifier? fromCorners({
    required List<Offset> cornersWidgetPx,
    required double widthMm,
    required double heightMm,
  }) {
    if (cornersWidgetPx.length != 4) return null;
    final topPx = (cornersWidgetPx[1] - cornersWidgetPx[0]).distance;
    final rightPx = (cornersWidgetPx[2] - cornersWidgetPx[1]).distance;
    final imageIsLandscape = topPx >= rightPx;
    final refIsLandscape = widthMm >= heightMm;
    final mappedW = imageIsLandscape == refIsLandscape ? widthMm : heightMm;
    final mappedH = imageIsLandscape == refIsLandscape ? heightMm : widthMm;
    cv.VecPoint2f? srcVec;
    cv.VecPoint2f? dstVec;
    cv.Mat? src;
    cv.Mat? dst;
    cv.Mat? h;
    try {
      srcVec = cv.VecPoint2f.fromList([
        for (final p in cornersWidgetPx) cv.Point2f(p.dx, p.dy),
      ]);
      dstVec = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(mappedW, 0),
        cv.Point2f(mappedW, mappedH),
        cv.Point2f(0, mappedH),
      ]);
      src = cv.Mat.fromVec(srcVec);
      dst = cv.Mat.fromVec(dstVec);
      h = cv.findHomography(src, dst);
      if (h.isEmpty || h.rows != 3 || h.cols != 3) return null;
      final m = [
        for (var r = 0; r < 3; r++)
          [for (var c = 0; c < 3; c++) h.atF64(r, i1: c)],
      ];
      return PlanarRectifier._(m);
    } catch (_) {
      return null;
    } finally {
      srcVec?.dispose();
      dstVec?.dispose();
      src?.dispose();
      dst?.dispose();
      h?.dispose();
    }
  }

  /// 위젯 좌표 한 점을 카드 평면 mm 좌표로 변환.
  Offset toMm(Offset widgetPx) {
    final u = widgetPx.dx;
    final v = widgetPx.dy;
    final x = _h[0][0] * u + _h[0][1] * v + _h[0][2];
    final y = _h[1][0] * u + _h[1][1] * v + _h[1][2];
    final w = _h[2][0] * u + _h[2][1] * v + _h[2][2];
    if (w == 0) return Offset.zero;
    return Offset(x / w, y / w);
  }

  /// 두 점 사이의 평면 mm 거리.
  double distanceMm(Offset a, Offset b) {
    final ma = toMm(a);
    final mb = toMm(b);
    return (ma - mb).distance;
  }

  /// 폴리라인 총 mm 길이.
  double polylineLengthMm(List<Offset> points) {
    if (points.length < 2) return 0;
    final mapped = points.map(toMm).toList();
    var sum = 0.0;
    for (var i = 1; i < mapped.length; i++) {
      sum += (mapped[i] - mapped[i - 1]).distance;
    }
    return sum;
  }

  /// 폴리곤 mm² 면적 (Shoelace, 자동 닫힘).
  double polygonAreaMm2(List<Offset> points) {
    if (points.length < 3) return 0;
    final mapped = points.map(toMm).toList();
    var sum = 0.0;
    for (var i = 0; i < mapped.length; i++) {
      final a = mapped[i];
      final b = mapped[(i + 1) % mapped.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// 세 점 a-vertex-b 각도(°). 평면 mm 좌표 기준이라 원근 왜곡 보정됨.
  double angleAtVertexDegrees(Offset a, Offset vertex, Offset b) {
    final ma = toMm(a);
    final mv = toMm(vertex);
    final mb = toMm(b);
    final v1 = ma - mv;
    final v2 = mb - mv;
    final m1 = v1.distance;
    final m2 = v2.distance;
    if (m1 == 0 || m2 == 0) return 0;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final cosv = (dot / (m1 * m2)).clamp(-1.0, 1.0);
    return math.acos(cosv) * 180 / math.pi;
  }
}
