extends AudioStreamPlayer
## Procedural synthwave loop (Am - F - C - G, 112 BPM), synthesized once on a worker thread and cached.

const RATE := 22050
const BPM := 112.0
const BARS := 8
const ROOTS := [57, 53, 48, 55]  # A, F, C, G (MIDI), two bars each
const MINOR := [true, false, false, false]

static var cached: AudioStreamWAV

var task := -1
var buffer := PackedFloat32Array()


func _ready() -> void:
	volume_db = -13.0
	if cached:
		_start(cached)
	else:
		task = WorkerThreadPool.add_task(_synthesize)


func _process(_delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		cached = _to_stream(buffer)
		buffer = PackedFloat32Array()
		_start(cached)


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


func _start(s: AudioStreamWAV) -> void:
	stream = s
	play()


static func _freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _synthesize() -> void:
	var step := 60.0 / BPM / 4.0  # sixteenth note
	var steps := BARS * 16
	var n := int(steps * step * RATE)
	buffer.resize(n)
	for s in steps:
		var chord := (s / 32) % 4
		var root: int = ROOTS[chord]
		var third := 3 if MINOR[chord] else 4
		var t0 := int(s * step * RATE)
		var beat := s % 16
		# Bass: driving eighth notes, octave jump on the off-beat.
		if s % 2 == 0:
			_tone(t0, step * 1.8, _freq(root - 24 + (12 if s % 4 == 2 else 0)), 0.28, "saw", 6.0)
		# Arpeggio: chord tones climbing, an octave up.
		var arp: int = [0, third, 7, 12, 7, third][s % 6]
		_tone(t0, step * 0.9, _freq(root + 12 + arp), 0.07, "square", 9.0)
		# Pad on each chord change.
		if s % 32 == 0:
			for iv in [0, third, 7]:
				_tone(t0, step * 31.0, _freq(root + iv), 0.05, "saw", 0.4)
		# Drums.
		if beat % 4 == 0:
			_kick(t0)
		if beat == 4 or beat == 12:
			_noise(t0, 0.16, 0.22, 0.4)
		if beat % 4 == 2:
			_noise(t0, 0.05, 0.07, 0.0)


func _tone(t0: int, dur: float, f: float, amp: float, shape: String, decay: float) -> void:
	var count := int(dur * RATE)
	var phase := 0.0
	var lp := 0.0
	for i in count:
		var idx := t0 + i
		if idx >= buffer.size():
			idx -= buffer.size()  # wrap so the loop is seamless
		phase = fmod(phase + f / RATE, 1.0)
		var v := (phase * 2.0 - 1.0) if shape == "saw" else (1.0 if phase < 0.5 else -1.0)
		lp += (v - lp) * 0.18  # soften the edges
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 200.0) * minf(1.0, (count - i) / 120.0)
		buffer[idx] += lp * amp * env


func _kick(t0: int) -> void:
	var count := int(0.25 * RATE)
	var phase := 0.0
	for i in count:
		var idx := (t0 + i) % buffer.size()
		var t := float(i) / RATE
		phase += (40.0 + 110.0 * exp(-t * 28.0)) / RATE
		buffer[idx] += sin(phase * TAU) * 0.55 * exp(-t * 11.0)


func _noise(t0: int, dur: float, amp: float, tone: float) -> void:
	var count := int(dur * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = t0
	for i in count:
		var idx := (t0 + i) % buffer.size()
		var t := float(i) / RATE
		var v := lerpf(rng.randf_range(-1.0, 1.0), sin(t * 190.0 * TAU), tone)
		buffer[idx] += v * amp * exp(-t * (14.0 / dur * 0.1))


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = buf.size()
	return w
