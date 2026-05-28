// MethodChannel 기반 ARCore 세션 어댑터(Android). Activity 측 ArcoreSessionHandler와 통신.
import 'package:flutter/services.dart';

import '../domain/ar_session.dart';

class ArcoreSession implements ArSession {
  ArcoreSession({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.lionplusmaster.length/arcore');

  final MethodChannel _channel;

  @override
  Future<ArAvailability> checkAvailability() async {
    final raw = await _channel.invokeMethod<String>('checkAvailability');
    return _mapAvailability(raw);
  }

  @override
  Future<ArInstallStatus> requestInstall() async {
    final raw = await _channel.invokeMethod<String>('requestInstall');
    return raw == 'INSTALL_REQUESTED'
        ? ArInstallStatus.installRequested
        : ArInstallStatus.installed;
  }

  @override
  Future<void> create() async {
    await _channel.invokeMethod<void>('createSession');
  }

  @override
  Future<void> release() async {
    await _channel.invokeMethod<void>('releaseSession');
  }

  ArAvailability _mapAvailability(String? raw) {
    switch (raw) {
      case 'SUPPORTED_INSTALLED':
        return ArAvailability.supported;
      case 'SUPPORTED_APK_TOO_OLD':
      case 'SUPPORTED_NOT_INSTALLED':
        return ArAvailability.needsInstall;
      case 'UNSUPPORTED_DEVICE_NOT_CAPABLE':
        return ArAvailability.unsupported;
      default:
        return ArAvailability.unknown;
    }
  }
}
