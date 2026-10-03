extends AudioStreamPlayer
## Peaceful lakeside loop: soft pad chords, a slow plucked pentatonic melody and a gentle bass.
## Synthesized once on a worker thread and cached on the Engine (survives restarts and hot reloads).

const RATE := 22050
const BPM := 70.0
const BARS := 16
const CACHE := "fishing_lake_music"
# Chord roots (MIDI), one per 2 bars, and whether each is minor.
const ROOTS: Array[int] = [60, 57, 53, 55, 60, 64, 53, 55]
const MINOR: Array[bool] = [false, true, false, false, false, true, false, false]
const SCALE: Array[int] = [0, 2, 4, 7, 9]  # major pentatonic: nothing ever clashes

var task := -1
var buffer := PackedFloat32Array()


func _ready() -> void:
	volume_db = -15.0
	if Engine.has_meta(CACHE):
		stream = Engine.get_meta(CACHE)
		play()
	else:
		task = WorkerThreadPool.add_task(_synthesize)


func _process(_delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		var w := _to_stream(buffer)
		buffer = PackedFloat32Array()
		Engine.set_meta(CACHE, w)
		stream = w
		play()


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1


static func _freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _synthesize() -> void:
	var beat := 60.0 / BPM
	var total := int(BARS * 4 * beat * RATE)
	buffer.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var deg := 2
	for bar in BARS:
		var ci := (bar / 2) % ROOTS.size()
		var root: int = ROOTS[ci]
		var third := 3 if MINOR[ci] else 4
		var t_bar := bar * 4 * beat
		if bar % 2 == 0:
			for iv in [0, third, 7, 12]:
				var ivi: int = iv
				_tone(int(t_bar * RATE), beat * 8.2, _freq(root + ivi), 0.035, 0.6, 1.2)
			_tone(int(t_bar * RATE), beat * 3.8, _freq(root - 24), 0.12, 1.2, 0.05)
		else:
			_tone(int(t_bar * RATE), beat * 3.8, _freq(root - 17), 0.1, 1.2, 0.05)
		# Melody: a slow random walk on the pentatonic scale, with rests.
		for b in 8:
			if rng.randf() < 0.3:
				continue
			deg = clampi(deg + rng.randi_range(-2, 2), 0, 9)
			var note := 72 + SCALE[deg % 5] + 12 * (deg / 5)
			var t0 := t_bar + b * beat * 0.5
			_tone(int(t0 * RATE), beat * 2.0, _freq(note), 0.06, 3.5, 0.0)
			if rng.randf() < 0.25:
				_tone(int((t0 + beat * 0.25) * RATE), beat * 1.5, _freq(note + 12), 0.025, 4.5, 0.0)


## Sine tone with a soft attack (seconds) and exponential decay; wraps for a seamless loop.
func _tone(t0: int, dur: float, f: float, amp: float, decay: float, attack: float) -> void:
	var count := int(dur * RATE)
	var phase := 0.0
	var step := f / RATE
	var n := buffer.size()
	for i in count:
		var idx := (t0 + i) % n
		phase += step
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t / maxf(attack, 0.004)) * minf(1.0, float(count - i) / 400.0)
		var s := sin(phase * TAU) + 0.25 * sin(phase * TAU * 2.0)
		buffer[idx] += s * amp * env


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = buf.size()
	return w
