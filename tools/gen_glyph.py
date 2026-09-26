#!/usr/bin/env python3
"""Generate muOS launcher glyph for File-GD X.
Output: glyph/file_grid_diver.png (72x72 RGBA).
Pure stdlib PNG writer.
"""
import struct, zlib, os, math

OUT_DIR = "glyph"
os.makedirs(OUT_DIR, exist_ok=True)
W = H = 72

AMBER     = (240, 168,  90, 255)
AMBER_HI  = (255, 200, 130, 255)
AMBER_LO  = ( 90,  62,  30, 255)
BG        = (  8,   7,   6, 255)
CYAN      = ( 78, 205, 230, 255)
DARK      = ( 18,  16,  14, 255)

def _chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data +
            struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))

def write_png(path, pixels):
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)
    raw = bytearray()
    for y in range(H):
        raw.append(0)
        for x in range(W):
            r, g, b, a = pixels[y * W + x]
            raw += bytes([r, g, b, a])
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(_chunk(b'IHDR', ihdr))
        f.write(_chunk(b'IDAT', idat))
        f.write(_chunk(b'IEND', b''))

px = [BG] * (W * H)

def blend(x, y, col):
    if 0 <= x < W and 0 <= y < H:
        i = y * W + x
        o = px[i]
        a = col[3] / 255.0
        px[i] = (
            int(o[0] * (1 - a) + col[0] * a),
            int(o[1] * (1 - a) + col[1] * a),
            int(o[2] * (1 - a) + col[2] * a),
            255,
        )

def hex_points(cx, cy, r, rot=0.0):
    pts = []
    for i in range(6):
        a = -math.pi/2 + i * math.pi/3 + rot
        pts.append((cx + math.cos(a)*r, cy + math.sin(a)*r))
    return pts

def draw_polyline(pts, col, thick=2):
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i+1) % len(pts)]
        steps = max(2, int(max(abs(x2-x1), abs(y2-y1)) * 2) + 1)
        for s in range(steps):
            t = s / (steps - 1)
            x = x1 + (x2 - x1) * t
            y = y1 + (y2 - y1) * t
            for dx in range(-thick//2, thick//2 + 1):
                for dy in range(-thick//2, thick//2 + 1):
                    if abs(dx) + abs(dy) <= thick:
                        blend(int(round(x)) + dx, int(round(y)) + dy, col)

# outer hex (frame)
draw_polyline(hex_points(36, 36, 32, 0),         AMBER,   3)
# inner hex (rotated)
draw_polyline(hex_points(36, 36, 22, math.pi/6), AMBER_LO, 2)

# central folder icon
# top tab
for x in range(20, 32):
    for y in range(26, 32):
        blend(x, y, AMBER)
# main body
for x in range(18, 54):
    for y in range(32, 50):
        blend(x, y, AMBER_HI)

# folder inner "lines" hinting at files
for i, x in enumerate((22, 26, 30, 34, 38)):
    color = CYAN if i == 2 else AMBER_LO
    for y in range(36, 46):
        blend(x, y, color)
        blend(x + 1, y, color)

# drop the central pixel of the eye-like folder tab? no, add a small dot
for dx in range(-1, 2):
    for dy in range(-1, 2):
        blend(36 + dx, 30 + dy, CYAN)

write_png(os.path.join(OUT_DIR, "file_grid_diver.png"), px)
print("  wrote glyph/file_grid_diver.png (72x72)")

# Also produce a 144x144 variant (some muOS builds look for @2x)
W = H = 144
px = [BG] * (W * H)
# simple scale: 2x everything by nearest neighbor
src_px = []
# re-generate directly at 2x
def blend2(x, y, col):
    if 0 <= x < W and 0 <= y < H:
        i = y * W + x
        o = px[i]
        a = col[3] / 255.0
        px[i] = (
            int(o[0] * (1 - a) + col[0] * a),
            int(o[1] * (1 - a) + col[1] * a),
            int(o[2] * (1 - a) + col[2] * a),
            255,
        )

def draw_polyline2(pts, col, thick=4):
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i+1) % len(pts)]
        steps = max(2, int(max(abs(x2-x1), abs(y2-y1)) * 2) + 1)
        for s in range(steps):
            t = s / (steps - 1)
            x = x1 + (x2 - x1) * t
            y = y1 + (y2 - y1) * t
            for dx in range(-thick//2, thick//2 + 1):
                for dy in range(-thick//2, thick//2 + 1):
                    if abs(dx) + abs(dy) <= thick:
                        blend2(int(round(x)) + dx, int(round(y)) + dy, col)

def hex_points2(cx, cy, r, rot=0.0):
    pts = []
    for i in range(6):
        a = -math.pi/2 + i * math.pi/3 + rot
        pts.append((cx + math.cos(a)*r, cy + math.sin(a)*r))
    return pts

draw_polyline2(hex_points2(72, 72, 64, 0),         AMBER,   5)
draw_polyline2(hex_points2(72, 72, 44, math.pi/6), AMBER_LO, 3)
for x in range(40, 64):
    for y in range(52, 64):
        blend2(x, y, AMBER)
for x in range(36, 108):
    for y in range(64, 100):
        blend2(x, y, AMBER_HI)
for i, x in enumerate((44, 52, 60, 68, 76)):
    color = CYAN if i == 2 else AMBER_LO
    for y in range(72, 92):
        blend2(x, y, color)
        blend2(x + 1, y, color)
for dx in range(-2, 3):
    for dy in range(-2, 3):
        blend2(72 + dx, 60 + dy, CYAN)

write_png(os.path.join(OUT_DIR, "file_grid_diver@2x.png"), px)
print("  wrote glyph/file_grid_diver@2x.png (144x144)")
