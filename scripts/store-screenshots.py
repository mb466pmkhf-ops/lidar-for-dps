#!/usr/bin/env python3
"""Turns raw Simulator screenshots into App Store screenshots: one caption line above the screen,
on a plain dark background, at the exact pixel sizes App Store Connect accepts.

    python3 scripts/store-screenshots.py <raw dir> <out dir>

The raw dir holds `iphone-<screen>.png` and `ipad-<screen>.png` from .github/workflows/store-screenshots.yml.
Captions are the ones in the store listing doc; keep the two in step.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "FrameScout/Resources/Fonts/Poppins-SemiBold.ttf"

# Order = order in the store. (screen name in DemoContent, caption)
# The 3D view doesn't draw in the CI Simulator (no Metal there), so no screen here shows it.
SHOTS = [
    ("location", "Scan the room on the recce."),
    ("lightpanel", "Light it before you arrive."),
    ("shots", "Line up every shot."),
    ("sun", "Know where the sun will be."),
    ("measurements", "Every number says where it came from."),
    ("plan-night", "Readable on a dark set."),
]

# App Store Connect sizes (portrait): 6.9-inch iPhone and 13-inch iPad.
SIZES = {"iphone": (1320, 2868), "ipad": (2064, 2752)}
BACKGROUND = (20, 24, 26)      # the app's day text colour, #14181A
CAPTION = (243, 244, 241)      # the app's day background, #F3F4F1


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def wrap(draw, text, font, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def compose(raw: Path, caption: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    canvas = Image.new("RGB", size, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    margin = round(w * 0.07)
    # Same visual weight on both: the iPad canvas is wider, so its caption is a smaller share of it.
    font = ImageFont.truetype(str(FONT), round(w * (0.068 if w < 1600 else 0.05)))
    lines = wrap(draw, caption, font, w - 2 * margin)
    line_h = round(font.size * 1.25)
    top = round(h * 0.05)
    for i, line in enumerate(lines):
        tw = draw.textlength(line, font=font)
        draw.text(((w - tw) / 2, top + i * line_h), line, font=font, fill=CAPTION)
    caption_bottom = top + len(lines) * line_h + round(h * 0.03)

    shot = Image.open(raw).convert("RGB")
    avail_w, avail_h = w - 2 * margin, h - caption_bottom - round(h * 0.03)
    scale = min(avail_w / shot.width, avail_h / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    shot = rounded(shot, round(shot.width * 0.06))
    canvas.paste(shot, ((w - shot.width) // 2, caption_bottom), shot)
    return canvas


def main(raw_dir: Path, out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    missing = []
    for device, size in SIZES.items():
        for n, (screen, caption) in enumerate(SHOTS, 1):
            raw = raw_dir / f"{device}-{screen}.png"
            if not raw.exists():
                missing.append(raw.name)
                continue
            img = compose(raw, caption, size)
            assert img.size == size
            img.save(out_dir / f"{device}-{n}-{screen}.png", optimize=True)
    if missing:
        print("Missing raw screenshots: " + ", ".join(missing))
        return 1
    print(f"Wrote {len(SHOTS) * len(SIZES)} store screenshots to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
