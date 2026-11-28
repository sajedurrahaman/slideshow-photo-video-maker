#!/usr/bin/env python3
"""Generate CapCut-style Balloon Rise In-anim: color + alpha matte MP4s.

Photoreal latex balloons (not cartoon circles).
Motion: dense full-screen cover → float up → clear.
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
WORK = ROOT / ".tools_tmp" / "balloon_rise"
FRAMES = WORK / "frames"
COLOR_FRAMES = FRAMES / "color"
ALPHA_FRAMES = FRAMES / "alpha"

W, H = 720, 1280
FPS = 24
DURATION = 2.2
N_FRAMES = int(round(DURATION * FPS))

ASSETS = Path(
    "/Users/mdsajedurrahman/.cursor/projects/"
    "Users-mdsajedurrahman-App-Development-ClipCraft-Slideshow-Flutter/assets"
)
SPRITE_PATHS = [
    ASSETS / "balloon_red.jpg",
    ASSETS / "balloon_blue.jpg",
    ASSETS / "balloon_gold.jpg",
    ASSETS / "balloon_pink.jpg",
    ASSETS / "balloon_white.jpg",
]

BAKE_WIDTHS = (160, 200, 240, 280, 320)


def log(msg: str) -> None:
    print(msg, flush=True)


def sharpen(img: Image.Image) -> Image.Image:
    return img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=140, threshold=2))


def remove_black_bg(img: Image.Image, threshold: int = 24) -> Image.Image:
    rgba = img.convert("RGBA")
    arr = np.asarray(rgba).astype(np.float32)
    rgb = arr[..., :3]
    lum = rgb.max(axis=2)
    alpha = np.clip((lum - threshold) / 12.0, 0.0, 1.0)
    # Keep dark ribbon/knot; only kill pure black field.
    near_black = (rgb < 16).all(axis=2)
    alpha[near_black] = 0.0
    arr[..., 3] = (alpha * 255.0).astype(np.uint8)
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")
    bbox = out.split()[-1].getbbox()
    if bbox:
        # Keep a little string below the knot.
        l, t, r, b = bbox
        pad = int((r - l) * 0.08)
        out = out.crop(
            (
                max(0, l - pad),
                max(0, t - pad),
                min(out.width, r + pad),
                min(out.height, b + pad * 2),
            )
        )
    out = ImageEnhance.Contrast(out).enhance(1.08)
    out = ImageEnhance.Sharpness(out).enhance(1.25)
    return sharpen(out)


def load_masters() -> list[Image.Image]:
    masters: list[Image.Image] = []
    for path in SPRITE_PATHS:
        if not path.exists():
            log(f"missing: {path}")
            continue
        m = remove_black_bg(Image.open(path))
        log(f"  master {path.name} -> {m.width}x{m.height}")
        masters.append(m)
    if not masters:
        raise SystemExit("No balloon sprites")
    return masters


def bake_sizes(masters: list[Image.Image]) -> list[dict[int, Image.Image]]:
    baked: list[dict[int, Image.Image]] = []
    for m in masters:
        sizes: dict[int, Image.Image] = {}
        for tw in BAKE_WIDTHS:
            scale = tw / m.width
            nh = max(24, int(m.height * scale))
            img = m.resize((tw, nh), Image.Resampling.LANCZOS)
            sizes[tw] = sharpen(img)
        baked.append(sizes)
    return baked


@dataclass
class Balloon:
    sprite_i: int
    bake_w: int
    rest_x: float
    rest_y: float
    rest_rot: float
    sway: float
    rise_delay: float
    rise_speed: float
    brightness: float
    # Appear / settle briefly before rising.
    settle_dur: float


def ease_out_cubic(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1.0 - (1.0 - t) ** 3


def build_balloons(n: int, rng: random.Random) -> list[Balloon]:
    balloons: list[Balloon] = []
    cols, rows = 6, 11
    cell_w, cell_h = W / cols, H / rows
    idx = 0
    for r in range(rows):
        for c in range(cols):
            for layer in range(3):
                cx = (c + 0.5) * cell_w + rng.uniform(-cell_w * 0.45, cell_w * 0.45)
                # Edge-to-edge pack so frame 0 has no empty rim.
                cy = (r + 0.5) * cell_h + rng.uniform(-cell_h * 0.45, cell_h * 0.45)
                bake_w = BAKE_WIDTHS[rng.randrange(len(BAKE_WIDTHS))]
                if layer == 0:
                    bake_w = BAKE_WIDTHS[min(len(BAKE_WIDTHS) - 1, rng.randrange(2, 5))]
                rot = rng.uniform(-18, 18)
                # Hold full-screen cover first, then float up.
                rise_delay = 0.55 + (1.0 - r / max(1, rows - 1)) * 0.45 + rng.uniform(
                    0.0, 0.15
                )
                balloons.append(
                    Balloon(
                        sprite_i=idx % n,
                        bake_w=bake_w,
                        rest_x=cx,
                        rest_y=cy,
                        rest_rot=rot,
                        sway=rng.uniform(18, 55) * rng.choice([-1, 1]),
                        rise_delay=rise_delay,
                        rise_speed=rng.uniform(780, 1180),
                        brightness=rng.uniform(0.92, 1.08),
                        settle_dur=rng.uniform(0.12, 0.28),
                    )
                )
                idx += 1
    # Extra fill balloons for no-gap cover (corners / edges).
    for _ in range(70):
        balloons.append(
            Balloon(
                sprite_i=rng.randrange(n),
                bake_w=BAKE_WIDTHS[rng.randrange(len(BAKE_WIDTHS))],
                rest_x=rng.uniform(-80, W + 80),
                rest_y=rng.uniform(-80, H + 100),
                rest_rot=rng.uniform(-22, 22),
                sway=rng.uniform(20, 60) * rng.choice([-1, 1]),
                rise_delay=rng.uniform(0.55, 1.15),
                rise_speed=rng.uniform(820, 1250),
                brightness=rng.uniform(0.93, 1.07),
                settle_dur=rng.uniform(0.1, 0.25),
            )
        )
    return balloons


def pose_at(
    b: Balloon, t: float
) -> tuple[float, float, float, float, float] | None:
    """x, y, rot, size_scale, alpha — or None if offscreen.

    Frame 0 must already be a full opaque wall of balloons.
    """
    if t < b.rise_delay:
        # Hold dense cover from the first frame (no fade-in / empty start).
        x = b.rest_x + math.sin(t * 3.2 + b.rest_y * 0.01) * 4
        y = b.rest_y + math.cos(t * 2.4 + b.rest_x * 0.01) * 3
        rot = b.rest_rot + math.sin(t * 2.8) * 2.5
        return x, y, rot, 1.0, 1.0

    ft = t - b.rise_delay
    # Accelerate upward.
    y = b.rest_y - (b.rise_speed * ft + 420 * ft * ft)
    x = b.rest_x + b.sway * math.sin(ft * 2.6 + b.rest_y * 0.02)
    rot = b.rest_rot + b.sway * 0.08 * ft + math.sin(ft * 3.0) * 6
    scale = 1.0 + 0.06 * ft
    if y < -320:
        return None
    return x, y, rot, scale, 1.0


def blit(
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
        w = max(10, int(sprite.width * size_scale))
        h = max(10, int(sprite.height * size_scale))
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
    rng = random.Random(21)
    balloons = build_balloons(len(baked), rng)
    log(f"sprites={len(baked)} balloons={len(balloons)} frames={N_FRAMES}")

    for fi in range(N_FRAMES):
        t = fi / FPS
        color = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        order = sorted(
            range(len(balloons)),
            key=lambda i: (balloons[i].rest_y, balloons[i].bake_w),
        )
        for bi in order:
            b = balloons[bi]
            pose = pose_at(b, t)
            if pose is None:
                continue
            x, y, rot, scale, alpha = pose
            sprite = baked[b.sprite_i][b.bake_w]
            blit(color, sprite, x, y, rot, scale, alpha, b.brightness)

        # From frame 0 through hold: patch any holes so cover is solid.
        if t <= 0.85 and coverage_ratio(color.split()[-1]) < 0.995:
            hole_rng = random.Random(fi * 911 + 7)
            for _ in range(40):
                si = hole_rng.randrange(len(baked))
                bw = BAKE_WIDTHS[hole_rng.randrange(len(BAKE_WIDTHS))]
                blit(
                    color,
                    baked[si][bw],
                    hole_rng.uniform(0, W),
                    hole_rng.uniform(0, H),
                    hole_rng.uniform(-20, 20),
                    1.05,
                    1.0,
                    hole_rng.uniform(0.94, 1.05),
                )

        color = sharpen(color)
        rgb = Image.new("RGB", (W, H), (0, 0, 0))
        rgb.paste(color, mask=color.split()[-1])
        a_ch = color.split()[-1]
        alpha = Image.merge("RGB", (a_ch, a_ch, a_ch))
        rgb.save(COLOR_FRAMES / f"c_{fi + 1:04d}.png")
        alpha.save(ALPHA_FRAMES / f"a_{fi + 1:04d}.png")
        if fi % 8 == 0 or fi == N_FRAMES - 1:
            log(
                f"frame {fi + 1}/{N_FRAMES} t={t:.2f}s "
                f"coverage={coverage_ratio(a_ch):.3f}"
            )

    mid = COLOR_FRAMES / "c_0012.png"
    if mid.exists():
        thumb = Image.open(mid).resize((180, 320), Image.Resampling.LANCZOS)
        thumb = ImageEnhance.Sharpness(thumb).enhance(1.3)
        thumb.save(OUT_DIR / "fx_03_balloon_rise_thumb.png")
    log("frames ready → encoding mp4")


if __name__ == "__main__":
    try:
        render()
    except Exception as e:
        print(f"FAILED: {e}", file=sys.stderr)
        raise
