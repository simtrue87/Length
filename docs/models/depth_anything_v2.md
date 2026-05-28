<!-- Depth Anything V2 Small TFLite 모델 준비 절차 -->

# Depth Anything V2 — 모델 변환·번들 절차

> 앱은 `assets/models/depth_anything_v2_small.tflite`가 있으면 자동으로 사용하고,
> 없으면 `StubDepthEstimator`로 폴백합니다. 모델 파일을 리포지터리에 커밋하지 않는 이유는 라이선스·용량 때문입니다.

## 1. 준비
- Python 3.10+, PyTorch 2.x, onnx, onnxruntime, ai_edge_torch (또는 tf2onnx + tensorflow)
- 가상환경 권장:
  ```bash
  python -m venv .venv
  .venv\Scripts\activate  # PowerShell
  pip install torch torchvision onnx onnxruntime ai-edge-torch
  ```

## 2. 모델 다운로드
`Depth-Anything-V2-Small` HuggingFace에서 PyTorch 체크포인트:
- https://huggingface.co/depth-anything/Depth-Anything-V2-Small
- `depth_anything_v2_vits.pth` (약 25MB)

## 3. PyTorch → TFLite 변환 스크립트 예시
`scripts/convert_depth_anything_v2.py`(직접 작성, 리포지터리 미포함):

```python
import torch
from depth_anything_v2.dpt import DepthAnythingV2
import ai_edge_torch

model = DepthAnythingV2(encoder='vits', features=64, out_channels=[48, 96, 192, 384])
model.load_state_dict(torch.load('depth_anything_v2_vits.pth', map_location='cpu'))
model.eval()

# 입력: 1x3x256x256 [0,1] normalized
sample = (torch.rand(1, 3, 256, 256),)

edge_model = ai_edge_torch.convert(model, sample)
edge_model.export('depth_anything_v2_small.tflite')
```

## 4. INT8 양자화 (선택, 모델 ~25MB → ~7MB)
`ai_edge_torch.quantize`로 동적 양자화 또는 representative dataset 기반 정적 양자화. 정확도/크기 트레이드오프 평가 후 결정.

## 5. 앱에 번들
1. `assets/models/` 디렉터리 생성:
   ```bash
   mkdir -p assets/models
   cp depth_anything_v2_small.tflite assets/models/
   ```
2. `pubspec.yaml`에 자산 등록:
   ```yaml
   flutter:
     assets:
       - assets/models/depth_anything_v2_small.tflite
   ```
3. `flutter pub get` → `flutter run`
4. 앱에서 AI 깊이 모드 진입 시 메시지가 "Depth Anything V2 모델 로드 완료"로 변경되면 성공.

## 6. 코드 측 변경 사항
- 입력 크기·전처리(평균·표준편차)가 다르면 `lib/features/photo_measure/ai_depth/infrastructure/tflite_depth_estimator.dart`의 `_inputSize`와 `_imageToFloat32` 수정.
- 출력 깊이가 미터/디스패리티 등 단위가 다르면 후처리 추가. 현재는 모델 raw 출력을 그대로 `DepthMap.depths`에 담음(`isMetric: false`).

## 7. 알려진 한계
- 상대 깊이만 출력 → 절대 mm 보정 별도 필요(평면 가정 또는 참조 객체 보정 결합).
- 모바일 추론: arm64-v8a 기준 256×256 입력에서 약 100~300ms (단말 사양 의존). UI 진행률 필요.
- 반사·투명 물체, 학습 분포 밖 객체에서 오차 큼.

## 8. 검토 트리거
모델 통합 후 W11 게이트:
- 평균 오차 ≤ **15%** 검증.
- 콜드 추론 시간 측정.
- 메모리·발열 모니터링 (특히 중급 Android).
