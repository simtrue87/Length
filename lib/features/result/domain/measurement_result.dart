// 측정 결과 모델. 측정 종류(거리/둘레/면적/각도) + 값 + 신뢰도 + 부가 설명.
enum MeasureKind {
  distance('거리'),
  perimeter('둘레'),
  area('면적'),
  angle('각도');

  const MeasureKind(this.label);
  final String label;
}

enum MeasurementConfidence {
  high('정확'),
  medium('참고용'),
  low('낮음');

  const MeasurementConfidence(this.label);
  final String label;
}

/// 측정 결과. value의 단위는 kind에 따라 다르다.
/// - distance/perimeter: mm
/// - area: mm²
/// - angle: degrees
class MeasurementResult {
  const MeasurementResult({
    required this.kind,
    required this.value,
    required this.modeLabel,
    required this.confidence,
    this.note,
    this.imagePath,
  });

  final MeasureKind kind;
  final double value;
  final String modeLabel;
  final MeasurementConfidence confidence;
  final String? note;

  /// 측정선 오버레이가 그려진 결과 이미지(PNG) 경로. 공유·이력에 사용.
  final String? imagePath;
}
