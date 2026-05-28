// MeasurementMode 선별 로직 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/capability/device_capability.dart';
import 'package:length/core/capability/measurement_mode.dart';

DeviceCapability _cap({
  bool ar = false,
  bool npu = false,
  int? ram,
}) =>
    DeviceCapability(
      arSupported: ar,
      lidarAvailable: false,
      tofAvailable: false,
      neuralEngineAvailable: npu,
      osVersion: 'test',
      ramMb: ram,
    );

void main() {
  test('AR 미지원·NPU 없음: 참조 객체 + 캘리브레이션만', () {
    final modes = selectAvailableModes(_cap());
    expect(modes, [
      MeasurementMode.photoReference,
      MeasurementMode.photoCalibration,
    ]);
  });

  test('AR 지원: AR 모드 포함', () {
    final modes = selectAvailableModes(_cap(ar: true));
    expect(modes.first, MeasurementMode.arTwoPoint);
  });

  test('NPU 있고 RAM 4GB 이상: AI 깊이 모드 포함', () {
    final modes = selectAvailableModes(_cap(npu: true, ram: 6000));
    expect(modes, contains(MeasurementMode.photoAiDepth));
  });

  test('NPU 있어도 RAM 4GB 미만: AI 깊이 모드 제외', () {
    final modes = selectAvailableModes(_cap(npu: true, ram: 3000));
    expect(modes, isNot(contains(MeasurementMode.photoAiDepth)));
  });

  test('NPU 없음: RAM 충분해도 AI 깊이 모드 제외', () {
    final modes = selectAvailableModes(_cap(ram: 8000));
    expect(modes, isNot(contains(MeasurementMode.photoAiDepth)));
  });
}
