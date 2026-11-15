"""Draws the Vela app icon: a sailfish's raised dorsal fin breaking the water.

Needs Pillow. Run from anywhere:

    python make_icon.py

It writes icon-1024.png into the app's asset catalog.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 3  # draw at three times the size, then shrink, for smooth edges
W = SIZE * SS
OUT = Path(__file__).resolve().parent.parent / "Vela/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(round(lerp(a, b, t)) for a, b in zip(c1, c2))


def vertical_gradient(top, bottom, y0=0, y1=W):
    img = Image.new("RGB", (W, W))
    px = ImageDraw.Draw(img)
    for y in range(W):
        t = min(1, max(0, (y - y0) / (y1 - y0)))
        px.line([(0, y), (W, y)], fill=mix(top, bottom, t))
    return img


def s(v):
    """Icon units (0 to 1024) to drawing pixels."""
    return v * SS


# --- the fish's back: a shallow arc the fin stands on
def back_y(x):
    # highest near the middle, slipping under the water at both ends
    t = (x - 70) / (960 - 70)
    return 796 - 84 * math.sin(math.pi * min(1, max(0, t)) ** 0.95)


FIN_X0, FIN_X1 = 138, 872
FIN_HEIGHT = 556
RAYS = 26

# The sail's outline as (position along the back, height). A steep leading edge,
# tallest a little ahead of the middle, then a long ragged fall toward the tail.
PROFILE = [
    (0.00, 0.00), (0.02, 0.52), (0.06, 0.82), (0.13, 0.94), (0.24, 1.00), (0.35, 0.97),
    (0.46, 0.88), (0.57, 0.73), (0.67, 0.56), (0.76, 0.41), (0.85, 0.29), (0.92, 0.20), (0.97, 0.11), (1.00, 0.00),
]
# Each ray ends a little higher or lower than its neighbours, as on the real fin.
RAGGED = [0.0, 0.02, -0.01, 0.03, -0.02, 0.01, 0.04, -0.03, 0.02, 0.0, -0.04, 0.03, 0.01,
          -0.02, 0.04, -0.01, -0.05, 0.03, 0.0, -0.03, 0.05, -0.02, 0.02, -0.04, 0.03, 0.0, 0.0]


def fin_height(t):
    for (t0, h0), (t1, h1) in zip(PROFILE, PROFILE[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)  # ease between the points
            return FIN_HEIGHT * lerp(h0, h1, u)
    return 0.0


def ray(t, ragged=0.0):
    """Base and tip of the ray at position t along the fin."""
    x = lerp(FIN_X0, FIN_X1, t)
    base = (x, back_y(x))
    h = fin_height(t) * (1 + ragged)
    lean = lerp(0.12, 0.30, t)  # rays sweep back more toward the tail
    return base, (x + lean * h, base[1] - h)


def ray_at(i):
    return ray(i / RAYS, RAGGED[i % len(RAGGED)] if 0 < i < RAYS else 0.0)


def fin_outline():
    pts = []
    for i in range(RAYS + 1):
        base, tip = ray_at(i)
        if i == 0:
            pts.append(base)
        pts.append(tip)
        if i < RAYS:  # the membrane dips a little between ray tips
            _, nxt = ray_at(i + 1)
            mid = ((tip[0] + nxt[0]) / 2, (tip[1] + nxt[1]) / 2 + 11)
            pts.append(mid)
    # back along the base
    for i in range(40, -1, -1):
        x = lerp(FIN_X0, FIN_X1, i / 40)
        pts.append((x, back_y(x) + 6))
    return [(s(x), s(y)) for x, y in pts]


def main():
    # sky: deep navy, a little lighter toward the horizon
    icon = vertical_gradient((6, 22, 40), (16, 58, 92), 0, s(800))

    # the fin, bright against the dark sky
    outline = fin_outline()
    fin_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(fin_mask).polygon(outline, fill=255)
    fin_fill = vertical_gradient((104, 214, 255), (30, 70, 210), s(140), s(760))
    icon.paste(fin_fill, (0, 0), fin_mask)

    overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    # dark spots, in loose rows like the real sail
    for row, (frac, size) in enumerate([(0.26, 14), (0.47, 12), (0.66, 9)]):
        for i in range(2, RAYS - 1):
            if (i + row * 2) % 3:
                continue
            t = (i + 0.5) / RAYS
            base, tip = ray(t)
            if fin_height(t) < 250:
                continue
            x, y = lerp(base[0], tip[0], frac), lerp(base[1], tip[1], frac)
            r = size * (0.75 + 0.25 * math.sin(i * 1.7))
            d.ellipse([s(x - r), s(y - r * 1.25), s(x + r), s(y + r * 1.25)], fill=(10, 30, 96, 150))

    # the rays
    for i in range(RAYS + 1):
        base, tip = ray_at(i)
        d.line([(s(base[0]), s(base[1])), (s(tip[0]), s(tip[1]))], fill=(235, 248, 255, 135), width=s(3))

    # a light rim along the top edge
    top_edge = outline[: 2 * RAYS + 2]
    d.line(top_edge, fill=(224, 244, 255, 235), width=s(7), joint="curve")
    overlay.putalpha(Image.composite(overlay.getchannel("A"), Image.new("L", (W, W), 0), fin_mask.filter(ImageFilter.MaxFilter(2 * SS * 3 + 1))))
    icon = Image.alpha_composite(icon.convert("RGBA"), overlay)

    # the fish's back, a dark sliver under the fin
    d = ImageDraw.Draw(icon)
    back = [(s(x), s(back_y(x))) for x in range(70, 961, 6)]
    belly = [(s(x), s(back_y(x) + 150)) for x in range(960, 69, -6)]
    d.polygon(back + belly, fill=(10, 30, 56, 255))
    d.line(back, fill=(86, 140, 190, 255), width=s(5), joint="curve")

    # the tip of the tail, a slim blade standing out of the water behind the fin
    tail = [(912, 800), (938, 706), (982, 618), (968, 712), (956, 800)]
    d.polygon([(s(x), s(y)) for x, y in tail], fill=(10, 30, 56, 255))
    d.line([(s(x), s(y)) for x, y in tail[:3]], fill=(86, 140, 190, 255), width=s(4), joint="curve")

    # the sea, with a gentle swell, covering the rest of the fish
    def sea_y(x):
        return 772 + 11 * math.sin(x / 92 + 0.6) + 5 * math.sin(x / 37)

    sea = vertical_gradient((20, 150, 170), (8, 70, 104), s(770), s(1024)).convert("RGBA")
    sea_mask = Image.new("L", (W, W), 0)
    surface = [(s(x), s(sea_y(x))) for x in range(-10, 1035, 6)]
    ImageDraw.Draw(sea_mask).polygon(surface + [(W, W), (0, W)], fill=255)
    icon.paste(sea, (0, 0), sea_mask)

    d = ImageDraw.Draw(icon)
    d.line(surface, fill=(190, 240, 245, 255), width=s(6), joint="curve")
    # two lighter streaks of water further down
    for dy, x0, x1, alpha in [(70, 150, 520, 120), (135, 470, 900, 90)]:
        streak = [(s(x), s(sea_y(x * 1.3) + dy)) for x in range(x0, x1, 6)]
        d.line(streak, fill=(170, 230, 238, alpha), width=s(5), joint="curve")

    icon.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
