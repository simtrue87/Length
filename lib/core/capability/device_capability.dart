// 디바이스 측정 캐퍼빌리티 모델. AR/LiDAR/ToF/NPU/RAM/OS/카메라 내부 파라미터.
class DeviceCapability {
  const DeviceCapability({
    required this.arSupported,
    required this.lidarAvailable,
    required this.tofAvailable,
    required this.neuralEngineAvailable,
    required this.osVersion,
    this.ramMb,
    this.cameraIntrinsics = const {},
  });

  final bool arSupported;
  final bool lidarAvailable;
  final bool tofAvailable;
  final bool neuralEngineAvailable;
  final String osVersion;
  final int? ramMb;
  final Map<String, dynamic> cameraIntrinsics;

  factory DeviceCapability.fromMap(Map<dynamic, dynamic> map) {
    return DeviceCapability(
      arSupported: map['arSupported'] as bool? ?? false,
      lidarAvailable: map['lidarAvailable'] as bool? ?? false,
      tofAvailable: map['tofAvailable'] as bool? ?? false,
      neuralEngineAvailable: map['neuralEngineAvailable'] as bool? ?? false,
      osVersion: map['osVersion'] as String? ?? 'unknown',
      ramMb: (map['ramMb'] as num?)?.toInt(),
      cameraIntrinsics: Map<String, dynamic>.from(
        (map['cameraIntrinsics'] as Map?) ?? const {},
      ),
    );
  }
}
