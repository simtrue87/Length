# AnyLabeling(LabelMe JSON) → YOLO seg 포맷 변환. SAM이 생성한 다각형을 minAreaRect로 4점 축약.
"""
사용법:
  python convert_labelme_to_yolo.py --src data/raw/real --class-name credit_card

기대 입력:
  data/raw/real/
    images/000.jpg
    images/000.json   ← AnyLabeling 출력 (LabelMe 포맷)
    images/001.jpg
    images/001.json
    ...

출력:
  data/raw/real/
    labels/000.txt    ← YOLO seg: 0 x1 y1 x2 y2 x3 y3 x4 y4 (정규화)
    labels/001.txt
    ...

AnyLabeling JSON 예:
{
  "shapes": [
    {"label": "credit_card",
     "points": [[x,y], ...],   ← SAM 출력은 N점, 수동 폴리곤은 4점일 수도 있음
     "shape_type": "polygon"}
  ],
  "imageWidth": 2250, "imageHeight": 4000
}
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np
from tqdm import tqdm


def _reduce_to_4_corners(points: list[list[float]]) -> np.ndarray:
    """N점 폴리곤을 4점(TL,TR,BR,BL 시계방향)으로 축약."""
    pts = np.array(points, dtype=np.float32)
    if len(pts) < 3:
        raise ValueError(f"점이 {len(pts)}개로 너무 적음")
    if len(pts) == 4:
        ordered = _order_clockwise(pts)
    else:
        # minAreaRect → 4 corners
        rect = cv2.minAreaRect(pts)
        box = cv2.boxPoints(rect)
        ordered = _order_clockwise(box)
    return ordered


def _order_clockwise(pts: np.ndarray) -> np.ndarray:
    """4점을 (TL, TR, BR, BL) 순서로 정렬."""
    cx, cy = pts.mean(axis=0)
    by_angle = sorted(pts, key=lambda p: math.atan2(p[1] - cy, p[0] - cx))
    # atan2 오름차순은 반시계. 시계로 뒤집고 TL(min x+y) 시작.
    cw = list(reversed(by_angle))
    tl_idx = min(range(4), key=lambda i: cw[i][0] + cw[i][1])
    return np.array([cw[(tl_idx + k) % 4] for k in range(4)], dtype=np.float32)


def _convert_one(json_path: Path, class_name: str) -> str | None:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    w = data.get("imageWidth")
    h = data.get("imageHeight")
    if not w or not h:
        return None
    shapes = [s for s in data.get("shapes", []) if s.get("label") == class_name]
    if not shapes:
        return None
    # 첫 번째 카드만 (단일 객체 가정).
    s = shapes[0]
    if s.get("shape_type") not in ("polygon", "rectangle"):
        return None
    pts = s["points"]
    if s.get("shape_type") == "rectangle":
        # rectangle: [[x1,y1],[x2,y2]] → 4점 변환
        (x1, y1), (x2, y2) = pts
        pts = [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
    corners = _reduce_to_4_corners(pts)
    flat = " ".join(f"{c[0] / w:.6f} {c[1] / h:.6f}" for c in corners)
    return f"0 {flat}\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, required=True, help="data/raw/{name} 경로 (images/*.json 필요)")
    ap.add_argument("--class-name", default="credit_card")
    args = ap.parse_args()

    img_dir = args.src / "images"
    lbl_dir = args.src / "labels"
    lbl_dir.mkdir(parents=True, exist_ok=True)

    json_files = sorted(img_dir.glob("*.json"))
    if not json_files:
        raise SystemExit(f"JSON 파일 없음: {img_dir}/*.json")

    ok = 0
    skipped = 0
    for jp in tqdm(json_files, desc="convert"):
        line = _convert_one(jp, args.class_name)
        if line is None:
            skipped += 1
            continue
        (lbl_dir / (jp.stem + ".txt")).write_text(line, encoding="utf-8")
        ok += 1
    print(f"변환 완료: {ok}장, 스킵 {skipped}장 → {lbl_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
