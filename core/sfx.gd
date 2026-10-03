extends Node
## Procedurally generated sound effects, so the game needs no audio files.

const RATE := 22050
const VOICES := 24

var streams := {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)


# name: [seconds, start Hz, end Hz, volume, wave, noise mix]
const DEFS := {
	"shoot": [0.07, 950.0, 420.0, 0.16, "square", 0.0],
	"hit": [0.05, 260.0, 120.0, 0.3, "square", 0.4],
	"kill": [0.22, 420.0, 60.0, 0.45, "saw", 0.6],
	"big_kill": [0.7, 180.0, 25.0, 0.7, "saw", 0.5],
	"hurt": [0.12, 320.0, 140.0, 0.35, "saw", 0.2],
	"down": [0.8, 620.0, 70.0, 0.5, "saw", 0.1],
	"revive": [0.45, 330.0, 1320.0, 0.35, "sine", 0.0],
	"pickup": [0.18, 620.0, 1560.0, 0.3, "square", 0.0],
	"dash": [0.14, 1400.0, 300.0, 0.22, "sine", 0.8],
	"wave": [0.5, 392.0, 784.0, 0.35, "tri", 0.0],
	"clear": [0.7, 523.0, 1046.0, 0.35, "tri", 0.0],
	"gameover": [1.4, 330.0, 40.0, 0.5, "saw", 0.15],
	"zap": [0.09, 1800.0, 900.0, 0.12, "saw", 0.5],
	"spit": [0.18, 260.0, 620.0, 0.3, "sine", 0.35],
}


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		if not DEFS.has(sound):
			return
		var d: Array = DEFS[sound]
		streams[sound] = _make(d[0], d[1], d[2], d[3], d[4], d[5])
	var p := voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func _make(duration: float, f0: float, f1: float, vol: float, shape: String, noise: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var held := 0.0
	for i in n:
		var t := float(i) / n
		phase += f0 * pow(f1 / f0, t) / RATE
		var ph := fmod(phase, 1.0)
		var s := 0.0
		match shape:
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = ph * 2.0 - 1.0
			"tri":
				s = absf(ph * 4.0 - 2.0) - 1.0
			_:
				s = sin(phase * TAU)
		if noise > 0.0:
			if i % 3 == 0:
				held = randf_range(-1.0, 1.0)
			s = lerpf(s, held, noise)
		var env := (1.0 - t) * (1.0 - t) * minf(1.0, i / (RATE * 0.004))
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
