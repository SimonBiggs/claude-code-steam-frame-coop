extends RefCounted
## One procedural song: tempo, chords, style, the backing loop (bass, chord stabs, kick and shaker,
## shaped by the style) and the note charts for the guitars (3 lanes) and the drums (4 pads).
## The same (index, bars) gives the same song on both machines (seeded RNG, no randf()).
## The players ARE the melody and the drums: hitting a guitar note plays its pitch (chord tones, so
## the left lane is low and the right lane is high), hitting a drum plays that drum.
## Every note has a LEVEL: 0 = EASY (on the beat, well spaced), 1 = NORMAL, 2 = ROCK (extra notes).
## A player plays the notes up to their own level, so a little kid on EASY and a grown-up on ROCK
## play the same song together. Notes in the STAR phrases are gold: hitting them charges STAR POWER.
## Simple mode (main.gd SIMPLE_MODE) sets no_stars (no gold notes) and, for the first song, two_lanes
## (the middle lane's notes move to the outer lanes, alternating; the pitches stay the same).

const RATE := 22050
const COUNT_IN := 2  # bars of backing + count-in clicks before the first note
const OUTRO := 1
const LOOP_BARS := 8
const MIN_GAP := 0.26  # seconds between NORMAL guitar notes (kid friendly)
const EASY_GAP := 0.9  # EASY: about every other beat
const ROCK_GAP := 0.17
const SONGS := [
	# name, bpm, key (MIDI), chord progression [root offset, minor?] (2 bars each), style
	{"name": "Sunny Skip", "bpm": 92.0, "key": 60, "prog": [[0, false], [7, false], [9, true], [5, false]], "style": "pop"},
	{"name": "Dino Stomp", "bpm": 84.0, "key": 52, "prog": [[0, true], [8, false], [5, true], [7, false]], "style": "stomp"},
	{"name": "Jungle Drums", "bpm": 104.0, "key": 62, "prog": [[0, false], [5, false], [7, false], [5, false]], "style": "bongo"},
	{"name": "Rocket Pop", "bpm": 112.0, "key": 55, "prog": [[9, true], [5, false], [0, false], [7, false]], "style": "rock"},
	{"name": "Bubble Disco", "bpm": 120.0, "key": 57, "prog": [[0, true], [5, true], [10, false], [3, false]], "style": "disco"},
	{"name": "Thunder Jam", "bpm": 132.0, "key": 57, "prog": [[0, true], [8, false], [3, false], [10, false]], "style": "rock"},
]
const LEVEL_NAMES: Array[String] = ["EASY", "NORMAL", "ROCK"]

var idx := 0
var title := ""
var style := "pop"
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
var g_lvl := PackedByteArray()
var g_star := PackedByteArray()
var d_t := PackedFloat32Array()
var d_pad := PackedByteArray()
var d_lvl := PackedByteArray()
var d_star := PackedByteArray()
var no_stars := false  # set before setup()
var two_lanes := false  # set before setup()
var loop_bytes := PackedByteArray()  # filled by synth_loop() (runs on a worker thread)


static func song_count() -> int:
	return SONGS.size()


static func song_name(i: int) -> String:
	var d: Dictionary = SONGS[posmod(i, SONGS.size())]
	return str(d["name"])


static func song_bpm(i: int) -> float:
	var d: Dictionary = SONGS[posmod(i, SONGS.size())]
	return float(d["bpm"])


## A tour: one slow, one middle and one fast song (random each time, slow -> fast).
static func make_setlist(rng_seed: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var order: Array[int] = []
	for i in SONGS.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return song_bpm(a) < song_bpm(b))
	var third := order.size() / 3
	var out: Array[int] = []
	for k in 3:
		out.append(order[k * third + rng.randi_range(0, third - 1)])
	return out


func setup(index: int, note_bars: int) -> void:
	idx = index
	var base: Dictionary = SONGS[index % SONGS.size()]
	var lap := index / SONGS.size()
	title = str(base["name"]) + ("" if lap == 0 else " (ENCORE)")
	style = str(base.get("style", "pop"))
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
	return "rb2_%d" % idx


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


## STAR phrases: two bars out of every eight (gold notes).
func is_star_bar(nb: int) -> bool:
	if no_stars:
		return false
	return nb % 8 == 4 or nb % 8 == 5


## How many notes a player on `level` gets (for the results and the bots).
func guitar_count(level: int) -> int:
	var n := 0
	for l in g_lvl:
		if int(l) <= level:
			n += 1
	return n


func _make_charts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx * 7919
	# Busyness from the tempo (slow songs simple, fast songs busy), plus one per encore lap.
	var diff := (0 if bpm < 100.0 else (1 if bpm < 118.0 else 2)) + idx / SONGS.size()
	# Guitar: one catchy 2-bar motif per section (16 eighth-note steps), repeated over the chords.
	# notes: [time, lane, pitch, level, star]
	var notes: Array = []
	var last := -10.0
	var last_easy := -10.0
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
			var star := 1 if is_star_bar(nb) else 0
			for st in 8:
				var ln := motif[half * 8 + st]
				var t := (bar * 4.0 + st * 0.5) * spb
				if ln < 0:
					# ROCK players get extra notes in some of the gaps.
					if st % 2 == 1 and nb != bars - 1 and rng.randf() < 0.45 and t - last >= ROCK_GAP:
						var rl := clampi(lane + (1 if rng.randf() < 0.5 else -1), 0, 2)
						notes.append([t, rl, pitch_for(c, rl), 2, star])
					continue
				if nb == bars - 1 and st > 0:
					continue  # last bar: one big final note
				if nb % 4 == 3 and st >= 6:
					continue  # breathe at the end of each phrase
				if t - last < MIN_GAP:
					continue
				last = t
				var lvl := 1
				if st % 2 == 0 and t - last_easy >= EASY_GAP:
					lvl = 0
					last_easy = t
				notes.append([t, ln, pitch_for(c, ln), lvl, star])
	notes.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	g_t = PackedFloat32Array()
	g_lane = PackedByteArray()
	g_pitch = PackedInt32Array()
	g_lvl = PackedByteArray()
	g_star = PackedByteArray()
	var prev_lane := 2
	for nv in notes:
		var na: Array = nv
		g_t.append(float(na[0]))
		var nl := int(na[1])
		if two_lanes:
			if nl == 1:
				nl = 0 if prev_lane == 2 else 2
			prev_lane = nl
		g_lane.append(nl)
		g_pitch.append(int(na[2]))
		g_lvl.append(int(na[3]))
		g_star.append(int(na[4]))
	# Drums (hi-hat 0, snare 1, tom 2, crash 3): beats that get busier through the song, in the song's
	# style. EASY: the snare backbeat and a crash on each phrase. ROCK: extra hi-hats.
	var drums: Array = []  # [beat, pad, level]
	d_t = PackedFloat32Array()
	d_pad = PackedByteArray()
	d_lvl = PackedByteArray()
	d_star = PackedByteArray()
	for nb in bars:
		var bar := COUNT_IN + nb
		var sec := nb * 3 / bars
		var lvl := diff + sec
		var hits := _drum_bar(lvl, nb)
		if nb % 4 == 0 and lvl >= 1:
			var first: Array = hits[0]
			if float(first[0]) == 0.0:
				hits[0] = [0.0, 3]
			else:
				hits.push_front([0.0, 3])
		if nb == bars - 1:
			hits = [[0.0, 3]]
		var used := {}
		for h in hits:
			var ha: Array = h
			var beat: float = ha[0]
			var pad: int = ha[1]
			var level := 1
			if (pad == 1 and (beat == 1.0 or beat == 3.0)) or (pad == 3 and beat == 0.0 and nb % 4 == 0):
				level = 0
			used[beat] = true
			drums.append([bar * 4.0 + beat, pad, level, 1 if is_star_bar(nb) else 0])
		# Easy players always have their backbeat, even in bars whose pattern has none.
		if nb != bars - 1:
			for bb in [1.0, 3.0]:
				var bbf: float = bb
				if not used.has(bbf):
					drums.append([bar * 4.0 + bbf, 1, 0, 1 if is_star_bar(nb) else 0])
					used[bbf] = true
		# ROCK: hi-hats on the free off-beats.
		if nb != bars - 1 and nb % 4 != 3:
			for ob in [0.5, 1.5, 2.5, 3.5]:
				var obf: float = ob
				if not used.has(obf) and rng.randf() < 0.7:
					drums.append([bar * 4.0 + obf, 0, 2, 1 if is_star_bar(nb) else 0])
	drums.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for dv in drums:
		var da: Array = dv
		d_t.append(float(da[0]) * spb)
		d_pad.append(int(da[1]))
		d_lvl.append(int(da[2]))
		d_star.append(int(da[3]))


## One bar of drums for this style and busyness level: [[beat, pad], ...]
func _drum_bar(lvl: int, nb: int) -> Array:
	var hits: Array = []
	match style:
		"stomp":
			hits = [[0.0, 2], [1.0, 1], [2.0, 2], [3.0, 1]]
			if lvl >= 2:
				hits = [[0.0, 2], [1.0, 1], [2.0, 2], [2.5, 2], [3.0, 1]]
		"bongo":
			hits = [[0.0, 2], [1.0, 1], [1.5, 2], [3.0, 1]]
			if lvl >= 1:
				hits = [[0.0, 2], [0.5, 2], [1.0, 1], [2.0, 2], [3.0, 1], [3.5, 2]]
		"disco":
			hits = [[0.5, 0], [1.0, 1], [1.5, 0], [3.0, 1], [3.5, 0]]
			if lvl >= 1:
				hits = [[0.0, 2], [0.5, 0], [1.0, 1], [1.5, 0], [2.0, 2], [2.5, 0], [3.0, 1], [3.5, 0]]
		_:
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
	return hits


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
		match style:
			"disco":
				if b16 % 2 == 0:
					var oct := 12 if b16 % 4 == 2 else 0  # octave-jumping disco bass
					_tone(buf, t0, step * 1.5, freq(key - 24 + r + oct), 0.3, true, 8.0)
				if b16 % 4 == 0:
					_kick(buf, t0, 0.4)
				if b16 % 4 == 2:
					_noise(buf, t0, 0.09, 0.07, s)  # open hat on the off-beat
				if b16 % 8 == 4:
					for iv in [0, third, 7]:
						var ivi: int = iv
						_tone(buf, t0, step * 1.2, freq(key + r + ivi), 0.08, false, 10.0)
			"stomp":
				if b16 % 4 == 0:
					_tone(buf, t0, step * 3.5, freq(key - 24 + r), 0.36, true, 4.0)
				if b16 % 8 == 0:
					_kick(buf, t0, 0.55)
				if b16 % 8 == 4:
					for iv in [0, 7]:
						var ivi2: int = iv
						_tone(buf, t0, step * 3.0, freq(key - 12 + r + ivi2), 0.1, true, 3.0)
				if b16 % 4 == 2:
					_noise(buf, t0, 0.03, 0.04, s)
			"bongo":
				if b16 % 4 == 0 or b16 % 16 == 6 or b16 % 16 == 10:
					_tone(buf, t0, step * 1.4, freq(key - 24 + r), 0.3, false, 9.0)
				if b16 % 3 == 0:
					_bongo(buf, t0, 0.18 if b16 % 2 == 0 else 0.12, 220.0 if b16 % 6 == 0 else 330.0)
				if b16 % 8 == 4:
					for iv in [0, third, 7, 12]:
						var ivi3: int = iv
						_tone(buf, t0 + int(ivi3 * 0.004 * RATE), step * 1.6, freq(key + r + ivi3), 0.05, false, 7.0)
				_noise(buf, t0, 0.02, 0.025, s)
			_:
				if b16 % 2 == 0:
					var oct2 := 12 if (b16 % 8 == 6 and idx >= 1) else 0
					_tone(buf, t0, step * 1.7, freq(key - 24 + r + oct2), 0.3, true, 7.0)
				if b16 % 4 == 2:
					for iv in [0, third, 7]:
						var ivi4: int = iv
						_tone(buf, t0, step * 1.4, freq(key + r + ivi4), 0.07, false, 9.0)
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


func _bongo(buf: PackedFloat32Array, t0: int, amp: float, f: float) -> void:
	var count := int(0.16 * RATE)
	var n := buf.size()
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += (f + f * 0.6 * exp(-t * 40.0)) / RATE
		buf[(t0 + i) % n] += sin(phase * TAU) * amp * exp(-t * 22.0)


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
