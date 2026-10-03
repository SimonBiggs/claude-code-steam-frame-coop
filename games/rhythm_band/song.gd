extends RefCounted
## One procedural song: tempo, chords, the backing loop (bass, off-beat chord stabs, soft kick and
## shaker) and the note charts for the guitars (3 lanes) and the drums (4 pads).
## The same (index, bars) gives the same song on both machines (seeded RNG, no randf()).
## The players ARE the melody and the drums: hitting a guitar note plays its pitch (chord tones, so
## the left lane is low and the right lane is high), hitting a drum plays that drum.

const RATE := 22050
const COUNT_IN := 2  # bars of backing + count-in clicks before the first note
const OUTRO := 1
const LOOP_BARS := 8
const MIN_GAP := 0.26  # seconds between guitar notes (kid friendly)
const SONGS := [
	# name, bpm, key (MIDI), chord progression [root offset, minor?] (2 bars each)
	{"name": "Sunny Skip", "bpm": 92.0, "key": 60, "prog": [[0, false], [7, false], [9, true], [5, false]]},
	{"name": "Rocket Pop", "bpm": 112.0, "key": 55, "prog": [[9, true], [5, false], [0, false], [7, false]]},
	{"name": "Thunder Jam", "bpm": 132.0, "key": 57, "prog": [[0, true], [8, false], [3, false], [10, false]]},
]

var idx := 0
var title := ""
var bpm := 100.0
var spb := 0.6
var bars := 24
var total_bars := 27
var length := 0.0
var key := 60
var roots: Array[int] = []
var minor: Array[bool] = []
var g_t := PackedFloat32Array()
var g_lane := PackedByteArray()
var g_pitch := PackedInt32Array()
var d_t := PackedFloat32Array()
var d_pad := PackedByteArray()
var loop_bytes := PackedByteArray()  # filled by synth_loop() (runs on a worker thread)


static func song_count() -> int:
	return SONGS.size()


func setup(index: int, note_bars: int) -> void:
	idx = index
	var base: Dictionary = SONGS[index % SONGS.size()]
	var lap := index / SONGS.size()
	title = str(base["name"]) + ("" if lap == 0 else " (ENCORE)")
	bpm = float(base["bpm"]) + 12.0 * lap
	spb = 60.0 / bpm
	key = int(base["key"])
	roots.clear()
	minor.clear()
	var prog: Array = base["prog"]
	for c in prog:
		var ca: Array = c
		var r: int = int(ca[0])
		if r > 6:
			r -= 12  # keep the chords close to the key
		roots.append(r)
		minor.append(bool(ca[1]))
	bars = maxi(2, note_bars)
	total_bars = COUNT_IN + bars + OUTRO
	length = total_bars * 4.0 * spb
	_make_charts()


func loop_key() -> String:
	return "rb1_%d" % idx


func chord_of_bar(bar: int) -> int:
	return (bar / 2) % 4


func bar_at(t: float) -> int:
	return int(floorf(t / (4.0 * spb)))


## The chord tone a lane plays: left = root, middle = third, right = fifth (an octave up).
func pitch_for(chord: int, lane: int) -> int:
	var third := 3 if minor[chord] else 4
	var tones: Array[int] = [0, third, 7]
	return key + 12 + roots[chord] + tones[clampi(lane, 0, 2)]


func lane_pitch_at(t: float, lane: int) -> int:
	return pitch_for(chord_of_bar(maxi(0, bar_at(t))), lane)


func _make_charts() -> void:
	g_t = PackedFloat32Array()
	g_lane = PackedByteArray()
	g_pitch = PackedInt32Array()
	d_t = PackedFloat32Array()
	d_pad = PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx * 7919
	var diff := mini(idx, 3)
	# Guitar: one catchy 2-bar motif per section (16 eighth-note steps), repeated over the chords.
	var last := -10.0
	for sec in 3:
		var motif: Array[int] = []
		var density := 0.3 + 0.12 * diff + 0.1 * sec
		var lane := 1
		for s in 16:
			var on := false
			if s % 2 == 0:
				on = rng.randf() < density + 0.35
			elif diff >= 1:
				on = rng.randf() < density - 0.3
			if s == 0:
				on = true
			if on:
				if rng.randf() < 0.25:
					lane = rng.randi_range(0, 2)
				else:
					lane = clampi(lane + rng.randi_range(-1, 1), 0, 2)
				motif.append(lane)
			else:
				motif.append(-1)
		var b0 := sec * bars / 3
		var b1 := (sec + 1) * bars / 3
		for nb in range(b0, b1):
			var bar := COUNT_IN + nb
			var half := nb % 2
			var c := chord_of_bar(bar)
			for st in 8:
				var ln := motif[half * 8 + st]
				if ln < 0:
					continue
				if nb == bars - 1 and st > 0:
					continue  # last bar: one big final note
				if nb % 4 == 3 and st >= 6:
					continue  # breathe at the end of each phrase
				var t := (bar * 4.0 + st * 0.5) * spb
				if t - last < MIN_GAP:
					continue
				last = t
				g_t.append(t)
				g_lane.append(ln)
				g_pitch.append(pitch_for(c, ln))
	# Drums: simple rock beats that get busier through the song (hi-hat 0, snare 1, tom 2, crash 3).
	for nb in bars:
		var bar := COUNT_IN + nb
		var sec := nb * 3 / bars
		var lvl := diff + sec
		var hits: Array = []
		if lvl <= 0:
			hits = [[1.0, 1], [3.0, 1]]
		elif lvl == 1:
			hits = [[0.0, 2], [1.0, 1], [3.0, 1]]
		elif lvl == 2:
			hits = [[0.0, 2], [1.0, 1], [2.0, 2], [3.0, 1]]
		elif lvl == 3:
			hits = [[0.0, 2], [1.0, 1], [2.0, 0], [3.0, 1]]
		else:
			hits = [[0.0, 2], [1.0, 1], [2.0, 0], [2.5, 0], [3.0, 1]]
		if lvl >= 3 and nb % 4 == 3 and nb != bars - 1:
			hits = [[0.0, 2], [1.0, 1], [2.0, 1], [2.5, 2], [3.0, 1], [3.5, 2]]  # a little fill
		if nb % 4 == 0 and lvl >= 1:
			var first: Array = hits[0]
			if float(first[0]) == 0.0:
				hits[0] = [0.0, 3]
			else:
				hits.push_front([0.0, 3])
		if nb == bars - 1:
			hits = [[0.0, 3]]
		for h in hits:
			var ha: Array = h
			d_t.append((bar * 4.0 + float(ha[0])) * spb)
			d_pad.append(int(ha[1]))


# --- Backing track (worker thread) -------------------------------------------------------

static func freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Synthesizes LOOP_BARS bars of backing into loop_bytes (16-bit mono). Touches only this object.
func synth_loop() -> void:
	var step := spb / 4.0
	var n := int(LOOP_BARS * 16 * step * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for s in LOOP_BARS * 16:
		var bar := s / 16
		var b16 := s % 16
		var c := chord_of_bar(bar)
		var r: int = roots[c]
		var third := 3 if minor[c] else 4
		var t0 := int(s * step * RATE)
		if b16 % 2 == 0:
			var oct := 12 if (b16 % 8 == 6 and idx >= 1) else 0
			_tone(buf, t0, step * 1.7, freq(key - 24 + r + oct), 0.3, true, 7.0)
		if b16 % 4 == 2:
			for iv in [0, third, 7]:
				var ivi: int = iv
				_tone(buf, t0, step * 1.4, freq(key + r + ivi), 0.07, false, 9.0)
		if b16 % 8 == 0:
			_kick(buf, t0, 0.4)
		if b16 % 2 == 1:
			_noise(buf, t0, 0.035, 0.05, s)
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	var g := 0.85 / peak
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	loop_bytes = data


func _tone(buf: PackedFloat32Array, t0: int, dur: float, f: float, amp: float, saw: bool, decay: float) -> void:
	var count := int(dur * RATE)
	var n := buf.size()
	var phase := 0.0
	var lp := 0.0
	var inc := f / RATE
	for i in count:
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var v := (phase * 2.0 - 1.0) if saw else (1.0 if phase < 0.5 else -1.0)
		lp += (v - lp) * 0.2
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 300.0) * minf(1.0, float(count - i) / 100.0)
		buf[(t0 + i) % n] += lp * amp * env


func _kick(buf: PackedFloat32Array, t0: int, amp: float) -> void:
	var count := int(0.2 * RATE)
	var n := buf.size()
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += (45.0 + 100.0 * exp(-t * 30.0)) / RATE
		buf[(t0 + i) % n] += sin(phase * TAU) * amp * exp(-t * 14.0)


func _noise(buf: PackedFloat32Array, t0: int, dur: float, amp: float, seed_v: int) -> void:
	var count := int(dur * RATE)
	var n := buf.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var prev := 0.0
	for i in count:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		buf[(t0 + i) % n] += (w - prev) * amp * exp(-t * 60.0)
		prev = w


## The whole song's backing: the loop repeated to the song's length (cheap byte copies).
func make_stream() -> AudioStreamWAV:
	var total := int(length * RATE) * 2
	var data := PackedByteArray()
	if loop_bytes.size() > 0:
		while data.size() < total:
			data.append_array(loop_bytes)
	data.resize(total)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
