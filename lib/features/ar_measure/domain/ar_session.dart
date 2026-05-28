// AR 세션 추상 인터페이스. ARCore/ARKit 어댑터가 구현한다.
enum ArAvailability {
  unknown,
  supported,
  unsupported,
  needsInstall,
}

enum ArInstallStatus {
  installed,
  installRequested,
}

abstract class ArSession {
  Future<ArAvailability> checkAvailability();
  Future<ArInstallStatus> requestInstall();
  Future<void> create();
  Future<void> release();
}
