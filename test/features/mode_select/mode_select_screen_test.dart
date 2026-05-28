// 모드 선택 화면 — 4종 카드 표시 + AR capability에 따라 안내문 변경.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/capability/capability_detector.dart';
import 'package:length/core/capability/device_capability.dart';
import 'package:length/core/capability/providers.dart';
import 'package:length/features/mode_select/presentation/mode_select_screen.dart';

class _FakeDetector implements CapabilityDetector {
  _FakeDetector(this.cap);
  final DeviceCapability cap;
  @override
  Future<DeviceCapability> detect() async => cap;
}

DeviceCapability _cap({required bool ar}) => DeviceCapability(
      arSupported: ar,
      lidarAvailable: false,
      tofAvailable: false,
      neuralEngineAvailable: false,
      osVersion: 'test',
    );

Future<void> _pump(WidgetTester tester, DeviceCapability cap) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(_FakeDetector(cap)),
      ],
      child: const MaterialApp(home: ModeSelectScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('모드 카드를 표시한다', (tester) async {
    await _pump(tester, _cap(ar: true));
    expect(find.text('AR 두 점 측정'), findsOneWidget);
    expect(find.text('참조 객체'), findsOneWidget);
    expect(find.text('QR/마커'), findsOneWidget);
    expect(find.text('AI 깊이 추정'), findsOneWidget);
    expect(find.text('캘리브레이션 + 평면'), findsOneWidget);
    expect(find.text('자동'), findsOneWidget);
    expect(find.text('베타'), findsNWidgets(2)); // AI 깊이 + 물고기
    expect(find.text('물고기'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('이력 보기'), 200);
    expect(find.text('이력 보기'), findsOneWidget);
  });

  testWidgets('AR 미지원 시 AR 카드 부제목이 안내문으로 변경', (tester) async {
    await _pump(tester, _cap(ar: false));
    expect(
      find.text('이 기기는 AR 미지원 — 진입 시 사진 모드 안내.'),
      findsOneWidget,
    );
  });
}
