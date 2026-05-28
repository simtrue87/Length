<!-- Length 컨텍스트 노트: 설계 중 내린 결정과 근거를 누적 기록 -->

# Length 컨텍스트 노트

> 작업 중 내린 결정과 이유를 시간 순으로 누적. 다음 세션이 재해석 없이 이어갈 수 있도록.

---

## 2026-05-26 — 초기 설계 결정

### 결정 1. 플랫폼: Flutter 단일 코드베이스
- 근거: iOS+Android 동시 출시, UI 일관성.
- 트레이드오프: AR 네이티브 기능은 플러그인 의존. 최악의 경우 MethodChannel로 우회.

### 결정 2. 구현 범위: Phase 1~3 풀스코프
- 사용자 방침: "제안한 기능 전체를 구현해두고, 운영하며 부족한 부분을 보완".
- 포함: AR(두 점 + LiDAR), 참조 객체(카드/A4/동전/마커), SAM 2 세그멘테이션, AI 깊이 추정, 캘리브레이션·평면 가정, 이력·공유·다중 측정.
- Phase 4(자동 벤치마크 파이프라인, 다국어, 사용자 보정)는 운영 단계 보완 영역으로 남김.
- 영향: 일정 약 16주. W6·W10·W16에 게이트 재검토.

### 결정 3. AR 플러그인: `arkit_plugin`(iOS) + `arcore_flutter_plugin`(Android) 분리
- 근거: 통합 플러그인(`ar_flutter_plugin` 계열) 유지보수 리스크 회피. 각 네이티브 SDK 기능(LiDAR API 등)을 직접 노출 가능.
- 영향: Flutter 측 `ArSession` 추상 인터페이스로 차이 흡수. 어댑터 2개를 `features/ar_measure/infrastructure/`에 분리(`arkit_session.dart`, `arcore_session.dart`).
- 리스크: 두 플러그인 모두 유지보수가 들쭉날쭉. W1 PoC에서 빌드·hit-test·렌더링 검증 필수. 막히면 해당 플랫폼만 MethodChannel + 네이티브로 부분 전환.

### 결정 4. 상태관리: Riverpod 2.x (+ `riverpod_generator`)
- 근거: AR 세션·카메라 스트림을 `AsyncNotifier`/`StreamProvider`로 자연스럽게 처리. DI로 어댑터 테스트 교체 용이.
- 영향: 모든 features의 application 레이어는 `*Notifier` + `riverpod_generator` 코드 생성.

### 결정 5. 최소 OS: iOS 14 / Android 8 (API 26)
- 근거: ARKit 4(Depth API) + ARCore 안정 동작. 커버리지·코드 단순성 균형.
- 영향: iOS 13/Android 7에서 발생할 LiDAR·NPU 분기 복잡도 회피.

### 결정 6. 디자인: Material 3 + 시드 컬러 Teal `#00897B`
- 근거: 별도 시안 없음. 기능 구현 비중을 높이기 위해 시스템 디자인 최대 활용. 측정 도구 톤(정밀·차분)에 부합.
- 적용: `ColorScheme.fromSeed(seedColor: Color(0xFF00897B))` + `useMaterial3: true`.

### 결정 7. 성공 기준
- AR ≤ 3%, 참조 객체 ≤ 5%, AI 깊이 ≤ 15%, 콜드스타트~첫 측정 ≤ 30초.
- 근거: 전략 문서의 정확도 표를 보수적으로 잡음. AI 깊이는 모델 한계(±5~15%) 상한 반영.

### 결정 8. core 계층은 순수 Dart
- 외부 플러그인 import 금지 → 단위 테스트 가능, 플랫폼 무관.
- features/infrastructure가 어댑터 역할.

### 결정 9. 참조 객체 자동 감지 + 수동 4점 폴백 병행
- 풀스코프 전제하에 YOLOv8 커스텀 모델로 자동 감지 진행.
- 신뢰도 < 0.7 또는 감지 실패 시 수동 4점 UI로 폴백 → UX 일관성 유지.

---

### 결정 11. 초기 빌드 타겟: Android 우선
- 일자: 2026-05-26
- 사용자 환경이 Windows이므로 iOS 빌드 불가. 우선 Android에서 W1~Wn 진행, iOS는 Mac 확보 후 별도 시점에 빌드·테스트.
- 영향: 코드는 cross-platform Flutter로 유지(iOS 어댑터 코드 포함 작성). 단, 실기기 검증은 Android만. iOS 검증 단계는 Mac 확보 시점으로 이동.
- 체크리스트의 iOS 항목(arkit_plugin PoC, ARKit 어댑터 등)은 코드 작성은 진행하되 "iOS 실기기 테스트"는 보류 상태로 표시.

### 결정 10. 식별자
- 조직명(prefix): `com.lionplusmaster`
- 번들 ID: `com.lionplusmaster.length` (iOS Bundle Identifier == Android applicationId)
- 앱 이름: `Length` (영문 단일. 다국어는 Phase 4 진입 시 추가)
- 적용: `flutter create --org com.lionplusmaster --project-name length length`
- 근거: 사용자 이메일 `lionplusmaster1` 기반 역도메인. 도메인 미보유지만 개인 프로젝트에 흔히 쓰이는 패턴.
- 변경 불가: 출시 후 번들 ID는 변경 불가. 앱 이름은 언제든 변경 가능.

---

### 결정 12. ARCore — 폐기된 플러그인 대신 MethodChannel + 네이티브 직접 구현
- 일자: 2026-05-27
- `arcore_flutter_plugin`은 2020년 이후 유지보수 중단. Flutter 3.44 + AGP 8.9에서 빌드 불가 예상.
- 대안: ARCore SDK(com.google.ar:core)를 app에 직접 의존, `ArcoreSessionHandler.kt`로 세션 라이프사이클(checkAvailability/requestInstall/createSession/releaseSession) 노출. Dart 측은 `ArSession` 추상 + `ArcoreSession` 어댑터.
- iOS도 동일 패턴(MethodChannel + ARKit 네이티브)으로 통일 예정. Mac 확보 시 ArkitSession 작성.
- 영향: PlatformView + GL 렌더링은 W2/W3 본격 AR 측정 구현 시점에 추가. W1은 세션 생성 가능성까지만 검증.

### 결정 13. Flutter SDK·툴체인 버전 일괄 업그레이드
- 일자: 2026-05-27
- Flutter 3.22.0 → **3.44.0** (Dart 3.12). 3.22는 `flutter.compileSdkVersion` extension 미지원 → 최신 플러그인(sensors_plus 7.0 등) 빌드 실패.
- Gradle 7.6.3 → **8.11.1** (Java 21 + AGP 8.9 호환).
- AGP 7.3 → **8.9.1** (image_picker가 androidx.activity 1.12.4 요구).
- Kotlin 1.7.10 → **2.2.20** (Flutter 3.44 권장 + sensors_plus의 KGP 2.2.0 호환).
- Java 컴파일 타깃 8 → **17**.
- 영향: 향후 플러그인 호환성은 신경 덜 써도 됨. 단, 다른 머신 셋업 시 동일 버전 명시 필요.

### 결정 14. W2/W3(AR 본격 구현) 보류, W4(참조 객체) 우선 진행
- 일자: 2026-05-27
- 이유: PlatformView + 네이티브 GL 렌더러 작업이 크고 (2~3주), 에뮬레이터 검증도 빈약. 사진 기반 측정은 Flutter 단독으로 빠르게 가시적 결과 가능.
- 결과: W4 + W5(결과 화면/단위 변환/엔진 단위 테스트) + 자이로 경고까지 일괄 구현 완료(2026-05-27).
- 후속: AR 본격 구현은 (a) ARCore 에뮬레이터 검증 통과 후, 또는 (b) 실기기 확보 후 재개.

### 결정 15. 디렉터리 스캐폴딩은 "필요할 때" 생성
- 일자: 2026-05-27
- design.md 3.1의 전체 트리(`features/photo_measure/{reference_object,ai_depth,calibration,segmentation,...}`)를 미리 빈 폴더로 깔지 않음.
- 각 모듈은 해당 주차 작업 시 생성. 현재 존재: `core/{capability,measurement,units}`, `features/{ar_measure,photo_measure/reference_object,result,history,mode_select}`, `shared/sensors`.

---

### 결정 16. drift_dev 도입을 위한 의존성 정리
- 일자: 2026-05-27
- drift_dev가 build ^3.0.0을 요구하는데 `riverpod_generator 2.4`(build ^2.0.0)와 `riverpod_lint 2.3`(custom_lint 0.6.x)가 충돌.
- 현재 두 패키지 모두 미사용 → 제거. Riverpod은 손코딩 Provider/StreamProvider로 충분.
- 영향: 향후 Riverpod codegen이 필요해지면 `riverpod_generator 3.x`로 직접 추가. 그 시점에 다시 종속성 검토.

### 결정 17. MeasureKind 도입(거리/둘레/면적/각도) + DB 스키마 v1→v2
- 일자: 2026-05-27
- `MeasurementResult`를 일반화: `value` 필드 + `kind` enum. 값 단위는 kind별로 다름(거리/둘레=mm, 면적=mm², 각도=°).
- DB: `value_mm` 컬럼을 `value`로 rename + `kind` 컬럼 추가(기본 'distance'). 기존 이력 보존.
- 영향: 결과·이력·공유 화면이 kind별로 분기. 단위 토글은 각도 모드에서 숨김.

### 결정 18. 측정선 오버레이 이미지 캡처 — `RepaintBoundary`
- 일자: 2026-05-27
- 결과 공유와 이력 썸네일을 위해 측정 단계의 RepaintBoundary를 PNG로 캡처해 임시파일에 저장(`shared/capture/capture_widget.dart`).
- 경로는 `MeasurementResult.imagePath`로 전달. DB의 image_path 컬럼에 영속.
- SharePlus 시 파일이 존재하면 텍스트+이미지, 없으면 텍스트만.

### 결정 19. W2/W3 우회 — 사진 모드 4종으로 Phase 1~3 사용성 확보
- 일자: 2026-05-27
- AR이 막힌 동안 사진 모드 라인업 완비: 참조 객체(W4) → 다중 측정(W14) → 캘리브레이션(W12) → AI 깊이 베타(W11 스텁).
- 4종 모두 N점 입력 + 거리/둘레/면적/각도 4가지 측정 종류 지원.
- 코드 중복: PhotoReferenceScreen/PhotoCalibrationScreen/PhotoAiDepthScreen이 measure 단계를 일부 복사. 세 번째 사용처가 나타난 시점에 추출 검토(현 시점은 premature abstraction 회피).

### 결정 20. W11 AI 깊이는 스텁부터 — 모델 통합은 분리 단계
- 일자: 2026-05-27
- `StubDepthEstimator`로 흐름·UI·결과 신뢰도 표기까지 완비. 실제 Depth Anything V2 모델 통합은 별도 작업(tflite_flutter + .tflite 자산 번들).
- 스텁 모드 결과는 `confidence: low` 강제 + 메모에 '⚠ 상대 깊이(스텁) — 참고용' 표기.
- 영향: 폰 검증 시점에 모델 교체 가능. UX·아키텍처는 이미 검증 대상.

### 결정 21. CameraIntrinsics 근사 — 35mm 환산만 사용
- 일자: 2026-05-27
- design.md는 EXIF focal length + 디바이스 폴백 테이블을 명시했지만, 1차 구현은 `FocalLengthIn35mmFilm` 한 필드만 사용 + 26mm 기본 폴백.
- fx = (focal35mm / 36) * widthPx, fy = (focal35mm / 24) * heightPx, 주점은 이미지 중심으로 가정.
- 영향: 정확도 한계 인지. 캘리브레이션 보정·디바이스 테이블은 W11 본격 통합 시 보완.

### 결정 22. 캘리브레이션 모드는 위젯 높이 기준 mm/픽셀
- 일자: 2026-05-27
- 평면 위 수직 촬영 가정에서, 이미지 → 위젯 픽셀 스케일링이 일정하므로 위젯 높이로 직접 환산: `mmPerPx = 2 * h * tan(FOV/2) / widgetHeightPx`.
- 호모그래피 보정·기울기 보정은 W9에서 추가 예정. 현재는 기울기 > 10° 시 메모 경고, > 20° 시 신뢰도 low.

### 결정 23. W9 마커 모드는 `mobile_scanner` QR로 1차 — opencv_dart/ArUco는 보류
- 일자: 2026-05-27
- 마커 모드 첫 번째 구현으로 QR(`mobile_scanner`) 선택. ArUco·호모그래피는 `opencv_dart`(~30MB) 도입을 W10/W16에 묶어 진행.
- QR 자동 감지 성공 시 신뢰도 `high`, 실패 시 수동 4점 폴백(중간 신뢰도). 4변 평균으로 mm/픽셀 계산.
- 영향: opencv_dart 의존성 미진입 → 앱 크기 안정. 다만 호모그래피 평면 정합·ArUco 정밀도는 미확보.

### 결정 24. 사용자 설정 영속화는 화면별 작은 AsyncNotifier
- 일자: 2026-05-27
- `shared_preferences` 도입. `core/settings/`에 화면 단위로 작은 `AsyncNotifier` 작성(`preferredUnitProvider`, `calibrationPrefsProvider`, `markerSideMmProvider`).
- 화면은 `initState`에서 `ref.read(provider.future)`로 1회 로드 → TextField 초기값 설정. 입력 확정 시 `notifier.save(...)` 호출.
- 영향: 추상 SettingsRepository 같은 공통화 회피(과도한 일반화 방지). 새 설정은 같은 패턴으로 1파일 1Notifier 추가.

### 결정 25. 측정 진행 중 이탈 보호는 `PopScope` + 사용자 확인 다이얼로그
- 일자: 2026-05-27
- 사진 측정 4종 모두 초기 입력 화면 이후 단계에서는 `PopScope(canPop: !inProgress)` + `confirmExitMeasurement` 다이얼로그 적용.
- 다이얼로그 결과 true일 때만 `Navigator.pop` 호출. 시스템 뒤로가기·스와이프 모두 캡처.
- 영향: 진행 중 점·보정 정보 손실 방지. 초기 화면은 자유 이탈 유지.

### 결정 26. 사진 화면 measure 단계 공통화는 4번째 사용처에서 — 현재는 보류
- 일자: 2026-05-27
- reference/calibration/marker/ai_depth 4개 사진 화면이 measure 단계(점 입력·드래그·실행 취소·캡처)를 일부 복사 중.
- 4번째인 ai_depth는 2점 전용으로 약간 다름 → 완전 동일은 3개. 추출 후보지만 차이점(reference의 4점 overlay, marker의 자동 감지) 흡수 비용이 큼.
- 다섯 번째 사진 모드 또는 큰 UX 변경 시 `MeasureStage` 위젯으로 추출.

### 결정 27. 모드 선택 IA(정보 구조) 정리
- 일자: 2026-05-27
- 모드가 5개로 늘어남 → 섹션 헤더(AR/사진/도구), leading 아이콘, 배지(자동/베타), 추천 카드 강조(primaryContainer)로 시각적 정리.
- "이력 보기"를 별도 버튼 → 도구 섹션 카드로 통합.

### 결정 31. 사진 모드 스케일은 4-edge 평균 → 호모그래피로 교체
- 일자: 2026-05-27
- 기존 `_mmPerPixel()`(top/bottom edge 평균)는 카메라가 정확히 수직일 때만 정확. 일반 사용 케이스(약간 비스듬한 위에서 촬영)에서 카드가 사다리꼴로 나오면 위치별 픽셀 스케일이 달라져 오차 10%+.
- `PlanarRectifier.fromCorners(corners, widthMm, heightMm)`로 `cv.findHomography` 사용. 위젯 픽셀 → 카드 평면 mm 좌표로 매핑.
- `distanceMm`, `polylineLengthMm`, `polygonAreaMm2`, `angleAtVertexDegrees` 모두 mm 공간에서 계산해 원근 왜곡 보정.
- 적용 모드: photo_reference, photo_marker, photo_fish. 캘리브레이션·AI 깊이는 다른 스케일 모델이라 별도.
- 영향: 같은 평면 위 측정은 카드가 사다리꼴로 보여도 정확. 평면 가정만 유지되면 됨.
- 테스트: opencv_dart 네이티브 라이브러리는 Dart VM 단위 테스트 환경에 없어 디바이스/에뮬레이터 통합 검증으로만 가능. `phone_verification.md` 섹션 1.0에 사다리꼴 카드 시나리오 추가.

### 결정 30. W11 모델 인프라 완비 — 모델 파일만 추가하면 동작
- 일자: 2026-05-27
- `tflite_flutter 0.12.1` 도입. JVM target 17 강제(서브프로젝트 afterEvaluate에서 Java+Kotlin 정렬)로 빌드 통과.
- `TfliteDepthEstimator.load()`는 자산(`assets/models/depth_anything_v2_small.tflite`)이 없으면 `ModelMissingException` → `resolveDepthEstimator()`가 `StubDepthEstimator`로 폴백.
- 모델 변환 절차는 `docs/models/depth_anything_v2.md`에 분리. 라이선스·용량 문제로 리포지터리에 모델 미포함.
- UI는 자동 분기: 모델 있으면 "Depth Anything V2 모델 로드 완료" + 모드 라벨 "사진 — AI 깊이", 없으면 "사진 — AI 깊이 (스텁)".
- 영향: ML 환경에서 모델 만들어 `assets/models/`에 떨구는 것만으로 실제 추론 모드 진입 가능. Dart/Native 추가 코드 불필요.

### 결정 29. opencv_dart 도입 — W8 신용카드 자동 4점 감지
- 일자: 2026-05-27
- `opencv_dart 1.4.5`(dartcv4 1.1.8) 도입. Android 빌드 통과 확인.
- `CardDetector`: Canny → findContours → approxPolyDP(4점) → 면적 1%~90% + 종횡비(1.586 ±20%) 필터 → 점수 = 면적 × (1 − 종횡비오차) 최대값 선택. 시계방향(TL/TR/BR/BL) 정렬.
- 결과: 자동 감지 성공 시 신뢰도 `high` + 메모 "자동 4점 감지", 실패 시 기존 수동 폴백.
- **APK 크기**(`--split-per-abi --release`): armeabi-v7a 43.3MB / arm64-v8a 55.9MB / x86_64 66.1MB. design.md 예상(~30MB 증가)과 일치.
- 영향: Play Store ABI 분리 배포로 사용자 다운로드 크기 ~45~56MB. W9 ArUco·호모그래피·W10 YOLO 추가 시 동일 의존성 재사용 가능.

### 결정 28. 이력 화면은 Kind 필터 + 날짜 그룹 + 썸네일로 운영성 확보
- 일자: 2026-05-27
- 단순 목록 → ChoiceChip 필터(전체/4종) + 날짜 그룹(오늘/어제/이번주/이전) + 캡처 썸네일(없으면 종류 아이콘).
- 부제목에 `{kind} · {modeLabel} · HH:mm` 정보 밀도 ↑. 그룹 헤더가 날짜를 대체.

### 결정 33. ArUco 마커 감지 추가 (W9)
- 일자: 2026-05-28
- `aruco_detector.dart` 신설. `opencv_dart`의 `ArucoDetector` + `ArucoDictionary.predefined` 사용.
- 사전 4종 순회: DICT_4X4_50 → DICT_5X5_100 → DICT_6X6_250 → DICT_APRILTAG_36h11. 첫 매칭 사용.
- `photo_marker_screen._detect`: 1차 QR (mobile_scanner) → 실패 시 2차 ArUco. 감지된 마커 타입·ID를 상태 텍스트로 표시.
- 다중 마커 발견 시 가장 큰(가장 잘 보이는) 마커 선택.
- 모드 선택 화면 라벨: "QR/마커" → "QR/ArUco 마커". 위젯 테스트도 함께 갱신.
- 향후: 마커 크기(mm) 입력은 기존 그대로. 호모그래피는 PlanarRectifier가 처리.

### 결정 32. YOLO 카드 모델 ML 환경 — Colab Pro
- 일자: 2026-05-28
- 학습 GPU 환경: **Colab Pro (T4/L4)**. 로컬 GPU 없음, Colab Pro 100컴퓨트 유닛으로 yolo11n-seg 100 epochs 충분.
- 데이터 준비(합성·MIDV-500·실사)는 로컬에서 `ml/card_detector/` 워크스페이스.
- 학습은 Google Drive에 데이터 업로드 → Colab 노트북에서 `ultralytics` 호출.
- 노트북: `ml/card_detector/train_colab.ipynb` (Phase A 끝나면 작성).

### 결정 31. 신용카드 검출 — 자체 YOLO11n-seg 모델 경로로 전환
- 일자: 2026-05-28
- 배경: A90 5G 실기기 테스트에서 OpenCV 기반 CardDetector 한계 확인. 카드+폰 인접 시 모폴로지 close가 두 윤곽을 융합, 카드 외곽이 깨져 RETR_EXTERNAL이 내부 작은 영역만 잡음. 점수 튜닝·ROI 재검색·코너 스냅으로 임시 운영 가능하나 자동 4점 검출 정확도 낮음.
- ML Kit Document Scanner는 카메라 풀스크린 UI 방식으로 *기존 사진의 카드 4점 추출*에는 부적합(보정·잘린 이미지만 반환). 측정 시나리오(카드+대상 동시 촬영)와 충돌.
- Apple Vision `VNDetectRectanglesRequest`는 임의 사진에서 4점 추출 가능하나 iOS 한정.
- 결정: 크로스플랫폼 정공법으로 **YOLO11n-seg 단일 클래스(credit_card) 자체 모델** 도입. `tflite_flutter` 인프라 이미 존재(depth_anything).
- 절차: `docs/models/credit_card_yolo.md`. Phase A~F 단계 분해, 예상 4~7일.
- 기존 CV CardDetector는 폴백(YOLO → CV → ROI 수동)으로 유지.

### 결정 30. PlanarRectifier 카드 방향 자동 보정
- 일자: 2026-05-28
- 증상: 갤럭시 A90 실기기에서 세로로 놓인 신용카드 사진 측정 시 16.5cm 대상이 8.58cm로 출력 (≈0.52배 축소).
- 원인: `_orderClockwise`는 TL을 `min(x+y)` 코너로만 정렬. 카드가 세로면 `TL→TR`이 실제로는 단변(53.98mm)인데 호모그래피 dst가 `widthMm(85.6mm)`로 매핑 → 스케일이 단변/장변 비율로 어긋남.
- 수정: `PlanarRectifier.fromCorners`에서 `topPx vs rightPx` 비교로 `imageIsLandscape` 판정 후, 참조물 가로·세로(`refIsLandscape`)와 부호가 다르면 `widthMm/heightMm` 스왑하여 dstVec 구성.
- 적용 범위: 신용카드(85.6/53.98) 외에 A4·QR(대각 4점) 모두 자동 적용. 정사각 참조물(동전·QR `widthMm==heightMm`)은 영향 없음.
- 검증: A90 실기기, 16.5cm 대상 근사치 확인 (2026-05-28).

---

## 진행 현황 (2026-05-28 종료 시점)

- W0~W1: 완료. ARCore PoC는 세션 생성까지.
- W2/W3: ⏸ 보류 (실기기 확보 후 결정).
- W4: 완료 + 에뮬 검증.
- W5: 완료 (권한 거부·AR 폴백·위젯 테스트 포함).
- W6: 코드/문서 완료, 사용자 실측 대기.
- W7: ⏸ 보류 (iOS Pro 기기 필요).
- W8: 신용카드 자동 4점 감지 완료(opencv_dart). 다른 참조물(A4·동전)은 W10 단계에서 YOLOv8과 함께. **A90 실기기 검증 + 방향 인식 버그 픽스(2026-05-28)**.
- W9: QR 부분 완료. ArUco/호모그래피는 opencv_dart 활용 추후.
- W10: 미착수.
- W11: 인프라 완비. 모델 자산(`assets/models/`) 추가만 남음. 미배치 시 자동 Stub 폴백.
- W12: 완료.
- W13: 완료 + 검증.
- W14: 완료. 검증 대기.
- W15/W16: 미착수.

추가 UX 작업(checklist 외):
- 카메라 권한 영구 거부 핸들링 (`permission_handler`).
- 모드 선택 IA 정리 (섹션·배지·아이콘·추천 강조).
- 이력 필터·그룹·썸네일.
- 사용자 설정 영속화 (단위·캘리브레이션·QR 크기).
- 측정 진행 중 뒤로가기 보호 (`PopScope`).

테스트: 52개 통과. debug/release APK 빌드 통과.

---

## 미확정 / 사용자 검토 대기

1. Phase 4 진입 시점.
2. W2/W3(AR 본격 구현) 재개 시점 — 폰 확보 후 결정.
3. W6 게이트 실측 결과 — 사용자가 phase1_benchmark.md 시트 채울 예정.
4. W11 실제 모델 통합 시점 — Depth Anything V2 변환·번들링 (별도 ML 환경 필요).
5. W8/W9 opencv_dart 도입 시점 — 호모그래피·ArUco·자동 감지 묶어서 결정.

---

## 위험 관리 메모

- **AR 플러그인 리스크**: 폐기된 플러그인 회피 → MethodChannel + 네이티브 직접(결정 12). 실측 검증은 폰 확보 후.
- **opencv_dart 부담**: 앱 크기 ~30MB 증가. W8 도입 직전 빌드 검증.
- **모델 자산 관리**: YOLOv8·SAM 2·Depth Anything V2 합치면 수십 MB. 앱 내 번들 vs 첫 실행 시 다운로드 전략을 W10 전에 결정.
- **YOLOv8 데이터셋**: 참조물(카드·A4·동전) 학습 데이터 부족 가능. 합성 데이터(`Albumentations` + 배경 합성) 준비 사전 계획.
- **벤치마크 누락 방지**: W6·W10·W16에 명시적 벤치마크 일정. 누적 회귀 방지.
- **Android 중급 기기**: SAM 2/Depth 모델 OOM·발열 가능. 모델 다운사이즈 + 토글 + 캐퍼빌리티 기준 강화.
- **AI 깊이 정확도**: 상대 깊이 모델은 절대 mm 변환이 불안정. EXIF 누락 시 폴백 폭이 커짐. UX에서 "참고용" 명시 + 신뢰도 low로 보수적 운영.
- **사진 측정 화면 중복**: 4개 화면(reference/calibration/ai_depth + 향후 marker)이 measure 단계 코드를 일부 복사. 1~2개 더 늘면 공통 위젯 추출 필수.
- **Flutter SDK·플러그인 호환성**: 3.22→3.44 일괄 업그레이드 후 안정. 향후 SDK 업그레이드 시 sensors_plus·image_picker·drift 모두 함께 검토.
