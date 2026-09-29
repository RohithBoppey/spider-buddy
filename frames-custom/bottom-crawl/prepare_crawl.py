"""Prepares the bottom-edge crawl frames for the app.

- Splits frames/095.png (two poses ripped side by side) into 095a.png and 095b.png.
- Writes anchors.json: per frame, the point that stays fixed while the loop plays:
  x = centre of the eye (head-fixed alignment), y = bottom row (hands and feet on the ground).
- Writes _preview.gif: the loop aligned on those anchors.

All frames face right; the app mirrors them for crawling left.
Run:  python3 frames-custom/bottom-crawl/prepare_crawl.py
"""
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.abspath(os.path.join(HERE, "..", "..", "frames"))
EYE = {(0xD6, 0xDE, 0xD6), (0xA5, 0xA5, 0xA5)}
SPLIT_095_AT = 62   # column between the two poses in 095


def split_095():
    im = Image.open(os.path.join(FRAMES, "095.png")).convert("RGBA")
    for suffix, box in (("a", (0, 0, SPLIT_095_AT, im.height)), ("b", (SPLIT_095_AT, 0, im.width, im.height))):
        part = im.crop(box)
        part.crop(part.getbbox()).save(os.path.join(HERE, f"095{suffix}.png"))
    merged = os.path.join(HERE, "095.png")
    if os.path.exists(merged):
        os.remove(merged)


def eye_x(im):
    xs = [x for y in range(im.height) for x in range(im.width)
          if im.getpixel((x, y))[3] and im.getpixel((x, y))[:3] in EYE]
    return round(sum(xs) / len(xs))


def main():
    split_095()
    names = sorted(f[:-4] for f in os.listdir(HERE) if f.endswith(".png") and not f.startswith("_"))
    ims = {n: Image.open(os.path.join(HERE, f"{n}.png")).convert("RGBA") for n in names}
    anchors = {n: [eye_x(im), im.height] for n, im in ims.items()}
    with open(os.path.join(HERE, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=2)

    # preview: 088 (landing/rest) then the crawl cycle three times, head fixed, feet on the ground
    cycle = [n for n in names if n != "088"]
    seq = ["088"] * 5 + cycle * 3
    w, h, scale = 200, 40, 4
    out = []
    for n in seq:
        im, (ax, ay) = ims[n], anchors[n]
        canvas = Image.new("RGBA", (w, h), (70, 70, 70, 255))
        canvas.alpha_composite(im, (120 - ax, h - 2 - ay))
        for x in range(w):
            canvas.putpixel((x, h - 2), (30, 30, 30, 255))
            canvas.putpixel((x, h - 1), (30, 30, 30, 255))
        out.append(canvas.resize((w * scale, h * scale), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
    out[0].save(os.path.join(HERE, "_preview.gif"), save_all=True, append_images=out[1:], duration=120, loop=0)
    print("anchors:", anchors)


if __name__ == "__main__":
    main()
