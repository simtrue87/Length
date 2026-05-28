// 디바이스 캐퍼빌리티 Riverpod provider. AsyncValue로 노출.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capability_detector.dart';
import 'device_capability.dart';

final capabilityDetectorProvider = Provider<CapabilityDetector>(
  (ref) => MethodChannelCapabilityDetector(),
);

final deviceCapabilityProvider = FutureProvider<DeviceCapability>((ref) {
  return ref.watch(capabilityDetectorProvider).detect();
});
