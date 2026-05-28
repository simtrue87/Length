// 단말 기울기 30° 초과 시 SnackBar로 경고. 사진 측정 화면들에서 재사용.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

const double _gravity = 9.80665;
const double _thresholdDegrees = 30.0;
const Duration _cooldown = Duration(seconds: 5);

/// 가속도 z성분 기준 수평면 대비 기울기 각도(0=평평, 90=수직).
double tiltDegreesFromAccel(double z) {
  final ratio = (z / _gravity).clamp(-1.0, 1.0);
  return math.acos(ratio) * 180 / math.pi;
}

class TiltWarning extends StatefulWidget {
  const TiltWarning({super.key, required this.child});
  final Widget child;

  @override
  State<TiltWarning> createState() => _TiltWarningState();
}

class _TiltWarningState extends State<TiltWarning> {
  StreamSubscription<AccelerometerEvent>? _sub;
  DateTime _lastShown = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream().listen(_onAccel);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onAccel(AccelerometerEvent e) {
    final tilt = tiltDegreesFromAccel(e.z);
    if (tilt <= _thresholdDegrees) return;
    final now = DateTime.now();
    if (now.difference(_lastShown) < _cooldown) return;
    _lastShown = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('기울기 ${tilt.toStringAsFixed(0)}°. 카메라를 위에서 수직으로 비추세요.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
