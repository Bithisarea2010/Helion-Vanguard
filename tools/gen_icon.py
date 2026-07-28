#!/usr/bin/env python3
"""Helion Vanguard app icon generator — pure numpy + zlib PNG writer."""
import numpy as np, zlib, struct, os

S = 1024
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "icons")
os.makedirs(OUT, exist_ok=True)

y, x = np.mgrid[0:S, 0:S].astype(np.float64)
cx, cy = S / 2, S / 2
img = np.zeros((S, S, 4))

# rounded-square mask (macOS style, the OS applies its own mask but we pre-shape)
rad = S * 0.225
inner = S * 0.04
bx = np.clip(np.maximum(np.abs(x - cx), 0) - (S / 2 - rad - inner), 0, None)
by = np.clip(np.maximum(np.abs(y - cy), 0) - (S / 2 - rad - inner), 0, None)
dist_rr = np.sqrt(bx ** 2 + by ** 2)
mask = np.clip((rad - dist_rr) / 3.0, 0, 1)

# background: deep navy radial gradient + nebula wisps
r = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (S / 2)
bg_r = 0.02 + 0.05 * (1 - r)
bg_g = 0.04 + 0.08 * (1 - r)
bg_b = 0.10 + 0.16 * (1 - r)
rng = np.random.default_rng(4)
def wisp(cx2, cy2, sx, sy, col, amp):
    g = np.exp(-(((x - cx2) / sx) ** 2 + ((y - cy2) / sy) ** 2))
    return g[..., None] * np.array(col) * amp
neb = wisp(300, 720, 340, 220, [0.35, 0.1, 0.45], 0.35) + wisp(760, 280, 300, 260, [0.05, 0.3, 0.5], 0.3)
img[..., 0] = bg_r; img[..., 1] = bg_g; img[..., 2] = bg_b
img[..., :3] += neb

# stars
for i in range(90):
    sx_, sy_ = rng.integers(60, S - 60, 2)
    b = rng.uniform(0.3, 1.0)
    sz = rng.uniform(1.0, 2.6)
    g = np.exp(-(((x - sx_) ** 2 + (y - sy_) ** 2) / (2 * sz ** 2)))
    img[..., :3] += g[..., None] * b * 0.9

# cyan orbit ring (ellipse, tilted)
th = np.deg2rad(-28)
xr = (x - cx) * np.cos(th) + (y - cy) * np.sin(th)
yr = -(x - cx) * np.sin(th) + (y - cy) * np.cos(th)
er = np.sqrt((xr / (S * 0.40)) ** 2 + (yr / (S * 0.16)) ** 2)
ring = np.exp(-((er - 1.0) / 0.018) ** 2)
img[..., :3] += ring[..., None] * np.array([0.3, 0.75, 1.0]) * 0.9

# orange delta ship pointing up-right
def tri_mask(p1, p2, p3):
    def edge(a, b):
        return (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])
    e1, e2, e3 = edge(p1, p2), edge(p2, p3), edge(p3, p1)
    return ((e1 <= 0) & (e2 <= 0) & (e3 <= 0)) | ((e1 >= 0) & (e2 >= 0) & (e3 >= 0))

cxs, cys = 512, 520
ang = np.deg2rad(38)
def rot(px, py):
    return (cxs + px * np.cos(ang) - py * np.sin(ang), cys + px * np.sin(ang) + py * np.cos(ang))
nose = rot(0, -330)
lw = rot(-210, 240)
rw = rot(210, 240)
tail = rot(0, 130)
body = tri_mask(nose, lw, tail) | tri_mask(nose, tail, rw)
shp = body.astype(np.float64)
# soften edges
from numpy.fft import rfft2, irfft2
img[body, 0] = 0.95; img[body, 1] = 0.42; img[body, 2] = 0.06
# cockpit slit
ck1 = rot(0, -180); ck2 = rot(-26, -60); ck3 = rot(26, -60)
ck = tri_mask(ck1, ck2, ck3)
img[ck, 0] = 0.15; img[ck, 1] = 0.7; img[ck, 2] = 0.95
# engine glow at tail
tg = np.exp(-(((x - tail[0]) ** 2 + (y - tail[1]) ** 2) / (2 * 46.0 ** 2)))
img[..., :3] += tg[..., None] * np.array([0.3, 0.7, 1.0]) * 0.9

img[..., 3] = mask
img[..., :3] = np.clip(img[..., :3], 0, 1) * mask[..., None]

def write_png(path, arr):
    h, w = arr.shape[:2]
    raw = (np.clip(arr, 0, 1) * 255).astype(np.uint8)
    rows = b"".join(b"\x00" + raw[i].tobytes() for i in range(h))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 6))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)

write_png(os.path.join(OUT, "icon.png"), img)
print("icon.png written:", os.path.join(OUT, "icon.png"))
