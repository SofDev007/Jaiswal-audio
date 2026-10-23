"""Renders the JARX intro-animation options as MP4 previews.

Each frame is drawn with Pillow at 2x resolution and downsampled (smooth
edges), then piped to ffmpeg (libx264). Uses only Pillow, numpy, ffmpeg and
Windows' Segoe UI fonts; no network.

    python make_intro_videos.py            # all options
    python make_intro_videos.py A C        # some of them

These are previews of motion design. In the app the chosen animation would be
drawn in Flutter code, not played as a video.
"""
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS, SS = 720, 1280, 60, 2  # output size, frame rate, supersampling
SW, SH = W * SS, H * SS
INK = (14, 14, 16)
PULSE = (255, 77, 46)
PAPER = (245, 245, 245)
OUT = Path(__file__).parent

U = 4.2 * SS                     # px per mark unit (mark is drawn on a 120 grid)
CX, CY = SW / 2, 560 * SS        # where the mark's centre (60, 60) lands
STROKE = 10 * U                  # stroke width in px

FONT_WORD = ImageFont.truetype("C:/Windows/Fonts/seguibl.ttf", 104 * SS)
FONT_TAG = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 20 * SS)

# The J1 mark: pulse bar, then stem, then the hook (arc centre (68,78), r 20).
PULSE_PART = [(32, 38), (46, 38), (53, 22), (62, 54), (68, 38), (88, 38)]
ARC = [(68 + 20 * math.cos(a), 78 + 20 * math.sin(a))
       for a in np.linspace(0, math.pi, 48)[1:]]
STEM_PART = [(88, 38), (88, 78)] + ARC
MARK = PULSE_PART + STEM_PART[1:]


# ── easing ──────────────────────────────────────────────────────────────────
def clamp01(x): return max(0.0, min(1.0, x))
def seg(t, a, b): return clamp01((t - a) / (b - a))
def in_out_cubic(x): return 4 * x ** 3 if x < .5 else 1 - (-2 * x + 2) ** 3 / 2
def out_cubic(x): return 1 - (1 - x) ** 3
def out_back(x, c=1.6): return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2
def lerp(a, b, x): return a + (b - a) * x
def mix(c1, c2, x): return tuple(int(lerp(a, b, x)) for a, b in zip(c1, c2))


# ── geometry ────────────────────────────────────────────────────────────────
def px(p, k=1.0, dy=0.0):
    """Mark units → supersampled pixels, scaled by k around the mark centre."""
    return (CX + (p[0] - 60) * U * k, CY + (p[1] - 60 + dy) * U * k)


def partial(points, f):
    """The first fraction f (by length) of a polyline."""
    if f >= 1:
        return list(points)
    if f <= 0:
        return points[:1]
    lens = [math.dist(a, b) for a, b in zip(points, points[1:])]
    target, out = f * sum(lens), [points[0]]
    for (a, b), l in zip(zip(points, points[1:]), lens):
        if target <= l:
            r = target / l if l else 0
            out.append((lerp(a[0], b[0], r), lerp(a[1], b[1], r)))
            return out
        out.append(b)
        target -= l
    return out


def stroke(draw, pts, width, color):
    if len(pts) >= 2:
        draw.line(pts, fill=color, width=int(width), joint="curve")
    for p in (pts[0], pts[-1]):
        r = width / 2
        draw.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=color)


# ── frame ───────────────────────────────────────────────────────────────────
class Frame:
    def __init__(self):
        self.img = Image.new("RGB", (SW, SH), INK)
        self.draw = ImageDraw.Draw(self.img)
        g = 4  # glow is drawn at 1/4 resolution and blurred
        self.glow = Image.new("L", (SW // g, SH // g), 0)
        self.gdraw = ImageDraw.Draw(self.glow)
        self.g = g

    def mark(self, pts_units, k=1.0, color=PULSE, width=STROKE, glow=0.0):
        pts = [px(p, k) for p in pts_units]
        if glow > 0:
            stroke(self.gdraw, [(x / self.g, y / self.g) for x, y in pts],
                   width * 1.6 / self.g, int(255 * clamp01(glow)))
        stroke(self.draw, pts, width * k, color)

    def dot_glow(self, p_units, radius_units, amount):
        x, y = px(p_units)
        r = radius_units * U / self.g
        x, y = x / self.g, y / self.g
        self.gdraw.ellipse((x - r, y - r, x + r, y + r), fill=int(255 * clamp01(amount)))

    def word(self, t, start, drop=28, from_above=False):
        """JARX letters fading in one after another, then the full name."""
        letters, track = "JARX", 14 * SS
        widths = [FONT_WORD.getlength(ch) for ch in letters]
        x = SW / 2 - (sum(widths) + track * 3) / 2
        y0 = 800 * SS
        for i, ch in enumerate(letters):
            a = out_cubic(seg(t, start + i * 0.07, start + i * 0.07 + 0.4))
            if a > 0:
                off = (1 - a) * drop * SS * (-1 if from_above else 1)
                self.draw.text((x, y0 + off), ch, font=FONT_WORD, fill=mix(INK, PAPER, a))
            x += widths[i] + track

    def tagline(self, t, start):
        a = out_cubic(seg(t, start, start + 0.5))
        if a <= 0:
            return
        text, track = "JAISWAL AUDIO RESPONSE EXPERIENCE", 5 * SS
        widths = [FONT_TAG.getlength(ch) for ch in text]
        x = SW / 2 - (sum(widths) + track * (len(text) - 1)) / 2
        for ch, w in zip(text, widths):
            self.draw.text((x, 950 * SS), ch, font=FONT_TAG, fill=mix(INK, PAPER, 0.72 * a))
            x += w + track

    def finish(self):
        if self.glow.getbbox():
            blur = self.glow.filter(ImageFilter.GaussianBlur(9)).resize((SW, SH), Image.BILINEAR)
            m = np.asarray(blur, dtype=np.float32)[..., None] / 255 * 0.85
            arr = np.asarray(self.img, dtype=np.float32)
            arr = arr + m * (np.array(PULSE, np.float32) - arr * 0.35)
            self.img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        return self.img.resize((W, H), Image.LANCZOS).tobytes()


def beat(t, start, length=0.36):
    """Scale and glow of one heartbeat on the finished mark."""
    s = math.sin(math.pi * seg(t, start, start + length))
    return 1 + 0.06 * s, 0.35 + 0.65 * s


# ── options ─────────────────────────────────────────────────────────────────
def option_a(t):
    """A · Pulse draw: the J is drawn in one stroke, then beats once."""
    f = Frame()
    if t < 0.3:  # a spark appears where the stroke will start
        a = out_cubic(seg(t, 0, 0.3))
        f.mark([MARK[0], MARK[0]], color=mix(INK, PULSE, a), glow=a)
    draw = in_out_cubic(seg(t, 0.3, 1.5))
    if t >= 0.3:
        k, g = beat(t, 1.5)
        pts = partial(MARK, draw)
        f.mark(pts, k=k if draw >= 1 else 1, glow=g if draw >= 1 else 0.45)
        if draw < 1:
            f.dot_glow(pts[-1], 9, 0.9)
    f.word(t, 1.75)
    f.tagline(t, 2.2)
    return f.finish()


def option_b(t):
    """B · Heartbeat: a flat line carries a pulse in, the line folds into the J."""
    f = Frame()
    left, right = 60 - (SW / 2) / U - 4, 60 + (SW / 2) / U + 4
    xs = lerp(-70, 46, out_cubic(seg(t, 0.15, 1.15)))
    trim = in_out_cubic(seg(t, 1.1, 1.55))
    l, r = lerp(left, 32, trim), lerp(right, 88, trim)
    spike = [(xs, 38), (xs + 7, 22), (xs + 16, 54), (xs + 22, 38)]
    line = [(l, 38)] + [p for p in spike if l <= p[0] <= r or p[1] != 38] + [(r, 38)]
    a = out_cubic(seg(t, 0, 0.25))
    stem = partial(STEM_PART, in_out_cubic(seg(t, 1.55, 2.05)))
    k, g = beat(t, 2.05)
    done = t >= 2.05
    color = mix(INK, PULSE, a)
    f.mark(line + (stem[1:] if t >= 1.55 else []), k=k if done else 1,
           color=color, glow=g if done else 0.35 * a)
    f.word(t, 2.25)
    f.tagline(t, 2.7)
    return f.finish()


def option_c(t):
    """C · Ripple reveal: response rings spread, the mark springs in."""
    f = Frame()
    for i in range(3):
        e = seg(t, 0.05 + i * 0.18, 1.15 + i * 0.18)
        if 0 < e < 1:
            rad = lerp(18, 100, out_cubic(e)) * U
            col = mix(INK, PULSE, 0.75 * (1 - e) ** 1.5)
            w = max(2, int(1.4 * U))
            f.draw.ellipse((CX - rad, CY - rad, CX + rad, CY + rad), outline=col, width=w)
    s = seg(t, 0.25, 0.95)
    if s > 0:
        k = 0.35 + 0.65 * out_back(s)
        flash = math.sin(math.pi * seg(t, 0.85, 1.3))
        f.mark(MARK, k=k, color=mix(INK, PULSE, out_cubic(seg(t, 0.25, 0.5))),
               glow=0.35 + 0.65 * flash)
    f.word(t, 1.05, drop=34, from_above=True)
    f.tagline(t, 1.5)
    return f.finish()


def option_d(t):
    """D · Sound bars: an equalizer plays, then folds into the J."""
    f = Frame()
    collapse = in_out_cubic(seg(t, 0.95, 1.35))
    if collapse < 1:
        for i, x in enumerate([36, 48, 60, 72, 84]):
            h = 46 * (0.3 + 0.7 * abs(math.sin(2 * math.pi * 1.6 * t + i * 1.1)))
            h *= (1 - collapse) * out_cubic(seg(t, 0, 0.3))
            x0, y0 = px((x - 3.5, 60 - h / 2))
            x1, y1 = px((x + 3.5, 60 + h / 2))
            if y1 - y0 > x1 - x0:  # fade out before a bar shrinks into a dot
                f.draw.rounded_rectangle((x0, y0, x1, y1), radius=(x1 - x0) / 2,
                                         fill=mix(INK, PULSE, 1 - collapse ** 2))
    if t >= 1.0:
        p = partial(PULSE_PART, in_out_cubic(seg(t, 1.0, 1.5)))
        stem = partial(STEM_PART, in_out_cubic(seg(t, 1.45, 2.0)))
        k, g = beat(t, 2.0)
        done = t >= 2.0
        f.mark(p + (stem[1:] if t >= 1.45 else []), k=k if done else 1,
               glow=g if done else 0.4)
    f.word(t, 2.15)
    f.tagline(t, 2.6)
    return f.finish()


OPTIONS = {
    "A": ("jarx-intro-A-pulse-draw.mp4", option_a, 3.3),
    "B": ("jarx-intro-B-heartbeat.mp4", option_b, 3.5),
    "C": ("jarx-intro-C-ripple-reveal.mp4", option_c, 2.9),
    "D": ("jarx-intro-D-sound-bars.mp4", option_d, 3.3),
}


def render(key):
    name, fn, seconds = OPTIONS[key]
    out = OUT / name
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", str(out)],
        stdin=subprocess.PIPE)
    for i in range(int(seconds * FPS)):
        ff.stdin.write(fn(i / FPS))
    ff.stdin.close()
    if ff.wait() != 0:
        raise SystemExit(f"ffmpeg failed for {name}")
    print(f"{name}: {seconds}s, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    for k in (sys.argv[1:] or OPTIONS):
        render(k.upper())
