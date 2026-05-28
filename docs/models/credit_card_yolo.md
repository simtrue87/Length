<!-- 신용카드 YOLO11n-seg 단일 클래스 모델 학습·변환·통합 절차 -->

# 신용카드 영역 검출 YOLO11n-seg 모델

> Length 앱에서 카드+측정 대상이 함께 있는 임의 사진의 카드 4점을 추출하기 위한 자체 모델. 결정 31(2026-05-28) 참조.

## 목표 지표
- 자동 4점 검출 성공률 **≥ 85%** (벤치마크 시나리오)
- corner pixel error **≤ 10px** (원본 이미지 기준)
- 추론 시간 **≤ 150ms** (Galaxy A90 5G, INT8)
- 모델 크기 **≤ 8MB**

## 디렉터리 규칙
- 학습 코드·노트북: `ml/card_detector/` (앱 코드와 분리)
- 합성 데이터 스크립트: `ml/card_detector/synth/`
- 최종 모델: `assets/models/card_yolo11n_seg.tflite`
- 벤치마크 시트: `docs/benchmarks/card_detection_v2.md`

---

## Phase A — 데이터셋 (예상 1~2일)

### A1. 공개 데이터셋 다운로드
- **MIDV-500 / MIDV-2019 / MIDV-2020**: 신분증·카드 영상. 비디오 프레임 단위, 4점 라벨 포함
  - https://github.com/fcakyon/midv500
  - 약 50개 카드/신분증 클래스 × 다양한 각도·배경
- 카드(`credit_card`)에 해당하는 서브셋만 추출

### A2. 합성 데이터 생성 (3000~5000장)
- 카드 텍스처: 대표 카드 디자인 20~30종 (앞·뒷면, 단색/그라데이션/패턴)
- 배경 이미지: 책상·바닥·천·종이 등 100~200장
- 변형: 원근(±20° 회전), 조명(밝기 ±30%, 색온도), 그림자, 모션 블러, 노이즈
- 라이브러리: `Albumentations` + `OpenCV` (Python)
- 자동 라벨: 4점 좌표는 변환 행렬에서 직접 계산

### A3. 실사 데이터 보강 (100~200장)
- A90 5G로 직접 촬영: 폰+카드, 반사, 저조도, 손그림자, 다양한 책상 배경
- 라벨링: Roboflow(SaaS) 또는 CVAT(로컬). 4점 폴리곤
- 분할: train 70%, val 20%, test 10%

### A4. 데이터셋 포맷
- YOLO seg 포맷: 각 이미지에 `.txt` 라벨
  ```
  0 x1 y1 x2 y2 x3 y3 x4 y4
  ```
- 좌표는 0~1 정규화

---

## Phase B — 학습 (예상 0.5~1일)

### B1. 환경
- Python 3.11
- 패키지: `ultralytics>=8.3`, `albumentations`, `opencv-python`
- GPU: Colab Pro T4 또는 로컬

### B2. 학습 명령
```bash
yolo segment train \
  data=card.yaml \
  model=yolo11n-seg.pt \
  imgsz=640 \
  epochs=100 \
  batch=16 \
  hsv_h=0.015 hsv_s=0.7 hsv_v=0.4 \
  degrees=0.0 translate=0.1 scale=0.5 \
  perspective=0.0005 fliplr=0.5 \
  mosaic=1.0 mixup=0.1 \
  patience=30
```

### B3. 평가
- `yolo segment val` → mAP50/95, mask IoU
- 자체 메트릭: corner pixel error (라벨 4점 ↔ 예측 마스크 minAreaRect 4점)

---

## Phase C — 변환·양자화 (예상 0.5일)

### C1. ONNX
```bash
yolo export model=runs/segment/train/weights/best.pt format=onnx imgsz=640
```

### C2. TFLite INT8
- `onnx-tf` 또는 `onnxruntime`로 ONNX → TF SavedModel
- TF SavedModel → TFLite Converter
- INT8 PTQ: representative dataset 100장 (val에서 샘플)
- 검증: TFLite vs ONNX 정확도 차 ≤ 2%p

---

## Phase D — Flutter 통합 (예상 1~2일)

### D1. 모델 자산
- `assets/models/card_yolo11n_seg.tflite` (≤8MB 목표)
- `pubspec.yaml` assets에 추가

### D2. 새 Dart 클래스
- `lib/features/photo_measure/reference_object/yolo_card_detector.dart`
- 의존: `tflite_flutter`, `image` (전처리), `opencv_dart` (후처리 minAreaRect)
- API:
  ```dart
  class YoloCardDetector {
    Future<void> load();
    Future<CardDetection?> detect(String imagePath);
  }
  ```

### D3. 전·후처리
- 전처리: `image.decodeImage(...)` → resize 640×640 (letterbox 유지) → normalize 0..1 → CHW float32
- 추론: `Interpreter.run` (GPU/NNAPI delegate 시도)
- 후처리:
  1. 출력 mask (640×640) → 임계 0.5
  2. `cv.findContours(mask, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE)` → 최대 면적 컨투어
  3. `cv.minAreaRect` → 4점
  4. 종횡비 검증 (`PlanarRectifier`가 가로/세로 자동 매핑하므로 prior로 쓰기만)
- 좌표 복원: 640 → 원본 (letterbox padding 역산)

### D4. 폴백 체인
- `PhotoReferenceScreen._pick` 안에서:
  1. `YoloCardDetector.detect()` 시도. 성공 + confidence 충분하면 사용
  2. 실패 → 기존 `CardDetector` (CV) 시도
  3. 그것도 실패 → ROI 모드 수동 보정 (기존 fallback)

---

## Phase E — 검증 (예상 0.5~1일)

### E1. 벤치마크 시나리오 (10개 이상)
- 단독 카드 (정면, 위에서)
- 카드+폰 인접 (오늘 실패 케이스 재현)
- 카드+폰 떨어짐 (3cm+ 간격)
- 반사·홀로그램 카드
- 저조도
- 기울임 (±20°)
- 모션 블러
- 복잡 배경 (책·서류 위)
- 다중 카드 (2장 이상)
- 빈 책상 (false positive 확인)

### E2. 시트: `docs/benchmarks/card_detection_v2.md`
- 시나리오 × {자동 4점 hit/miss, corner err, 추론 ms}

### E3. 게이트
- 자동 4점 hit ≥ 85%
- 평균 corner err ≤ 10px (원본 기준)
- A90 5G 추론 ≤ 150ms

---

## Phase F — 롤아웃

### F1. 자산 배포 전략
- 옵션 1: APK 번들 (≤8MB면 부담 작음)
- 옵션 2: 첫 실행 다운로드 (네트워크 의존, 앱 용량 절감)
- 결정: Phase E 후 모델 크기 보고 정함

### F2. 변경 파일
- `lib/features/photo_measure/reference_object/yolo_card_detector.dart` (신규)
- `lib/features/photo_measure/presentation/photo_reference_screen.dart` (폴백 체인 통합)
- `pubspec.yaml` (자산 등록, image 패키지 추가)
- `assets/models/card_yolo11n_seg.tflite` (모델)

### F3. 회귀 방지
- 기존 `CardDetector` (CV) 및 ROI 모드 수동 보정은 폴백으로 유지
- 모델 로딩 실패 시 자동 폴백 (디바이스 호환성 확보)

---

## 사전 결정 사항
1. **ML 환경** — Colab Pro (결정 32, 2026-05-28)
2. **라벨링 도구** — Roboflow (2026-05-28 결정)
3. **모델 배포** — 미정. Phase E 후 결정 (번들 vs 첫 실행 다운로드)

## Colab 학습 흐름
1. 로컬에서 데이터 준비 완료 후 `ml/card_detector/data/` 압축 → Google Drive 업로드
2. Colab 노트북에서 Drive 마운트, 압축 해제
3. `ultralytics` 설치 후 Phase B 명령 실행
4. 학습 산출물(best.pt + 메트릭) Drive에 저장
5. ONNX/TFLite 변환은 동일 노트북에서 진행 가능
6. 최종 `.tflite` 다운로드 → `assets/models/` 배치

---

*Last updated: 2026-05-28*
