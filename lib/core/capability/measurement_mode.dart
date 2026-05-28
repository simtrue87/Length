// 측정 모드 종류와 캐퍼빌리티 기반 사용 가능 모드 선별.
import 'device_capability.dart';

enum MeasurementMode {
  arTwoPoint,
  photoReference,
  photoAiDepth,
  photoCalibration,
}

List<MeasurementMode> selectAvailableModes(DeviceCapability cap) {
  final modes = <MeasurementMode>[];
  if (cap.arSupported) modes.add(MeasurementMode.arTwoPoint);
  modes.add(MeasurementMode.photoReference);
  if (cap.neuralEngineAvailable && (cap.ramMb ?? 0) >= 4096) {
    modes.add(MeasurementMode.photoAiDepth);
  }
  modes.add(MeasurementMode.photoCalibration);
  return modes;
}
