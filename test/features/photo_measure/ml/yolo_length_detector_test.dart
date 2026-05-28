// YoloLengthDetector 단위 테스트 — 모델 자산이 없을 때 ModelMissingException을 던지는지.
// 실제 추론은 디바이스/에뮬레이터에서만 가능하므로 통합 테스트는 별도.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/features/photo_measure/ml/length_detection.dart';
import 'package:length/features/photo_measure/ml/yolo_length_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LengthDetection', () {
    test('isEmpty는 양쪽 모두 null일 때 true', () {
      const det = LengthDetection();
      expect(det.isEmpty, isTrue);
    });
  });

  test('모델 자산 없으면 ModelMissingException', () async {
    expect(
      () => YoloLengthDetector.load(),
      throwsA(isA<ModelMissingException>()),
    );
  });
}
