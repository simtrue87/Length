<!-- 신용카드 YOLO11n-seg 단일 클래스 모델 학습·변환·통합 절차 -->

# Length 다중 클래스 YOLO11n-seg 모델

> Length 앱에서 한 번의 추론으로 카드(scale)와 측정 대상(물고기 등)을 동시에 검출. 결정 31(2026-05-28) + 결정 35(2026-05-28, 다중 클래스 확장) 참조.

## 클래스
- `0`: `credit_card` — 4점 추출 → mm/픽셀 스케일
- `1`: `fish` — 마스크 외곽 추출 → 머리~꼬리 직선 길이 계산

## 목표 지표
- 자동 4점 검출 성공률 **≥ 85%** (벤치마크 시나리오)
- corner pixel error **≤ 10px** (원본 이미지 기준)
- 추론 시간 **≤ 150ms** (Galaxy A90 5G, INT8)
- 모델 크기 **≤ 8MB**

## 디렉터리 규칙
- 학습 코드·노트북: `ml/card_detector/` (앱 코드와 분리. 폴더 이름은 유지하되 다중 클래스 의미로 사용)
- 합성 데이터 스크립트: `ml/card_detector/synth/` (카드 전용. 물고기는 합성 불가, 실사만)
- 최종 모델: `assets/models/length_yolo11n_seg.tflite`
- 벤치마크 시트: `docs/benchmarks/length_detection_v2.md`

---

## Phase A — 데이터셋 (예상 1~2일)

### A1. 공개 데이터셋 다운로드
- **MIDV-500 / MIDV-2019 / MIDV-2020**: 신분증·카드 영상. 비디오 프레임 단위, 4점 라벨 포함
  - https://github.com/fcakyon/midv500
  - 약 50개 카드/신분증 클래스 × 다양한 각도·배경
- 카드(`credit_card`)에 해당하는 서브셋만 추출

### A2. 합성 데이터 생성 (3000~5000장, 카드 전용)
- 카드 텍스처: 대표 카드 디자인 20~30종 (앞·뒷면, 단색/그라데이션/패턴)
- 배경 이미지: 책상·바닥·천·종이 등 100~200장
- 변형: 원근(±20° 회전), 조명(밝기 ±30%, 색온도), 그림자, 모션 블러, 노이즈
- 라이브러리: `OpenCV` (Python) — Albumentations는 Python 3.14 미지원으로 미사용
- 자동 라벨: 4점 좌표는 변환 행렬에서 직접 계산. 클래스 `0` (credit_card).
- 물고기는 합성 부적합(현실감 부족) — 실사만 사용.

### A3. 실사 데이터 보강 (200~400장)
**시나리오 다양화**
- 카드 단독 (100장+): 폰+카드, 반사, 저조도, 손그림자, 책상·바닥·천 배경
- 카드 + 물고기 동시 (100장+): 다양한 어종, 다양한 자세(옆면 풍선 자세 권장). 카드를 물고기 옆 같은 평면에 둠
- 물고기 단독 (50장+, 선택): 카드 없는 일반 어획 사진. 카드 클래스 없이 fish만 라벨

**라벨링**
- Roboflow Annotate (Smart Polygon 권장) — 카드는 4점 폴리곤, 물고기는 외곽 자유 폴리곤
- 클래스: `credit_card`, `fish`
- 분할: train 70%, val 20%, test 10%

### A4. 데이터셋 포맷
- YOLO seg 포맷: 각 이미지에 `.txt` 라벨 (한 줄당 한 객체)
  ```
  0 x1 y1 x2 y2 x3 y3 x4 y4        ← credit_card (4점)
  1 fx1 fy1 fx2 fy2 ... fxN fyN    ← fish (N점, N≥3)
  ```
- 좌표는 0~1 정규화. 한 이미지에 카드+물고기 동시 라벨 가능 (다중 줄).

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
- `lib/features/photo_measure/ml/yolo_length_detector.dart`
- 의존: `tflite_flutter`, `image` (전처리), `opencv_dart` (후처리 minAreaRect/외곽 추출)
- API:
  ```dart
  class YoloLengthDetector {
    Future<void> load();
    Future<LengthDetection?> detect(String imagePath);
  }
  class LengthDetection {
    final CardDetection? card;        // class 0: 4점
    final FishDetection? fish;        // class 1: 외곽 폴리곤
  }
  ```

### D3. 전·후처리
- 전처리: `image.decodeImage(...)` → letterbox resize 640×640 → normalize 0..1 → CHW float32
- 추론: `Interpreter.run` (GPU/NNAPI delegate 시도)
- 후처리:
  1. 클래스별 mask 분리 (class 0=card, class 1=fish)
  2. 각 mask 임계 0.5 → `cv.findContours(RETR_EXTERNAL)`
  3. **카드(class 0)**: 최대 컨투어 → `cv.minAreaRect` → 4점 → 종횡비 1.586 검증
  4. **물고기(class 1)**: 최대 컨투어 → 외곽 폴리곤 유지. 머리·꼬리 직선은 `cv.minAreaRect` 장변 또는 PCA 주축
- 좌표 복원: 640 → 원본 (letterbox padding 역산)

### D4. 폴백 체인
- `PhotoReferenceScreen._pick`:
  1. `YoloLengthDetector.detect()` → card 결과 사용
  2. 실패 → 기존 `CardDetector` (CV) 시도
  3. 그것도 실패 → ROI 모드 수동 보정
- `PhotoFishScreen._pick` (자동 fish 감지 새 흐름):
  1. `YoloLengthDetector.detect()` → card + fish 결과 동시 사용
  2. fish 못 잡으면 → 기존 수동 fish 박스 모드
  3. card 못 잡으면 → 기존 카드 ROI 모드

---

## Phase E — 검증 (예상 0.5~1일)

### E1. 벤치마크 시나리오 (15개 이상)
**카드 단독**
- 단독 카드 (정면, 위에서)
- 카드+폰 인접 (실패 케이스 재현)
- 카드+폰 떨어짐 (3cm+ 간격)
- 반사·홀로그램 카드
- 저조도, 기울임 (±20°), 모션 블러
- 복잡 배경 (책·서류 위)
- 빈 책상 (false positive 확인)

**물고기**
- 카드+물고기 (다양한 어종 3종 이상)
- 물고기 단독 (카드 미포함, fish만)
- 물고기 입수 직후(젖은 표면 반사)
- 물고기 겹침(2마리 이상)
- 물고기 부분 가림(손)

### E2. 시트: `docs/benchmarks/card_detection_v2.md`
- 시나리오 × {자동 4점 hit/miss, corner err, 추론 ms}

### E3. 게이트
- **카드** 자동 4점 hit ≥ 85%, 평균 corner err ≤ 10px (원본 기준)
- **물고기** 마스크 IoU ≥ 0.85 (라벨 대비), 머리~꼬리 길이 오차 ≤ 5%
- A90 5G 추론 ≤ 200ms (다중 클래스라 단일보다 여유)

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
