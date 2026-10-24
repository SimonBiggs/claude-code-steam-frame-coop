#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow", "numpy"]
# ///
"""recsheet OUT_PREFIX [--audio F32 --rate HZ] [--events TXT] T1:PATH1 T2:PATH2 ...: picture sheets of recorded frames, for Claude to look at
(Simon, 2026-10-24: many screenshots at once plus a "movement image" of what moved between them).

Writes and prints, one path per line:
  OUT_PREFIX-N.jpg          up to 8 tiles per sheet (2 x 4). Each tile (Simon: "each frame should include a diff
                            image between them" + "a spectrograph of the sounds between the two images") is:
                            the frame | what changed since the previous frame (unchanged areas grey; changed
                            areas as an anaglyph, RED = what was there before, CYAN = what is there now, so a
                            moving thing shows red behind it and cyan ahead; yellow outlines around each changed
                            region; noise specks dropped; SCENE CHANGE when mostly new), then under both:
  OUT_PREFIX-motion.jpg     one image: the frame after the last scene change dimmed, every change since then
                            drawn on it, coloured by time (blue early -> red late), so paths show as trails
Every tile has two bands under the pictures: a spectrogram of the sound since the previous tile (log
frequency 60 Hz..12 kHz bottom to top; --audio is mono float32 starting at t = 0) and the inputs pressed
since the previous tile (--events: "SECONDS TEXT" lines). Used by godot.ts (g.span); works on any timestamped frames (gdev .dev/frames, screen-rec).
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TILE_W, TILE_H, COLS, PER_SHEET = 480, 270, 2, 8  # TILE_W x TILE_H per picture; a tile is two pictures wide
SPEC_H, KEYS_H = 64, 46  # bands under each picture
THRESH = 40  # summed RGB difference that counts as "changed" (ignores JPEG noise)
CELL = 15  # outline grid (px): a cell with > CELL_FRAC of its pixels changed is outlined
CELL_FRAC = 0.04
CUT = 0.6  # more than this fraction changed = a scene change, not movement

from PIL import ImageFilter


def change_mask(a, b):
    """Pixels that changed between frames a and b, with isolated specks removed (3x3 opening)."""
    raw = (np.abs(a - b).sum(axis=2) > THRESH).astype(np.uint8) * 255
    m = Image.fromarray(raw).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    return np.asarray(m) > 0


def diff_picture(prev_im, im, mask):
    """Grey where unchanged; red = previous frame, cyan = this frame where changed; yellow region outlines."""
    cur = np.asarray(im.convert("L"), dtype=np.float32)
    old = np.asarray(prev_im.convert("L"), dtype=np.float32)
    out = np.stack([cur * 0.55] * 3, axis=2)
    lift = lambda x: 50 + x * 0.8  # keep dark things visible in the anaglyph
    out[mask, 0] = lift(old[mask])
    out[mask, 1] = lift(cur[mask])
    out[mask, 2] = lift(cur[mask])
    pic = Image.fromarray(out.astype(np.uint8))
    h, w = mask.shape
    cells = mask[: h // CELL * CELL, : w // CELL * CELL].reshape(h // CELL, CELL, w // CELL, CELL).mean(axis=(1, 3)) > CELL_FRAC
    d = ImageDraw.Draw(pic)
    ch, cw = cells.shape
    on = lambda r, c: 0 <= r < ch and 0 <= c < cw and cells[r, c]
    for r in range(ch):
        for c in range(cw):
            if not cells[r, c]:
                continue
            x, y = c * CELL, r * CELL
            if not on(r - 1, c): d.line([(x, y), (x + CELL, y)], fill=(255, 220, 0), width=2)
            if not on(r + 1, c): d.line([(x, y + CELL), (x + CELL, y + CELL)], fill=(255, 220, 0), width=2)
            if not on(r, c - 1): d.line([(x, y), (x, y + CELL)], fill=(255, 220, 0), width=2)
            if not on(r, c + 1): d.line([(x + CELL, y), (x + CELL, y + CELL)], fill=(255, 220, 0), width=2)
    return pic


def font(size):
    for f in ("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", "/usr/share/fonts/noto/NotoSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def label(im, text, f):
    d = ImageDraw.Draw(im)
    d.text((8, 6), text, font=f, fill=(255, 255, 90), stroke_width=3, stroke_fill=(0, 0, 0))


PAIR_W = TILE_W * 2 + 6


def sheets(tiles, prefix, f):
    out = []
    for n in range(0, len(tiles), PER_SHEET):
        page = tiles[n:n + PER_SHEET]
        rows = (len(page) + COLS - 1) // COLS
        cols = min(COLS, len(page))
        th = TILE_H + SPEC_H + KEYS_H
        sheet = Image.new("RGB", (cols * PAIR_W + (cols - 1) * 10, rows * th + (rows - 1) * 10), (70, 70, 84))
        for i, (im, text) in enumerate(page):
            im = im.copy()
            label(im, text, f)
            sheet.paste(im, ((i % COLS) * (PAIR_W + 10), (i // COLS) * (th + 10)))
        path = f"{prefix}-{n // PER_SHEET + 1}.jpg"
        sheet.save(path, quality=85)
        out.append(path)
    return out


def spectrogram(audio, rate, t0, t1):
    """TILE_W x SPEC_H picture of the sound between t0 and t1 (black when silent or missing)."""
    out = np.zeros((SPEC_H, PAIR_W, 3), dtype=np.uint8)
    if audio is None:
        return out
    a, b = int(max(0, t0) * rate), int(max(0, t1) * rate)
    seg = audio[a:b]
    n = 1024
    if len(seg) < n:
        return out
    hop = max(64, (len(seg) - n) // PAIR_W)
    idx = np.arange(0, len(seg) - n, hop)[:PAIR_W]
    win = np.hanning(n).astype(np.float32)
    mag = np.abs(np.fft.rfft(np.stack([seg[i:i + n] * win for i in idx]), axis=1))  # [time, freq]
    freqs = np.fft.rfftfreq(n, 1 / rate)
    edges = np.geomspace(60, min(12000, rate / 2), SPEC_H + 1)
    bins = np.clip(np.searchsorted(freqs, edges), 1, len(freqs) - 1)
    rows = np.stack([mag[:, bins[k]:max(bins[k] + 1, bins[k + 1])].max(axis=1) for k in range(SPEC_H)])  # [freq, time]
    db = np.clip((20 * np.log10(rows + 1e-6) + 20) / 60, 0, 1)[::-1]  # loud = 1, top = high pitch
    db = np.asarray(Image.fromarray((db * 255).astype(np.uint8)).resize((PAIR_W, SPEC_H), Image.BILINEAR), dtype=np.float32) / 255
    out[..., 0] = np.clip(db * 2.2, 0, 1) * 255          # black -> red -> yellow -> white ("hot")
    out[..., 1] = np.clip(db * 2.2 - 0.9, 0, 1) * 255
    out[..., 2] = np.clip(db * 3 - 2.2, 0, 1) * 255
    return out


def tile(picture, diff, diff_label, spec, keys, f_small):
    t = Image.new("RGB", (PAIR_W, TILE_H + SPEC_H + KEYS_H), (18, 18, 24))
    t.paste(picture, (0, 0))
    t.paste(diff, (TILE_W + 6, 0))
    dd = ImageDraw.Draw(t)
    dd.text((TILE_W + 14, 6), diff_label, font=f_small, fill=(255, 255, 90), stroke_width=3, stroke_fill=(0, 0, 0))
    t.paste(Image.fromarray(spec), (0, TILE_H))
    d = ImageDraw.Draw(t)
    text = "  ".join(keys) if keys else "(no input)"
    lines, line = [], ""
    for word in text.split("  "):
        if d.textlength(line + "  " + word, font=f_small) > PAIR_W - 12 and line:
            lines.append(line)
            line = word
        else:
            line = (line + "  " + word).strip()
    lines.append(line)
    if len(lines) > 2:
        lines = [lines[0], lines[1][:90] + f"  (+{len(keys)} total)"]
    for i, l in enumerate(lines):
        d.text((6, TILE_H + SPEC_H + 3 + i * 20), l, font=f_small, fill=(150, 230, 255) if keys else (110, 110, 120))
    return t


def main():
    args = sys.argv[1:]
    opt = {}
    while len(args) > 1 and args[1].startswith("--"):
        opt[args[1][2:]] = args[2]
        del args[1:3]
    prefix, items = args[0], args[1:]
    audio = None
    if opt.get("audio"):
        try:
            audio = np.fromfile(opt["audio"], dtype=np.float32)
        except OSError:
            pass
    rate = float(opt.get("rate", 44100))
    events = []
    if opt.get("events"):
        try:
            for l in open(opt["events"]):
                t, _, text = l.strip().partition(" ")
                events.append((float(t), text))
        except OSError:
            pass
    f_small = font(16)
    frames = []
    for it in items:
        t, path = it.split(":", 1)
        frames.append((float(t), Image.open(path).convert("RGB").resize((TILE_W, TILE_H), Image.BILINEAR)))
    f = font(20)
    arrs = [np.asarray(im, dtype=np.int16) for _, im in frames]
    tiles = []
    motion_t = np.full((TILE_H, TILE_W), -1.0)  # latest time each pixel changed (-1: never)
    trail_from = 0  # the motion summary starts after the last scene change
    blank = Image.new("RGB", (TILE_W, TILE_H), (30, 30, 36))
    for i, (t, im) in enumerate(frames):
        prev = frames[i - 1][0] if i else max(0.0, t - 0.5)
        spec = spectrogram(audio, rate, prev, t)
        keys = [txt.replace("▶ ", "") for et, txt in events if prev < et <= t]
        if i == 0:
            diff, dl = blank, "changes: (first frame)"
        else:
            mask = change_mask(arrs[i], arrs[i - 1])
            if mask.mean() > CUT:
                trail_from = i
                motion_t[:] = -1
                diff, dl = im, "SCENE CHANGE"
            else:
                motion_t[mask] = i
                diff, dl = diff_picture(frames[i - 1][1], im, mask), f"changes since {prev:.1f}s: {100 * mask.mean():.0f}%  (red=was, cyan=now)"
        tiles.append((tile(im, diff, dl, spec, keys, f_small), f"{t:.1f}s"))
    paths = sheets(tiles, prefix, f)

    # Motion summary at double tile size: trails coloured blue -> red by when they moved.
    big = (TILE_W * 2, TILE_H * 2)
    base = np.asarray(frames[trail_from][1].convert("L").resize(big), dtype=np.float32) * 0.45
    out = np.stack([base] * 3, axis=2)
    mt = np.asarray(Image.fromarray(motion_t.astype(np.float32), mode="F").resize(big, Image.NEAREST))
    hit = mt >= 0
    k = np.clip((mt - trail_from) / max(1, len(frames) - 1 - trail_from), 0, 1)[hit]
    out[hit] = np.stack([255 * k, 60 + 60 * (1 - abs(2 * k - 1)), 255 * (1 - k)], axis=1)
    summary = Image.fromarray(out.astype(np.uint8))
    label(summary, f"motion {frames[trail_from][0]:.1f}s -> {frames[-1][0]:.1f}s  (blue early, red late){'  since scene change' if trail_from else ''}", font(26))
    summary.save(f"{prefix}-motion.jpg", quality=88)
    paths.append(f"{prefix}-motion.jpg")
    print("\n".join(paths))


if __name__ == "__main__":
    main()
