<!-- Length 개발 설계 문서: Flutter 기반 AR + 단일 이미지 측정 풀스코프 -->

# Length — 개발 설계 문서

> 전략 문서 `length_measurement_implementation_strategy_1.md`의 **Phase 1~3 전체**를 Flutter로 구현하기 위한 설계.
> 접근 방식: 제안 기능 전체를 우선 구현해두고, 운영하며 부족한 부분을 보완.
> 검토 대상: 아키텍처, 모듈 경계, 외부 의존성, 데이터 흐름, 인터페이스 시그니처, 폴백/에러 처리.

---

## 1. 구현 범위 확정

### 1.1 포함 (Phase 1~3 전체)
- **공통**: 디바이스 케이퍼빌리티 감지(ARKit/ARCore/LiDAR/ToF/NPU/RAM), 공통 측정 엔진, 단위 변환(mm/cm/inch)
- **모드 1 — AR 두 점 찍기**: iOS=ARKit, Android=ARCore + **LiDAR 활용 분기**(iPhone 12 Pro+ / iPad Pro 2020+)
- **모드 2 — 참조 객체**: 신용카드, A4 용지, 100원·500원 동전, ArUco/QR 마커 (자동 감지 + 수동 4점 폴백)
- **모드 2 — 세그멘테이션**: SAM 2(또는 모바일 경량 대안) 통합으로 대상 외곽선 자동 추출
- **모드 2 — AI 깊이 추정**: Depth Anything V2 온디바이스 추론 (NPU/RAM 기준 충족 기기만)
- **모드 2 — 캘리브레이션 + 평면 가정**: 자이로 각도 + 사용자 입력 단말 높이로 거리 계산
- **UI**: 모드 선택 / AR 측정 / 사진 측정(서브 방식 선택) / 결과 / 이력 화면
- **확장 기능**: 측정 이력 저장·공유, 다중 측정(둘레·면적·각도), AR 측정선 3D 공간 고정·재시청

### 1.2 제외 (Phase 4 이후 / 운영 보완 영역)
- 클라우드 동기화, 계정 시스템
- 다국어 (1차는 한국어만, 영어는 운영 단계 추가)
- 측정 정확도 자동 벤치마크 파이프라인 (수동 벤치마크 시트로 대체)
- 사용자 피드백 기반 자동 보정 알고리즘

### 1.3 성공 기준 (검증 가능 목표)
- AR 모드: 30cm~2m 실측 대비 평균 오차 ≤ **3%** (LiDAR 분기 시 ≤ 1cm)
- 사진 모드(참조 객체): 평균 오차 ≤ **5%**
- 사진 모드(AI 깊이): 평균 오차 ≤ **15%** (모델 한계)
- 콜드 스타트~첫 측정 완료 ≤ **30초**
- iOS 14+ / Android 8+ 기기 80% 이상에서 최소 하나의 모드 동작

---

## 2. 기술 스택 확정

| 영역 | 선택 | 사유 |
|------|------|------|
| 프레임워크 | Flutter 3.22+ / Dart 3.4+ | iOS·Android 동시 지원, UI 일관성 |
| 최소 OS | iOS 14 / Android 8 (API 26) | ARKit 4 + ARCore 안정. 커버리지·코드 단순성 균형 |
| AR (iOS) | `arkit_plugin` | LiDAR API(`sceneDepth`, `ARMeshAnchor`) 접근 가능 |
| AR (Android) | `arcore_flutter_plugin` | ARCore HitTest·Anchor 노출 |
| 카메라 (사진) | `camera` (공식) | 안정성 |
| 이미지 처리 | `opencv_dart` + 네이티브 채널 보조 | 호모그래피, ArUco 감지, 마스킹 |
| 객체 감지 | TFLite YOLOv8 (참조 객체·일반 객체) + ML Kit 보조 | A4·카드·동전 자동 감지 |
| 세그멘테이션 | SAM 2 모바일 변환(Core ML / TFLite) 또는 MobileSAM | 대상 외곽선 자동 추출 |
| AI 깊이 추정 | Depth Anything V2 (Small/Base) — Core ML / TFLite INT8 양자화 | 단안 깊이 |
| ArUco/QR | `opencv_dart` ArUco 모듈 + `mobile_scanner` | 마커 기반 정밀 측정 |
| 센서 | `sensors_plus` | 자이로/가속도 (기울기 경고, 평면 가정) |
| 상태관리 | **Riverpod 2.x** (+ `riverpod_generator`) | AsyncNotifier·DI·테스트 용이 |
| 라우팅 | go_router | 선언적 |
| 영속화 | `drift` (SQLite) | 측정 이력 저장 |
| 공유 | `share_plus` | 결과 이미지·텍스트 공유 |
| 권한 | `permission_handler` | 카메라·저장소 |
| 로깅 | `logger` | 디버깅 |

**플러그인 PoC 정책**: AR 플러그인 두 개(`arkit_plugin`/`arcore_flutter_plugin`)는 유지보수가 들쭉날쭉하므로 W1에서 (1) Flutter 3.22+ 빌드, (2) hit-test, (3) 라인·앵커 렌더링을 검증. 막히는 플랫폼은 MethodChannel + 네이티브(Swift/Kotlin) 직접 구현으로 부분 전환.

---

## 3. 아키텍처

### 3.1 계층 구조

```
lib/
├── main.dart
├── app/                          # 앱 진입, 라우팅, 테마 (Material 3 + seed color #00897B)
├── core/
│   ├── capability/               # 디바이스 감지 (AR/LiDAR/NPU/RAM)
│   ├── measurement/              # 공통 측정 엔진 (순수 Dart)
│   ├── units/                    # 단위 변환
│   └── persistence/              # 측정 이력 DB (drift)
├── features/
│   ├── mode_select/              # 모드 선택 (AR / 사진-서브방식)
│   ├── ar_measure/               # AR 두 점 찍기
│   │   ├── presentation/
│   │   ├── application/          # Notifier (Riverpod)
│   │   └── infrastructure/       # arkit_session.dart / arcore_session.dart / lidar_*.dart
│   ├── photo_measure/
│   │   ├── reference_object/     # 카드/A4/동전/ArUco 자동·수동 감지
│   │   ├── ai_depth/             # Depth Anything V2 추론
│   │   ├── calibration/          # 자이로 + 단말 높이 기반 평면 가정
│   │   ├── segmentation/         # SAM 2 모바일 (대상 외곽선)
│   │   ├── presentation/
│   │   ├── application/
│   │   └── infrastructure/       # camera / opencv / tflite / coreml 어댑터
│   ├── multi_measure/            # 둘레·면적·각도
│   ├── history/                  # 측정 이력 조회·삭제·공유
│   └── result/                   # 결과 화면 (단위 토글, 공유, 저장)
└── shared/                       # 위젯, 유틸, 디자인 토큰
```

### 3.2 의존성 방향
`presentation → application → infrastructure / core`
`features/*`는 서로를 직접 참조하지 않음. `core/measurement`만 공유.

### 3.3 공통 측정 엔진 (순수 함수)

```dart
// core/measurement/measurement_engine.dart
class MeasurementEngine {
  // AR 모드: 두 3D 점의 유클리디안 거리
  static double distance3D(Vector3 a, Vector3 b);

  // 사진 모드: 픽셀 거리 × (mm/픽셀 스케일)
  static double pixelToMm({
    required double pixelDistance,
    required double mmPerPixel,
  });

  // 참조 객체에서 스케일 계산
  // refPixelLength: 감지된 참조물의 픽셀 길이
  // refRealMm: 참조물의 실제 mm
  static double computeScale(double refPixelLength, double refRealMm);
}
```

---

## 4. 모듈별 상세 설계

### 4.1 Capability Detector

```dart
class DeviceCapability {
  final bool arSupported;       // ARKit 또는 ARCore 지원
  final bool lidarAvailable;    // iOS Pro 라인
  final bool tofAvailable;      // Android ToF 센서
  final bool neuralEngineAvailable; // NPU/Neural Engine
  final String osVersion;
  final int? ramMb;
  final Map<String, dynamic> cameraIntrinsics; // EXIF/네이티브에서 추출
}

abstract class CapabilityDetector {
  Future<DeviceCapability> detect();
}

List<MeasurementMode> selectAvailableModes(DeviceCapability cap) {
  final modes = <MeasurementMode>[];
  if (cap.arSupported) modes.add(MeasurementMode.arTwoPoint);
  modes.add(MeasurementMode.photoReference);            // 항상 사용 가능
  if (cap.neuralEngineAvailable && (cap.ramMb ?? 0) >= 4096) {
    modes.add(MeasurementMode.photoAiDepth);
  }
  modes.add(MeasurementMode.photoCalibration);          // 자이로 기반, 항상 가능
  return modes;
}
```

- iOS: `ARWorldTrackingConfiguration.isSupported`, `supportsSceneReconstruction`(LiDAR)
- Android: `ArCoreApk.checkAvailability()`, ToF 센서 카메라 메타데이터
- MethodChannel 1회 호출, 결과 캐싱

### 4.2 AR 측정 모듈

**상태 머신**
```
idle → initializing → planeDetected → firstPointSet → measuring → done
                ↑              ↓ (실패)
                └──── error ←──┘
```

**핵심 인터페이스**
```dart
abstract class ArSession {
  Stream<ArTrackingState> get state;
  Future<Vector3?> hitTest(Offset screenPoint);     // 화면 좌표 → 3D 월드 좌표
  Future<void> placeAnchor(Vector3 point);
  Future<void> drawLine(Vector3 a, Vector3 b);
  Future<void> persistMeasurement(String id, List<Vector3> points); // 3D 공간 고정
  Future<void> dispose();
}
```

**LiDAR 분기 (iOS Pro 라인)**
- `ARWorldTrackingConfiguration.sceneReconstruction = .mesh` 활성화
- `ARMeshAnchor`로 더 정밀한 표면 hit-test
- 측정 정확도 ±1cm 달성 목표

**UX 가이드**
- 초기화 5초 이상 지속 시 "단말을 천천히 좌우로 움직여주세요" 토스트
- 트래킹 손실 시 점 고정 표시 + 재시작 버튼
- 측정 완료 후 앵커 유지하여 화면 회전·이동 시 라인 따라감

### 4.3 사진 측정 — 참조 객체 모듈

**지원 참조물**
| 참조물 | 실제 크기 | 감지 방식 |
|--------|----------|----------|
| 신용카드 | 85.6 × 53.98 mm | YOLOv8 커스텀 + 수동 4점 폴백 |
| A4 용지 | 210 × 297 mm | YOLOv8 + 엣지 검출(Canny) 보조 |
| 100원 동전 | 직경 24.0 mm | YOLOv8 + Hough Circle |
| 500원 동전 | 직경 26.5 mm | YOLOv8 + Hough Circle |
| ArUco / QR 마커 | 사용자 정의 | `opencv_dart` ArUco / `mobile_scanner` |

**플로우**
1. 참조물 종류 선택
2. `camera` 촬영 또는 `image_picker` 갤러리 선택
3. 자동 감지 → 신뢰도 ≥ 0.7이면 자동 진행, 아니면 수동 4점 보정 UI
4. 호모그래피로 평면 정합 (`opencv_dart` `findHomography` + `warpPerspective`)
5. SAM 2 세그멘테이션으로 대상 외곽선 자동 추출 (옵션 토글) 또는 수동 두 점 탭
6. `MeasurementEngine.pixelToMm`로 결과 산출

**핵심 인터페이스**
```dart
enum ReferenceObject { creditCard, a4, coin100, coin500, arucoMarker }

class ReferenceDetectionResult {
  final ReferenceObject type;
  final Rect? boundingBox;
  final List<Offset>? corners;       // 4점 (호모그래피용)
  final double confidence;
}

abstract class ReferenceObjectDetector {
  Future<ReferenceDetectionResult?> detect(Uint8List imageBytes, ReferenceObject hint);
}

abstract class TargetSegmenter {
  Future<List<Offset>> segment(Uint8List imageBytes, Offset seedPoint);
}
```

**가정 및 경고**
- 참조물과 대상이 같은 평면·비슷한 거리 → UI 명시
- 자이로 30° 초과 기울기 시 경고
- 호모그래피 보정으로 평면 기울기 일부 완화

### 4.4 사진 측정 — AI 깊이 추정 모듈

**모델**: Depth Anything V2 Small (INT8 양자화). iOS=Core ML, Android=TFLite + GPU/NNAPI delegate.

**플로우**
1. 사진 한 장 입력
2. EXIF에서 focal length(mm/35mm 환산) 추출, 없으면 디바이스 기본값 테이블 폴백
3. 깊이 모델로 픽셀별 깊이 맵 생성
4. 사용자가 두 점 탭 → 카메라 내부 파라미터 + 깊이로 3D 좌표 역투영
5. 두 3D 점 거리 계산

```dart
abstract class DepthEstimator {
  Future<DepthMap> estimate(Uint8List imageBytes);
}
class DepthMap {
  final Float32List depths; // width*height
  final int width;
  final int height;
}
Vector3 unproject(Offset px, double depth, CameraIntrinsics k);
```

**제약**: 반사·투명 물체, 학습 분포 밖 사물에서 오차 큼 → 결과에 "AI 추정 (오차 ±15%)" 명시.

### 4.5 사진 측정 — 캘리브레이션 + 평면 가정 모듈

**용도**: 발 사이즈, 바닥/테이블에 놓인 사물.

**플로우**
1. 사용자 단말 높이 입력(또는 LiDAR/ToF로 자동) + 기준 평면 선택(바닥/테이블)
2. 자이로·가속도계로 단말 기울기 측정
3. 평면 거리·각도로 호모그래피 계산
4. 평면 좌표계로 두 점 변환 → 거리 산출

### 4.6 단위 변환

```dart
enum LengthUnit { mm, cm, inch }
class UnitConverter {
  static double fromMm(double mm, LengthUnit to);
  static String format(double mm, LengthUnit to, {int digits = 1});
}
```

---

## 5. UI/UX 화면 명세

### 5.1 화면 목록
1. **ModeSelectScreen**: AR / 사진 + 사진 서브방식(참조 객체 / AI 깊이 / 캘리브레이션) 선택. 미지원 항목은 disabled + 사유.
2. **ArMeasureScreen**: 카메라 풀스크린 + 크로스헤어 + 측정선 오버레이 + "다시 측정"·"확정" + 다중 측정 모드(둘레/면적/각도) 토글
3. **PhotoReferenceScreen**:
   - Step1: 참조물 종류 선택 (카드/A4/동전/마커)
   - Step2: 안내 시트 + 카메라/갤러리
   - Step3: 자동 감지 결과 + 4점 수동 보정 (드래그)
   - Step4: 대상 두 점 탭 (또는 SAM 2 자동 외곽선)
4. **PhotoAiDepthScreen**: 사진 입력 → 깊이 추정 진행률 → 두 점 탭 → 결과
5. **PhotoCalibrationScreen**: 단말 높이 입력 + 평면 종류 선택 → 촬영 → 두 점 탭
6. **MultiMeasureScreen**: 둘레(점 N개)·면적(폴리곤)·각도(3점) 측정
7. **ResultScreen**: 수치 + 단위 토글(mm/cm/inch) + 신뢰도 배지 + 저장·공유
8. **HistoryScreen**: 저장된 측정 목록 + 상세 보기 + 삭제·공유

### 5.2 공통 가이드 문구 (한국어, 마침표 종결)
- AR: "조명이 밝은 곳에서 측정하세요."
- AR: "단말을 천천히 움직여주세요."
- 사진: "참조물이 평평하게 놓여있는지 확인하세요."
- 사진: "카메라를 위에서 수직으로 비추세요."

---

## 6. 에러·폴백 정책

| 상황 | 처리 |
|------|------|
| AR 미지원 기기 | 모드 선택 화면에서 AR 카드 비활성화 + 사진 모드로 유도 |
| AR 초기화 실패 (60초 초과) | 에러 화면 + 사진 모드 폴백 버튼 |
| AR 트래킹 손실 | 인라인 배너 + 자동 복구 시도 |
| 참조 객체 자동 감지 실패 | 수동 4점 지정 UI로 폴백 |
| 자동 감지 신뢰도 < 0.7 | 결과에 "신뢰도 낮음" 배지 + 수동 보정 권유 |
| AI 깊이 모델 미탑재 기기 | 모드 선택에서 disabled + "사양 미충족" 사유 |
| EXIF focal length 누락 | 디바이스 기본값 테이블 폴백 + 정확도 경고 |
| SAM 2 추론 실패/타임아웃 | 수동 두 점 탭으로 폴백 |
| 카메라 권한 거부 | 권한 안내 화면 + 설정 진입 버튼 |

---

## 7. 패키지 구조 의존성 그래프

```
main → app → features/* → core/*
                       ↘ infrastructure (외부 플러그인)
```
- `core`는 외부 플러그인 import 금지 (순수 Dart, 단위 테스트 용이)
- `infrastructure`는 features 내부에 두고 외부에서 직접 import 금지

---

## 8. 테스트 전략

| 레이어 | 도구 | 범위 |
|--------|------|------|
| 단위 테스트 | `flutter_test` | `core/measurement`, `core/units`, 스케일 계산 |
| 위젯 테스트 | `flutter_test` | 모드 선택·결과 화면 분기 |
| 통합 테스트 | `integration_test` | 카메라 권한 거부 흐름, 모드 전환 |
| 수동 측정 벤치마크 | 체크리스트 | 자·줄자로 실측 대비 오차 기록 (10개 대상 × 2모드) |

---

## 9. 외부 의존성 위험

| 패키지 | 위험 | 대응 |
|--------|------|------|
| `arkit_plugin` / `arcore_flutter_plugin` | 유지보수 불확실, Flutter 신버전 호환 | W1 PoC에서 빌드·런타임 확인, 실패 시 MethodChannel + 네이티브 직접 |
| `opencv_dart` | 빌드 복잡, 앱 크기 ~30MB 증가 | 호모그래피·ArUco·Hough 등 필수 기능에만 사용. iOS는 정적 라이브러리 분리 빌드 검토 |
| YOLOv8 TFLite/Core ML | 모델 학습·라벨링 비용. 참조물 클래스 직접 추가 필요 | 초기엔 공개 학습 모델 + 추가 파인튜닝, 데이터 부족 시 합성 데이터 생성 |
| SAM 2 모바일 | 모바일 추론 시 메모리·시간 부담 (특히 Android 중급 기기) | MobileSAM 또는 SAM 2 Tiny로 다운사이즈 + 사용자 토글로 옵션화 |
| Depth Anything V2 | 절대 깊이 정확도 한계 (±15%) | UI에 "AI 추정" 명시, 결과에 신뢰도 배지 |
| `drift` | 마이그레이션 관리 | 스키마 버전 관리 + 마이그레이션 테스트 |

---

## 10. 개발 로드맵 (Phase 1~3 풀스코프, 1인 풀타임 가정)

### Phase 1 — 핵심 골격 (W1~W6)
| 주차 | 작업 |
|------|------|
| W1 | 프로젝트 셋업, Capability 모듈, AR 플러그인 PoC(iOS+Android), 라우팅·테마(Material 3 + Teal #00897B) |
| W2 | AR 측정 (iOS ARKit) — 두 점 찍기 동작 |
| W3 | AR 측정 (Android ARCore) + 공통 UI 골격 |
| W4 | 참조 객체 모드 (신용카드) — 수동 4점 + 스케일 계산 + 두 점 탭 |
| W5 | 결과 화면, 단위 변환, 폴백·에러 처리, 단위 테스트 |
| W6 | 1차 수동 벤치마크, 버그픽스, Phase 1 내부 빌드 |

### Phase 2 — 정확도 확장 (W7~W10)
| 주차 | 작업 |
|------|------|
| W7 | LiDAR 활용 모듈 (iOS Pro 라인) + 정확도 검증 |
| W8 | 참조 객체 확장 (A4, 100원/500원 동전) + YOLOv8 커스텀 파인튜닝 |
| W9 | ArUco/QR 마커 지원 + 호모그래피 보정 통합 |
| W10 | SAM 2 / MobileSAM 통합 (자동 대상 외곽선) + 2차 벤치마크 |

### Phase 3 — 확장 기능 (W11~W16)
| 주차 | 작업 |
|------|------|
| W11 | AI 깊이 추정 모듈 (Depth Anything V2 Core ML/TFLite) |
| W12 | 카메라 캘리브레이션 + 평면 가정 모드 |
| W13 | 측정 이력 저장 (drift) + 조회·삭제 화면 |
| W14 | 결과 공유 (이미지+텍스트), 다중 측정(둘레/면적/각도) |
| W15 | AR 측정선 3D 공간 고정·재시청 (앵커 영속화) |
| W16 | 3차 통합 벤치마크, 성능 최적화, Phase 3 내부 빌드 |

**총 16주 (4개월)**. 일정은 W6·W10·W16 종료 시점에 재검토.

---

## 11. 확정된 결정 사항

| # | 항목 | 결정 | 일자 |
|---|------|------|------|
| 1 | 플랫폼 | Flutter (iOS + Android) | 2026-05-26 |
| 2 | 구현 범위 | Phase 1~3 풀스코프 + 운영 단계 보완 | 2026-05-26 |
| 3 | AR 플러그인 | `arkit_plugin` + `arcore_flutter_plugin` 분리 | 2026-05-26 |
| 4 | 상태관리 | Riverpod 2.x | 2026-05-26 |
| 5 | 최소 OS | iOS 14 / Android 8 (API 26) | 2026-05-26 |
| 6 | 디자인 | Material 3 + 시드 컬러 Teal `#00897B` | 2026-05-26 |
| 7 | 성공 기준 | AR ≤3% / 참조객체 ≤5% / AI깊이 ≤15% / 콜드스타트 ≤30초 | 2026-05-26 |
| 8 | 조직 / 번들 ID / 앱 이름 | `com.lionplusmaster` / `com.lionplusmaster.length` / `Length` | 2026-05-26 |

---

## 12. 향후 검토 받을 사항

- W6·W10·W16 종료 시점 일정 재검토
- Phase 4 (자동 벤치마크 파이프라인, 다국어, 사용자 피드백 기반 보정) 진입 시점
