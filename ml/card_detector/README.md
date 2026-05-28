<!-- 신용카드 YOLO11n-seg 학습 워크스페이스 -->

# Length — Credit Card YOLO11n-seg

> 카드+측정 대상이 함께 있는 사진에서 카드 4점을 추출하기 위한 단일 클래스 세그멘테이션 모델 학습 워크스페이스. 자세한 절차는 `../../docs/models/credit_card_yolo.md` 참조.

## 디렉터리 구조

```
ml/card_detector/
  README.md                  ← 이 파일
  requirements.txt           ← Python 의존성
  synth/
    generate.py              ← 합성 데이터 생성기
    card_textures/           ← 카드 디자인 PNG (앞·뒷면) — 수동 수집
    backgrounds/             ← 배경 이미지 — 수동 수집
  data/
    raw/                     ← 원본(공개 데이터셋, 합성, 실사) 분류 전
    train/  val/  test/      ← YOLO 포맷 split
    card.yaml                ← Ultralytics 데이터셋 정의
  runs/                      ← 학습 산출물 (Ultralytics 기본)
```

## 환경 셋업

```bash
cd ml/card_detector
python -m venv .venv
.venv/Scripts/activate    # Windows
# source .venv/bin/activate  # Mac/Linux
pip install -r requirements.txt
```

## Phase A 작업 순서 (v4: Roboflow 통합 워크플로우)

### 사전 셋업
- Roboflow 워크스페이스에 **Instance Segmentation** 프로젝트 생성 완료
- `.env` 파일에 자격증명 설정 (`.env.example` 참고)
- venv 의존성 설치 완료

### 데이터 수집·업로드
1. **카드 텍스처 수집** — `synth/card_textures/`에 카드 디자인 PNG 20~30장 (정면, 비율 1.586:1 권장).
   - 본인 카드 정면 촬영(번호 마스킹) + 무료 이미지
2. **배경 수집** — `synth/backgrounds/`에 배경 100~200장 (책상·바닥·천·종이·소파 등).
3. **합성 데이터 생성** (라벨 자동 포함):
   ```
   .venv/Scripts/python.exe synth/generate.py --out data/raw/synth --count 3000
   ```
4. **합성 업로드** (라벨 자동 import):
   ```
   .venv/Scripts/python.exe upload_to_roboflow.py --src data/raw/synth --batch synth_v1
   ```
5. **실사 촬영** — Galaxy A90 5G로 100~200장. 다양한 조건(폰+카드 인접, 반사, 저조도, 기울임).
   `data/raw/real/images/` 에 배치.
6. **실사 업로드** (라벨 없이):
   ```
   .venv/Scripts/python.exe upload_to_roboflow.py --src data/raw/real --batch real_v1 --no-labels
   ```

### Roboflow UI에서 라벨링·분할·export
7. **실사 라벨링** — Roboflow Annotate 탭에서 각 이미지의 카드 4 모서리를 폴리곤으로 클릭.
   - 클래스명: `credit_card`
   - Smart Polygon(SAM 보조) 옵션 활성화 권장 — 카드 위 클릭 한 번으로 자동 폴리곤
8. **버전 생성** — Generate New Version
   - Preprocessing: Resize 640×640 (Stretch to)
   - Augmentations: 기본값 또는 비활성 (Colab 학습에서 mosaic·mixup·perspective 추가)
   - Train/Val/Test: 70/20/10
9. **Export** — Format: **YOLOv8 (Instance Segmentation)** 또는 **YOLO11** → "show download code" → zip 다운로드
10. **압축 해제 + Drive 업로드** — `data/dataset/` 에 두고, zip 으로 Google Drive `Length/card_yolo/dataset.zip` 업로드
11. **Colab 학습** — `train_colab.md` 절차로 Phase B 진입

### 대안: AnyLabeling (로컬 라벨링)
Roboflow 무료 한도(1000장 source)를 넘으면 로컬 SAM 라벨링도 가능. 절차:
1. AnyLabeling 설치 (https://github.com/vietanhdev/anylabeling/releases) + SAM 모델 다운로드
2. `data/raw/real/images/` 에서 카드 위 클릭 → SAM 자동 마스크
3. `convert_labelme_to_yolo.py --src data/raw/real` 로 JSON → YOLO seg 변환
4. `assemble_dataset.py --sources data/raw/synth data/raw/real --out data/dataset` 로 병합

### 선택: MIDV-500
정확도 부족 시 추가. `data/sources/midv500.md` 참조.

## Phase B 학습

`../../docs/models/credit_card_yolo.md` 의 Phase B 명령 참조.

## 사전 결정
- 라벨링 도구: **Roboflow** (2026-05-28 결정)
- ML 환경: 미정 (Colab Pro vs 로컬 GPU)
- 모델 배포: 미정 (Phase E 후)
