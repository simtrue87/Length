<!-- Colab Pro에서 YOLO11n-seg 카드 모델 학습·변환 절차 -->

# Colab Pro 학습 노트북 절차

Phase A(데이터셋 준비) 완료 후 Colab에서 이 절차로 학습·변환.

## 0. 사전
- Google Drive에 `Length/card_yolo/` 폴더 생성
- 로컬 `ml/card_detector/data/` (train/val/test + card.yaml) 압축 → Drive 업로드
  - 약 5000장 × 100~200KB ≈ 1GB. Drive 무료 15GB 한도 안에서 충분
- Colab Pro 런타임: T4 (또는 L4 가능 시)

## 1. 노트북 셀

```python
# 1. Drive 마운트
from google.colab import drive
drive.mount('/content/drive')

# 2. 작업 디렉터리
import os
os.makedirs('/content/card', exist_ok=True)
%cd /content/card

# 3. 데이터 압축 해제
!unzip -q "/content/drive/MyDrive/Length/card_yolo/dataset.zip" -d .
!ls

# 4. ultralytics 설치
!pip install -q ultralytics==8.3.*

# 5. 학습 (yolo11n-seg.pt 자동 다운로드)
!yolo segment train \
  data=card.yaml \
  model=yolo11n-seg.pt \
  imgsz=640 \
  epochs=100 \
  batch=16 \
  hsv_h=0.015 hsv_s=0.7 hsv_v=0.4 \
  translate=0.1 scale=0.5 \
  perspective=0.0005 fliplr=0.5 \
  mosaic=1.0 mixup=0.1 \
  patience=30 \
  project=runs name=card_v1

# 6. 평가
!yolo segment val model=runs/card_v1/weights/best.pt data=card.yaml imgsz=640

# 7. ONNX 변환
!yolo export model=runs/card_v1/weights/best.pt format=onnx imgsz=640 simplify=True

# 8. TFLite INT8 변환 (representative dataset 필요)
!pip install -q tensorflow onnx-tf onnx
# Phase C 절차: ONNX → TF SavedModel → TFLite INT8
# (스크립트는 Phase C 진입 시 보강)

# 9. 산출물 Drive로 백업
!cp runs/card_v1/weights/best.pt "/content/drive/MyDrive/Length/card_yolo/best.pt"
!cp runs/card_v1/weights/best.onnx "/content/drive/MyDrive/Length/card_yolo/best.onnx"
```

## 2. 시간 예상
- T4에서 5000장 × 100 epochs ≈ 1.5~2시간
- 컴퓨트 유닛 약 25~40 소비

## 3. 산출물
- `best.pt` — PyTorch 학습 가중치
- `best.onnx` — ONNX
- `best.tflite` — Phase C에서 변환

## 4. 정상 동작 지표
- mAP50 ≥ 0.95 (단일 클래스, 잘 라벨링된 데이터셋 기준)
- mask IoU ≥ 0.85
- corner pixel error 별도 측정 (Phase E 벤치마크)
