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

## Phase A 작업 순서

1. **공개 데이터셋 다운로드** — MIDV-500/2019/2020 중 카드 서브셋
   - `midv500` Python 패키지 사용 (`requirements.txt`에 포함)
   - 노트 정리: `data/sources/midv500.md`
2. **카드 텍스처·배경 수집** — `synth/card_textures/`, `synth/backgrounds/`에 수동 배치
3. **합성 데이터 생성** — `python synth/generate.py --out data/raw/synth --count 3000`
4. **실사 촬영** — Galaxy A90 5G로 100~200장, `data/raw/real/` 배치
5. **Roboflow 업로드 + 4점 폴리곤 라벨링** — train/val/test 자동 분할 후 YOLO seg 포맷 export
6. **`data/` 디렉터리로 export 결과 압축 풀기**

## Phase B 학습

`../../docs/models/credit_card_yolo.md` 의 Phase B 명령 참조.

## 사전 결정
- 라벨링 도구: **Roboflow** (2026-05-28 결정)
- ML 환경: 미정 (Colab Pro vs 로컬 GPU)
- 모델 배포: 미정 (Phase E 후)
