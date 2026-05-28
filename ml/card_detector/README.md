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

## Phase A 작업 순서 (v3: AnyLabeling 로컬 라벨링)

1. **카드 텍스처 수집** — `synth/card_textures/`에 카드 디자인 PNG 20~30장 (정면, 비율 1.586:1 권장).
   - 예시 소스: 본인 카드 정면 촬영(번호 마스킹) + 무료 이미지
2. **배경 수집** — `synth/backgrounds/`에 배경 100~200장 (책상·바닥·천·종이·소파 등).
3. **합성 데이터 생성**:
   ```
   .venv/Scripts/python.exe synth/generate.py --out data/raw/synth --count 3000
   ```
4. **실사 촬영** — Galaxy A90 5G로 100~200장. 다양한 조건(폰+카드 인접, 반사, 저조도, 기울임).
   `data/raw/real/images/` 에 배치.
5. **AnyLabeling 설치** — https://github.com/vietanhdev/anylabeling/releases 에서 Windows 빌드 다운로드.
   - 첫 실행 시 `Brain` 메뉴 → `Segment Anything (SAM)` 모델 다운로드(자동, ~95MB MobileSAM).
6. **실사 라벨링** (SAM 자동):
   - AnyLabeling에서 `data/raw/real/images/` 폴더 열기
   - 각 이미지에서 카드 위 한 번 클릭 → SAM이 카드 마스크 생성 → 폴리곤 자동 변환
   - 라벨명 `credit_card` 입력
   - 저장하면 같은 폴더에 `{이미지}.json` 출력 (LabelMe 포맷)
7. **LabelMe JSON → YOLO seg 변환**:
   ```
   .venv/Scripts/python.exe convert_labelme_to_yolo.py --src data/raw/real
   ```
   SAM이 만든 N점 폴리곤이 minAreaRect로 자동 4점 축약됨.
8. **데이터셋 병합 + 분할**:
   ```
   .venv/Scripts/python.exe assemble_dataset.py \
     --sources data/raw/synth data/raw/real \
     --out data/dataset
   ```
   train 70% / val 20% / test 10% 자동 분할, `card.yaml` 생성.
9. **압축 + Drive 업로드**:
   - `data/dataset/` 폴더 zip
   - Google Drive `Length/card_yolo/dataset.zip` 업로드
10. **Colab 학습** — `train_colab.md` 절차로 Phase B 진입.
11. (선택) **MIDV-500 추가** — Phase E에서 정확도 부족 시 `data/sources/midv500.md` 참조

## 대안: Roboflow (구버전 워크플로우)
무료 한도 내(1000장/3프로젝트)에서 쓰고 싶다면 `upload_to_roboflow.py` + `.env` 사용. 단, AnyLabeling이 SAM 통합으로 더 빠르므로 권장하지 않음.

## Phase B 학습

`../../docs/models/credit_card_yolo.md` 의 Phase B 명령 참조.

## 사전 결정
- 라벨링 도구: **Roboflow** (2026-05-28 결정)
- ML 환경: 미정 (Colab Pro vs 로컬 GPU)
- 모델 배포: 미정 (Phase E 후)
