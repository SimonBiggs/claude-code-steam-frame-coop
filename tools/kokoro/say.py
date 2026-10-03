# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["kokoro-onnx", "soundfile"]
# ///
"""kokoro say: uv run say.py VOICE OUT.wav < text"""
import sys, soundfile as sf
from kokoro_onnx import Kokoro
k = Kokoro(__file__.rsplit("/", 1)[0] + "/kokoro-v1.0.onnx", __file__.rsplit("/", 1)[0] + "/voices-v1.0.bin")
lang = "en-gb" if sys.argv[1].startswith("b") else "en-us"
samples, sr = k.create(sys.stdin.read(), voice=sys.argv[1], speed=1.05, lang=lang)
sf.write(sys.argv[2], samples, sr)
