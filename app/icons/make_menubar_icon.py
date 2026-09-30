"""Generates the menu-bar icon: Spidey's two eyes, outlined (design D).

Writes app/Resources/MenuBarIcon.png (@1x) and MenuBarIcon@2x.png as template images:
black + alpha, which macOS tints black on a light menu bar and white on a dark one.
Run:  python3 app/icons/make_menubar_icon.py   (needs Pillow)
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Resources")
SS = 1600            # supersampling canvas for a 100x100 design space
HEIGHT_PT = 13       # icon height in points (menu bar is 24 pt tall)
OUTLINE = 0.62       # inner cut-out size relative to the eye: smaller = thicker outline


def eye(side):
    """Classic Spidey eye: wide and raised at the outer edge, pointed toward the nose."""
    base = [(18, 32), (29, 33), (45, 47), (43, 59), (32, 61), (20, 50)]
    cx, cy = 31, 46
    pts = [(cx + (x - cx) * 1.25, cy + (y - cy) * 1.25) for x, y in base]
    return pts if side == "L" else [(100 - x, y) for x, y in pts]


def scaled(pts):
    return [(x * SS / 100, y * SS / 100) for x, y in pts]


def main():
    mask = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(mask)
    for side in "LR":
        outer = eye(side)
        d.polygon(scaled(outer), fill=255)
        cx = sum(p[0] for p in outer) / len(outer)
        cy = sum(p[1] for p in outer) / len(outer)
        d.polygon(scaled([(cx + (x - cx) * OUTLINE, cy + (y - cy) * OUTLINE) for x, y in outer]), fill=0)
    mask = mask.crop(mask.getbbox())

    for suffix, px_per_pt in (("", 1), ("@2x", 2)):
        h = HEIGHT_PT * px_per_pt
        w = round(mask.width * h / mask.height)
        alpha = mask.resize((w, h), Image.LANCZOS)
        icon = Image.new("RGBA", (w, h), (0, 0, 0, 255))
        icon.putalpha(alpha)
        icon.save(os.path.join(OUT, f"MenuBarIcon{suffix}.png"))
        print(f"MenuBarIcon{suffix}.png", icon.size)


if __name__ == "__main__":
    main()
