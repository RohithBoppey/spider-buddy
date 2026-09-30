"""Builds the app icon from spiderman-logo.jpg.

The logo (square, black background) is fitted into the standard macOS icon plate: an 824 px
rounded square with a soft shadow on a 1024 px canvas. Every size macOS needs is written to
an .iconset and packed into app/Resources/AppIcon.icns with `iconutil`.
Run:  python3 app/icons/make_app_icon.py   (needs Pillow; iconutil ships with macOS)
"""
import math
import os
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "spiderman-logo.jpg")
ICNS = os.path.join(HERE, "..", "Resources", "AppIcon.icns")
N, PLATE, SS = 1024, 824, 2


def squircle(size, offset, n=5.0, steps=720):
    r = size / 2
    return [(offset + r + r * math.copysign(abs(math.cos(t)) ** (2 / n), math.cos(t)),
             offset + r + r * math.copysign(abs(math.sin(t)) ** (2 / n), math.sin(t)))
            for t in (2 * math.pi * i / steps for i in range(steps))]


def icon_1024():
    size, plate, off = N * SS, PLATE * SS, (N - PLATE) * SS // 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shape = squircle(plate, off)
    shadow = Image.new("L", img.size, 0)
    ImageDraw.Draw(shadow).polygon([(x, y + 10 * SS) for x, y in shape], fill=110)
    img.paste(Image.new("RGBA", img.size, (0, 0, 0, 255)), mask=shadow.filter(ImageFilter.GaussianBlur(14 * SS)))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(shape, fill=255)
    logo = Image.new("RGBA", img.size, (0, 0, 0, 255))
    logo.paste(Image.open(SOURCE).convert("RGBA").resize((plate, plate), Image.LANCZOS), (off, off))
    img.paste(logo, mask=mask)
    return img.resize((N, N), Image.LANCZOS)


def main():
    icon = icon_1024()
    icon.save(os.path.join(HERE, "AppIcon-1024.png"))
    iconset = os.path.join(HERE, "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", ICNS], check=True)
    shutil.rmtree(iconset)
    print("wrote", os.path.normpath(ICNS))


if __name__ == "__main__":
    main()
