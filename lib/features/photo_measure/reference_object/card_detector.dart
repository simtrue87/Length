// 신용카드 자동 4점 감지. 적응형 Canny + 모폴로지 + 다단계 ε 시도 + 점수화.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv.dart' as cv;

class CardDetection {
  const CardDetection({
    required this.cornersImagePx,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.score,
  });

  /// 시계방향 정렬된 4점: TL, TR, BR, BL (이미지 픽셀 좌표).
  final List<Offset> cornersImagePx;
  final int imageWidthPx;
  final int imageHeightPx;

  /// 종합 점수: 종횡비·솔리디티·중심거리·면적 가중 평균. 0~1 정규화.
  final double score;
}

class CardDetector {
  static const double _cardAspect = 85.6 / 53.98; // ≈ 1.5858
  static const double _aspectTolerance = 0.22; // 원근 단축 여유. 폰(≈2:1) 같은 오인식 차단.
  static const double _minAreaRatio = 0.005;
  static const double _maxAreaRatio = 0.80;
  static const int _maxDim = 1000; // 다운샘플 상한 (긴 변 기준).

  /// [roi]가 주어지면 해당 이미지 픽셀 영역만 잘라 검출. 좌표는 원본 이미지 기준으로 복원.
  Future<CardDetection?> detect(String imagePath, {Rect? roi}) async {
    cv.Mat? src;
    cv.Mat? cropped;
    cv.Mat? work;
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? edges;
    cv.Mat? closed;
    cv.Mat? kernel;
    cv.Mat? otsu;
    try {
      src = cv.imread(imagePath);
      if (src.isEmpty) return null;
      final origW = src.cols;
      final origH = src.rows;

      // ROI 적용 — 이미지 좌표계의 영역으로 자름. 이후 모든 계산은 잘린 영역 기준.
      double roiOffX = 0;
      double roiOffY = 0;
      cv.Mat sourceForResize;
      if (roi != null) {
        final rx = roi.left.clamp(0, origW - 1).toInt();
        final ry = roi.top.clamp(0, origH - 1).toInt();
        final rw = roi.width.clamp(1, origW - rx).toInt();
        final rh = roi.height.clamp(1, origH - ry).toInt();
        cropped = src.region(cv.Rect(rx, ry, rw, rh));
        roiOffX = rx.toDouble();
        roiOffY = ry.toDouble();
        sourceForResize = cropped;
      } else {
        sourceForResize = src;
      }
      final regionW = sourceForResize.cols;
      final regionH = sourceForResize.rows;

      // 1) 다운샘플: 긴 변을 _maxDim으로.
      final longSide = math.max(regionW, regionH);
      final scale = longSide > _maxDim ? _maxDim / longSide : 1.0;
      if (scale < 1.0) {
        work = cv.resize(
          sourceForResize,
          ((regionW * scale).round(), (regionH * scale).round()),
          interpolation: cv.INTER_AREA,
        );
      } else {
        work = sourceForResize.clone();
      }
      final w = work.cols;
      final h = work.rows;

      gray = cv.cvtColor(work, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 1.2);

      // 2) Otsu로 자동 Canny 임계값 도출.
      final (otsuT, otsuMat) = cv.threshold(
        blurred,
        0,
        255,
        cv.THRESH_BINARY + cv.THRESH_OTSU,
      );
      otsu = otsuMat;
      final low = math.max(10.0, otsuT * 0.5);
      final high = math.min(255.0, otsuT);
      edges = cv.canny(blurred, low, high);

      // 3) Adaptive threshold (조명 불균일·저대비 윤곽 보강).
      //    blockSize는 이미지 짧은 변의 ~5%, 홀수.
      var block = (math.min(w, h) * 0.05).round();
      if (block % 2 == 0) block += 1;
      if (block < 11) block = 11;
      final adaptive = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        block,
        7,
      );

      // 4) 두 에지맵 OR로 합치고 모폴로지 close (5x5로 끊긴 외곽 강하게 연결).
      final union = cv.bitwiseOR(edges, adaptive);
      adaptive.dispose();
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      closed = cv.morphologyEx(union, cv.MORPH_CLOSE, kernel);
      union.dispose();

      // RETR_EXTERNAL: 카드 내부 패턴(글자·칩·로고)은 무시하고 최외곽만.
      final (contours, _) =
          cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      final imageArea = w * h.toDouble();
      final imgCx = w / 2.0;
      final imgCy = h / 2.0;
      final diag = math.sqrt(w * w + h * h.toDouble());

      // 진단 카운터.
      var nTotal = 0;
      var nAreaFail = 0;
      var nFillFail = 0;
      var nAspectFail = 0;
      var nAccepted = 0;
      double bestAspectErr = double.infinity;
      double bestFill = 0;

      // 면적 통과 후보 모두를 (aspect, area%, fill) 기록 — 상위 5개 로그.
      final candidates = <(double aspectErr, double areaPct, double fill)>[];

      CardDetection? best;
      double bestScore = -1;
      for (var i = 0; i < contours.length; i++) {
        nTotal++;
        final c = contours[i];
        final contourAreaPx = cv.contourArea(c);
        if (contourAreaPx < imageArea * _minAreaRatio ||
            contourAreaPx > imageArea * _maxAreaRatio) {
          nAreaFail++;
          continue;
        }

        // minAreaRect로 회전된 최소면적 사각형 4점 강제 추출 (윤곽 노이즈에 강함).
        final rrect = cv.minAreaRect(c);
        final boxPts = cv.boxPoints(rrect);
        final pts = <Offset>[
          for (var k = 0; k < 4; k++)
            Offset(boxPts[k].x.toDouble(), boxPts[k].y.toDouble()),
        ];
        boxPts.dispose();

        // 직사각형 적합도: 컨투어가 minAreaRect 면적을 얼마나 채우는지.
        final rectArea = rrect.ref.size.width * rrect.ref.size.height;
        final fill = rectArea > 0 ? (contourAreaPx / rectArea).clamp(0.0, 1.0) : 0.0;
        if (fill > bestFill) bestFill = fill;
        // 면적 통과 후보 무조건 기록(점수 단계에서 fill 가중).
        {
          final aTmp = _quadAspect(_orderClockwise(pts));
          final aErrTmp = (aTmp - _cardAspect).abs() / _cardAspect;
          candidates.add((aErrTmp, rectArea / imageArea, fill));
        }
        // fill 임계 제거 — 카드 외곽이 깨진 L자형 컨투어도 통과시킴(점수에서 평가).

        final ordered = _orderClockwise(pts);
        final aspect = _quadAspect(ordered);
        final aspectErr = (aspect - _cardAspect).abs() / _cardAspect;
        if (aspectErr < bestAspectErr) bestAspectErr = aspectErr;
        if (aspectErr > _aspectTolerance) {
          nAspectFail++;
          continue;
        }
        nAccepted++;

        final aspectScore = (1 - aspectErr / _aspectTolerance).clamp(0.0, 1.0);
        final cx = ordered.map((p) => p.dx).reduce((a, b) => a + b) / 4;
        final cy = ordered.map((p) => p.dy).reduce((a, b) => a + b) / 4;
        final centerDist =
            math.sqrt(math.pow(cx - imgCx, 2) + math.pow(cy - imgCy, 2));
        final centerScore = (1 - centerDist / (diag / 2)).clamp(0.0, 1.0);
        final areaRatio = rectArea / imageArea;
        // 클수록 좋음 — 5% 이상이면 만점. 1~2%(마그넷·로고) 페널티.
        final areaScore = (areaRatio / 0.05).clamp(0.0, 1.0);

        // 가중치: 종횡비 0.50(주), 면적 0.25, fill 0.15, 중심 0.10.
        final score = aspectScore * 0.50 +
            areaScore * 0.25 +
            fill * 0.15 +
            centerScore * 0.10;

        if (score > bestScore) {
          // 다운샘플 좌표 → ROI 좌표 → 원본 이미지 좌표.
          final restored = ordered
              .map((p) => Offset(
                    (scale < 1.0 ? p.dx / scale : p.dx) + roiOffX,
                    (scale < 1.0 ? p.dy / scale : p.dy) + roiOffY,
                  ))
              .toList();
          best = CardDetection(
            cornersImagePx: restored,
            imageWidthPx: origW,
            imageHeightPx: origH,
            score: score,
          );
          bestScore = score;
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[CardDetector] orig=${origW}x$origH work=${w}x$h '
          'otsuT=${otsuT.toStringAsFixed(1)} canny=(${low.toStringAsFixed(1)},${high.toStringAsFixed(1)}) '
          'contours=$nTotal areaFail=$nAreaFail fillFail=$nFillFail aspectFail=$nAspectFail accepted=$nAccepted '
          'bestFill=${bestFill.toStringAsFixed(3)} '
          'bestAspectErr=${bestAspectErr == double.infinity ? "-" : bestAspectErr.toStringAsFixed(3)} '
          'bestScore=${bestScore < 0 ? "-" : bestScore.toStringAsFixed(3)} '
          'card=${best == null ? "miss" : "hit"}',
        );
        candidates.sort((a, b) => a.$1.compareTo(b.$1));
        final top = candidates.take(5).toList();
        for (var i = 0; i < top.length; i++) {
          final t = top[i];
          debugPrint(
            '[CardDetector] cand#$i aspectErr=${t.$1.toStringAsFixed(3)} '
            'area%=${(t.$2 * 100).toStringAsFixed(2)} fill=${t.$3.toStringAsFixed(3)}',
          );
        }
      }
      return best;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[CardDetector] error: $e\n$st');
      return null;
    } finally {
      src?.dispose();
      cropped?.dispose();
      work?.dispose();
      gray?.dispose();
      blurred?.dispose();
      otsu?.dispose();
      edges?.dispose();
      closed?.dispose();
      kernel?.dispose();
    }
  }

  /// 이미지에서 강한 코너 후보를 추출 (스냅용). 좌표는 원본 이미지 픽셀.
  /// [maxCorners] 최대 후보 수. [qualityLevel] 0~1, 클수록 엄격.
  Future<List<Offset>> findCornerCandidates(
    String imagePath, {
    int maxCorners = 80,
    double qualityLevel = 0.02,
    double minDistanceFrac = 0.02,
  }) async {
    cv.Mat? src;
    cv.Mat? gray;
    cv.VecPoint2f? corners;
    try {
      src = cv.imread(imagePath);
      if (src.isEmpty) return const [];
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      final minDist = math.max(8.0, math.min(src.cols, src.rows) * minDistanceFrac);
      corners = cv.goodFeaturesToTrack(gray, maxCorners, qualityLevel, minDist);
      final out = <Offset>[];
      for (var i = 0; i < corners.length; i++) {
        final p = corners[i];
        out.add(Offset(p.x.toDouble(), p.y.toDouble()));
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      src?.dispose();
      gray?.dispose();
      corners?.dispose();
    }
  }

  /// 4점을 시계방향(TL, TR, BR, BL)으로 정렬.
  List<Offset> _orderClockwise(List<Offset> pts) {
    final cx = pts.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = pts.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    final sorted = [...pts]
      ..sort((a, b) => math.atan2(a.dy - cy, a.dx - cx)
          .compareTo(math.atan2(b.dy - cy, b.dx - cx)));
    final reversed = sorted.reversed.toList();
    var tlIdx = 0;
    var tlSum = double.infinity;
    for (var i = 0; i < 4; i++) {
      final s = reversed[i].dx + reversed[i].dy;
      if (s < tlSum) {
        tlSum = s;
        tlIdx = i;
      }
    }
    return [
      reversed[tlIdx],
      reversed[(tlIdx + 1) % 4],
      reversed[(tlIdx + 2) % 4],
      reversed[(tlIdx + 3) % 4],
    ];
  }

  double _quadAspect(List<Offset> p) {
    final top = (p[1] - p[0]).distance;
    final right = (p[2] - p[1]).distance;
    final bottom = (p[2] - p[3]).distance;
    final left = (p[3] - p[0]).distance;
    final width = (top + bottom) / 2;
    final height = (right + left) / 2;
    if (width == 0 || height == 0) return 0;
    // 카드 방향과 무관하게 비율(>=1) 반환 → 카드 종횡비(1.586)와 직접 비교.
    return width >= height ? width / height : height / width;
  }
}
