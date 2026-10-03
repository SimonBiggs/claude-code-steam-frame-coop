extends AudioStreamPlayer
## Procedural soundtrack: several synthwave loops, each synthesized once on a worker thread and cached.
## The track changes with the wave (track = wave % count), so both machines play the same one.

const RATE := 22050
const BARS := 8
const TRACKS := [
	# name, bpm, chord roots (MIDI, 2 bars each), minor chords?, arpeggio steps, bass pattern
	{"name": "Neon Drive", "bpm": 112.0, "roots": [57, 53, 48, 55], "minor": [true, false, false, false],
		"arp": [0, "3rd", 7, 12, 7, "3rd"], "bass": "octave"},
	{"name": "Overdrive", "bpm": 128.0, "roots": [50, 46, 48, 45], "minor": [true, false, false, true],
		"arp": [12, 7, "3rd", 0, "3rd", 7, 12, 15], "bass": "gallop"},
	{"name": "Night City", "bpm": 96.0, "roots": [48, 55, 57, 53], "minor": [false, false, true, false],
		"arp": [0, 7, 12, "3rd", 12, 7], "bass": "root"},
]

static var cached := {}  # track index -> AudioStreamWAV

var current := -1
var wanted := 0
var task := -1
var task_track := -1
var buffer := PackedFloat32Array()
var track: Dictionary


func _ready() -> void:
	volume_db = -13.0
	play_track(0)


## Switch to a track (by index, wrapped). Synthesizes it in the background the first time.
func play_track(index: int) -> void:
	wanted = index % TRACKS.size()
	if wanted == current:
		return
	if cached.has(wanted):
		current = wanted
		stream = cached[wanted]
		play()
	elif task < 0:
		task_track = wanted
		track = TRACKS[wanted]
		buffer = PackedFloat32Array()
		task = WorkerThreadPool.add_task(_synthesize)


func _process(_delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		cached[task_track] = _to_stream(buffer)
		buffer = PackedFloat32Array()
		var w := wanted
		current = -1
		play_track(w)


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


static func _freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _synthesize() -> void:
	var step := 60.0 / float(track.bpm) / 4.0  # sixteenth note
	var steps := BARS * 16
	buffer.resize(int(steps * step * RATE))
	var arp_steps: Array = track.arp
	for s in steps:
		var chord := (s / 32) % 4
		var root: int = track.roots[chord]
		var third := 3 if track.minor[chord] else 4
		var t0 := int(s * step * RATE)
		var beat := s % 16
		match track.bass:
			"octave":
				if s % 2 == 0:
					_tone(t0, step * 1.8, _freq(root - 24 + (12 if s % 4 == 2 else 0)), 0.28, "saw", 6.0)
			"gallop":
				if beat % 4 != 1:
					_tone(t0, step * 0.9, _freq(root - 24), 0.3, "saw", 10.0)
			_:
				if s % 4 == 0:
					_tone(t0, step * 3.6, _freq(root - 24), 0.3, "saw", 3.0)
		var a = arp_steps[s % arp_steps.size()]
		var interval: int = third if a is String else a
		_tone(t0, step * 0.9, _freq(root + 12 + interval), 0.07, "square", 9.0)
		if s % 32 == 0:
			for iv in [0, third, 7]:
				_tone(t0, step * 31.0, _freq(root + iv), 0.05, "saw", 0.4)
		if beat % 4 == 0:
			_kick(t0)
		if beat == 4 or beat == 12:
			_noise(t0, 0.16, 0.22, 0.4)
		if beat % 2 == 1 and track.bpm > 120.0:
			_noise(t0, 0.03, 0.05, 0.0)  # busier hats on the fast track
		elif beat % 4 == 2:
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
