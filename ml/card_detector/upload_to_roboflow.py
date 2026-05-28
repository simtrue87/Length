# 합성·실사 이미지를 Roboflow Instance Segmentation 프로젝트에 일괄 업로드
"""
사용법:
  # 1. .env 파일에 API 키·워크스페이스·프로젝트 설정
  #    ROBOFLOW_API_KEY=...
  #    ROBOFLOW_WORKSPACE=your-workspace-slug
  #    ROBOFLOW_PROJECT=length-credit-card
  #
  # 2. 합성(라벨 포함) 업로드
  python upload_to_roboflow.py --src data/raw/synth --batch synth_v1
  #
  # 3. 실사(라벨 없음) 업로드 — 라벨링은 Roboflow UI에서 수동
  python upload_to_roboflow.py --src data/raw/real --batch real_v1 --no-labels

사전 조건:
  - Roboflow 계정 + 프로젝트 (Instance Segmentation 타입)
  - 클래스명: "credit_card" (단일 클래스, id=0)
  - .env 또는 환경 변수에 API 키 설정

업로드 포맷:
  - 이미지: data/raw/{src}/images/*.{jpg,png}
  - 라벨: data/raw/{src}/labels/*.txt (YOLO seg: class x1 y1 ... x4 y4 정규화)
"""

from __future__ import annotations

import argparse
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from dotenv import load_dotenv
from tqdm import tqdm


def _collect_images(src: Path) -> list[Path]:
    exts = {".jpg", ".jpeg", ".png"}
    img_dir = src / "images"
    if not img_dir.exists():
        raise SystemExit(f"이미지 디렉터리 없음: {img_dir}")
    return sorted([p for p in img_dir.iterdir() if p.suffix.lower() in exts])


def _label_path(src: Path, img_path: Path) -> Path:
    return src / "labels" / (img_path.stem + ".txt")


def _upload_one(project, img_path: Path, lbl_path: Path | None, batch: str) -> tuple[str, bool, str]:
    try:
        kwargs = {
            "image_path": str(img_path),
            "batch_name": batch,
            "num_retry_uploads": 3,
        }
        if lbl_path and lbl_path.exists():
            kwargs["annotation_path"] = str(lbl_path)
            kwargs["annotation_labelmap"] = {0: "credit_card"}
        project.upload(**kwargs)
        return (img_path.name, True, "")
    except Exception as e:  # noqa: BLE001
        return (img_path.name, False, str(e))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, required=True, help="data/raw/{name} 경로")
    ap.add_argument("--batch", type=str, required=True, help="Roboflow batch name (예: synth_v1)")
    ap.add_argument("--no-labels", action="store_true", help="라벨 없이 이미지만 업로드 (Roboflow UI에서 수동 라벨링)")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    load_dotenv()
    api_key = os.environ.get("ROBOFLOW_API_KEY")
    workspace_slug = os.environ.get("ROBOFLOW_WORKSPACE")
    project_slug = os.environ.get("ROBOFLOW_PROJECT")
    if not all([api_key, workspace_slug, project_slug]):
        raise SystemExit(
            "환경 변수 ROBOFLOW_API_KEY / ROBOFLOW_WORKSPACE / ROBOFLOW_PROJECT 필요. "
            ".env 파일에 정의하거나 셸에서 export 하세요.")

    # 무거우니 main 안에서 lazy import.
    from roboflow import Roboflow
    rf = Roboflow(api_key=api_key)
    project = rf.workspace(workspace_slug).project(project_slug)
    print(f"Project: {project.id} (type={project.type})")

    images = _collect_images(args.src)
    print(f"이미지 {len(images)}장, batch={args.batch}, labels={not args.no_labels}")

    failures: list[tuple[str, str]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = []
        for img in images:
            lbl = None if args.no_labels else _label_path(args.src, img)
            futures.append(ex.submit(_upload_one, project, img, lbl, args.batch))
        for f in tqdm(as_completed(futures), total=len(futures), desc="upload"):
            name, ok, err = f.result()
            if not ok:
                failures.append((name, err))

    if failures:
        print(f"실패 {len(failures)}건:")
        for n, e in failures[:20]:
            print(f"  - {n}: {e}")
        return 1
    print("완료")
    return 0


if __name__ == "__main__":
    sys.exit(main())
