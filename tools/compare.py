#!/usr/bin/env python3
"""Compare a Bend frame against a reference-demo frame, by eye and by number.

Takes two PNGs, resizes the reference to the Bend frame's size with Lanczos if
they differ, and writes three artifacts into ``--outdir``:

  side.png     labelled side-by-side: Bend on the left, reference on the right
  diff.png     absolute difference, contrast-stretched so small deltas show
  metrics.json machine-readable numbers (the same ones printed to stdout)

The numbers are deliberately dumb and comparable, not perceptual: mean absolute
error, RMSE, per-channel means, mean luminance, the dark/hot pixel fractions and
a 16-bin luminance histogram for each image.  See ``definitions`` in
``metrics.json`` for the exact formulas.

Usage::

  tools/compare.py --bend out/compare/bend.png --ref out/compare/reference.png \\
      --outdir out/compare --title "Bend | reference"
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Luma weights (Rec. 709).  Any pixel statistic described as "luminance" uses
# these, on 0..1 linear-ish sRGB values -- no gamma decoding is applied.
LUMA = np.array([0.2126, 0.7152, 0.0722])

DARK_LEVEL = 8 / 255.0      # "dark": luminance below this
HOT_LEVEL = 200 / 255.0     # "hot":  luminance above this
HIST_BINS = 16

FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def load_rgb(path: pathlib.Path) -> np.ndarray:
    """Load a PNG as an HxWx3 float array in 0..1."""
    if not path.is_file():
        raise SystemExit(f"compare: no such image: {path}")
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.float64) / 255.0


def luminance(rgb: np.ndarray) -> np.ndarray:
    """Per-pixel luminance, HxW."""
    return rgb @ LUMA


def image_stats(rgb: np.ndarray) -> dict:
    """Per-image summary: channel means, luminance, dark/hot, histogram."""
    lum = luminance(rgb)
    counts, _ = np.histogram(lum, bins=HIST_BINS, range=(0.0, 1.0))
    hist = (counts / lum.size).tolist()
    return {
        "size": [int(rgb.shape[1]), int(rgb.shape[0])],
        "channel_mean": {
            "r": float(rgb[:, :, 0].mean()),
            "g": float(rgb[:, :, 1].mean()),
            "b": float(rgb[:, :, 2].mean()),
        },
        "luminance_mean": float(lum.mean()),
        "dark_fraction": float((lum < DARK_LEVEL).mean()),
        "hot_fraction": float((lum > HOT_LEVEL).mean()),
        "luminance_histogram": hist,
    }


def compare_arrays(bend: np.ndarray, ref: np.ndarray) -> dict:
    """Error metrics between two same-size float arrays."""
    diff = np.abs(bend - ref)
    return {
        "mae": float(diff.mean()),
        "rmse": float(np.sqrt((diff ** 2).mean())),
        "max_abs_diff": float(diff.max()),
        "p999_abs_diff": float(np.percentile(diff, 99.9)),
        "changed_fraction_gt_4_255": float((diff.max(axis=2) > 4 / 255.0).mean()),
    }


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if pathlib.Path(path).is_file():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def draw_side_by_side(bend: Image.Image, ref: Image.Image,
                      title: str | None) -> Image.Image:
    """Left panel Bend, right panel reference, with captions and a title."""
    w = bend.width + ref.width
    h = max(bend.height, ref.height)
    fsize = max(14, min(28, h // 28))
    f = font(fsize)
    pad = 6
    title_h = (fsize + 2 * pad) if title else 0
    cap_h = fsize + pad

    canvas = Image.new("RGB", (w, title_h + cap_h + h), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    if title:
        d.text((pad, pad), title, fill=(235, 238, 245), font=f)
    d.text((pad, title_h + pad // 2), "Bend", fill=(150, 210, 255), font=f)
    d.text((bend.width + pad, title_h + pad // 2), "reference",
           fill=(255, 200, 150), font=f)
    canvas.paste(bend, (0, title_h + cap_h))
    canvas.paste(ref, (bend.width, title_h + cap_h))
    return canvas


def draw_diff(bend: np.ndarray, ref: np.ndarray) -> Image.Image:
    """Absolute difference, stretched so that small deltas are visible."""
    diff = np.abs(bend - ref)
    # 99.9th percentile rather than max, so one hot pixel cannot flatten the
    # rest of the image; never below one 8-bit step.
    scale = max(float(np.percentile(diff, 99.9)), 1 / 255.0)
    stretched = np.clip(diff / scale, 0.0, 1.0)
    return Image.fromarray((stretched * 255.0 + 0.5).astype(np.uint8), "RGB")


def fmt(x: float) -> str:
    return f"{x:.6f}"


def print_report(name: str, s: dict) -> None:
    print(f"[{name}] {s['size'][0]}x{s['size'][1]}  "
          f"lum={fmt(s['luminance_mean'])}  dark={fmt(s['dark_fraction'])}  "
          f"hot={fmt(s['hot_fraction'])}")
    cm = s["channel_mean"]
    print(f"[{name}] mean R={fmt(cm['r'])} G={fmt(cm['g'])} B={fmt(cm['b'])}")
    print(f"[{name}] luma histogram (16 bins over 0..1): "
          + " ".join(f"{v:.4f}" for v in s["luminance_histogram"]))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bend", required=True, help="Bend frame PNG")
    ap.add_argument("--ref", required=True, help="reference frame PNG")
    ap.add_argument("--outdir", required=True, help="output directory")
    ap.add_argument("--title", default=None, help="title drawn on side.png")
    args = ap.parse_args(argv)

    bend_path, ref_path = pathlib.Path(args.bend), pathlib.Path(args.ref)
    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    bend_rgb = load_rgb(bend_path)
    ref_rgb = load_rgb(ref_path)
    bh, bw = bend_rgb.shape[:2]
    rh, rw = ref_rgb.shape[:2]

    resized = (rh, rw) != (bh, bw)
    if resized:
        ref_img = Image.open(ref_path).convert("RGB").resize((bw, bh), Image.LANCZOS)
        ref_rgb = np.asarray(ref_img, dtype=np.float64) / 255.0
    else:
        ref_img = Image.open(ref_path).convert("RGB")
    bend_img = Image.open(bend_path).convert("RGB")

    bend_stats = image_stats(bend_rgb)
    ref_stats = image_stats(ref_rgb)
    ref_stats["original_size"] = [rw, rh]
    ref_stats["resized_to_bend"] = resized

    metrics = {
        "title": args.title,
        "bend": {"path": str(bend_path), **bend_stats},
        "reference": {"path": str(ref_path), **ref_stats},
        "comparison": compare_arrays(bend_rgb, ref_rgb),
        "definitions": {
            "values": "all means and fractions are over RGB in 0..1 (or pixel counts); RMSE/MAE are in 0..1",
            "luminance": "Rec.709: 0.2126 R + 0.7152 G + 0.0722 B per pixel",
            "dark_fraction": f"fraction of pixels with luminance < {DARK_LEVEL:.8f} (8/255)",
            "hot_fraction": f"fraction of pixels with luminance > {HOT_LEVEL:.8f} (200/255)",
            "luminance_histogram": f"{HIST_BINS} bins over luminance 0..1, values are fractions summing to 1",
            "diff_png": "|bend - reference| per channel, divided by the 99.9th percentile of the difference (min one 8-bit step)",
        },
    }

    side = draw_side_by_side(bend_img, ref_img, args.title)
    side.save(outdir / "side.png")
    draw_diff(bend_rgb, ref_rgb).save(outdir / "diff.png")
    (outdir / "metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    c = metrics["comparison"]
    print(f"bend={bend_path}  ref={ref_path}")
    if resized:
        print(f"reference resized {rw}x{rh} -> {bw}x{bh} (Lanczos)")
    print_report("bend", bend_stats)
    print_report("reference", ref_stats)
    print(f"[compare] mae={fmt(c['mae'])}  rmse={fmt(c['rmse'])}  "
          f"max={fmt(c['max_abs_diff'])}  p99.9={fmt(c['p999_abs_diff'])}  "
          f"changed(>4/255)={fmt(c['changed_fraction_gt_4_255'])}")
    print(f"wrote {outdir / 'side.png'}, {outdir / 'diff.png'}, "
          f"{outdir / 'metrics.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
