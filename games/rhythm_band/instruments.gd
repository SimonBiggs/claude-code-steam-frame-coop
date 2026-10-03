extends Node
## The band's instruments, synthesized in code: four drums, a plucked guitar (Karplus-Strong) for any
## pitch, count-in sticks, a cheering crowd and a few UI chimes. Streams are cached on the Engine so
## restarts and hot reloads don't rebuild them.

const RATE := 22050
const VOICES := 20

var voices: Array[AudioStreamPlayer] = []
var next_voice := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)


func _cache() -> Dictionary:
	if not Engine.has_meta("rhythm_band_sounds"):
		Engine.set_meta("rhythm_band_sounds", {})
	return Engine.get_meta("rhythm_band_sounds")


func _play(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	if voices.is_empty():
		return
	var p := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _stream_for(sound_key: String) -> AudioStreamWAV:
	var c := _cache()
	if c.has(sound_key):
		return c[sound_key]
	var buf := PackedFloat32Array()
	match sound_key:
		"drum0":
			buf = _hat()
		"drum1":
			buf = _snare()
		"drum2":
			buf = _tom()
		"drum3":
			buf = _crash()
		"click":
			buf = _sine(1900.0, 0.035, 60.0, 0.5)
		"cheer":
			buf = _cheer()
		"miss":
			buf = _sine(150.0, 0.12, 25.0, 0.35)
		"chime":
			buf = _chime()
		_:
			if sound_key.begins_with("pluck"):
				buf = _pluck(int(sound_key.substr(5)))
	var w := _to_stream(buf)
	c[sound_key] = w
	return w


func drum(pad: int, volume_db: float = 0.0) -> void:
	_play(_stream_for("drum%d" % clampi(pad, 0, 3)), volume_db, randf_range(0.97, 1.03))


func pluck(midi: int, volume_db: float = -3.0) -> void:
	_play(_stream_for("pluck%d" % clampi(midi, 36, 96)), volume_db)


func click(accent: bool) -> void:
	_play(_stream_for("click"), -4.0 if accent else -9.0, 1.25 if accent else 1.0)


func cheer(volume_db: float = -4.0) -> void:
	_play(_stream_for("cheer"), volume_db, randf_range(0.92, 1.08))


func miss() -> void:
	_play(_stream_for("miss"), -14.0)


func chime(pitch: float = 1.0) -> void:
	_play(_stream_for("chime"), -6.0, pitch)


## Builds the drum and guitar sounds a song needs before it starts (no hitch on the first hit).
func warm(midis: Array[int]) -> void:
	for i in 4:
		_stream_for("drum%d" % i)
	for m in midis:
		_stream_for("pluck%d" % clampi(m, 36, 96))


# --- Synthesis -----------------------------------------------------------------------

func _hat() -> PackedFloat32Array:
	var n := int(0.09 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := randf_range(-1.0, 1.0)
		b[i] = (w - prev) * 0.6 * exp(-t * 45.0)
		prev = w
	return b


func _snare() -> PackedFloat32Array:
	var n := int(0.26 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.6
		b[i] = lp * 0.8 * exp(-t * 16.0) + sin(t * 185.0 * TAU) * 0.6 * exp(-t * 28.0)
	return b


func _tom() -> PackedFloat32Array:
	var n := int(0.42 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += (85.0 + 90.0 * exp(-t * 14.0)) / RATE
		b[i] = sin(phase * TAU) * exp(-t * 7.0) + randf_range(-1.0, 1.0) * 0.15 * exp(-t * 40.0)
	return b


func _crash() -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var prev := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		lp += (hp - lp) * 0.7
		b[i] = lp * 0.7 * exp(-t * 3.2) * minf(1.0, t * 400.0)
	return b


func _sine(f: float, dur: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / RATE
		b[i] = sin(t * f * TAU) * amp * exp(-t * decay)
	return b


func _chime() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / RATE
		b[i] = (sin(t * 1046.5 * TAU) * 0.5 + sin(t * 1568.0 * TAU) * 0.35 + sin(t * 2093.0 * TAU) * 0.2) * exp(-t * 5.0)
	return b


## A plucked string: a burst of noise in a delay line that softens every round trip.
func _pluck(midi: int) -> PackedFloat32Array:
	var f := 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
	var period := maxi(2, int(RATE / f))
	var n := int(0.7 * RATE)
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = randf_range(-1.0, 1.0)
	var b := PackedFloat32Array()
	b.resize(n)
	var k := 0
	for i in n:
		var a := line[k]
		var nxt := line[(k + 1) % period]
		var v := (a + nxt) * 0.5 * 0.997
		line[k] = v
		k = (k + 1) % period
		var t := float(i) / RATE
		# A touch of square on top so it cuts through like a little electric guitar.
		var sq := 0.18 if fmod(t * f, 1.0) < 0.5 else -0.18
		b[i] = a * 0.8 + sq * exp(-t * 9.0)
	return b


func _cheer() -> PackedFloat32Array:
	var n := int(1.8 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rates: Array[float] = [5.3, 7.1, 9.7, 6.2, 11.3]
	var phases: Array[float] = [0.0, 1.3, 2.1, 0.7, 2.9]
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		var mod := 0.0
		for k in rates.size():
			mod += 0.5 + 0.5 * sin(t * rates[k] * TAU + phases[k])
		mod /= rates.size()
		var env := minf(1.0, t * 4.0) * minf(1.0, (1.8 - t) * 1.2)
		b[i] = (lp - lp2 * 0.5) * (0.4 + 0.8 * mod) * env * 1.4
	return b


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var g := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
