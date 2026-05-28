// ArUco 마커를 정지 이미지에서 감지해 4 모서리(이미지 픽셀 좌표)와 ID 반환.
import 'dart:ui';

import 'package:opencv_dart/opencv.dart' as cv;

class ArucoDetection {
  const ArucoDetection({
    required this.cornersImagePx,
    required this.markerId,
    required this.dictionaryName,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  /// TL, TR, BR, BL 시계방향. OpenCV ArUco는 본래 TL, TR, BR, BL 순서.
  final List<Offset> cornersImagePx;
  final int markerId;
  final String dictionaryName;
  final int imageWidthPx;
  final int imageHeightPx;
}

class ArucoDetector {
  /// 가장 흔한 사전들을 순서대로 시도 (4x4 50 → 5x5 100 → 6x6 250 → APRILTAG_36h11).
  static const List<cv.PredefinedDictionaryType> _dictionaries = [
    cv.PredefinedDictionaryType.DICT_4X4_50,
    cv.PredefinedDictionaryType.DICT_5X5_100,
    cv.PredefinedDictionaryType.DICT_6X6_250,
    cv.PredefinedDictionaryType.DICT_APRILTAG_36h11,
  ];

  /// 이미지에서 첫 번째 감지된 ArUco 마커 반환. 시도한 모든 사전에서 실패하면 null.
  Future<ArucoDetection?> detect(String imagePath) async {
    cv.Mat? src;
    cv.Mat? gray;
    try {
      src = cv.imread(imagePath);
      if (src.isEmpty) return null;
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      final origW = src.cols;
      final origH = src.rows;

      for (final dictType in _dictionaries) {
        cv.ArucoDictionary? dict;
        cv.ArucoDetectorParameters? params;
        cv.ArucoDetector? detector;
        try {
          dict = cv.ArucoDictionary.predefined(dictType);
          params = cv.ArucoDetectorParameters.empty();
          detector = cv.ArucoDetector.create(dict, params);
          final (corners, ids, _) = detector.detectMarkers(gray);
          if (ids.isNotEmpty && corners.isNotEmpty) {
            // 가장 큰 마커(이미지 안 가장 잘 보이는 것) 선택.
            int bestIdx = 0;
            double bestArea = -1;
            for (var i = 0; i < corners.length; i++) {
              final c = corners[i];
              if (c.length != 4) continue;
              final pts = [
                for (var k = 0; k < 4; k++)
                  Offset(c[k].x.toDouble(), c[k].y.toDouble()),
              ];
              final area = _quadArea(pts);
              if (area > bestArea) {
                bestArea = area;
                bestIdx = i;
              }
            }
            final best = corners[bestIdx];
            final pts = [
              for (var k = 0; k < 4; k++)
                Offset(best[k].x.toDouble(), best[k].y.toDouble()),
            ];
            return ArucoDetection(
              cornersImagePx: pts,
              markerId: ids[bestIdx],
              dictionaryName: dictType.name,
              imageWidthPx: origW,
              imageHeightPx: origH,
            );
          }
        } finally {
          detector?.dispose();
          params?.dispose();
          dict?.dispose();
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      src?.dispose();
      gray?.dispose();
    }
  }

  double _quadArea(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }
}
