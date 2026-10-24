"""Shared timing for the rolling raw recorders (voice-record, deck-mic).

Each minute file X.raw gets a sidecar X.json listing segments (one per stream that wrote into it):
  byte_offset           where the segment starts in X.raw
  samples               16 kHz mono samples in the segment
  first_sample_unix     best estimate (Steam Machine wall clock, NTP) of when the first sample was captured
                        = min over the segment's 100 ms chunks of (receive time - samples so far / 16000)
                          + samples before the segment / 16000. The min removes network/buffer jitter;
                          per-minute anchoring removes audio-clock drift.
  jitter_ms             spread (max - min) of those per-chunk estimates in this segment
  stream_start_unix     receive-based estimate of the stream's first sample (for continuity checks)
  plus any extra fields from the recorder (deck clock offset at connect, NTP state, ...).
Latency NOT removed: the constant capture->receive floor (PipeWire buffer + one-way network), typically
a few tens of ms; it is similar for every Deck on the same Wi-Fi."""
import json, os, time

RATE, BPS = 16000, 2


class Segment:
    def __init__(self, raw_path, byte_offset, stream_samples, extra):
        self.raw_path, self.byte_offset, self.start_samples = raw_path, byte_offset, stream_samples
        self.samples, self.rmin, self.rmax, self.extra = 0, None, None, extra

    def add(self, nbytes, recv_t, stream_samples_after):
        self.samples += nbytes // BPS
        r = recv_t - stream_samples_after / RATE          # estimate of stream sample 0 time
        self.rmin = r if self.rmin is None else min(self.rmin, r)
        self.rmax = r if self.rmax is None else max(self.rmax, r)

    def info(self):
        return dict(byte_offset=self.byte_offset, samples=self.samples, rate=RATE,
                    first_sample_unix=round(self.rmin + self.start_samples / RATE, 4) if self.rmin else None,
                    first_sample_iso=time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.rmin + self.start_samples / RATE)) if self.rmin else None,
                    jitter_ms=round((self.rmax - self.rmin) * 1000, 1) if self.rmin else None,
                    stream_start_unix=round(self.rmin, 4) if self.rmin else None,
                    stream_sample_offset=self.start_samples, **self.extra)

    def write(self, final=False):
        side = self.raw_path[:-4] + ".json"
        try:
            d = json.load(open(side))
        except Exception:
            d = {"segments": []}
        segs = [s for s in d.get("segments", []) if s.get("byte_offset") != self.byte_offset]
        info = self.info(); info["final"] = final
        segs.append(info); segs.sort(key=lambda s: s["byte_offset"])
        d["segments"] = segs
        tmp = side + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f, indent=1)
        os.chmod(tmp, 0o600); os.replace(tmp, side)


class Writer:
    """Splits one stream into minute files with sidecars."""
    def __init__(self, dir_, extra=None):
        self.dir, self.extra = dir_, extra or {}
        self.cur, self.f, self.seg, self.stream_samples, self.last_side = None, None, None, 0, 0

    def write(self, raw):
        now = time.time()
        name = time.strftime("%Y%m%d-%H%M.raw", time.localtime(now))
        if name != self.cur:
            self.close()
            self.cur = name
            p = os.path.join(self.dir, name)
            self.f = open(p, "ab"); os.chmod(p, 0o600)
            self.seg = Segment(p, self.f.tell(), self.stream_samples, self.extra)
        self.f.write(raw); self.f.flush()
        self.stream_samples += len(raw) // BPS
        self.seg.add(len(raw), now, self.stream_samples)
        if now - self.last_side > 5:          # provisional sidecar, refreshed every 5 s
            self.last_side = now; self.seg.write()

    def close(self):
        if self.f:
            self.f.close(); self.f = None
            if self.seg and self.seg.samples:
                self.seg.write(final=True)
