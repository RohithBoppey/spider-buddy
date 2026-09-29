"""Prepares the wall frames (left/right edges) for the app.

Writes anchors.json in wall-ready/ and wall-crawl/: per frame, the point that stays fixed
while an animation plays:
  x = the wall-side edge (so he never floats off the wall),
  y = centre of the eye (head-fixed, like the bottom crawl).

Native orientation (the app mirrors for the other wall):
  wall-ready 018/019    -> right wall (feet and hand on the right edge)
  wall-crawl 129-141    -> left wall  (129-131 crouch-to-climb, 132-141 climbing up)

The ready frame is 018 with its lower legs bent 4 px toward the wall so the feet touch it
(in the original only the hand does); it is rebuilt from frames/018.png on every run.

He always climbs head-first: climbing down uses the same frames flipped vertically (head down),
played forward. The ready pose is 018 alone, held still.

Also writes wall-crawl/_preview.gif on a left wall:
ready -> transition -> climb up -> transition back -> ready -> head-down transition -> climb down -> ready.
Run:  python3 frames-custom/wall-crawl/prepare_wall.py
"""
import json
import os

from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
READY = os.path.join(HERE, "..", "wall-ready")
EYE = {(0xD6, 0xDE, 0xD6), (0xDE, 0xDE, 0xDE), (0xA5, 0xA5, 0xA5)}   # 018/019 use #DEDEDE
CLIMB_STEP = 3          # sprite pixels per climb frame in the preview
FRAMES = os.path.join(HERE, "..", "..", "frames")
FEET_SHIFT = 4          # px the feet move toward the wall in the ready frame


def load(folder):
    names = sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".png") and not f.startswith("_"))
    return {n: Image.open(os.path.join(folder, f"{n}.png")).convert("RGBA") for n in names}


def plant_ready_feet():
    """018 with the lower legs sheared toward the wall (right side in its native orientation):
    no shift above the knees, ramping up to FEET_SHIFT at the feet."""
    src = Image.open(os.path.join(FRAMES, "018.png")).convert("RGBA")
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    ramp_top, feet_top = 27, 38   # rows: start of the bend, feet fully shifted
    for y in range(src.height):
        t = min(max((y - ramp_top) / (feet_top - ramp_top), 0), 1)
        shift = round(FEET_SHIFT * t)
        for x in range(src.width):
            px = src.getpixel((x, y))
            if px[3] and x + shift < src.width:
                out.putpixel((x + shift, y), px)
    out.save(os.path.join(READY, "018.png"))
    unused = os.path.join(READY, "019.png")   # ready pose is a single held frame
    if os.path.exists(unused):
        os.remove(unused)


def eye_y(im):
    ys = [y for y in range(im.height) for x in range(im.width)
          if im.getpixel((x, y))[3] and im.getpixel((x, y))[:3] in EYE]
    return round(sum(ys) / len(ys))


def write_anchors(folder, ims, wall_on_right):
    anchors = {n: [im.width if wall_on_right else 0, eye_y(im)] for n, im in ims.items()}
    with open(os.path.join(folder, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=2)
    return anchors


def preview(ready, ready_anchors, crawl, crawl_anchors):
    # everything on a LEFT wall: mirror the ready frame (its anchor x becomes 0)
    frames = {("ready", "018"): (ImageOps.mirror(ready["018"]), [0, ready_anchors["018"][1]])}
    for n, im in crawl.items():
        ax, ay = crawl_anchors[n]
        frames[("up", n)] = (im, [ax, ay])
        frames[("down", n)] = (ImageOps.flip(im), [ax, im.height - ay])   # head down

    rest = [("ready", "018")] * 8
    into = ["129", "130", "131"]
    cycle = [str(i) for i in range(132, 142)]
    # (frame, vertical move in sprite px before showing it: negative = up)
    seq = [(f, 0) for f in rest]
    seq += [(("up", n), 0) for n in into] + [(("up", n), -CLIMB_STEP) for n in cycle * 2]
    seq += [(("up", n), 0) for n in reversed(into)] + [(f, 0) for f in rest]
    seq += [(("down", n), 0) for n in into] + [(("down", n), CLIMB_STEP) for n in cycle * 2]
    seq += [(("down", n), 0) for n in reversed(into)] + [(f, 0) for f in rest]

    w, h, scale = 110, 190, 3
    head_y = h - 60
    out = []
    for key, dy in seq:
        head_y += dy
        im, (ax, ay) = frames[key]
        canvas = Image.new("RGBA", (w, h), (70, 70, 70, 255))
        canvas.alpha_composite(im, (2 + ax, head_y - ay))
        for y in range(h):                       # the wall (screen edge)
            canvas.putpixel((0, y), (30, 30, 30, 255))
            canvas.putpixel((1, y), (30, 30, 30, 255))
        out.append(canvas.resize((w * scale, h * scale), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
    out[0].save(os.path.join(HERE, "_preview.gif"), save_all=True, append_images=out[1:], duration=110, loop=0)


def main():
    plant_ready_feet()
    ready, crawl = load(READY), load(HERE)
    ready_anchors = write_anchors(READY, ready, wall_on_right=True)
    crawl_anchors = write_anchors(HERE, crawl, wall_on_right=False)
    preview(ready, ready_anchors, crawl, crawl_anchors)
    print("wall-ready:", ready_anchors)
    print("wall-crawl:", crawl_anchors)


if __name__ == "__main__":
    main()
