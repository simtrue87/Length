<!-- Length 개발 체크리스트: Phase 1~3 풀스코프 작업 단위 -->

# Length 개발 체크리스트

> `design.md`의 Phase 1~3 전체 범위를 실행 단위로 분해. 완료 시 체크.

---

## Phase 1 — 핵심 골격 (W1~W6)

### W0 — 사전 환경 (사용자 진행)
- [ ] ~~Flutter SDK 3.22~~+ 설치 후 PATH 등록
- [ ] Android Studio 설치 (SDK, platform-tools, emulator)
- [ ] `flutter doctor` 결과 공유
- [ ] (iOS는 Mac 확보 시점에 별도 처리, 현재 보류)

### W1 — 셋업 & PoC (Android 우선)
- [ ] Flutter 프로젝트 생성 (`length`), Dart 3.4+, Flutter 3.22+
- [ ] `flutter create --org com.lionplusmaster --project-name length length` 실행
- [ ] iOS Info.plist `CFBundleDisplayName = Length`
- [ ] Android `android:label="Length"` 설정
- [ ] 최소 OS 설정 (iOS 14 / Android 8 / minSdk 26)
- [ ] 의존성 추가: `flutter_riverpod` + `riverpod_generator`, `go_router`, `camera`, `sensors_plus`, `permission_handler`, `logger`
- [ ] 디렉터리 스캐폴딩 (`core/`, `features/`, `shared/`, `app/`)
- [ ] 라우팅 골격 (모드 선택 + 측정 + 결과 + 이력 빈 스캐폴드)
- [ ] Material 3 테마 + 시드 컬러 Teal `#00897B`
- [ ] `arkit_plugin` PoC (iOS 실기기 빌드·hit-test 검증)
- [ ] `arcore_flutter_plugin` PoC (Android 실기기)
- [ ] Capability Detector MethodChannel 구현 (AR/LiDAR/ToF/NPU/RAM)
- [ ] Capability 단위 테스트

### W2 — AR 측정 (iOS — 코드만, 빌드/실기기는 Mac 확보 후)
- [ ] iOS 카메라/AR 권한 Info.plist
- [ ] `ArSession` 추상 인터페이스 정의
- [ ] `ArkitSession` 어댑터 구현 (raycast, anchor, line draw)
- [ ] AR 상태 머신 Riverpod Notifier
- [ ] AR 측정 화면 UI (크로스헤어, 상태 텍스트, 측정선)
- [ ] 두 점 찍기 → 거리 → 결과 이동
- [ ] ⏸ iOS 실기기 테스트 (Mac 확보 시 진행)

### W3 — AR 측정 (Android) & 공통 UI
- [ ] Android 카메라/AR 권한, ARCore manifest
- [ ] `ArcoreSession` 어댑터 구현
- [ ] 모드 선택 화면 (capability에 따른 disabled)
- [ ] AR 트래킹 손실 배너 + 복구 흐름
- [ ] Android 실기기 테스트

### W4 — 참조 객체 (신용카드)
- [ ] 카메라 촬영·갤러리 선택 화면
- [ ] 신용카드 4점 수동 지정 UI (드래그 핸들 4개)
- [ ] `computeScale(refPixelLength, 85.6)` 적용
- [ ] 측정 대상 두 점 탭 UI
- [ ] 자이로 기울기 30° 경고 토스트

### W5 — 결과·폴백·테스트
- [x] 결과 화면 (수치 + mm/cm/inch 토글, 신뢰도 배지)
- [x] 단위 변환 단위 테스트
- [x] 측정 엔진 단위 테스트 (distance3D, pixelToMm, computeScale, polyline, polygon, angle, intrinsics)
- [x] 카메라 권한 거부 흐름 (permission_handler, 영구 거부 시 설정 안내 다이얼로그)
- [x] AR 미지원 기기 사진 폴백 (ArMeasureScreen에서 자동 안내 + 사진 모드 진입 버튼)
- [x] 위젯 테스트 (모드 선택, 결과)

### W6 — 1차 벤치마크 & 빌드
- [x] 벤치마크 시트 템플릿 (`docs/benchmarks/phase1_benchmark.md`) — 10개 대상 × 측정 종류
- [ ] ⏸ AR 평균 오차 ≤ 3% 검증 (W2/W3 보류로 1차 게이트 제외, W10에 재진입)
- [ ] 참조 객체 평균 오차 ≤ 5% 검증 (사용자 실측 — 시트 채우기)
- [ ] 콜드 스타트~첫 측정 ≤ 30초 검증 (스톱워치 절차 문서화)
- [ ] iOS TestFlight (Mac 확보 후) / Android 릴리스 APK 빌드

---

## Phase 2 — 정확도 확장 (W7~W10)

### W7 — LiDAR
- [ ] `ARWorldTrackingConfiguration.sceneReconstruction = .mesh` 활성화
- [ ] `ARMeshAnchor` 기반 정밀 hit-test 분기
- [ ] Capability에 따라 LiDAR 자동 활성화
- [ ] LiDAR 기기 정확도 ±1cm 검증

### W8 — 참조 객체 확장
- [x] `opencv_dart` 도입 및 빌드 검증 (1.4.5, APK ~45~56MB per ABI)
- [x] 신용카드 자동 4점 감지 (Canny + findContours + approxPolyDP)
- [x] 신용카드 검출 고도화 v1 (minAreaRect, 적응형 Canny, adaptive threshold, ROI 재검색 fallback, 코너 스냅) — A90 5G 실기기 검증 후 한계 확인 (카드+폰 인접 시 컨투어 융합)
- [ ] **신용카드 YOLO11n-seg 모델 도입 (W8b)** — 카드+폰 인접·반사·복잡 배경 대응 정공법. `docs/models/credit_card_yolo.md` 절차
  - [ ] Phase A: 데이터셋 준비 (MIDV-500 + 합성 + 실사)
  - [ ] Phase B: YOLO11n-seg 학습 (단일 클래스 credit_card)
  - [ ] Phase C: ONNX → TFLite INT8 변환 (≤8MB, ≤150ms)
  - [ ] Phase D: `YoloCardDetector` Dart 통합 + CV 폴백 체인
  - [ ] Phase E: 벤치마크 검증 (자동 4점 ≥85%, corner err ≤10px)
  - [ ] Phase F: 롤아웃 (모델 자산 번들 또는 다운로드)
- [ ] A4 감지 (YOLO 다중 클래스 확장)
- [ ] 100원/500원 동전 감지 (YOLO + Hough Circle)

### W9 — 마커 & 호모그래피
- [ ] ArUco 마커 감지 (`opencv_dart`) — opencv_dart 도입 보류로 추후
- [x] QR 코드 감지 (`mobile_scanner`) + 자동 4점 보정 + 수동 폴백
- [ ] `findHomography` + `warpPerspective` 평면 정합 — opencv_dart 필요
- [ ] 호모그래피 적용 전후 정확도 비교

### W10 — 세그멘테이션 & 벤치마크
- [ ] SAM 2 Tiny 또는 MobileSAM 모바일 변환
- [ ] 대상 외곽선 자동 추출 + 사용자 토글
- [ ] 추론 시간·메모리 측정 (중급 Android 포함)
- [ ] 2차 벤치마크

---

## Phase 3 — 확장 기능 (W11~W16)

### W11 — AI 깊이 추정 (스텁 + TFLite 인프라 완비)
- [ ] Depth Anything V2 Small 모델 변환 (Python ML 환경 필요, `docs/models/depth_anything_v2.md`)
- [ ] INT8 양자화 + GPU/NNAPI delegate 설정
- [x] EXIF focal length 파싱 (`exif` 패키지) + 26mm 기본 폴백
- [x] `unproject(u, v, depth, intrinsics)` 구현 + 단위 테스트
- [x] AI 깊이 화면 + 결과 (신뢰도 배지 "낮음" + 스텁/실모델 분기)
- [x] `TfliteDepthEstimator` 구현 + 자산 누락 시 Stub 폴백 (`tflite_flutter` 통합)
- [ ] `assets/models/depth_anything_v2_small.tflite` 번들 (사용자 작업)

### W12 — 캘리브레이션 + 평면 가정
- [x] 단말 높이·FOV 입력 UI (LiDAR/ToF 자동 분기는 추후)
- [x] 자이로 기울기 실시간 표시 + 메모/신뢰도 강등 (10° / 20° 임계)
- [ ] 호모그래피로 평면 좌표계 변환 (현재는 수직 촬영 가정 단순 모델)
- [ ] ⏸ 발 사이즈 측정 시나리오 검증 (폰 확보 후)

### W13 — 이력 저장
- [x] `drift` 도입, 스키마 정의 (id, modeLabel, value, kind, confidence, note, imagePath, createdAt)
- [x] 측정 완료 시 저장 버튼
- [x] 이력 목록·재조회·스와이프 삭제 화면
- [x] CRUD + 스키마 v1→v2 마이그레이션 테스트

### W14 — 공유 & 다중 측정
- [x] `share_plus` 통합 (텍스트 + 캡처 PNG)
- [x] 결과 캔버스 렌더링 (RepaintBoundary 측정선 오버레이 PNG)
- [x] 둘레 측정 (점 N개, 폴리라인)
- [x] 면적 측정 (폴리곤, Shoelace 공식)
- [x] 각도 측정 (3점 → cos 역산)

### W15 — AR 측정선 3D 공간 고정
- [ ] 앵커 영속화 (ARWorldMap / Cloud Anchors 검토)
- [ ] 측정 다시 보기 (이력 → AR 복원)
- [ ] 앵커 손실 시 폴백

### W16 — 3차 벤치마크 & 최적화
- [ ] 통합 벤치마크 (모든 모드 × 20개 대상)
- [ ] 앱 시작 시간·메모리·배터리 프로파일링
- [ ] 모델 다운로드 방식 검토 (앱 크기 감축)
- [ ] Phase 3 내부 빌드

---

## 검토 대기 항목
- [x] 시드 컬러 — Teal #00897B 확정 (2026-05-26)
- [x] 번들 ID·조직명·앱 이름 확정 — `com.lionplusmaster.length` / `Length` (2026-05-26)
- [ ] Phase 4 (자동 벤치마크, 다국어, 사용자 보정) 진입 시점
- [x] opencv_dart 도입 (2026-05-27, 1.4.5)
- [ ] Depth Anything V2 모델 변환·번들 (인프라 완비, 절차 docs/models/depth_anything_v2.md)

---

## 추가 UX 작업 (checklist 원안 외, 운영 단계 보강)
- [x] 카메라 권한 영구 거부 다이얼로그 (`permission_handler`)
- [x] 사용자 설정 영속화 (`shared_preferences`) — 선호 단위·캘리브레이션 높이/FOV·QR 크기
- [x] 측정 진행 중 뒤로가기 보호 (`PopScope` + 확인 다이얼로그)
- [x] 모드 선택 IA — 섹션 헤더/leading 아이콘/배지/추천 카드 강조
- [x] 이력 화면 — Kind 필터 + 날짜 그룹 + 캡처 썸네일
