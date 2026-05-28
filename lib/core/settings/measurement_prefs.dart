// 사진 측정 모드별 기본값(SharedPreferences). 마지막 사용 값을 입력 필드 초기값으로 사용.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCalibHeight = 'calib_height_mm';
const _kCalibFov = 'calib_fov_deg';
const _kMarkerSide = 'marker_side_mm';

class CalibrationPrefs {
  const CalibrationPrefs({required this.heightMm, required this.fovDegrees});
  final double heightMm;
  final double fovDegrees;
}

class CalibrationPrefsNotifier extends AsyncNotifier<CalibrationPrefs> {
  @override
  Future<CalibrationPrefs> build() async {
    final prefs = await SharedPreferences.getInstance();
    return CalibrationPrefs(
      heightMm: prefs.getDouble(_kCalibHeight) ?? 300,
      fovDegrees: prefs.getDouble(_kCalibFov) ?? 60,
    );
  }

  Future<void> save({required double heightMm, required double fovDegrees}) async {
    state = AsyncData(
      CalibrationPrefs(heightMm: heightMm, fovDegrees: fovDegrees),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCalibHeight, heightMm);
    await prefs.setDouble(_kCalibFov, fovDegrees);
  }
}

final calibrationPrefsProvider =
    AsyncNotifierProvider<CalibrationPrefsNotifier, CalibrationPrefs>(
        CalibrationPrefsNotifier.new);

class MarkerPrefsNotifier extends AsyncNotifier<double> {
  @override
  Future<double> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kMarkerSide) ?? 50;
  }

  Future<void> save(double sideMm) async {
    state = AsyncData(sideMm);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMarkerSide, sideMm);
  }
}

final markerSideMmProvider =
    AsyncNotifierProvider<MarkerPrefsNotifier, double>(MarkerPrefsNotifier.new);
