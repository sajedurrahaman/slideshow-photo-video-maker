#!/usr/bin/env python3
"""Generate CapCut-style Dollar Rain: color + alpha matte MP4s.

Sharpness rules:
- Use high-res bill cutouts only (no low-res pile upscale — that caused blur).
- Pre-bake a few on-screen sizes from the master (single Lanczos downscale).
- Encode high-quality yuv444p.
"""

from __future__ import annotations

import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "animations"
WORK = ROOT / ".tools_tmp" / "dollar_rain"
FRAMES = WORK / "frames"
COLOR_FRAMES = FRAMES / "color"
ALPHA_FRAMES = FRAMES / "alpha"

W, H = 720, 1280
FPS = 24
DURATION = 2.2
N_FRAMES = int(round(DURATION * FPS))

SPRITE_PATHS = [
    Path(
        "/Users/mdsajedurrahman/.cursor/projects/"
        "Users-mdsajedurrahman-App-Development-ClipCraft-Slideshow-Flutter/"
        "assets/dollar_bill_sharp_a.jpg"
    ),
    Path(
        "/Users/mdsajedurrahman/.cursor/projects/"
        "Users-mdsajedurrahman-App-Development-ClipCraft-Slideshow-Flutter/"
        "assets/dollar_bill_sharp_b.jpg"
    ),
    Path(
        "/Users/mdsajedurrahman/.cursor/projects/"
        "Users-mdsajedurrahman-App-Development-ClipCraft-Slideshow-Flutter/"
        "assets/dollar_bill_sprite.jpg"
    ),
]

# Prebaked on-screen widths (downscaled once from ~1200px masters).
BAKE_WIDTHS = (260, 320, 380, 440)


def log(msg: str) -> None:
    print(msg, flush=True)


def sharpen(img: Image.Image) -> Image.Image:
    return img.filter(ImageFilter.UnsharpMask(radius=1.3, percent=170, threshold=1))


def remove_black_bg(img: Image.Image, threshold: int = 22) -> Image.Image:
    rgba = img.convert("RGBA")
    arr = np.asarray(rgba).astype(np.float32)
    rgb = arr[..., :3]
    lum = rgb.max(axis=2)
    alpha = np.clip((lum - threshold) / 10.0, 0.0, 1.0)
    alpha[(rgb < 14).all(axis=2)] = 0.0
    arr[..., 3] = (alpha * 255.0).astype(np.uint8)
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")
    bbox = out.split()[-1].getbbox()
    if bbox:
        out = out.crop(bbox)
    out = ImageEnhance.Contrast(out).enhance(1.2)
    out = ImageEnhance.Sharpness(out).enhance(1.6)
    return sharpen(out)


def load_masters() -> list[Image.Image]:
    masters: list[Image.Image] = []
    for path in SPRITE_PATHS:
        if not path.exists():
            log(f"missing sprite: {path}")
            continue
        m = remove_black_bg(Image.open(path))
        log(f"  master {path.name} -> {m.width}x{m.height}")
        masters.append(m)
    if not masters:
        raise SystemExit("No sprites loaded")
    return masters


def bake_sizes(masters: list[Image.Image]) -> list[dict[int, Image.Image]]:
    """One Lanczos downscale per size — reused every frame (keeps engraving sharp)."""
    baked: list[dict[int, Image.Image]] = []
    for m in masters:
        sizes: dict[int, Image.Image] = {}
        for tw in BAKE_WIDTHS:
            scale = tw / m.width
            nh = max(24, int(m.height * scale))
            img = m.resize((tw, nh), Image.Resampling.LANCZOS)
            img = sharpen(img)
            sizes[tw] = img
        baked.append(sizes)
    return baked


@dataclass
class Bill:
    sprite_i: int
    bake_w: int
    rest_x: float
    rest_y: float
    rest_rot: float
    throw_delay: float
    throw_dur: float
    start_x: float
    start_y: float
    start_scale: float  # relative to bake size during throw
    start_rot: float
    fall_delay: float
    fall_vx: float
    fall_spin: float
    brightness: float


def ease_out_cubic(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1.0 - (1.0 - t) ** 3


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def build_bills(n: int, rng: random.Random) -> list[Bill]:
    bills: list[Bill] = []
    cols, rows = 6, 12
    cell_w, cell_h = W / cols, H / rows
    idx = 0
    for r in range(rows):
        for c in range(cols):
            for layer in range(3):
                cx = (c + 0.5) * cell_w + rng.uniform(-cell_w * 0.42, cell_w * 0.42)
                cy = (r + 0.5) * cell_h + rng.uniform(-cell_h * 0.45, cell_h * 0.45)
                bake_w = BAKE_WIDTHS[rng.randrange(len(BAKE_WIDTHS))]
                if layer == 0:
                    bake_w = BAKE_WIDTHS[min(len(BAKE_WIDTHS) - 1, rng.randrange(1, 4))]
                rot = rng.uniform(-48, 48) + layer * rng.uniform(-15, 15)
                # Start already resting — full cover from frame 0 (no throw-in gap).
                fall_delay = 0.55 + (r / max(1, rows - 1)) * 0.45 + rng.uniform(0, 0.12)
                bills.append(
                    Bill(
                        sprite_i=idx % n,
                        bake_w=bake_w,
                        rest_x=cx,
                        rest_y=cy,
                        rest_rot=rot,
                        throw_delay=0.0,
                        throw_dur=0.01,
                        start_x=cx,
                        start_y=cy,
                        start_scale=1.0,
                        start_rot=rot,
                        fall_delay=fall_delay,
                        fall_vx=rng.uniform(-110, 110),
                        fall_spin=rng.uniform(-240, 240),
                        brightness=rng.uniform(0.95, 1.06),
                    )
                )
                idx += 1
    for _ in range(70):
        bake_w = BAKE_WIDTHS[rng.randrange(len(BAKE_WIDTHS))]
        rot = rng.uniform(-70, 70)
        cx = rng.uniform(-60, W + 60)
        cy = rng.uniform(-60, H + 60)
        bills.append(
            Bill(
                sprite_i=rng.randrange(n),
                bake_w=bake_w,
                rest_x=cx,
                rest_y=cy,
                rest_rot=rot,
                throw_delay=0.0,
                throw_dur=0.01,
                start_x=cx,
                start_y=cy,
                start_scale=1.0,
                start_rot=rot,
                fall_delay=rng.uniform(0.55, 1.15),
                fall_vx=rng.uniform(-140, 140),
                fall_spin=rng.uniform(-280, 280),
                brightness=rng.uniform(0.95, 1.05),
            )
        )
    return bills


def pose_at(bill: Bill, t: float) -> tuple[float, float, float, float, float] | None:
    """x, y, rot, size_scale (1=bake size), alpha.

    Frame 0 must already be a full opaque wall of dollars.
    """
    if t < bill.fall_delay:
        return bill.rest_x, bill.rest_y, bill.rest_rot, 1.0, 1.0
    ft = t - bill.fall_delay
    y = bill.rest_y + 1600 * ft * ft + 420 * ft
    x = bill.rest_x + bill.fall_vx * ft
    rot = bill.rest_rot + bill.fall_spin * ft
    if y > H + 280:
        return None
    return x, y, rot, 1.0 + 0.1 * ft, 1.0


def blit_bill(
    canvas: Image.Image,
    sprite: Image.Image,
    x: float,
    y: float,
    rot: float,
    size_scale: float,
    alpha: float,
    brightness: float,
) -> None:
    if alpha <= 0.02 or size_scale <= 0.05:
        return
    img = sprite
    if abs(size_scale - 1.0) > 0.02:
        w = max(12, int(sprite.width * size_scale))
        h = max(8, int(sprite.height * size_scale))
        img = sprite.resize((w, h), Image.Resampling.BILINEAR)
    if abs(brightness - 1.0) > 0.02:
        img = ImageEnhance.Brightness(img).enhance(brightness)
    img = img.rotate(rot, resample=Image.Resampling.BICUBIC, expand=True)
    if alpha < 0.999:
        a = img.split()[-1].point(lambda p: int(p * alpha))
        img.putalpha(a)
    canvas.alpha_composite(img, (int(x - img.width / 2), int(y - img.height / 2)))


def coverage_ratio(alpha_img: Image.Image) -> float:
    a = np.asarray(alpha_img.convert("L"))
    return float((a > 40).mean())


def render() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    COLOR_FRAMES.mkdir(parents=True, exist_ok=True)
    ALPHA_FRAMES.mkdir(parents=True, exist_ok=True)
    for p in COLOR_FRAMES.glob("*.png"):
        p.unlink()
    for p in ALPHA_FRAMES.glob("*.png"):
        p.unlink()

    masters = load_masters()
    baked = bake_sizes(masters)
    rng = random.Random(42)
    bills = build_bills(len(baked), rng)
    log(f"sprites={len(baked)} bills={len(bills)} frames={N_FRAMES}")

    for fi in range(N_FRAMES):
        t = fi / FPS
        color = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        order = sorted(
            range(len(bills)),
            key=lambda i: (bills[i].rest_y, bills[i].throw_delay),
        )
        for bi in order:
            bill = bills[bi]
            pose = pose_at(bill, t)
            if pose is None:
                continue
            x, y, rot, size_scale, alpha = pose
            sprite = baked[bill.sprite_i][bill.bake_w]
            blit_bill(color, sprite, x, y, rot, size_scale, alpha, bill.brightness)

        # From frame 0 through hold: patch holes so cover is solid.
        if t <= 0.85 and coverage_ratio(color.split()[-1]) < 0.995:
            hole_rng = random.Random(fi * 997 + 13)
            for _ in range(40):
                si = hole_rng.randrange(len(baked))
                bw = BAKE_WIDTHS[hole_rng.randrange(len(BAKE_WIDTHS))]
                blit_bill(
                    color,
                    baked[si][bw],
                    hole_rng.uniform(0, W),
                    hole_rng.uniform(0, H),
                    hole_rng.uniform(-45, 45),
                    1.0,
                    1.0,
                    hole_rng.uniform(0.96, 1.04),
                )

        # Final unsharp on the whole frame so text/engraving pops on phone.
        color = sharpen(color)
        rgb = Image.new("RGB", (W, H), (0, 0, 0))
        rgb.paste(color, mask=color.split()[-1])
        a_ch = color.split()[-1]
        alpha = Image.merge("RGB", (a_ch, a_ch, a_ch))
        rgb.save(COLOR_FRAMES / f"c_{fi + 1:04d}.png")
        alpha.save(ALPHA_FRAMES / f"a_{fi + 1:04d}.png")
        if fi % 8 == 0 or fi == N_FRAMES - 1:
            log(f"frame {fi + 1}/{N_FRAMES} t={t:.2f}s coverage={coverage_ratio(a_ch):.3f}")

    mid = COLOR_FRAMES / "c_0020.png"
    if mid.exists():
        thumb = Image.open(mid).resize((180, 320), Image.Resampling.LANCZOS)
        thumb = ImageEnhance.Sharpness(thumb).enhance(1.5)
        thumb.save(OUT_DIR / "fx_04_dollar_rain_thumb.png")
    log("frames ready → encoding mp4")


if __name__ == "__main__":
    try:
        render()
    except Exception as e:
        print(f"FAILED: {e}", file=sys.stderr)
        raise
