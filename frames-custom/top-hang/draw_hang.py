"""Generates the top-edge "hanging upside down on web" frames in the style of frames/.

Head and torso are frame 012 (front-facing idle) flipped vertically; legs, forearms,
hands and the web stub are drawn procedurally using only the source palette.

Run:  python3 frames-custom/top-hang/draw_hang.py
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

PAL = {
    "a": (0x21, 0x21, 0x21),  # outline
    "g": (0x63, 0x00, 0x00),  # red darkest
    "b": (0xA5, 0x00, 0x00),  # red shadow
    "c": (0xE7, 0x29, 0x21),  # red base
    "d": (0xE7, 0x5A, 0x42),  # red light
    "h": (0xF7, 0x9C, 0x94),  # red highlight
    "m": (0x00, 0x00, 0x21),  # blue darkest
    "l": (0x00, 0x00, 0x31),  # blue dark
    "i": (0x00, 0x18, 0x63),  # blue shadow
    "j": (0x00, 0x42, 0x94),  # blue base
    "k": (0x31, 0x73, 0xE7),  # blue light
    "n": (0x63, 0xA5, 0xF7),  # blue highlight
    "e": (0xA5, 0xA5, 0xA5),  # eye shade
    "f": (0xD6, 0xDE, 0xD6),  # eye white
    "w": (0xDE, 0xDE, 0xDE),  # web line, as in the game's web-swing frames (159-196)
}
RGB2KEY = {v: k for k, v in PAL.items()}

RED = ["g", "b", "c", "d"]    # dark -> light
BLUE = ["l", "i", "j", "k"]
RED_BIAS = 0.25   # user asked for slightly darker reds than a neutral shade
BLUE_BIAS = 0.45  # and darker pants, closer to the other poses

FLIP_SHADE = {"d": "b", "h": "b", "b": "c", "k": "i", "n": "j"}

CHEST_EMBLEM = True
# (dx, dy) from the chest axis; rows top->bottom are the upside-down spider:
# legs, body with legs, body, head dots
EMBLEM = {
    (-1, 0): "a", (0, 0): "b", (1, 0): "a",
    (-1, 1): "b", (0, 1): "a", (1, 1): "b",
    (0, 2): "a",
    (-1, 3): "a", (1, 3): "a",
}

W, H = 50, 66
CX = 25


class Canvas:
    def __init__(self):
        self.px = {}

    def put(self, x, y, k):
        if 0 <= x < W and 0 <= y < H:
            if k is None:
                self.px.pop((x, y), None)
            else:
                self.px[(x, y)] = k

    def paste(self, layer):
        self.px.update(layer)

    def save(self, path, scale=1):
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for (x, y), k in self.px.items():
            im.putpixel((x, y), PAL[k] + (255,))
        if scale > 1:
            im = im.resize((W * scale, H * scale), Image.NEAREST)
        im.save(path)
        return im


def outlined(fill):
    """Return fill plus a 1px outline ring (4-neighbour) as a new layer."""
    out = dict(fill)
    for (x, y) in fill:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in fill:
                out[p] = "a"
    return out


def limb(p0, p1, r0, r1, ramp, light=(-0.6, -0.8), bias=0.0):
    """Tapered capsule from p0 to p1 with radii r0..r1, cel-shaded by a light direction."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy or 1
    fill = {}
    minx, maxx = int(min(x0, x1) - max(r0, r1) - 1), int(max(x0, x1) + max(r0, r1) + 2)
    miny, maxy = int(min(y0, y1) - max(r0, r1) - 1), int(max(y0, y1) + max(r0, r1) + 2)
    for y in range(miny, maxy):
        for x in range(minx, maxx):
            t = max(0.0, min(1.0, ((x + .5 - x0) * dx + (y + .5 - y0) * dy) / L2))
            cx, cy = x0 + t * dx, y0 + t * dy
            r = r0 + (r1 - r0) * t
            ox, oy = x + .5 - cx, y + .5 - cy
            d = math.hypot(ox, oy)
            if d <= r:
                # lambert-ish: how much this surface point faces the light
                s = 0.0 if d == 0 else (ox * light[0] + oy * light[1]) / d
                s = s * min(1.0, d / max(r, .01)) - bias
                if s > 0.5:
                    k = ramp[3]
                elif s > 0.0:
                    k = ramp[2]
                elif s > -0.6:
                    k = ramp[1]
                else:
                    k = ramp[0]
                fill[(x, y)] = k
    return outlined(fill)


def load_grid(path):
    im = Image.open(path).convert("RGBA")
    g = {}
    for y in range(im.height):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if p[3]:
                g[(x, y)] = RGB2KEY[p[:3]]
    return g, im.width, im.height


def body_from_012(ox, oy, crop_bottom=41, head_tilt=0):
    """Frame 012 rows [0, crop_bottom) flipped vertically, forearms removed.

    Keeps the original head, torso and upper arms (the most hand-crafted pixels);
    upper arms end at the elbow (row 22), which lands at oy + crop_bottom - 23.
    """
    g, w, h = load_grid(os.path.join(ROOT, "frames", "012.png"))
    layer = {}
    for (x, y), k in g.items():
        if y >= crop_bottom:
            continue
        if y >= 23 and (x <= 7 or x >= 19):
            continue
        # flipping turns top-lit into bottom-lit: swap light and shadow tones
        k = FLIP_SHADE.get(k, k)
        layer[(ox + x, oy + (crop_bottom - 1 - y))] = k
    # 012 is lit from one side, which reads as a patchy chest once flipped;
    # mirror its right half (red front, blue side panel) so the torso is uniform
    # (torso rows only: the head is already symmetric and sits half a pixel off-axis)
    axis = ox + 13
    head_top = oy + crop_bottom - 1 - 10
    torso = {(x, y): k for (x, y), k in layer.items() if x >= axis and y < head_top}
    torso.update({(2 * axis - x, y): k for (x, y), k in torso.items()})
    # interior outline pixels are web/emblem detail; soften them to shadow so the chest reads plain
    for (x, y), k in list(torso.items()):
        if k == "a" and all((x + dx, y + dy) in torso for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            nb = [torso[(x + dx, y + dy)] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            torso[(x, y)] = "b" if sum(k in RED for k in nb) >= sum(k in BLUE for k in nb) else "i"
    # smooth isolated specks inside the red chest (stray blue, checkerboard shadow)
    for _ in range(2):
        for (x, y), k in list(torso.items()):
            nb = [torso.get((x + dx, y + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if k != "c" and k != "a" and sum(n == "c" for n in nb) >= 3:
                torso[(x, y)] = "c"
    shade_chest(torso, axis)
    # head tilt: shear the head rows, pivoting at the neck, up to |head_tilt| px at the crown
    last = max(y for _, y in layer)
    head = {}
    for (x, y), k in layer.items():
        if y >= head_top:
            head[(x + round(head_tilt * (y - head_top) / (last - head_top)), y)] = k
    layer = torso | head
    # close the outline where the forearms were cut off
    return outlined({p: k for p, k in layer.items() if k != "a"}) | {p: k for p, k in layer.items() if k == "a"}


def shade_chest(torso, axis):
    """Repaint the torso front as the suit's V: red chest wide at the shoulders,
    narrowing to the belt, with blue side panels — mirrored, upside down, top-lit.

    Only the run of pixels between the torso's own outline is touched, so the
    upper arms beside it keep their original pixels.
    """
    col = sorted(y for (x, y), k in torso.items() if x == axis and k in RED)
    if not col:
        return
    waist, collar = col[0], col[-1]      # belly side (top) .. collarbone side (bottom)
    span = collar - waist

    # half-width of the red V per row, as a fraction of the torso half-width
    def red_half(y, half):
        t = (y - waist) / span            # 0 at the belt, 1 at the shoulders
        return max(1, round(half * (0.25 + 0.75 * t ** 1.4)))

    pec_y = collar - 5                    # lower pec line (toward the belly when upside down)
    for y in range(waist, collar + 1):
        x0 = x1 = axis
        while torso.get((x0 - 1, y), "a") != "a":
            x0 -= 1
        while torso.get((x1 + 1, y), "a") != "a":
            x1 += 1
        half = min(axis - x0, x1 - axis)
        rh = red_half(y, half)
        for dx in range(0, half + 1):
            if dx <= rh:
                # soft, low-contrast shading: one step (c -> b / d), no hard muscle lines
                if dx == rh or y == collar:
                    k = "b"                                   # rim of the red, collarbone
                elif y == waist and dx <= rh - 1:
                    k = "d"                                   # belly faces the light
                elif y == pec_y and 3 <= dx <= rh - 1:
                    k = "b"                                   # soft shadow under the pecs
                elif y == pec_y + 1 and 2 <= dx <= rh - 2:
                    k = "d"                                   # lit top edge of the pecs
                else:
                    k = "c"
            else:
                edge = half - dx
                if edge == 0:
                    k = "l"                                   # panel's outer shadow
                elif edge == 1:
                    k = "i"
                else:
                    k = "j"
            for x in {axis - dx, axis + dx}:
                torso[(x, y)] = k

    if CHEST_EMBLEM:
        # frame 012's ~5x4 spider, made symmetric and flipped; its head end sits on the pec line
        for (dx, dy), k in EMBLEM.items():
            torso[(axis + dx, pec_y - 3 + dy)] = k


def web_stub(c, x, y0, y1):
    for y in range(y0, y1):
        c.put(x, y, "w")


def lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def leg(c, hip, knee, ankle, toe):
    """Frog-pose leg: blue thigh, blue upper shin, red boot, foot pointing up."""
    boot = lerp(knee, ankle, 0.4)
    c.paste(limb(boot, ankle, 2.4, 1.8, RED, bias=RED_BIAS))
    c.paste(limb(ankle, toe, 1.9, 1.3, RED, bias=RED_BIAS))
    c.paste(limb(knee, boot, 2.8, 2.5, BLUE, bias=BLUE_BIAS))
    c.paste(limb(hip, knee, 4.2, 3.0, BLUE, bias=BLUE_BIAS))


def frame(grip="closed", head_tilt=0, sway=0):
    """One hanging frame.

    grip:      "closed" = fists clasped on the web; "loose" = hands apart, sliding down it
    head_tilt: px the crown of the head shifts sideways (- = viewer's left)
    sway:      px the whole body swings sideways at the head, pivoting on the web anchor
    """
    c = Canvas()
    hip_y = 20
    ox = CX - 13  # body axis (ox + 13) sits on the web line
    body = body_from_012(ox, hip_y, head_tilt=head_tilt)
    elbow_y = hip_y + 40 - 23

    # right leg drawn first so the left foot crosses in front of it on the web
    leg(c, (CX + 5, hip_y + 2), (CX + 16, 14), (CX - 1, 6), (CX - 4, 2))
    leg(c, (CX - 5, hip_y + 2), (CX - 16, 14), (CX + 1, 6), (CX + 4, 2))
    c.paste(body)

    # forearms: from the original elbows, flared out slightly, fists meeting on the web
    spread = 1.5 if grip == "closed" else 3.0
    for side, ex in ((-1, CX - 9), (1, CX + 9)):
        elbow = (ex, elbow_y)
        flare = (CX + side * 7.5, 28)
        fist = (CX + side * spread, 18)
        c.paste(limb(elbow, flare, 2.0, 1.8, RED, bias=RED_BIAS))
        c.paste(limb(flare, fist, 1.8, 1.6, RED, bias=RED_BIAS))
    if grip == "closed":
        web_stub(c, CX, 0, 16)
        c.paste(limb((CX - 1.5, 16), (CX + 1.5, 16), 2.2, 2.2, RED, bias=RED_BIAS))  # clasped fists
    else:
        # hands open around the line; the web shows between them as it slides through
        for side in (-1, 1):
            c.paste(limb((CX + side * 3, 17), (CX + side * 2.5, 15), 1.8, 1.6, RED, bias=RED_BIAS))
        web_stub(c, CX, 0, 19)

    if sway:
        swayed = Canvas()
        for (x, y), k in c.px.items():
            swayed.put(x + round(sway * y / (H - 6)), y, k)
        c = swayed
    return c


def frame_h0():
    return frame()


# name -> frame; the app plays these, it does not need the order
FRAMES = {
    "hang_00": dict(),                        # H0 neutral hang, fists clasped
    "hang_01": dict(grip="loose"),            # H1 grip loosened: shown while sliding down the web
    "hang_02": dict(head_tilt=-2),            # H2 head tilt to viewer's left
    "hang_03": dict(head_tilt=2),             # H3 head tilt to viewer's right
    "hang_04": dict(sway=2),                  # H4 slight body sway around the web anchor
}

ANCHOR = (CX, 0)  # where the app attaches the web line, identical in every frame


def compare_sheet(frames, path, scale=6):
    """Existing frames beside the new ones, same scale, for style review."""
    refs = [Image.open(os.path.join(ROOT, "frames", f"{i:03d}.png")).convert("RGBA") for i in (12, 0, 130)]
    ims = refs + frames
    gap = 4
    sw = sum(im.width + gap for im in ims)
    sh = max(im.height for im in ims)
    sheet = Image.new("RGBA", (sw, sh), (70, 70, 70, 255))
    x = 0
    for im in ims:
        sheet.alpha_composite(im, (x, sh - im.height if im in refs else 0))
        x += im.width + gap
    sheet.resize((sw * scale, sh * scale), Image.NEAREST).save(path)


def preview_gif(frames, path, scale=3):
    """Simulates the app: web line from the screen's top edge, a short drop, then idle."""
    bw, bh = W + 30, H + 70
    top_bar = 3
    seq = [("hang_00", 0)] * 8
    seq += [("hang_01", d) for d in range(2, 34, 2)]            # web extends, he slides down
    drop = 32
    seq += [("hang_00", drop)] * 6
    seq += [("hang_02", drop)] * 7 + [("hang_00", drop)] * 3
    seq += [("hang_03", drop)] * 7 + [("hang_00", drop)] * 3
    seq += [("hang_04", drop)] * 4 + [("hang_00", drop)] * 4
    out = []
    for name, d in seq:
        im = Image.new("RGBA", (bw, bh), (70, 70, 70, 255))
        for x in range(bw):                                      # the screen's top edge
            for y in range(top_bar):
                im.putpixel((x, y), (30, 30, 30, 255))
        ox, oy = bw // 2 - ANCHOR[0], top_bar + 4 + d
        for y in range(top_bar, oy + ANCHOR[1]):                 # web drawn by the app
            im.putpixel((ox + ANCHOR[0], y), PAL["w"] + (255,))
        im.alpha_composite(frames[name], (ox, oy))
        out.append(im.resize((bw * scale, bh * scale), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
    out[0].save(path, save_all=True, append_images=out[1:], duration=100, loop=0)


if __name__ == "__main__":
    ims = {}
    for name, kw in FRAMES.items():
        frame(**kw).save(os.path.join(HERE, f"{name}.png"))
        ims[name] = Image.open(os.path.join(HERE, f"{name}.png")).convert("RGBA")
    compare_sheet(list(ims.values()), os.path.join(HERE, "_preview.png"))
    compare_sheet([ims["hang_00"]], os.path.join(HERE, "_compare.png"))
    preview_gif(ims, os.path.join(HERE, "_preview.gif"))
    print("ok")
