# 합성·실사 데이터 병합 → train/val/test 분할 → Ultralytics card.yaml 생성
"""
사용법:
  python assemble_dataset.py \
    --sources data/raw/synth data/raw/real \
    --out data/dataset \
    --train 0.70 --val 0.20 --test 0.10

출력:
  data/dataset/
    images/train/*.jpg
    images/val/*.jpg
    images/test/*.jpg
    labels/train/*.txt
    labels/val/*.txt
    labels/test/*.txt
    card.yaml

이후 압축해 Google Drive 업로드 → Colab에서 학습 (`train_colab.md` 참조).
"""

from __future__ import annotations

import argparse
import random
import shutil
from pathlib import Path

from tqdm import tqdm


def _collect_pairs(src: Path) -> list[tuple[Path, Path]]:
    """src/images/*.jpg 와 src/labels/*.txt 쌍을 반환. 라벨 없는 이미지는 제외."""
    img_dir = src / "images"
    lbl_dir = src / "labels"
    if not img_dir.exists() or not lbl_dir.exists():
        return []
    pairs = []
    for img in sorted(img_dir.iterdir()):
        if img.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        lbl = lbl_dir / (img.stem + ".txt")
        if lbl.exists():
            pairs.append((img, lbl))
    return pairs


def _split(pairs: list, train: float, val: float) -> tuple[list, list, list]:
    n = len(pairs)
    n_train = int(n * train)
    n_val = int(n * val)
    return pairs[:n_train], pairs[n_train:n_train + n_val], pairs[n_train + n_val:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", nargs="+", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--train", type=float, default=0.70)
    ap.add_argument("--val", type=float, default=0.20)
    ap.add_argument("--test", type=float, default=0.10)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    if abs(args.train + args.val + args.test - 1.0) > 1e-6:
        raise SystemExit("train+val+test 합이 1이 아님")

    random.seed(args.seed)
    all_pairs = []
    for src in args.sources:
        pairs = _collect_pairs(src)
        print(f"{src}: {len(pairs)}쌍")
        all_pairs.extend(pairs)
    random.shuffle(all_pairs)
    print(f"총 {len(all_pairs)}쌍")

    train_pairs, val_pairs, test_pairs = _split(all_pairs, args.train, args.val)
    print(f"분할: train={len(train_pairs)} val={len(val_pairs)} test={len(test_pairs)}")

    for split, pairs in [("train", train_pairs), ("val", val_pairs), ("test", test_pairs)]:
        img_out = args.out / "images" / split
        lbl_out = args.out / "labels" / split
        img_out.mkdir(parents=True, exist_ok=True)
        lbl_out.mkdir(parents=True, exist_ok=True)
        for img, lbl in tqdm(pairs, desc=split):
            shutil.copy2(img, img_out / img.name)
            shutil.copy2(lbl, lbl_out / lbl.name)

    yaml = (
        "# 자동 생성. Ultralytics 데이터셋 정의\n"
        "path: .\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n\n"
        "names:\n"
        "  0: credit_card\n"
    )
    (args.out / "card.yaml").write_text(yaml, encoding="utf-8")
    print(f"완료 → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
