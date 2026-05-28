// go_router 설정. 모드 선택 / AR / 사진 / 결과 / 이력 화면 라우팅.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/ar_measure/presentation/ar_measure_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/mode_select/presentation/mode_select_screen.dart';
import '../features/photo_measure/ai_depth/presentation/photo_ai_depth_screen.dart';
import '../features/photo_measure/calibration/photo_calibration_screen.dart';
import '../features/photo_measure/fish/photo_fish_screen.dart';
import '../features/photo_measure/marker/photo_marker_screen.dart';
import '../features/photo_measure/presentation/photo_reference_screen.dart';
import '../features/result/domain/measurement_result.dart';
import '../features/result/presentation/result_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ModeSelectScreen()),
    GoRoute(path: '/ar', builder: (_, __) => const ArMeasureScreen()),
    GoRoute(
      path: '/photo/reference',
      builder: (_, __) => const PhotoReferenceScreen(),
    ),
    GoRoute(
      path: '/photo/calibration',
      builder: (_, __) => const PhotoCalibrationScreen(),
    ),
    GoRoute(
      path: '/photo/ai-depth',
      builder: (_, __) => const PhotoAiDepthScreen(),
    ),
    GoRoute(
      path: '/photo/fish',
      builder: (_, __) => const PhotoFishScreen(),
    ),
    GoRoute(
      path: '/photo/marker',
      builder: (_, __) => const PhotoMarkerScreen(),
    ),
    GoRoute(
      path: '/result',
      builder: (_, state) {
        final extra = state.extra;
        if (extra is! MeasurementResult) {
          return const Scaffold(
            body: Center(child: Text('결과 데이터가 없습니다.')),
          );
        }
        return ResultScreen(result: extra);
      },
    ),
    GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
  ],
);
