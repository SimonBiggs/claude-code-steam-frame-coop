#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow", "numpy"]
# ///
"""recsheet OUT_PREFIX [--audio F32 --rate HZ] [--events TXT] T1:PATH1 T2:PATH2 ...: picture sheets of recorded frames, for Claude to look at
(Simon, 2026-10-24: many screenshots at once plus a "movement image" of what moved between them).

Writes and prints, one path per line:
  OUT_PREFIX-frames-N.jpg   the frames, labelled with their time, up to 12 per sheet (4 x 3)
  OUT_PREFIX-moves-N.jpg    the same tiles as change maps: the frame dimmed, magenta where it differs
                            from the previous frame (first tile: no previous frame, shown plain), % changed
  OUT_PREFIX-motion.jpg     one image: the first frame dimmed, every change across the span drawn on it,
                            coloured by time (blue early -> red late), so paths show as trails
Every tile has two bands under the picture: a spectrogram of the sound since the previous tile (log
frequency 60 Hz..12 kHz bottom to top; --audio is mono float32 starting at t = 0) and the inputs pressed
since the previous tile (--events: "SECONDS TEXT" lines). Used by godot.ts (g.span); works on any timestamped frames (gdev .dev/frames, screen-rec).
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TILE_W, TILE_H, COLS, PER_SHEET = 480, 270, 4, 12
SPEC_H, KEYS_H = 64, 46  # bands under each picture
THRESH = 40  # summed RGB difference that counts as "changed" (ignores JPEG noise)


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


def sheets(tiles, prefix, kind, f):
    out = []
    for n in range(0, len(tiles), PER_SHEET):
        page = tiles[n:n + PER_SHEET]
        rows = (len(page) + COLS - 1) // COLS
        cols = min(COLS, len(page))
        th = TILE_H + SPEC_H + KEYS_H
        sheet = Image.new("RGB", (cols * TILE_W + (cols - 1) * 4, rows * th + (rows - 1) * 4), (40, 40, 48))
        for i, (im, text) in enumerate(page):
            im = im.copy()
            label(im, text, f)
            sheet.paste(im, ((i % COLS) * (TILE_W + 4), (i // COLS) * (th + 4)))
        path = f"{prefix}-{kind}-{n // PER_SHEET + 1}.jpg"
        sheet.save(path, quality=85)
        out.append(path)
    return out


def spectrogram(audio, rate, t0, t1):
    """TILE_W x SPEC_H picture of the sound between t0 and t1 (black when silent or missing)."""
    out = np.zeros((SPEC_H, TILE_W, 3), dtype=np.uint8)
    if audio is None:
        return out
    a, b = int(max(0, t0) * rate), int(max(0, t1) * rate)
    seg = audio[a:b]
    n = 1024
    if len(seg) < n:
        return out
    hop = max(64, (len(seg) - n) // TILE_W)
    idx = np.arange(0, len(seg) - n, hop)[:TILE_W]
    win = np.hanning(n).astype(np.float32)
    mag = np.abs(np.fft.rfft(np.stack([seg[i:i + n] * win for i in idx]), axis=1))  # [time, freq]
    freqs = np.fft.rfftfreq(n, 1 / rate)
    edges = np.geomspace(60, min(12000, rate / 2), SPEC_H + 1)
    bins = np.clip(np.searchsorted(freqs, edges), 1, len(freqs) - 1)
    rows = np.stack([mag[:, bins[k]:max(bins[k] + 1, bins[k + 1])].max(axis=1) for k in range(SPEC_H)])  # [freq, time]
    db = np.clip((20 * np.log10(rows + 1e-6) + 20) / 60, 0, 1)[::-1]  # loud = 1, top = high pitch
    db = np.asarray(Image.fromarray((db * 255).astype(np.uint8)).resize((TILE_W, SPEC_H), Image.BILINEAR), dtype=np.float32) / 255
    out[..., 0] = np.clip(db * 2.2, 0, 1) * 255          # black -> red -> yellow -> white ("hot")
    out[..., 1] = np.clip(db * 2.2 - 0.9, 0, 1) * 255
    out[..., 2] = np.clip(db * 3 - 2.2, 0, 1) * 255
    return out


def tile(picture, spec, keys, f_small):
    t = Image.new("RGB", (TILE_W, TILE_H + SPEC_H + KEYS_H), (18, 18, 24))
    t.paste(picture, (0, 0))
    t.paste(Image.fromarray(spec), (0, TILE_H))
    d = ImageDraw.Draw(t)
    text = "  ".join(keys) if keys else "(no input)"
    lines, line = [], ""
    for word in text.split("  "):
        if d.textlength(line + "  " + word, font=f_small) > TILE_W - 12 and line:
            lines.append(line)
            line = word
        else:
            line = (line + "  " + word).strip()
    lines.append(line)
    if len(lines) > 2:
        lines = [lines[0], lines[1][:40] + f"  (+{len(keys)} total)"]
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
    plain, moves = [], []
    motion_t = np.full((TILE_H, TILE_W), -1.0)  # latest time each pixel changed (-1: never)
    for i, (t, im) in enumerate(frames):
        prev = frames[i - 1][0] if i else max(0.0, t - 0.5)
        spec = spectrogram(audio, rate, prev, t)
        keys = [txt.replace("▶ ", "") for et, txt in events if prev < et <= t]
        plain.append((tile(im, spec, keys, f_small), f"{t:.1f}s"))
        if i == 0:
            moves.append((tile(im, spec, keys, f_small), f"{t:.1f}s (start)"))
            continue
        mask = np.abs(arrs[i] - arrs[i - 1]).sum(axis=2) > THRESH
        motion_t[mask] = i
        gray = np.asarray(im.convert("L"), dtype=np.float32) * 0.35
        out = np.stack([gray] * 3, axis=2)
        out[mask] = (255, 40, 200)
        moves.append((tile(Image.fromarray(out.astype(np.uint8)), spec, keys, f_small), f"{t:.1f}s  {100 * mask.mean():.0f}% moved"))
    paths = sheets(plain, prefix, "frames", f) + sheets(moves, prefix, "moves", f)

    # Motion summary at double tile size: trails coloured blue -> red by when they moved.
    big = (TILE_W * 2, TILE_H * 2)
    base = np.asarray(frames[0][1].convert("L").resize(big), dtype=np.float32) * 0.3
    out = np.stack([base] * 3, axis=2)
    mt = np.asarray(Image.fromarray(motion_t.astype(np.float32), mode="F").resize(big, Image.NEAREST))
    hit = mt >= 0
    k = np.clip(mt / max(1, len(frames) - 1), 0, 1)[hit]
    out[hit] = np.stack([255 * k, 60 + 60 * (1 - abs(2 * k - 1)), 255 * (1 - k)], axis=1)
    summary = Image.fromarray(out.astype(np.uint8))
    label(summary, f"motion {frames[0][0]:.1f}s -> {frames[-1][0]:.1f}s  (blue early, red late)", font(26))
    summary.save(f"{prefix}-motion.jpg", quality=88)
    paths.append(f"{prefix}-motion.jpg")
    print("\n".join(paths))


if __name__ == "__main__":
    main()
