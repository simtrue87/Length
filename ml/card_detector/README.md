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

## Phase A 작업 순서 (v2: 합성+실사 우선, MIDV-500은 옵션)

1. **카드 텍스처 수집** — `synth/card_textures/`에 카드 디자인 PNG 20~30장 (정면, 비율 1.586:1 권장).
   - 예시 소스: 본인 카드 정면 촬영(번호 마스킹) + 무료 이미지(예: openverse, pixabay에서 "credit card front")
2. **배경 수집** — `synth/backgrounds/`에 배경 100~200장 (책상·바닥·천·종이·소파 등).
3. **합성 데이터 생성** — `python synth/generate.py --out data/raw/synth --count 3000`
4. **실사 촬영** — Galaxy A90 5G로 100~200장. 다양한 조건(폰+카드 인접, 반사, 저조도, 기울임).
   `data/raw/real/images/` 에 배치.
5. **Roboflow 프로젝트 준비** — 웹에서 새 프로젝트 생성, **타입: Instance Segmentation**, 클래스명 `credit_card` (id=0).
6. **API 설정** — `.env.example` → `.env`로 복사, API 키·워크스페이스·프로젝트 슬러그 입력.
7. **합성 업로드 (라벨 포함, 자동)**:
   ```
   .venv/Scripts/python.exe upload_to_roboflow.py --src data/raw/synth --batch synth_v1
   ```
8. **실사 업로드 (라벨 없음, UI에서 수동 라벨링)**:
   ```
   .venv/Scripts/python.exe upload_to_roboflow.py --src data/raw/real --batch real_v1 --no-labels
   ```
9. **Roboflow UI에서 실사 라벨링** — 4점 폴리곤 그리기. 합성은 라벨 자동 import됨.
10. **버전 생성 + Export** — train 70% / val 20% / test 10% 분할, YOLO seg 포맷으로 zip download.
11. **`data/` 디렉터리로 zip 압축 해제** — Colab 업로드 준비 완료.
12. (선택) **MIDV-500 추가** — Phase E에서 정확도 부족 시 `data/sources/midv500.md` 참조

## Phase B 학습

`../../docs/models/credit_card_yolo.md` 의 Phase B 명령 참조.

## 사전 결정
- 라벨링 도구: **Roboflow** (2026-05-28 결정)
- ML 환경: 미정 (Colab Pro vs 로컬 GPU)
- 모델 배포: 미정 (Phase E 후)
