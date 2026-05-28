# 신용카드 영역 검출용 합성 데이터 생성기 — 카드 텍스처를 배경 위에 원근 변형으로 합성
"""
사용법:
  python synth/generate.py --out data/raw/synth --count 3000

출력:
  data/raw/synth/images/{idx}.jpg
  data/raw/synth/labels/{idx}.txt  (YOLO seg 포맷: 0 x1 y1 x2 y2 x3 y3 x4 y4, 정규화)

카드 표준 종횡비: 85.6 / 53.98 ≈ 1.586

사전 준비:
  synth/card_textures/*.png      카드 디자인 (앞·뒷면). 정면 뷰 권장 (가로:세로 = 1.586:1)
  synth/backgrounds/*.{jpg,png}  배경 이미지 (책상·바닥·천 등)

의존성:
  opencv-python, numpy, Pillow, albumentations, tqdm
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

import cv2
import numpy as np
from tqdm import tqdm

CARD_ASPECT = 85.6 / 53.98  # ≈ 1.586


def _list_images(d: Path) -> list[Path]:
    exts = {".jpg", ".jpeg", ".png", ".webp"}
    return [p for p in d.iterdir() if p.suffix.lower() in exts]


def _random_perspective_pts(card_w: int, card_h: int, max_warp: float) -> np.ndarray:
    """카드 정면 4점에 무작위 변위를 가해 원근 변환 후 dst 4점 반환."""
    dx = card_w * max_warp
    dy = card_h * max_warp
    pts = np.float32([
        [random.uniform(0, dx),         random.uniform(0, dy)],
        [card_w - random.uniform(0, dx), random.uniform(0, dy)],
        [card_w - random.uniform(0, dx), card_h - random.uniform(0, dy)],
        [random.uniform(0, dx),         card_h - random.uniform(0, dy)],
    ])
    return pts


def _compose(
    card_img: np.ndarray,
    bg_img: np.ndarray,
    *,
    card_scale_range: tuple[float, float] = (0.15, 0.45),
    rotation_range: tuple[float, float] = (-20.0, 20.0),
    perspective_warp: float = 0.08,
    brightness_jitter: float = 0.25,
) -> tuple[np.ndarray, np.ndarray]:
    """카드 한 장 + 배경 한 장으로 합성 이미지와 4점 좌표(원본 픽셀)를 만든다."""
    bg_h, bg_w = bg_img.shape[:2]
    card_h0, card_w0 = card_img.shape[:2]

    # 카드 크기 정규화 (가로 기준으로 배경 폭의 일정 비율).
    target_w = int(bg_w * random.uniform(*card_scale_range))
    target_h = int(target_w / (card_w0 / card_h0))
    card_resized = cv2.resize(card_img, (target_w, target_h), interpolation=cv2.INTER_AREA)

    # 원근 변환: 카드 사각형 → 변형된 사각형.
    src = np.float32([
        [0, 0], [target_w, 0], [target_w, target_h], [0, target_h],
    ])
    dst_local = _random_perspective_pts(target_w, target_h, perspective_warp)
    M_persp = cv2.getPerspectiveTransform(src, dst_local)
    warped = cv2.warpPerspective(
        card_resized, M_persp, (target_w, target_h), borderMode=cv2.BORDER_CONSTANT
    )

    # 회전.
    angle = random.uniform(*rotation_range)
    rot_M = cv2.getRotationMatrix2D((target_w / 2, target_h / 2), angle, 1.0)
    cos = abs(rot_M[0, 0]); sin = abs(rot_M[0, 1])
    new_w = int(target_h * sin + target_w * cos)
    new_h = int(target_h * cos + target_w * sin)
    rot_M[0, 2] += (new_w / 2) - target_w / 2
    rot_M[1, 2] += (new_h / 2) - target_h / 2
    rotated = cv2.warpAffine(warped, rot_M, (new_w, new_h), borderMode=cv2.BORDER_CONSTANT)

    # 회전 후 dst 4점 위치 갱신.
    dst_h = cv2.transform(dst_local.reshape(-1, 1, 2), rot_M).reshape(-1, 2)

    # 카드 배치 위치 (배경 안에서).
    max_x = bg_w - new_w
    max_y = bg_h - new_h
    if max_x <= 0 or max_y <= 0:
        # 배경이 카드보다 작으면 스킵.
        raise ValueError("background too small for card")
    off_x = random.randint(0, max_x)
    off_y = random.randint(0, max_y)

    # 알파 합성: 회전 결과 중 비-zero 픽셀만 덮어쓰기.
    canvas = bg_img.copy()
    mask = (rotated.sum(axis=2) > 0).astype(np.uint8) * 255
    roi = canvas[off_y:off_y + new_h, off_x:off_x + new_w]
    inv = cv2.bitwise_not(mask)
    bg_part = cv2.bitwise_and(roi, roi, mask=inv)
    fg_part = cv2.bitwise_and(rotated, rotated, mask=mask)
    canvas[off_y:off_y + new_h, off_x:off_x + new_w] = cv2.add(bg_part, fg_part)

    # 밝기 jitter.
    bright = 1.0 + random.uniform(-brightness_jitter, brightness_jitter)
    canvas = np.clip(canvas.astype(np.float32) * bright, 0, 255).astype(np.uint8)

    # 4점 (원본 이미지 픽셀 좌표).
    corners = dst_h + np.array([off_x, off_y])
    return canvas, corners.astype(np.float32)


def _write_yolo_seg_label(path: Path, w: int, h: int, corners: np.ndarray) -> None:
    """YOLO seg 포맷: '<class> x1 y1 x2 y2 x3 y3 x4 y4' (모든 좌표 0~1 정규화)."""
    cls = 0  # credit_card
    flat = []
    for (x, y) in corners:
        flat.append(f"{x / w:.6f}")
        flat.append(f"{y / h:.6f}")
    path.write_text(f"{cls} " + " ".join(flat) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True, help="출력 디렉터리")
    ap.add_argument("--count", type=int, default=3000, help="생성 이미지 수")
    ap.add_argument("--textures", type=Path, default=Path(__file__).parent / "card_textures")
    ap.add_argument("--backgrounds", type=Path, default=Path(__file__).parent / "backgrounds")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    if not args.textures.exists():
        raise SystemExit(f"카드 텍스처 디렉터리 없음: {args.textures}")
    if not args.backgrounds.exists():
        raise SystemExit(f"배경 디렉터리 없음: {args.backgrounds}")

    textures = _list_images(args.textures)
    backgrounds = _list_images(args.backgrounds)
    if not textures:
        raise SystemExit("카드 텍스처 이미지가 없음")
    if not backgrounds:
        raise SystemExit("배경 이미지가 없음")

    img_dir = args.out / "images"
    lbl_dir = args.out / "labels"
    img_dir.mkdir(parents=True, exist_ok=True)
    lbl_dir.mkdir(parents=True, exist_ok=True)

    made = 0
    pbar = tqdm(total=args.count, desc="synth")
    while made < args.count:
        tx = cv2.imread(str(random.choice(textures)))
        bg = cv2.imread(str(random.choice(backgrounds)))
        if tx is None or bg is None:
            continue
        # 배경 크기 정규화: 짧은 변 800px 이상.
        h, w = bg.shape[:2]
        short = min(h, w)
        if short < 800:
            scale = 800 / short
            bg = cv2.resize(bg, (int(w * scale), int(h * scale)))
        try:
            img, corners = _compose(tx, bg)
        except ValueError:
            continue
        idx = made
        cv2.imwrite(str(img_dir / f"{idx:05d}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 90])
        _write_yolo_seg_label(lbl_dir / f"{idx:05d}.txt", img.shape[1], img.shape[0], corners)
        made += 1
        pbar.update(1)
    pbar.close()
    print(f"완료: {made}장 → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
