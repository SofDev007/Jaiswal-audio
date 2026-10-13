"""Render JARX splash-animation options as MP4 (1080x1920, 60 fps).

Brand (from jarx-j1-refined.html): ink #0E0E10, pulse #FF4D2E, paper #F5F5F5.
Mark path (120 grid): M32 38 L46 38 L53 22 L62 54 L68 38 L88 38 L88 78 A20 20 0 0 1 48 78
"""
import math, subprocess, sys
import numpy as np
import cairo
from PIL import Image, ImageFilter

W, H, FPS = 1080, 1920, 60
INK = (0x0E / 255, 0x0E / 255, 0x10 / 255)
PULSE = (1.0, 0x4D / 255, 0x2E / 255)
PAPER = (0xF5 / 255,) * 3
STROKE = 10.0
TAGLINE = "JAISWAL AUDIO RESPONSE EXPERIENCE"

# ---------- easing ----------
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def seg(t, a, b): return clamp((t - a) / (b - a))
def e_io3(x): return 4 * x ** 3 if x < .5 else 1 - (-2 * x + 2) ** 3 / 2
def e_o3(x): return 1 - (1 - x) ** 3
def e_o5(x): return 1 - (1 - x) ** 5
def e_oback(x, s=1.7):
    x -= 1
    return x * x * ((s + 1) * x + s) + 1
def lerp(a, b, x): return a + (b - a) * x

# ---------- mark path sampling (mark units) ----------
def sample_mark():
    pts = []
    lines = [(32, 38), (46, 38), (53, 22), (62, 54), (68, 38), (88, 38), (88, 78)]
    for (x0, y0), (x1, y1) in zip(lines, lines[1:]):
        n = max(2, int(math.hypot(x1 - x0, y1 - y0) * 4))
        for i in range(n):
            pts.append((x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n))
    # arc centre (68,78) r 20, from angle 0 to pi (clockwise on screen = bottom half)
    n = 260
    for i in range(n + 1):
        a = math.pi * i / n
        pts.append((68 + 20 * math.cos(a), 78 + 20 * math.sin(a)))
    return pts

def cumlen(pts):
    c = [0.0]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.append(c[-1] + math.hypot(x1 - x0, y1 - y0))
    return c

MARK = sample_mark()
MARK_C = cumlen(MARK)
MARK_LEN = MARK_C[-1]

def point_at(pts, c, L):
    L = clamp(L, 0, c[-1])
    lo, hi = 0, len(c) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if c[mid] <= L: lo = mid
        else: hi = mid
    span = c[hi] - c[lo] or 1
    f = (L - c[lo]) / span
    (x0, y0), (x1, y1) = pts[lo], pts[hi]
    return x0 + (x1 - x0) * f, y0 + (y1 - y0) * f

def sub_path(pts, c, L0, L1):
    if L1 <= L0: return []
    out = [point_at(pts, c, L0)]
    out += [p for p, l in zip(pts, c) if L0 < l < L1]
    out.append(point_at(pts, c, L1))
    return out

# ---------- drawing helpers ----------
class Xf:
    """mark units -> screen px: centre (60,60) at (cx,cy), scale s"""
    def __init__(self, cx, cy, s): self.cx, self.cy, self.s = cx, cy, s
    def __call__(self, x, y): return self.cx + (x - 60) * self.s, self.cy + (y - 60) * self.s

def stroke_poly(ctx, pts, xf, width_px, rgb, alpha=1.0):
    if len(pts) < 2: return
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_width(width_px)
    ctx.set_source_rgba(*rgb, alpha)
    ctx.move_to(*xf(*pts[0]))
    for p in pts[1:]: ctx.line_to(*xf(*p))
    ctx.stroke()

def dot(ctx, x, y, r, rgb, a=1.0):
    ctx.set_source_rgba(*rgb, a)
    ctx.arc(x, y, r, 0, 2 * math.pi)
    ctx.fill()

def text_tracked(ctx, s, cx, baseline, size, bold, rgb, alpha, tracking_em, per_char=None):
    """centred text with letter-spacing; per_char(i) -> (dy, alpha_mult)"""
    ctx.select_font_face("Poppins", cairo.FONT_SLANT_NORMAL,
                         cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(size)
    tr = tracking_em * size
    adv = [ctx.text_extents(ch).x_advance for ch in s]
    total = sum(adv) + tr * (len(s) - 1)
    x = cx - total / 2
    for i, ch in enumerate(s):
        dy, am = per_char(i) if per_char else (0, 1)
        ctx.set_source_rgba(*rgb, alpha * am)
        ctx.move_to(x, baseline + dy)
        ctx.show_text(ch)
        x += adv[i] + tr
    return total

def fit_size(ctx, s, size, tracking_em, max_w, bold=False):
    ctx.select_font_face("Poppins", cairo.FONT_SLANT_NORMAL,
                         cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    while size > 10:
        ctx.set_font_size(size)
        w = sum(ctx.text_extents(ch).x_advance for ch in s) + tracking_em * size * (len(s) - 1)
        if w <= max_w: return size
        size -= 1
    return size

# ---------- frame composition ----------
GS = 4  # glow layer downscale

class Frame:
    def __init__(self):
        self.base = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
        self.ctx = cairo.Context(self.base)
        self.ctx.set_source_rgb(*INK); self.ctx.paint()
        self.gsurf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W // GS, H // GS)
        self.g = cairo.Context(self.gsurf)
        self.g.scale(1 / GS, 1 / GS)
        self.glow_amt = 0.0

    def finish(self):
        img = np.ndarray((H, W, 4), np.uint8, self.base.get_data()).copy()
        rgb = img[:, :, [2, 1, 0]].astype(np.float32)
        if self.glow_amt > 0.001:
            g = np.ndarray((H // GS, W // GS, 4), np.uint8, self.gsurf.get_data()).copy()
            gi = Image.fromarray(g[:, :, [2, 1, 0]])
            gi = gi.filter(ImageFilter.GaussianBlur(9)).resize((W, H), Image.BILINEAR)
            rgb = rgb + np.asarray(gi, np.float32) * self.glow_amt
        return np.clip(rgb, 0, 255).astype(np.uint8).tobytes()

def final_layout_text(fr, t0, style="rise", alpha_all=1.0, cy_text=1215):
    """wordmark + tagline; t0 = seconds since text start"""
    ctx = fr.ctx
    size = 150
    if style == "rise":
        def pc(i):
            x = e_o3(seg(t0, i * 0.07, i * 0.07 + 0.45))
            return (lerp(46, 0, x), x)
        text_tracked(ctx, "JARX", W / 2, cy_text, size, True, PAPER, alpha_all, 0.12, pc)
    elif style == "track":
        x = e_o5(seg(t0, 0, 0.7))
        text_tracked(ctx, "JARX", W / 2, cy_text, size, True, PAPER, alpha_all * x, lerp(0.75, 0.12, x))
    elif style == "fade":
        x = e_o3(seg(t0, 0, 0.5))
        text_tracked(ctx, "JARX", W / 2, cy_text + lerp(20, 0, x), size, True, PAPER, alpha_all * x, 0.12)
    elif style == "wipe":
        x = e_io3(seg(t0, 0, 0.55))
        ctx.save()
        half = 330 * x
        ctx.rectangle(W / 2 - half, cy_text - 160, half * 2, 220); ctx.clip()
        text_tracked(ctx, "JARX", W / 2, cy_text, size, True, PAPER, alpha_all, 0.12)
        ctx.restore()
    tx = e_o3(seg(t0, 0.45, 0.95))
    ts = fit_size(ctx, TAGLINE, 30, 0.2, 880)
    text_tracked(ctx, TAGLINE, W / 2, cy_text + 78 + lerp(10, 0, tx), ts, False, PAPER, 0.62 * tx * alpha_all, 0.2)

def draw_mark_full(fr, xf, alpha=1.0, glow=True):
    w = STROKE * xf.s
    stroke_poly(fr.ctx, MARK, xf, w, PULSE, alpha)
    if glow: stroke_poly(fr.g, MARK, xf, w * 1.3, PULSE, alpha)

# ---------- options ----------
MARK_CY = 790
MARK_S = 5.0

def opt_draw(t):
    """A · Draw-on: the stroke writes itself, head glows, wordmark letters rise."""
    fr = Frame()
    xf = Xf(W / 2, MARK_CY, MARK_S)
    p = e_io3(seg(t, 0.15, 1.35))
    L = p * MARK_LEN
    w = STROKE * xf.s
    sp = sub_path(MARK, MARK_C, 0, L)
    stroke_poly(fr.ctx, sp, xf, w, PULSE)
    stroke_poly(fr.g, sp, xf, w * 1.3, PULSE)
    if 0 < p < 1:
        hx, hy = xf(*point_at(MARK, MARK_C, L))
        dot(fr.ctx, hx, hy, w * 0.32, PAPER, 0.95)
        dot(fr.g, hx, hy, w * 1.1, PAPER, 1)
    bloom = math.exp(-((t - 1.38) / 0.16) ** 2)
    fr.glow_amt = 0.55 + 0.9 * bloom
    if t > 1.2: final_layout_text(fr, t - 1.2, "rise")
    return fr.finish()

def opt_heartbeat(t):
    """B · Heartbeat: mark pops in, beats twice (lub-dub) with ripple rings."""
    fr = Frame()
    a = e_o3(seg(t, 0.1, 0.45))
    sc = lerp(0.55, 1.0, e_oback(seg(t, 0.1, 0.55), 1.4))
    def beat(t0, amp, dur=0.22):
        x = seg(t, t0, t0 + dur)
        return amp * math.sin(math.pi * x) if 0 < x < 1 else 0.0
    b1, b2 = beat(0.75, 0.085), beat(1.0, 0.05)
    s = MARK_S * sc * (1 + b1 + b2)
    xf = Xf(W / 2, MARK_CY, s)
    ctx = fr.ctx
    for t0, amp in ((0.75, 0.42), (1.0, 0.26)):
        x = seg(t, t0, t0 + 0.9)
        if 0 < x < 1:
            r = lerp(190, 560, e_o3(x))
            ctx.set_line_width(lerp(14, 2, x))
            ctx.set_source_rgba(*PULSE, amp * (1 - x) ** 1.5)
            ctx.arc(W / 2, MARK_CY, r, 0, 2 * math.pi); ctx.stroke()
    draw_mark_full(fr, xf, a)
    fr.glow_amt = a * (0.45 + 6 * (b1 + b2))
    if t > 1.25: final_layout_text(fr, t - 1.25, "fade")
    return fr.finish()

def opt_ekg(t):
    """C · Flatline to life: an oscilloscope line sweeps in, spikes into the mark."""
    fr = Frame()
    xf = Xf(W / 2, MARK_CY, MARK_S)
    lead_x0 = 60 - (W / 2 + 80) / MARK_S       # off-screen left, in mark units
    lead = [(lead_x0 + (32 - lead_x0) * i / 300, 38) for i in range(301)]
    full = lead[:-1] + MARK
    c = cumlen(full)
    LEAD = c[len(lead) - 1]
    p = e_io3(seg(t, 0.05, 1.5))
    L = p * c[-1]
    w = STROKE * xf.s
    ctx = fr.ctx
    # phosphor trail on the lead-in: thin, fades with distance behind head and over time
    fade_all = 1 - seg(t, 0.85, 1.25)
    for i in range(len(lead) - 1):
        l = c[i]
        if l > L: break
        behind = (min(L, LEAD) - l) + max(0, L - LEAD) * 0.6
        a = math.exp(-behind / 55) * fade_all
        if a < 0.01: continue
        (x0, y0), (x1, y1) = xf(*lead[i]), xf(*lead[i + 1])
        ctx.set_line_width(7); ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        ctx.set_source_rgba(*PULSE, a); ctx.move_to(x0, y0); ctx.line_to(x1, y1); ctx.stroke()
    if L > LEAD:
        ml = L - LEAD
        sp = sub_path(MARK, MARK_C, 0, ml)
        # stroke thickens from the thin trace to full weight over the first 12 units
        grow = lerp(7, w, e_o3(clamp(ml / 12)))
        stroke_poly(ctx, sp, xf, grow, PULSE)
        stroke_poly(fr.g, sp, xf, grow * 1.3, PULSE)
    if 0 < p < 1:
        hx, hy = xf(*point_at(full, c, L))
        dot(ctx, hx, hy, 12 if L < LEAD else w * 0.32, PAPER, 1)
        dot(fr.g, hx, hy, 70, PAPER, 1)
    bloom = math.exp(-((t - 1.52) / 0.15) ** 2)
    fr.glow_amt = 0.6 + 0.9 * bloom
    if t > 1.35: final_layout_text(fr, t - 1.35, "track")
    return fr.finish()

def opt_continuity(t):
    """D · Seamless: starts exactly like Android 12's system splash, a light pulse
    runs through the mark, then it lifts to make room for the wordmark."""
    fr = Frame()
    m = e_io3(seg(t, 0.75, 1.35))
    xf = Xf(W / 2, lerp(H / 2, MARK_CY, m), lerp(5.6, MARK_S, m))
    w = STROKE * xf.s
    draw_mark_full(fr, xf, 1.0, glow=False)
    # travelling highlight
    p = e_io3(seg(t, 0.3, 1.15))
    if 0 < p < 1:
        L = p * (MARK_LEN + 30)
        sp = sub_path(MARK, MARK_C, max(0, L - 30), min(L, MARK_LEN))
        stroke_poly(fr.ctx, sp, xf, w * 0.42, PAPER, 0.85)
        stroke_poly(fr.g, sp, xf, w * 1.6, PULSE, 1)
        stroke_poly(fr.g, sp, xf, w * 0.8, PAPER, 0.8)
    fr.glow_amt = 1.0 if 0 < p < 1 else 0.0
    if t > 1.05: final_layout_text(fr, t - 1.05, "wipe")
    return fr.finish()

OPTIONS = {
    "jarx-splash-A-draw": (opt_draw, 2.7),
    "jarx-splash-B-heartbeat": (opt_heartbeat, 2.6),
    "jarx-splash-C-flatline": (opt_ekg, 2.8),
    "jarx-splash-D-seamless": (opt_continuity, 2.5),
}

def render(name, fn, dur, outdir):
    out = f"{outdir}/{name}.mp4"
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow",
         "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out],
        stdin=subprocess.PIPE)
    n = int(dur * FPS)
    for i in range(n):
        ff.stdin.write(fn(i / FPS))
    ff.stdin.close(); ff.wait()
    return out

if __name__ == "__main__":
    outdir = sys.argv[1]
    only = sys.argv[2:] or list(OPTIONS)
    for name in only:
        fn, dur = OPTIONS[name]
        print(render(name, fn, dur, outdir), flush=True)
