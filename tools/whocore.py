"""whocore: who is talking, from the family's Steam Deck mics (+ the room mic when plugged in).

Asked for by Simon (2026-10-24). Everything stays on this machine; data lives in
~/GodotProjects/duo-arena/.dev/who/ (gitignored).

Pipeline (10 ms frames on one absolute clock, processed in ~1 s blocks):
  1. read   every channel by Steam-Machine time using the chunktime sidecars (+ a learned per-channel offset)
  2. align  GCC-PHAT between channel pairs every few seconds -> least-squares offset corrections (tracks drift)
  3. diff   per channel and STFT band: excess over its own noise floor X; common part = median of the other
            channels' X times a learned per-band gain; residual R = X - 2*gain*common ("near this Deck" sound)
  4. mask   a band belongs to the channel whose residual dominates it (ratio mask) x Wiener gain R/(X+1)
  5. VAD    per channel on residual energy; a segment where another channel is >=3 dB stronger is a leak
  6. label  loudness margin (residual dB over the next channel) + voice profile (TitaNet embedding) -> name + confidence
  7. ASR    Whisper on the masked "near this Deck" audio of every real segment (several at once = overlap)
"""
import difflib, json, math, os, re, threading, time
from pathlib import Path

import warnings

import numpy as np

warnings.filterwarnings("ignore", message="All-NaN slice")

RATE = 16000
HOP = 160                     # 10 ms
NFFT = 512
FPS = RATE // HOP             # 100 frames/s
WIN = np.hanning(NFFT).astype(np.float32)
BAND = slice(5, 129)          # 156 Hz .. 4 kHz: speech
DEV = Path.home() / "GodotProjects/duo-arena/.dev"
DECKS_DIR = DEV / "audio-decks"
ROOM_DIR = DEV / "audio"
WHO = DEV / "who"
OWNERS = {"simon-deck": "Simon", "esther-deck": "Mum", "david-deck": "David", "nathanael-deck": "Nathanael",
          "abigail-deck": "Abigail", "samuel-deck": "Samuel"}
NAMES = sorted(set(OWNERS.values()))

# tunables (env overrides for experiments)
ON_DB = float(os.environ.get("WHO_ON_DB", "7"))        # residual energy that starts speech
OFF_DB = float(os.environ.get("WHO_OFF_DB", "4"))      # ... and keeps it going
DOM_DB = float(os.environ.get("WHO_DOM_DB", "3"))      # a frame "belongs" to a channel this much above the rest
MARGIN_DB = float(os.environ.get("WHO_MARGIN_DB", "6"))  # clear loudness attribution
KAPPA = float(os.environ.get("WHO_KAPPA", "2"))        # over-subtraction of the common part
RING = 60 * FPS               # keep 60 s of per-frame state
# absolute floor per band: about -100 dBFS per bin for a Hann-windowed 512 FFT
FLOOR_MIN = (10 ** (-100 / 20) * NFFT / 4) ** 2


def hms(t: float) -> str:
    return time.strftime("%H:%M:%S", time.localtime(t))


# ---------------------------------------------------------------- reading by time
class FileSource:
    """Read any channel by absolute (Steam Machine) time from minute .raw files + .json sidecars."""

    def __init__(self):
        self.cache: dict = {}

    @staticmethod
    def channels() -> dict:
        ch = {}
        if DECKS_DIR.is_dir():
            for d in sorted(DECKS_DIR.iterdir()):
                if d.is_dir():
                    ch[d.name] = d
        ch["room"] = ROOM_DIR
        return ch

    def _segs(self, path: Path):
        side = path.with_suffix(".json")
        try:
            st, rs = side.stat(), path.stat()
        except FileNotFoundError:
            return []
        key = str(path)
        c = self.cache.get(key)
        if not c or c[0] != st.st_mtime:
            try:
                segs = json.loads(side.read_text()).get("segments", [])
            except Exception:
                return c[2] if c else []
            c = (st.st_mtime, 0, segs)
            self.cache[key] = c
            if len(self.cache) > 400:
                for k in list(self.cache)[:100]:
                    self.cache.pop(k)
        out = []
        segs = c[2]
        for i, s in enumerate(segs):
            if not s.get("first_sample_unix"):
                continue
            n = s["samples"]
            if i == len(segs) - 1 and not s.get("final"):
                n = max(n, (rs.st_size - s["byte_offset"]) // 2)   # provisional sidecar lags the file
            elif i + 1 < len(segs):
                n = min(n, (segs[i + 1]["byte_offset"] - s["byte_offset"]) // 2)
            out.append((s["first_sample_unix"], n, s["byte_offset"]))
        return out

    def read(self, chan: str, t0: float, n: int):
        """n samples from time t0 -> (float32 audio in -1..1, bool valid mask). Missing audio is zeros/False."""
        d = self.channels().get(chan)
        x = np.zeros(n, np.float32)
        ok = np.zeros(n, bool)
        if d is None:
            return x, ok
        t1 = t0 + n / RATE
        m = int(t0 // 60) - 1
        while m * 60 <= t1 + 60:
            p = d / time.strftime("%Y%m%d-%H%M.raw", time.localtime(m * 60))
            m += 1
            if not p.exists():
                continue
            for fs, cnt, off in self._segs(p):
                a = int(round((t0 - fs) * RATE))        # index of t0 inside this segment
                lo, hi = max(a, 0), min(a + n, cnt)
                if hi <= lo:
                    continue
                with open(p, "rb") as f:
                    f.seek(off + lo * 2)
                    raw = np.frombuffer(f.read((hi - lo) * 2), np.int16)
                k = len(raw)
                x[lo - a:lo - a + k] = raw / 32768.0
                ok[lo - a:lo - a + k] = True
        return x, ok


class ArraySource:
    """In-memory multichannel audio (tests, synthetic overlaps): {chan: (t0, samples)}."""

    def __init__(self, data: dict):
        self.data = data

    def channels(self):
        return {c: None for c in self.data}

    def read(self, chan, t0, n):
        x = np.zeros(n, np.float32)
        ok = np.zeros(n, bool)
        if chan not in self.data:
            return x, ok
        s0, a = self.data[chan]
        i = int(round((t0 - s0) * RATE))
        lo, hi = max(i, 0), min(i + n, len(a))
        if hi > lo:
            x[lo - i:hi - i] = a[lo:hi]
            ok[lo - i:hi - i] = True
        return x, ok


def frames_of(x: np.ndarray, nfr: int) -> np.ndarray:
    return np.lib.stride_tricks.sliding_window_view(x, NFFT)[::HOP][:nfr]


def istft(spec: np.ndarray) -> np.ndarray:
    """Overlap-add of rfft frames on the HOP grid (Hann analysis + synthesis, normalised)."""
    fr = np.fft.irfft(spec, n=NFFT, axis=1) * WIN
    n = NFFT + HOP * (len(fr) - 1)
    y, w = np.zeros(n), np.zeros(n)
    for i, f in enumerate(fr):
        y[i * HOP:i * HOP + NFFT] += f
        w[i * HOP:i * HOP + NFFT] += WIN ** 2
    return (y / np.maximum(w, 1e-3)).astype(np.float32)


# ---------------------------------------------------------------- alignment
def gcc_phat(a: np.ndarray, b: np.ndarray, max_lag: int):
    """Lag (samples) by which b is late relative to a, and peak quality (peak / mean |cc| in the window)."""
    n = 1 << int(math.ceil(math.log2(len(a) + len(b))))
    A, B = np.fft.rfft(a, n), np.fft.rfft(b, n)
    G = B * np.conj(A)
    G /= np.abs(G) + 1e-12
    cc = np.fft.irfft(G, n)
    cc = np.concatenate([cc[-max_lag:], cc[:max_lag + 1]])
    i = int(np.argmax(np.abs(cc)))
    q = float(np.abs(cc[i]) / (np.mean(np.abs(cc)) + 1e-12))
    return i - max_lag, q


# ---------------------------------------------------------------- the engine
class Engine:
    """Frame pipeline. step(k_end) processes all frames up to absolute frame index k_end (k = time*100)."""

    def __init__(self, source, chans=None, offsets=None, on_segment=None):
        self.src = source
        self.chans = list(chans or source.channels())
        self.off = {c: 0.0 for c in self.chans}
        self.off.update({c: v for c, v in (offsets or {}).items() if c in self.off})
        self.on_segment = on_segment or (lambda seg: None)
        C = len(self.chans)
        self.floor = [None] * C
        self.logg = np.zeros((C, NFFT // 2 + 1), np.float32)
        self.E = np.full((RING, C), np.nan, np.float32)        # residual energy dB per frame
        self.Eraw = np.full((RING, C), np.nan, np.float32)     # raw excess over floor dB (plain loudness)
        self.mask = np.ones((RING, C, NFFT // 2 + 1), np.float16)
        self.kring = np.full(RING, -1, np.int64)
        self.clip = np.zeros((RING, C), bool)
        self.k = None
        self.vad = [dict(on=False, start=0, last=0, hist=[]) for _ in range(C)]
        self.pair_hist: dict = {}
        self.last_gcc = 0.0
        self.align_log: list = []

    # ---- alignment
    def align(self, t_end: float, win_s: float = 4.0, max_lag_s: float = 0.25):
        """GCC-PHAT over the last win_s seconds between every pair of live channels. Each pair keeps its last 40
        confident lags (relative to the raw sidecar times); offsets = least-squares fit of the pair medians,
        mean zero (or the room mic fixed at zero when it is live). Slow drift is followed as old lags age out."""
        n = int(win_s * RATE)
        sig = {}
        for c in self.chans:
            x, ok = self.src.read(c, t_end - win_s + self.off[c], n)
            if ok.mean() > 0.95 and np.std(x) > 1e-4:
                sig[c] = x - x.mean()
        cs = list(sig)
        for i in range(len(cs)):
            for j in range(i + 1, len(cs)):
                lag, q = gcc_phat(sig[cs[i]], sig[cs[j]], int(max_lag_s * RATE))
                if q >= 12:   # b late by lag in the offset-corrected reads -> raw lag = lag + off_b - off_a
                    h = self.pair_hist.setdefault((cs[i], cs[j]), [])
                    h.append((t_end, lag / RATE + self.off[cs[j]] - self.off[cs[i]]))
                    del h[:-40]
        pairs = {k: v for k, v in self.pair_hist.items() if len(v) >= 8 and t_end - v[-1][0] < 600}
        known = sorted({c for k in pairs for c in k})
        if len(known) < 2:
            return None
        rows, ys = [], []
        for (a, b), v in pairs.items():
            r = np.zeros(len(known)); r[known.index(a)], r[known.index(b)] = -1, 1
            rows.append(r); ys.append(float(np.median([l for _, l in v])))
        anchor = np.array([1.0 if c == "room" else 0.0 for c in known]) if "room" in known else np.ones(len(known)) / len(known)
        e, *_ = np.linalg.lstsq(np.vstack(rows + [anchor * 10]), np.array(ys + [0.0]), rcond=None)
        for c, d in zip(known, e):
            self.off[c] = float(max(-0.1, min(0.1, d)))
        fit = {f"{a}~{b}": round(1000 * float(np.median([l for _, l in v]) - (self.off[b] - self.off[a])), 1)
               for (a, b), v in pairs.items()}
        spread = {f"{a}~{b}": round(1000 * float(np.subtract(*np.percentile([l for _, l in v], [75, 25]))), 1)
                  for (a, b), v in pairs.items()}
        self.align_log.append((t_end, dict(self.off), fit, spread))
        del self.align_log[:-200]
        return self.off

    # ---- frames
    def step(self, k_end: int):
        if self.k is None:
            self.k = k_end - FPS
        while self.k < k_end:
            k1 = min(self.k + FPS, k_end)
            self._block(self.k, k1)
            self.k = k1

    def _block(self, k0: int, k1: int):
        nfr = k1 - k0
        C = len(self.chans)
        F = NFFT // 2 + 1
        X = np.full((nfr, C, F), np.nan, np.float32)
        specs = {}
        rise = 10 ** (2.0 / 10 / FPS)                         # floor may rise 2 dB/s
        for ci, c in enumerate(self.chans):
            t0 = k0 / FPS - NFFT / 2 / RATE + self.off[c]
            x, ok = self.src.read(c, t0, (nfr - 1) * HOP + NFFT)
            if ok.mean() < 0.5 or not np.any(x):
                self.floor[ci] = None if not ok.any() else self.floor[ci]
                continue
            fr = frames_of(x, nfr)
            okf = frames_of(ok, nfr).mean(1) > 0.9
            # The Decks' mic pipeline has a noise gate: runs of exact zeros mean "quiet here". Such frames count
            # as at-the-floor (X = 0) and never pull the floor estimate down.
            gated = (fr == 0).mean(1) > 0.05
            P = np.abs(np.fft.rfft(fr * WIN, axis=1)) ** 2 + 1e-12
            usable = okf & ~gated
            fl = self.floor[ci] if self.floor[ci] is not None else np.median(P[usable], 0) if usable.any() else None
            if fl is None:
                if okf.any():
                    X[okf, ci] = 0
                continue
            # floor_i = min(floor_{i-1} * rise, P_i) as a running minimum in the log domain (vectorised)
            lr = math.log(rise)
            ii = np.arange(1, nfr + 1)[:, None]
            lp = np.where(usable[:, None], np.log(P), np.inf) - ii * lr
            run = np.minimum.accumulate(np.vstack([np.log(fl)[None], lp]), axis=0)[1:]
            FL = np.maximum(np.exp(run + ii * lr), FLOOR_MIN)
            X[usable, ci] = np.maximum(P[usable] / FL[usable] - 1, 0)
            X[okf & ~usable, ci] = 0
            fl = FL[-1]
            self.floor[ci] = fl
            idx = (np.arange(k0, k1)) % RING
            self.clip[idx, ci] = np.abs(fr).max(1) > 0.98
            specs[ci] = okf
        live = ~np.isnan(X[:, :, 0])                           # (nfr, C)
        R = np.zeros_like(X)
        alive = [j for j in range(C) if live[:, j].mean() > 0.5]
        X0 = np.nan_to_num(X)
        for ci in range(C):
            others = [j for j in alive if j != ci]
            if not others:
                M = np.zeros((nfr, F), np.float32)
            elif len(others) == 1:
                M = X0[:, others[0]]
            else:
                M = np.median(X0[:, others], axis=1)
            G = np.exp(self.logg[ci])
            R[:, ci] = np.maximum(np.nan_to_num(X[:, ci]) - KAPPA * G * M, 0)
            # learn the per-band gain from common sound while this channel is not speaking
            if not self.vad[ci]["on"] and live[:, ci].any():
                sel = live[:, ci] & (M.mean(1) > 3)
                if sel.any():
                    lr = np.log((X[sel, ci] + 0.1) / (M[sel] + 0.1)).mean(0)
                    self.logg[ci] = np.clip(self.logg[ci] + 0.02 * sel.sum() / FPS * np.clip(lr - self.logg[ci], -1, 1), -3, 3)
        E = 10 * np.log10(1 + R[:, :, BAND].mean(2))
        Er = 10 * np.log10(1 + np.nan_to_num(X[:, :, BAND]).mean(2))
        E[~live] = np.nan
        Er[~live] = np.nan
        D = R ** 2 / ((R ** 2).sum(1, keepdims=True) + 1e-9)
        W = R / (np.nan_to_num(X) + 1)
        mask = np.clip(np.sqrt(D * W), 0.1, 1.0)
        idx = np.arange(k0, k1) % RING
        self.E[idx], self.Eraw[idx], self.mask[idx], self.kring[idx] = E, Er, mask.astype(np.float16), np.arange(k0, k1)
        for ci in range(C):
            self._vad(ci, k0, E[:, ci])

    def _vad(self, ci: int, k0: int, e: np.ndarray):
        v = self.vad[ci]
        for i, val in enumerate(e):
            k = k0 + i
            val = -1 if np.isnan(val) else val
            v["hist"] = (v["hist"] + [val > ON_DB])[-8:]
            if not v["on"]:
                if sum(v["hist"]) >= 5:
                    v.update(on=True, start=k - 8 - 15, last=k)
                continue
            if val > OFF_DB:
                v["last"] = k
            if k - v["last"] > 50 or k - v["start"] > 15 * FPS:
                self._close(ci, v["start"], v["last"] + 15)
                v.update(on=False, hist=[])

    def flush(self):
        for ci, v in enumerate(self.vad):
            if v["on"]:
                self._close(ci, v["start"], min(v["last"] + 15, self.k - 1))
                v.update(on=False, hist=[])

    def frames(self, ka: int, kb: int):
        """Per-frame residual dB (frames, C) for [ka, kb) if still in the ring, else None."""
        ks = np.arange(ka, kb)
        if not len(ks) or (self.kring[ks % RING] != ks).any():
            return None
        return self.E[ks % RING], self.Eraw[ks % RING], self.clip[ks % RING]

    def _close(self, ci: int, ka: int, kb: int):
        f = self.frames(ka, kb)
        if f is None:
            return
        E, Er, clip = f
        c = self.chans[ci]
        e = np.nan_to_num(E[:, ci], nan=-1)
        voiced = e > ON_DB
        if voiced.sum() < 25:
            return
        oth = np.delete(E, ci, axis=1)
        with np.errstate(all="ignore"):
            omax = np.nanmax(oth, axis=1) if oth.shape[1] else np.full(len(e), np.nan)
        n_live = int((~np.isnan(oth[voiced])).any(0).sum()) if oth.shape[1] else 0
        dom = e - np.nan_to_num(omax, nan=-1)
        dom_frames = voiced & (dom >= DOM_DB)
        seg = dict(chan=c, owner=OWNERS.get(c), t0=round(ka / FPS, 2), t1=round(kb / FPS, 2), ka=ka, kb=kb,
                   voiced_s=round(voiced.sum() / FPS, 2), dom_s=round(dom_frames.sum() / FPS, 2),
                   live_others=n_live, energy_db=round(float(np.median(e[voiced])), 1),
                   clipped=bool(clip[voiced, ci].any()))
        seg["margin_db"] = round(float(np.median(dom[voiced])), 1) if n_live else None
        # mean residual of every channel over this segment's voiced frames (for the record / attribution)
        with np.errstate(all="ignore"):
            seg["levels"] = {self.chans[j]: (None if np.isnan(E[voiced, j]).all() else round(float(np.nanmedian(E[voiced, j])), 1))
                             for j in range(len(self.chans))}
        if n_live and dom_frames.sum() < 25:
            seg["leak"] = max((l, ch) for ch, l in seg["levels"].items() if l is not None and ch != c)[1]
        self.on_segment(seg)

    def masked_audio(self, chan: str, ka: int, kb: int, use_mask=True):
        """The "near this channel" audio for frames [ka, kb): its own STFT times the stored mask."""
        ci = self.chans.index(chan)
        nfr = kb - ka
        x, ok = self.src.read(chan, ka / FPS - NFFT / 2 / RATE + self.off[chan], (nfr - 1) * HOP + NFFT)
        spec = np.fft.rfft(frames_of(x, nfr) * WIN, axis=1)
        if use_mask:
            ks = np.arange(ka, kb)
            good = self.kring[ks % RING] == ks
            m = np.where(good[:, None], self.mask[ks % RING, ci].astype(np.float32), 1.0)
            spec = spec * m
        y = istft(spec)[NFFT // 2:NFFT // 2 + nfr * HOP]
        return y


# ---------------------------------------------------------------- voice profiles
class Profiles:
    """Per person, per mic kind ("deck" = masked Deck audio, "room" = room mic): mean TitaNet embedding."""
    FILE = WHO / "profiles.json"
    MODEL = Path.home() / ".local/share/voice-bridge/nemo_en_titanet_large.onnx"
    SEED = Path.home() / ".local/share/voice-bridge/speakers-local-titanet.json"

    def __init__(self, threads: int = 1):
        self.threads = threads
        self.ex = None
        self.lock = threading.RLock()
        self.load()

    def load(self):
        self.p = {}
        self.mtime = None
        if self.FILE.exists():
            self.mtime = self.FILE.stat().st_mtime
            for name, kinds in json.loads(self.FILE.read_text()).items():
                self.p[name] = {k: [np.array(v[0], np.float32), v[1]] for k, v in kinds.items()}
        elif self.SEED.exists():   # start the room prints from voice-bridge's enrolled room voiceprints
            for name, (emb, n) in json.loads(self.SEED.read_text()).items():
                if name in NAMES:
                    self.p.setdefault(name, {})["room"] = [np.array(emb, np.float32), min(n, 10)]

    def reload(self):
        if self.FILE.exists() and self.FILE.stat().st_mtime != self.mtime:
            self.load()

    def save(self):
        WHO.mkdir(parents=True, exist_ok=True)
        tmp = self.FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps({n: {k: [v[0].tolist(), v[1]] for k, v in kinds.items()} for n, kinds in self.p.items()}))
        os.replace(tmp, self.FILE)
        self.mtime = self.FILE.stat().st_mtime

    def embed(self, audio: np.ndarray):
        if len(audio) < RATE * 0.8:
            return None
        with self.lock:
            if self.ex is None:
                import sherpa_onnx
                self.ex = sherpa_onnx.SpeakerEmbeddingExtractor(
                    sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(self.MODEL), num_threads=self.threads))
            st = self.ex.create_stream()
            st.accept_waveform(RATE, audio.astype(np.float32))
            st.input_finished()
            e = np.array(self.ex.compute(st), np.float32)
        return e / (np.linalg.norm(e) + 1e-9)

    def scores(self, emb, kind: str):
        """[(cosine, name, n)] best first, only for profiles of this kind."""
        self.reload()
        out = []
        for name, kinds in self.p.items():
            if kind in kinds:
                m, n = kinds[kind]
                out.append((float(emb @ (m / (np.linalg.norm(m) + 1e-9))), name, n))
        return sorted(out, reverse=True)

    def learn(self, name: str, emb, kind: str, cap: int = 100):
        with self.lock:
            self.reload()
            m, n = self.p.setdefault(name, {}).get(kind, [np.zeros_like(emb), 0])
            self.p[name][kind] = [(m * n + emb) / (n + 1), min(n + 1, cap)]
            self.save()


def decide(owner, margin_db, sc, solo=False):
    """Combine loudness (owner of the loudest channel + margin) and profile scores -> (label, conf, why)."""
    cl = 0.0 if margin_db is None or owner is None else max(0.0, min(1.0, (margin_db - 2) / 8))
    best = sc[0] if sc and sc[0][2] >= 3 else None
    second = sc[1][0] if len(sc) > 1 else 0.0
    cp = 0.0
    if best:
        cp = max(0.0, min(1.0, (best[0] - 0.40) / 0.25)) * max(0.0, min(1.0, (best[0] - second) / 0.08))
        if best[2] < 8:
            cp *= 0.6                                    # young profile: trust less
    pname = best[1] if best else None
    own_score = next((s for s, n, _ in sc if n == owner), None)
    if owner and cl >= 0.5:
        mature = next((k for s, n, k in sc if n == owner), 0) >= 10
        if pname and pname != owner and cp >= 0.6 and mature and own_score is not None and own_score < best[0] - 0.1:
            return pname, round(cp * 0.8, 2), f"voice={pname} at {owner}'s Deck"
        if pname == owner:
            return owner, round(1 - (1 - cl) * (1 - cp), 2), "loud+voice"
        return owner, round(cl * (1 - 0.4 * cp), 2), "loud"
    if pname and cp >= 0.5:
        return pname, round(cp * 0.8, 2), "voice"
    if owner and cl > 0.25:
        return owner, round(cl, 2), "loud(weak)"
    return "unknown", round(max(cl, cp), 2), "unclear"


def label_text(label: str, conf: float) -> str:
    if label == "unknown" or conf < 0.3:
        return "unknown"
    return label if conf >= 0.5 else label + "?"


# ---------------------------------------------------------------- text helpers
JUNK = {"", "you", "thank you", "thanks for watching", "bye", "uh", "um", "hmm", "silence", "so", "oh", "okay"}


def words(t: str) -> list:
    return re.sub(r"[^a-z0-9' ]", " ", t.lower()).split()


def is_junk(t: str) -> bool:
    return "<" in t or "begin=" in t or " ".join(words(t)) in JUNK


def similar(a: str, b: str) -> float:
    wa, wb = words(a), words(b)
    if not wa or not wb:
        return 0.0
    return difflib.SequenceMatcher(None, wa, wb).ratio()


def wer(ref: str, hyp: str) -> float:
    r, h = words(ref), words(hyp)
    if not r:
        return 0.0 if not h else 1.0
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / len(r)
