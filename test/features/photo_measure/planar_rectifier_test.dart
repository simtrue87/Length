// PlanarRectifier 동작 검증은 opencv_dart 네이티브 라이브러리가 필요해 디바이스/에뮬레이터
// 통합 테스트로만 가능. 단위 테스트는 skip.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlanarRectifier 통합 검증은 디바이스 빌드에서', () {
    // 호모그래피 정확도는 docs/verification/phone_verification.md의 카드 사다리꼴 시나리오로 확인.
  }, skip: 'opencv_dart 네이티브 라이브러리는 디바이스/에뮬레이터에서만 로드됨');
}
