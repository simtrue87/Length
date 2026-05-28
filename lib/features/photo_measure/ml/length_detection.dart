// YOLO 다중 클래스(credit_card, fish) 검출 결과 도메인 타입.
import 'dart:ui';

import '../reference_object/card_detector.dart' show CardDetection;

class FishDetection {
  const FishDetection({
    required this.outlineImagePx,
    required this.headPoint,
    required this.tailPoint,
    required this.confidence,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  /// 외곽 폴리곤 (이미지 픽셀 좌표). minAreaRect 4점이 아니라 마스크 외곽 N점.
  final List<Offset> outlineImagePx;

  /// 머리·꼬리 추정 점. minAreaRect 장변의 두 끝점 또는 PCA 주축 양 끝.
  /// 측정 시 두 점 사이 mm 거리 = 머리~꼬리 직선 길이.
  final Offset headPoint;
  final Offset tailPoint;

  final double confidence;
  final int imageWidthPx;
  final int imageHeightPx;
}

class LengthDetection {
  const LengthDetection({this.card, this.fish});

  /// class 0 (credit_card) 결과. 기존 [CardDetection] 재사용 — `cornersImagePx`와 `score`(=confidence) 활용.
  final CardDetection? card;

  /// class 1 (fish) 결과.
  final FishDetection? fish;

  bool get isEmpty => card == null && fish == null;
}
