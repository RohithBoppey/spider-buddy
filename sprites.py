#!/usr/bin/env python3
"""
Sprite sheet helper for the desktop pet.

Step 1 — slice a sheet into individual frames:
    python3 sprites.py slice sheet.png
  -> frames/000.png, 001.png, ... (transparent background, tightly cropped)
  -> frames/_preview.png          (every frame with its number, to pick from)

Step 2 — you copy the frames you want into state folders, in play order:
    skin_raw/drag/   skin_raw/wall/   skin_raw/top/   skin_raw/bottom/

Step 3 — make them all the same size, aligned, and scaled up:
    python3 sprites.py pack skin_raw spiderman --scale 2
  -> spiderman/drag/01.png ... (every frame in every folder has the same canvas)

Setup:  pip3 install pillow numpy scipy
"""
import argparse
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

# Where each state's character "sticks" inside its canvas.
# wall = right wall (the app mirrors it for the left wall).
ANCHORS = {
    "wall": "right",
    "top": "top",
    "bottom": "bottom",
    "drag": "center",
}


# ---------------------------------------------------------------- slice

def background_color(arr):
    """Most common color along the image border = the sheet background."""
    border = np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]])[:, :3]
    colors, counts = np.unique(border.reshape(-1, 3), axis=0, return_counts=True)
    return colors[counts.argmax()]


def order_reading(boxes):
    """Sort boxes top-to-bottom in rows, then left-to-right inside a row."""
    if not boxes:
        return boxes
    heights = sorted(b[3] - b[1] for b in boxes)
    row_tol = heights[len(heights) // 2] / 2
    boxes = sorted(boxes, key=lambda b: (b[1] + b[3]) / 2)
    rows, current, row_y = [], [], None
    for b in boxes:
        cy = (b[1] + b[3]) / 2
        if row_y is None or abs(cy - row_y) <= row_tol:
            current.append(b)
            row_y = cy if row_y is None else (row_y + cy) / 2
        else:
            rows.append(current)
            current, row_y = [b], cy
    rows.append(current)
    return [b for row in rows for b in sorted(row, key=lambda b: b[0])]


def cmd_slice(args):
    img = Image.open(args.sheet).convert("RGBA")
    arr = np.array(img)
    bg = background_color(arr)

    # A pixel is "sprite" if it differs from the background color.
    diff = np.abs(arr[:, :, :3].astype(int) - bg.astype(int)).sum(axis=2)
    mask = (diff > args.tolerance) & (arr[:, :, 3] > 0)

    # Grow the mask a little so a sprite's detached bits (a hand, a foot)
    # join the same group, then label each group.
    grown = ndimage.binary_dilation(mask, iterations=args.gap) if args.gap else mask
    labels, count = ndimage.label(grown)

    boxes = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        if sl is None:
            continue
        own = mask[sl] & (labels[sl] == i)
        if own.sum() < args.min_area:
            continue  # stray dots, specks
        if max(sl[0].stop - sl[0].start, sl[1].stop - sl[1].start) > args.max_size:
            continue  # section borders / frames drawn around groups
        boxes.append((sl[1].start, sl[0].start, sl[1].stop, sl[0].stop, i))

    boxes = order_reading(boxes)

    out = args.out
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)

    frames = []
    for n, (x0, y0, x1, y1, i) in enumerate(boxes):
        crop = arr[y0:y1, x0:x1].copy()
        own = mask[y0:y1, x0:x1] & (labels[y0:y1, x0:x1] == i)
        crop[~own] = (0, 0, 0, 0)  # background (and neighbours) -> transparent
        frame = Image.fromarray(crop)
        frame = frame.crop(frame.getbbox())
        frame.save(os.path.join(out, f"{n:03d}.png"))
        frames.append(frame)

    make_preview(frames, os.path.join(out, "_preview.png"))
    print(f"background {tuple(bg)} -> {len(frames)} frames in {out}/")
    print(f"open {out}/_preview.png to pick frame numbers")


def make_preview(frames, path, cols=12, scale=2):
    """Grid of all frames with their number, on a checkerboard."""
    if not frames:
        return
    # Cell size from the 95th-percentile frame, so one odd big blob
    # (a credits box, a logo) doesn't blow up every cell.
    def pct(vals):
        vals = sorted(vals)
        return vals[min(len(vals) - 1, int(len(vals) * 0.95))]
    inner_w = pct(f.width for f in frames) * scale
    inner_h = pct(f.height for f in frames) * scale
    label_h = 26
    cw, ch = inner_w + 12, inner_h + label_h + 8
    try:
        font = ImageFont.load_default(size=20)
    except TypeError:  # older Pillow
        font = ImageFont.load_default()
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (40, 40, 40, 255))
    draw = ImageDraw.Draw(sheet)
    for n, f in enumerate(frames):
        x, y = (n % cols) * cw, (n // cols) * ch
        draw.rectangle([x, y, x + cw - 1, y + ch - 1], outline=(90, 90, 90, 255))
        for cx in range(x + 1, x + cw - 1, 8):   # checkerboard shows transparency
            for cy in range(y + label_h, y + ch - 1, 8):
                if ((cx - x) // 8 + (cy - y) // 8) % 2:
                    draw.rectangle([cx, cy, min(cx + 7, x + cw - 2),
                                    min(cy + 7, y + ch - 2)], fill=(58, 58, 58, 255))
        w, h = f.width * scale, f.height * scale
        shrink = min(1.0, inner_w / w, inner_h / h)
        big = f.resize((max(1, int(w * shrink)), max(1, int(h * shrink))), Image.NEAREST)
        px = x + (cw - big.width) // 2
        py = y + label_h + (inner_h + 8 - big.height) // 2
        sheet.alpha_composite(big, (px, py))
        draw.text((x + 6, y + 3), f"{n:03d}", fill=(255, 220, 0, 255), font=font)
    sheet.save(path)


# ----------------------------------------------------------------- pack

def place(frame, canvas_w, canvas_h, anchor):
    """Put frame on a transparent canvas, stuck to the anchor side."""
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    cx = (canvas_w - frame.width) // 2
    cy = (canvas_h - frame.height) // 2
    if anchor == "right":
        x, y = canvas_w - frame.width, cy
    elif anchor == "left":
        x, y = 0, cy
    elif anchor == "top":
        x, y = cx, 0
    elif anchor == "bottom":
        x, y = cx, canvas_h - frame.height
    else:
        x, y = cx, cy
    canvas.alpha_composite(frame, (x, y))
    return canvas


def cmd_pack(args):
    states = sorted(d for d in os.listdir(args.src)
                    if os.path.isdir(os.path.join(args.src, d)))
    if not states:
        sys.exit(f"no state folders inside {args.src}/")

    loaded = {}
    for s in states:
        folder = os.path.join(args.src, s)
        names = sorted(f for f in os.listdir(folder) if f.lower().endswith(".png"))
        frames = []
        for name in names:
            f = Image.open(os.path.join(folder, name)).convert("RGBA")
            box = f.getbbox()
            if box:
                frames.append(f.crop(box))  # trim any padding first
        if frames:
            loaded[s] = frames

    # One canvas size for everything, so the app never has to care.
    all_frames = [f for fs in loaded.values() for f in fs]
    w = max(f.width for f in all_frames)
    h = max(f.height for f in all_frames)
    side = max(w, h)  # square: frames get rotated 90° for walls/ceiling
    print(f"canvas {side}x{side} before scaling")

    if os.path.exists(args.dst):
        shutil.rmtree(args.dst)
    for s, frames in loaded.items():
        anchor = ANCHORS.get(s, "center")
        os.makedirs(os.path.join(args.dst, s))
        for n, f in enumerate(frames, start=1):
            out = place(f, side, side, anchor)
            if args.scale != 1:
                out = out.resize((side * args.scale, side * args.scale), Image.NEAREST)
            out.save(os.path.join(args.dst, s, f"{n:02d}.png"))
        print(f"  {s:<8} {len(frames):>2} frames, anchored {anchor}")
    print(f"done -> {args.dst}/")


# ----------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("slice", help="cut a sprite sheet into frames")
    s.add_argument("sheet")
    s.add_argument("--out", default="frames")
    s.add_argument("--tolerance", type=int, default=30,
                   help="how different from background a pixel must be")
    s.add_argument("--gap", type=int, default=2,
                   help="pixels apart that still count as one sprite")
    s.add_argument("--min-area", type=int, default=40,
                   help="ignore blobs smaller than this many pixels")
    s.add_argument("--max-size", type=int, default=300,
                   help="ignore blobs wider/taller than this (borders, boxes)")
    s.set_defaults(func=cmd_slice)

    k = sub.add_parser("pack", help="make chosen frames same size + aligned")
    k.add_argument("src", help="folder with drag/ wall/ top/ bottom/ inside")
    k.add_argument("dst", help="output skin folder")
    k.add_argument("--scale", type=int, default=2, help="whole-number upscale")
    k.set_defaults(func=cmd_pack)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
