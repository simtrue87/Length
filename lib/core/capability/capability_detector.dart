// CapabilityDetector 추상 인터페이스 + MethodChannel 구현.
import 'package:flutter/services.dart';

import 'device_capability.dart';

abstract class CapabilityDetector {
  Future<DeviceCapability> detect();
}

class MethodChannelCapabilityDetector implements CapabilityDetector {
  MethodChannelCapabilityDetector({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.lionplusmaster.length/capability');

  final MethodChannel _channel;
  DeviceCapability? _cached;

  @override
  Future<DeviceCapability> detect() async {
    if (_cached != null) return _cached!;
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('detect');
    _cached = DeviceCapability.fromMap(result ?? const {});
    return _cached!;
  }
}
