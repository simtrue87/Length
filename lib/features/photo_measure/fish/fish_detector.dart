// GrabCut + minAreaRect 기반 물고기 직선 끝점 자동 추출.
// 사용자 bbox(이미지 픽셀 좌표) 입력 → 마스크 → 최대 contour → 주축 양 끝점 반환.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:opencv_dart/opencv.dart' as cv;

class FishDetection {
  const FishDetection({
    required this.endpointAImagePx,
    required this.endpointBImagePx,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });
  final Offset endpointAImagePx;
  final Offset endpointBImagePx;
  final int imageWidthPx;
  final int imageHeightPx;
}

class FishDetector {
  /// GrabCut 처리용 다운스케일 한도(긴 변 기준). 메모리·속도 절충.
  static const int _maxSide = 512;

  /// 이미지에서 [bboxImagePx]가 가리키는 영역을 GrabCut으로 분할 후 주축 끝점 산출.
  /// 감지 실패 시 null.
  Future<FishDetection?> detect({
    required String imagePath,
    required Rect bboxImagePx,
  }) async {
    cv.Mat? src;
    cv.Mat? scaled;
    cv.Mat? mask;
    cv.Mat? bgd;
    cv.Mat? fgd;
    cv.Mat? binary;
    try {
      src = cv.imread(imagePath);
      if (src.isEmpty) return null;
      final origW = src.cols;
      final origH = src.rows;

      // 다운스케일.
      final scaleDown = _maxSide / math.max(origW, origH);
      final newW = (origW * scaleDown).round().clamp(1, origW);
      final newH = (origH * scaleDown).round().clamp(1, origH);
      scaled = cv.resize(src, (newW, newH));

      // bbox 좌표를 스케일 조정 + 이미지 경계로 클램프 + 최소 크기 보장.
      final rx = (bboxImagePx.left * scaleDown).round().clamp(0, newW - 2);
      final ry = (bboxImagePx.top * scaleDown).round().clamp(0, newH - 2);
      final rw = (bboxImagePx.width * scaleDown)
          .round()
          .clamp(2, newW - rx);
      final rh = (bboxImagePx.height * scaleDown)
          .round()
          .clamp(2, newH - ry);
      final rect = cv.Rect(rx, ry, rw, rh);

      mask = cv.Mat.zeros(newH, newW, cv.MatType.CV_8UC1);
      bgd = cv.Mat.zeros(1, 65, cv.MatType.CV_64FC1);
      fgd = cv.Mat.zeros(1, 65, cv.MatType.CV_64FC1);

      cv.grabCut(scaled, mask, rect, bgd, fgd, 3, mode: cv.GC_INIT_WITH_RECT);

      // mask 값 0/1/2/3 중 1, 3(=FG, PR_FG)만 전경. 홀수 비트로 판별.
      final maskData = mask.data;
      final binaryData = Uint8List(maskData.length);
      for (var i = 0; i < maskData.length; i++) {
        binaryData[i] = (maskData[i] & 1) == 1 ? 255 : 0;
      }
      binary =
          cv.Mat.fromList(newH, newW, cv.MatType.CV_8UC1, binaryData);

      final (contours, _) = cv.findContours(
        binary,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      if (contours.isEmpty) return null;

      // 가장 큰 contour.
      var bestIdx = 0;
      var bestArea = 0.0;
      for (var i = 0; i < contours.length; i++) {
        final a = cv.contourArea(contours[i]);
        if (a > bestArea) {
          bestArea = a;
          bestIdx = i;
        }
      }
      if (bestArea < (newW * newH) * 0.005) return null;

      // 주축: minAreaRect로 회전된 박스 → 긴 변 양 끝.
      final rr = cv.minAreaRect(contours[bestIdx]);
      final cx = rr.center.x;
      final cy = rr.center.y;
      final w = rr.size.width;
      final h = rr.size.height;
      final angleDeg = rr.angle;
      // OpenCV minAreaRect 각도는 [-90, 0). 긴 변 방향 결정.
      final longLen = math.max(w, h);
      final isWidthLong = w >= h;
      final axisAngleRad = isWidthLong
          ? angleDeg * math.pi / 180
          : (angleDeg + 90) * math.pi / 180;
      final half = longLen / 2;
      final ex = math.cos(axisAngleRad) * half;
      final ey = math.sin(axisAngleRad) * half;
      final aScaled = Offset(cx - ex, cy - ey);
      final bScaled = Offset(cx + ex, cy + ey);

      // 다운스케일 되돌리기 → 원본 이미지 픽셀 좌표.
      final scaleUp = 1 / scaleDown;
      return FishDetection(
        endpointAImagePx: aScaled * scaleUp,
        endpointBImagePx: bScaled * scaleUp,
        imageWidthPx: origW,
        imageHeightPx: origH,
      );
    } catch (_) {
      return null;
    } finally {
      src?.dispose();
      scaled?.dispose();
      mask?.dispose();
      bgd?.dispose();
      fgd?.dispose();
      binary?.dispose();
    }
  }
}
