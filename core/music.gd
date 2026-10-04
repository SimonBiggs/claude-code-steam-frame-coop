extends AudioStreamPlayer
## Procedural music, so the game needs no audio files. Two families:
##  - the 3 classic synthwave loops: play_track(i) (the original games: track = wave % 3).
##  - composed MOODS with melody, bass, chords, arpeggios, drums, echo and reverb:
##      music.play_mood("town")      cosy village       "overworld"  heroic adventure
##      "battle"   driving fight      "boss"       intense         "dungeon"  mysterious
##      "quiz"     quiz-show swing    "space"      floaty          "cosy"     sleepy lullaby (3/4)
##      "party"    four-on-the-floor  "shop"       bossa           "mystery"  detective jazz
##      "race"     fast rock          "tension"    countdown pulse
##      "victory" / "defeat": short one-shot jingles; afterwards the previous mood fades back in
##      (set resume_after_jingle = false to stay silent).
##    Aliases: sleepy, lullaby -> cosy; adventure -> overworld; detective -> mystery; fanfare -> victory;
##    gameover -> defeat; menu -> town.
## Moods crossfade on two internal decks that follow this node's volume_db, pitch_scale and bus
## ("Music"). Each mood is synthesised once on a worker thread (a few seconds the first time; call
## prepare([...]) early so later switches are instant) and cached for the whole session. Everything
## is seeded, so the host and the TV machine hear the same tune.
##
## Custom tracks: music.add_track({...}) then play_mood(name). Track definition (all optional but "name"):
##   name: String; bpm: float; beats: 4 or 3 (per bar); key: MIDI note of the tonic (60 = C4);
##   scale: "major" | "minor" | "harmonic" | "dorian" | "mixolydian" | "lydian" | "phrygian" | "pent_major" | "pent_minor" | "blues";
##   swing: 0..1; seed: int; loop: bool (false = one-shot jingle, plus "tail": seconds of ring-out);
##   parts: {"A": ["I", "vi", "IV", "V"], "B": [...]} (one chord per bar, roman numerals relative to the
##     key: upper case = major, lower = minor, prefix b/# to borrow (bVII, bVI, bII), suffix 7, maj7, dim,
##     sus4, sus2, 6, aug); form: ["A", "A", "B", "A"]; or simply chords: [...];
##   lead: {inst, vol, style: "lyrical"|"driving"|"bouncy"|"march"|"sparse"|"waltz", density 0..1,
##     oct (semitones above the key for the melody's centre), harmony: bool, echo: [beats, feedback, mix],
##     legato 0..1};
##   melody: [[beat, beats, semitones above key+oct, velocity], ...] (explicit tune instead of a generated one);
##   bass: {inst, vol, oct, pattern: "root"|"root5"|"long"|"drone"|"octave"|"pulse8"|"gallop"|"walking"|"bossa"|"syncop"|"waltz"};
##   pad: {inst, vol, oct, style: "sustain"|"comp"|"stabs"|"waltz"|"halves"|"offbeat"};
##   arp: {inst, vol, oct, rate (16ths per note), pattern: "up"|"updown"|"broken"|"random"};
##   drums: {style: "soft"|"march"|"rock"|"boss"|"four"|"shuffle"|"halftime"|"pulse"|"waltz"|"bossa"|"race"|"none", vol};
##   hits: [[beat, drum, velocity], ...] (drums: k s r h oh c sh t1 t2 cr ride b ti); roll: [from beat, to beat];
##   reverb: 0..1.
## Instruments: sine tri square chip saw brass strings warm organ flute sub synthbass bell epiano marimba
##   pluck guitar pluckbass ("none" = silent part).

signal mood_changed(mood: String)
signal jingle_finished(mood: String)

const SfxScript := preload("res://core/sfx.gd")
const ResCache := preload("res://core/res_cache.gd")

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
const MOOD_VERSION := "m1"
const TARGET_RMS := 0.15

const ALIASES := {"sleepy": "cosy", "lullaby": "cosy", "adventure": "overworld", "detective": "mystery",
	"fanfare": "victory", "gameover": "defeat", "menu": "town"}

const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "harmonic": [0, 2, 3, 5, 7, 8, 11],
	"dorian": [0, 2, 3, 5, 7, 9, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10], "lydian": [0, 2, 4, 6, 7, 9, 11],
	"phrygian": [0, 1, 3, 5, 7, 8, 10], "pent_major": [0, 2, 4, 7, 9], "pent_minor": [0, 3, 5, 7, 10],
	"blues": [0, 3, 5, 6, 7, 10],
}

## osc: subtractive voices (a/d/s/r envelope, lp = low-pass Hz, lpenv = filter sweep on attack, det =
## detuned 2nd oscillator, vib = [Hz, semitones, delay s]); fm = [ratio, index, index decay] bells;
## ks = Karplus-Strong plucked string (decay per sample). g = loudness trim.
const INSTRUMENTS := {
	"sine": {"osc": "sine", "a": 0.01, "d": 0.4, "s": 0.7, "r": 0.1, "g": 1.0},
	"tri": {"osc": "tri", "a": 0.01, "d": 0.4, "s": 0.7, "r": 0.1, "g": 1.0},
	"square": {"osc": "square", "lp": 2600.0, "a": 0.005, "d": 0.25, "s": 0.6, "r": 0.06, "g": 0.5},
	"chip": {"osc": "square", "duty": 0.25, "lp": 5000.0, "a": 0.002, "d": 0.15, "s": 0.55, "r": 0.04, "g": 0.42},
	"saw": {"osc": "saw", "lp": 2200.0, "a": 0.01, "d": 0.3, "s": 0.65, "r": 0.08, "vib": [5.5, 0.12, 0.3], "g": 0.6},
	"brass": {"osc": "saw", "lp": 1100.0, "lpenv": 2400.0, "det": 0.004, "a": 0.035, "d": 0.35, "s": 0.8, "r": 0.12,
		"vib": [5.5, 0.15, 0.25], "g": 0.7},
	"strings": {"osc": "saw", "lp": 1700.0, "det": 0.006, "a": 0.28, "d": 0.6, "s": 0.85, "r": 0.45, "vib": [5.0, 0.08, 0.3], "g": 0.55},
	"warm": {"osc": "tri", "det": 0.005, "a": 0.2, "d": 0.6, "s": 0.85, "r": 0.4, "g": 0.9},
	"organ": {"osc": "organ", "a": 0.03, "d": 0.2, "s": 0.9, "r": 0.12, "g": 0.45},
	"flute": {"osc": "flute", "a": 0.06, "d": 0.3, "s": 0.8, "r": 0.12, "vib": [5.0, 0.18, 0.18], "breath": 0.06, "g": 0.85},
	"sub": {"osc": "sub", "a": 0.008, "d": 0.4, "s": 0.85, "r": 0.08, "g": 1.0},
	"synthbass": {"osc": "saw", "lp": 500.0, "lpenv": 1600.0, "a": 0.004, "d": 0.2, "s": 0.65, "r": 0.06, "g": 0.85},
	"bell": {"fm": [4.0, 1.4, 5.0], "decay": 2.2, "r": 0.25, "g": 0.7},
	"epiano": {"fm": [1.0, 1.6, 3.5], "decay": 1.4, "r": 0.15, "g": 0.75},
	"marimba": {"fm": [4.0, 1.0, 22.0], "decay": 5.5, "r": 0.08, "g": 0.85},
	"pluck": {"ks": 0.996, "bright": 0.6, "r": 0.08, "g": 0.9},
	"guitar": {"ks": 0.998, "bright": 0.35, "r": 0.1, "g": 0.9},
	"pluckbass": {"ks": 0.997, "bright": 0.3, "r": 0.06, "g": 1.1},
}

## Drum grooves: one character per 16th note ("X" accent, "x" normal, "o" soft). k kick, s snare, r rim,
## h hat, oh open hat, c clap, sh shaker, b brush, ride, t1/t2 toms. k2 = kick on every other bar.
## fill: "snare" | "toms" on the last beat of each section; crash / timp on each section's first beat.
const DRUM_STYLES := {
	"soft": {"k": "x.......x.......", "r": "....o.......o...", "sh": "o.o.o.o.o.o.o.o."},
	"march": {"k": "X.......x.......", "s": "....x..o....x.oo", "h": "o.o.o.o.o.o.o.o.", "fill": "snare", "crash": true, "timp": true},
	"rock": {"k": "X.....x.x.......", "k2": "X.....x.x.x...x.", "s": "....X.......X...", "h": "x.x.x.x.x.x.x.x.", "fill": "toms", "crash": true},
	"boss": {"k": "X.x...x.x.x...x.", "s": "....X.......X...", "h": "xoxoxoxoxoxoxoxo", "fill": "toms", "crash": true, "timp": true},
	"four": {"k": "X...x...x...x...", "c": "....x.......x...", "oh": "..o...o...o...o.", "h": "o...o...o...o...", "fill": "snare", "crash": true},
	"shuffle": {"k": "x.......x.......", "ride": "x...x.x.x...x.x.", "h": "....o.......o...", "b": "....o.......o..."},
	"halftime": {"k": "x...............", "s": "........x.......", "h": "o...o...o...o..."},
	"pulse": {"k": "x..x............"},
	"waltz": {"k": "x...........", "h": "....o...o..."},
	"bossa": {"k": "x..x....x..x....", "r": "x..x..x...x..x..", "sh": "oooooooooooooooo"},
	"race": {"k": "X...x...X...x...", "s": "....X.......X...", "h": "xoxoxoxoxoxoxoxo", "fill": "snare", "crash": true},
	"none": {},
}

## Built-in moods (see the track definition format in the header).
const MOODS := {
	"town": {"bpm": 100.0, "key": 65, "scale": "major", "swing": 0.15, "seed": 11, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "vi", "IV", "V"], "B": ["IV", "V", "iii", "vi", "ii", "V", "I", "V"]},
		"lead": {"inst": "flute", "vol": 0.3, "style": "lyrical", "density": 0.85, "oct": 12, "echo": [0.75, 0.25, 0.3], "harmony": true},
		"bass": {"inst": "pluckbass", "vol": 0.42, "pattern": "root5", "oct": 12},
		"arp": {"inst": "guitar", "vol": 0.13, "pattern": "broken", "rate": 2, "oct": 0},
		"pad": {"inst": "warm", "vol": 0.07, "style": "sustain"},
		"drums": {"style": "soft", "vol": 0.45}, "reverb": 0.15},
	"overworld": {"bpm": 126.0, "key": 62, "scale": "major", "seed": 23, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "V", "vi", "IV"], "B": ["IV", "V", "iii", "vi", "ii", "IV", "bVII", "V"]},
		"lead": {"inst": "brass", "vol": 0.27, "style": "march", "density": 0.9, "oct": 12, "harmony": true, "echo": [0.5, 0.18, 0.2]},
		"bass": {"inst": "synthbass", "vol": 0.36, "pattern": "gallop"},
		"pad": {"inst": "strings", "vol": 0.1, "style": "sustain"},
		"arp": {"inst": "pluck", "vol": 0.07, "pattern": "up", "rate": 2, "oct": 12},
		"drums": {"style": "march", "vol": 0.5}, "reverb": 0.14},
	"battle": {"bpm": 150.0, "key": 57, "scale": "minor", "seed": 37, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["i", "bVI", "bVII", "i"], "B": ["iv", "bVI", "bVII", "V", "i", "bVI", "iv", "V"]},
		"lead": {"inst": "saw", "vol": 0.24, "style": "driving", "density": 0.9, "oct": 15, "echo": [0.75, 0.2, 0.25], "harmony": true},
		"bass": {"inst": "synthbass", "vol": 0.4, "pattern": "pulse8"},
		"pad": {"inst": "brass", "vol": 0.08, "style": "stabs"},
		"arp": {"inst": "chip", "vol": 0.05, "pattern": "broken", "rate": 1, "oct": 15},
		"drums": {"style": "rock", "vol": 0.55}, "reverb": 0.08},
	"boss": {"bpm": 164.0, "key": 50, "scale": "harmonic", "seed": 41, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["i", "bII", "i", "bII"], "B": ["iv", "bVI", "V", "V", "i", "bII", "V7", "V7"]},
		"lead": {"inst": "brass", "vol": 0.26, "style": "driving", "density": 0.85, "oct": 24, "harmony": true},
		"bass": {"inst": "synthbass", "vol": 0.42, "pattern": "gallop"},
		"pad": {"inst": "organ", "vol": 0.08, "style": "sustain", "oct": 12},
		"arp": {"inst": "square", "vol": 0.04, "pattern": "up", "rate": 1, "oct": 24},
		"drums": {"style": "boss", "vol": 0.6}, "reverb": 0.1},
	"victory": {"bpm": 132.0, "key": 60, "scale": "major", "seed": 3, "loop": false, "tail": 2.2,
		"chords": ["I", "IV", "V", "I"],
		"lead": {"inst": "brass", "vol": 0.3, "oct": 12, "echo": [0.5, 0.2, 0.2]},
		"melody": [[0.0, 0.3, 0], [0.333, 0.3, 4], [0.667, 0.3, 7], [1.0, 1.4, 12], [2.5, 0.45, 9], [3.0, 0.45, 11],
			[3.5, 0.45, 12], [4.0, 0.9, 9], [5.0, 0.45, 5], [5.5, 0.45, 7], [6.0, 1.9, 9], [8.0, 0.45, 7],
			[8.5, 0.45, 5], [9.0, 0.45, 4], [9.5, 0.45, 2], [10.0, 0.95, 11], [11.0, 0.3, 7], [11.333, 0.3, 9],
			[11.667, 0.3, 11], [12.0, 3.2, 12], [12.0, 3.2, 7, 0.7], [12.0, 3.2, 4, 0.6]],
		"bass": {"inst": "synthbass", "vol": 0.4, "pattern": "root"},
		"pad": {"inst": "strings", "vol": 0.12, "style": "sustain"},
		"hits": [[0.0, "ti", 1.0], [0.0, "cr", 0.5], [4.0, "ti", 0.8], [8.0, "ti", 0.8], [12.0, "ti", 1.0],
			[12.0, "k", 1.0], [12.0, "cr", 1.0]],
		"roll": [10.0, 12.0], "drums": {"style": "none", "vol": 0.55}, "reverb": 0.18},
	"defeat": {"bpm": 90.0, "key": 57, "scale": "minor", "seed": 5, "loop": false, "tail": 2.5,
		"chords": ["bVI", "V", "i"],
		"lead": {"inst": "flute", "vol": 0.28, "oct": 12, "echo": [0.75, 0.25, 0.3]},
		"melody": [[0.0, 0.9, 12], [1.0, 0.9, 8], [2.0, 1.8, 3], [4.0, 0.9, 7], [5.0, 0.9, 2], [6.0, 1.9, -1],
			[8.0, 3.5, 0], [8.0, 3.5, 3, 0.6]],
		"bass": {"inst": "sub", "vol": 0.4, "pattern": "long"},
		"pad": {"inst": "strings", "vol": 0.12, "style": "sustain"},
		"hits": [[0.0, "ti", 0.6], [8.0, "ti", 0.8]], "drums": {"style": "none", "vol": 0.5}, "reverb": 0.25},
	"dungeon": {"bpm": 84.0, "key": 57, "scale": "minor", "seed": 53, "form": ["A", "B"],
		"parts": {"A": ["i", "i", "bVI", "bVI", "iv", "iv", "V", "V"], "B": ["bVI", "bVII", "i", "i", "iv", "bVI", "V", "V"]},
		"lead": {"inst": "bell", "vol": 0.24, "style": "sparse", "density": 0.55, "oct": 15, "echo": [0.75, 0.4, 0.45]},
		"bass": {"inst": "sub", "vol": 0.4, "pattern": "long"},
		"pad": {"inst": "strings", "vol": 0.11, "style": "sustain"},
		"arp": {"inst": "pluck", "vol": 0.06, "pattern": "broken", "rate": 4, "oct": 0},
		"drums": {"style": "pulse", "vol": 0.4}, "reverb": 0.35},
	"quiz": {"bpm": 128.0, "key": 60, "scale": "major", "swing": 0.2, "seed": 61, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "vi", "ii", "V"], "B": ["IV", "V", "iii", "vi", "ii", "V", "I", "V7"]},
		"lead": {"inst": "marimba", "vol": 0.3, "style": "bouncy", "density": 0.9, "oct": 14},
		"bass": {"inst": "pluckbass", "vol": 0.42, "pattern": "walking", "oct": 12},
		"pad": {"inst": "epiano", "vol": 0.12, "style": "comp"},
		"drums": {"style": "shuffle", "vol": 0.45}, "reverb": 0.1},
	"space": {"bpm": 90.0, "key": 52, "scale": "lydian", "seed": 71, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "II", "I", "II"], "B": ["vi", "IV", "I", "V"]},
		"lead": {"inst": "sine", "vol": 0.22, "style": "sparse", "density": 0.6, "oct": 24, "echo": [0.75, 0.45, 0.5]},
		"bass": {"inst": "sub", "vol": 0.36, "pattern": "long"},
		"pad": {"inst": "strings", "vol": 0.12, "style": "sustain", "oct": 12},
		"arp": {"inst": "bell", "vol": 0.07, "pattern": "updown", "rate": 1, "oct": 24},
		"drums": {"style": "halftime", "vol": 0.3}, "reverb": 0.4},
	"cosy": {"bpm": 76.0, "beats": 3, "key": 65, "scale": "major", "seed": 83, "form": ["A", "A", "B"],
		"parts": {"A": ["I", "IV", "I", "V"], "B": ["vi", "IV", "I", "V", "I", "IV", "V", "I"]},
		"lead": {"inst": "bell", "vol": 0.26, "style": "waltz", "density": 0.85, "oct": 12, "echo": [1.0, 0.3, 0.3]},
		"bass": {"inst": "sine", "vol": 0.36, "pattern": "waltz", "oct": 12},
		"pad": {"inst": "epiano", "vol": 0.11, "style": "waltz"},
		"drums": {"style": "none"}, "reverb": 0.3},
	"party": {"bpm": 124.0, "key": 67, "scale": "major", "seed": 97, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "V", "vi", "IV"], "B": ["ii", "IV", "V", "V", "vi", "IV", "ii", "V"]},
		"lead": {"inst": "chip", "vol": 0.24, "style": "bouncy", "density": 0.9, "oct": 7, "harmony": true},
		"bass": {"inst": "synthbass", "vol": 0.4, "pattern": "octave"},
		"pad": {"inst": "saw", "vol": 0.06, "style": "offbeat"},
		"arp": {"inst": "pluck", "vol": 0.07, "pattern": "up", "rate": 1, "oct": 7},
		"drums": {"style": "four", "vol": 0.55}, "reverb": 0.08},
	"shop": {"bpm": 104.0, "key": 65, "scale": "major", "seed": 101, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["Imaj7", "vi7", "ii7", "V7"], "B": ["IVmaj7", "V7", "iii7", "vi7", "ii7", "V7", "Imaj7", "V7"]},
		"lead": {"inst": "marimba", "vol": 0.28, "style": "lyrical", "density": 0.8, "oct": 12, "echo": [0.75, 0.25, 0.3]},
		"bass": {"inst": "pluckbass", "vol": 0.42, "pattern": "bossa", "oct": 12},
		"pad": {"inst": "epiano", "vol": 0.13, "style": "comp"},
		"drums": {"style": "bossa", "vol": 0.4}, "reverb": 0.15},
	"mystery": {"bpm": 92.0, "key": 62, "scale": "harmonic", "swing": 0.25, "seed": 113, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["i", "iv", "bVI", "V7"], "B": ["iv", "i", "bII", "V7", "i", "iv", "V7", "V7"]},
		"lead": {"inst": "flute", "vol": 0.26, "style": "lyrical", "density": 0.65, "oct": 12, "echo": [0.75, 0.3, 0.3]},
		"bass": {"inst": "pluckbass", "vol": 0.44, "pattern": "walking", "oct": 12},
		"pad": {"inst": "epiano", "vol": 0.1, "style": "comp"},
		"drums": {"style": "shuffle", "vol": 0.35}, "reverb": 0.2},
	"race": {"bpm": 160.0, "key": 64, "scale": "mixolydian", "seed": 127, "form": ["A", "A", "B", "A"],
		"parts": {"A": ["I", "bVII", "IV", "I"], "B": ["vi", "IV", "V", "V"]},
		"lead": {"inst": "square", "vol": 0.24, "style": "driving", "density": 0.9, "oct": 10, "harmony": true},
		"bass": {"inst": "synthbass", "vol": 0.4, "pattern": "octave"},
		"pad": {"inst": "saw", "vol": 0.06, "style": "stabs"},
		"arp": {"inst": "chip", "vol": 0.05, "pattern": "up", "rate": 1, "oct": 10},
		"drums": {"style": "race", "vol": 0.55}, "reverb": 0.06},
	"tension": {"bpm": 100.0, "key": 57, "scale": "minor", "seed": 131, "form": ["A", "A"],
		"parts": {"A": ["i", "i", "bVI", "V", "i", "i", "bII", "V"]},
		"lead": {"inst": "none"},
		"bass": {"inst": "sub", "vol": 0.42, "pattern": "pulse8"},
		"pad": {"inst": "strings", "vol": 0.13, "style": "sustain"},
		"arp": {"inst": "pluck", "vol": 0.12, "pattern": "up", "rate": 1, "oct": 12},
		"drums": {"style": "pulse", "vol": 0.45}, "reverb": 0.2},
}


# --- Classic synthwave tracks (play_track) ----------------------------------------------
var current := -1
var wanted := 0
var task := -1
var task_track := -1
var buffer := PackedFloat32Array()
var track: Dictionary

# --- Moods --------------------------------------------------------------------------------
## The mood playing (or fading in); "" when none (or when a classic track plays).
var current_mood := ""
## After a one-shot mood ("victory", "defeat", or a custom loop = false track) fade back into the mood
## that was playing before it.
var resume_after_jingle := true
## Milliseconds each mood took to synthesise (diagnostics).
var synth_ms := {}

var _requested := false
var _classic := false  # play_track() is the latest request
var _custom := {}
var _decks: Array[AudioStreamPlayer] = []
var _gain: Array[float] = [0.0, 0.0]
var _target: Array[float] = [0.0, 0.0]
var _speed: Array[float] = [1.0, 1.0]
var _active := -1
var _want_mood := ""
var _want_fade := 1.5
var _queue: Array[String] = []
var _mood_task := -1
var _mood_task_name := ""
var _mood_task_def: Dictionary = {}
var _mood_buf := PackedFloat32Array()
var _mood_t0 := 0
var _jingle_left := -1.0
var _jingle_name := ""
var _resume_mood := ""
var _resume_pos := 0.0


func _ready() -> void:
	SfxScript.ensure_buses()
	bus = "Music"
	volume_db = -13.0
	_ensure_decks()
	_autoplay.call_deferred()


## Old games relied on track 0 starting by itself; skip it when the game asked for something already.
func _autoplay() -> void:
	if not _requested:
		play_track(0)


## Switch to a classic synthwave track (by index, wrapped). Synthesizes it in the background the first
## time. Fades any mood out.
func play_track(index: int) -> void:
	_requested = true
	_classic = true
	if current_mood != "" or _decks_busy():
		_fade_decks(0.8)
		current_mood = ""
		_want_mood = ""
		_jingle_left = -1.0
		_resume_mood = ""
	_play_classic(index)


func _play_classic(index: int) -> void:
	wanted = index % TRACKS.size()
	if wanted == current:
		return
	var cache := _cache()
	if cache.has(wanted):
		current = wanted
		stream = cache[wanted]
		play()
	elif task < 0:
		task_track = wanted
		track = TRACKS[wanted]
		buffer = PackedFloat32Array()
		task = WorkerThreadPool.add_task(_synthesize)


## Synthesized tracks, kept on the Engine so they survive scene restarts and hot reloads.
func _cache() -> Dictionary:
	if not Engine.has_meta("duo_music_tracks"):
		Engine.set_meta("duo_music_tracks", {})
	return Engine.get_meta("duo_music_tracks")


func _process(delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		_cache()[task_track] = _to_stream(buffer)
		buffer = PackedFloat32Array()
		if _classic:
			var w := wanted
			current = -1
			_play_classic(w)
	_poll_mood_task()
	_update_decks(delta)


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
	if _mood_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_mood_task)
		_mood_task = -1


# --- Mood API -------------------------------------------------------------------------------

## Crossfade to a mood (built-in or add_track name, or an alias) over `fade` seconds. Synthesises it
## first if needed (the current music keeps playing meanwhile). One-shot moods (victory, defeat)
## interrupt the current mood and, when resume_after_jingle is true, hand back to it afterwards.
func play_mood(mood: String, fade: float = 1.5) -> void:
	_requested = true
	var name_ := resolve(mood)
	var def := get_def(name_)
	if def.is_empty():
		push_warning("music: unknown mood '%s'" % mood)
		return
	_classic = false
	var looped := bool(def.get("loop", true))
	if looped and name_ == current_mood and _jingle_left < 0.0 and _active >= 0 and _decks[_active].playing:
		_want_mood = ""
		return
	if playing:
		_take_over_classic()
	var st := _cached(name_)
	if st != null:
		_start(name_, st, fade, 0.0)
	else:
		_want_mood = name_
		_want_fade = fade
		_enqueue(name_, true)


## Fade all music out (moods and classic tracks) over `seconds`.
func fade_out(seconds: float = 1.0) -> void:
	_requested = true
	_classic = false
	if playing:
		_take_over_classic()
	_fade_decks(seconds)
	current_mood = ""
	_want_mood = ""
	_jingle_left = -1.0
	_resume_mood = ""


## Register a custom track (see the format in the header); play it with play_mood(def.name).
func add_track(def: Dictionary) -> void:
	var n := str(def.get("name", ""))
	if n == "":
		push_warning("music: add_track needs a name")
		return
	_custom[n] = def


## Synthesise moods in the background now so switching to them later is instant.
func prepare(moods: Array) -> void:
	for m in moods:
		var n := resolve(str(m))
		if not get_def(n).is_empty() and _cached(n) == null:
			_enqueue(n, false)


## True once a mood is synthesised (play_mood will start it immediately).
func is_mood_ready(mood: String) -> bool:
	return _cached(resolve(mood)) != null


## Every playable mood name (built-in and custom).
func list_moods() -> PackedStringArray:
	var out := PackedStringArray()
	for k in MOODS:
		out.append(str(k))
	for k in _custom:
		if not MOODS.has(k):
			out.append(str(k))
	return out


## The built-in mood names (static, no instance needed).
static func builtin_moods() -> PackedStringArray:
	var out := PackedStringArray()
	for k in MOODS:
		out.append(str(k))
	return out


## Alias -> mood name ("sleepy" -> "cosy"); other names unchanged.
static func resolve(mood: String) -> String:
	if ALIASES.has(mood):
		return str(ALIASES[mood])
	return mood


## A mood's definition (custom first, then built-in), or {} if unknown.
func get_def(mood: String) -> Dictionary:
	if _custom.has(mood):
		var c: Dictionary = _custom[mood]
		return c
	if MOODS.has(mood):
		var m: Dictionary = MOODS[mood]
		return m
	return {}


## The synthesised stream of a mood if it is cached (else null).
func get_mood_stream(mood: String) -> AudioStreamWAV:
	return _cached(resolve(mood))


## True while some music is audible (a classic track or a mood).
func is_music_playing() -> bool:
	return playing or _decks_busy()


# --- Decks, crossfades and the synthesis queue ---------------------------------------------

func _ensure_decks() -> void:
	if not _decks.is_empty():
		return
	for i in 2:
		var d := AudioStreamPlayer.new()
		d.name = "Deck%d" % i
		d.bus = bus
		add_child(d)
		_decks.append(d)


func _decks_busy() -> bool:
	for d in _decks:
		if d.playing:
			return true
	return false


func _cache_key(mood: String) -> String:
	if _custom.has(mood):
		return "music_c_%s_%d" % [mood, str(_custom[mood]).hash()]
	return "music_%s_%s" % [MOOD_VERSION, mood]


func _cached(mood: String) -> AudioStreamWAV:
	var r := ResCache.fetch(_cache_key(mood))
	return r as AudioStreamWAV


## A classic track is playing on this node itself: move it onto a deck so it can crossfade out.
func _take_over_classic() -> void:
	_ensure_decks()
	var d := 0 if _active != 0 else 1
	var deck := _decks[d]
	deck.stream = stream
	deck.play(get_playback_position())
	_gain[d] = 1.0
	_target[d] = 1.0
	_active = d
	stop()
	current = -1


func _start(mood: String, st: AudioStreamWAV, fade: float, from: float) -> void:
	_ensure_decks()
	var def := get_def(mood)
	var looped := bool(def.get("loop", true))
	_want_mood = ""
	var fade_in := fade
	var fade_old := fade
	if not looped:
		if _jingle_left < 0.0:
			_resume_mood = current_mood
			_resume_pos = _decks[_active].get_playback_position() if _active >= 0 and current_mood != "" else 0.0
		fade_in = 0.02
		fade_old = minf(fade, 0.3)
		_jingle_left = st.get_length() + 0.05
		_jingle_name = mood
	else:
		_jingle_left = -1.0
		_resume_mood = ""
	var d := 0 if _active != 0 else 1
	if _active >= 0:
		_target[_active] = 0.0
		_speed[_active] = 1.0 / maxf(fade_old, 0.01)
	var deck := _decks[d]
	deck.stream = st
	deck.play(from)
	_gain[d] = 0.0 if fade_in > 0.0 else 1.0
	_target[d] = 1.0
	_speed[d] = 1.0 / maxf(fade_in, 0.01)
	_active = d
	current_mood = mood
	_update_decks(0.0)
	mood_changed.emit(mood)


func _fade_decks(seconds: float) -> void:
	for i in _decks.size():
		_target[i] = 0.0
		_speed[i] = 1.0 / maxf(seconds, 0.01)


func _update_decks(delta: float) -> void:
	for i in _decks.size():
		var deck := _decks[i]
		var g := move_toward(_gain[i], _target[i], _speed[i] * delta)
		_gain[i] = g
		if g <= 0.0 and _target[i] <= 0.0:
			if deck.playing:
				deck.stop()
			continue
		deck.volume_db = volume_db + linear_to_db(maxf(sin(g * PI * 0.5), 0.0001))
		deck.pitch_scale = pitch_scale
		deck.bus = bus
	if _jingle_left >= 0.0:
		_jingle_left -= delta * maxf(pitch_scale, 0.01)
		if _jingle_left < 0.0:
			_jingle_done()


func _jingle_done() -> void:
	var done := _jingle_name
	var prev := _resume_mood
	_resume_mood = ""
	_jingle_name = ""
	jingle_finished.emit(done)
	if current_mood != done:
		return  # something else took over meanwhile
	if resume_after_jingle and prev != "":
		var st := _cached(prev)
		if st != null:
			_start(prev, st, 1.2, _resume_pos)
			return
	current_mood = ""
	if _active >= 0:
		_target[_active] = 0.0
		_speed[_active] = 4.0


func _enqueue(mood: String, front: bool) -> void:
	if mood == _mood_task_name and _mood_task >= 0:
		return
	var i := _queue.find(mood)
	if i >= 0:
		if not front:
			return
		_queue.remove_at(i)
	if front:
		_queue.push_front(mood)
	else:
		_queue.append(mood)
	_next_task()


func _next_task() -> void:
	if _mood_task >= 0:
		return
	while not _queue.is_empty():
		var n: String = _queue.pop_front()
		if _cached(n) != null:
			continue
		_mood_task_name = n
		_mood_task_def = get_def(n).duplicate(true)
		_mood_buf = PackedFloat32Array()
		_mood_t0 = Time.get_ticks_msec()
		_mood_task = WorkerThreadPool.add_task(_synth_mood)
		return


func _synth_mood() -> void:
	_mood_buf = render_song(_mood_task_def)


func _poll_mood_task() -> void:
	if _mood_task < 0 or not WorkerThreadPool.is_task_completed(_mood_task):
		return
	WorkerThreadPool.wait_for_task_completion(_mood_task)
	_mood_task = -1
	var n := _mood_task_name
	_mood_task_name = ""
	synth_ms[n] = Time.get_ticks_msec() - _mood_t0
	var looped := bool(_mood_task_def.get("loop", true))
	var st := _to_stream(_mood_buf, looped, false)
	_mood_buf = PackedFloat32Array()
	ResCache.put(_cache_key(n), st)
	if _want_mood == n:
		_start(n, st, _want_fade, 0.0)
	_next_task()


# --- Classic synthwave synthesis (unchanged) --------------------------------------------------

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


## Samples to a 16-bit AudioStreamWAV. normalise = scale to a 0.9 peak (the classic tracks); looped
## streams loop over the whole buffer.
static func _to_stream(buf: PackedFloat32Array, looped: bool = true, normalise: bool = true) -> AudioStreamWAV:
	var peak := 0.001
	if normalise:
		for v in buf:
			peak = maxf(peak, absf(v))
	var scale := 0.9 / peak if normalise else 1.0
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * scale, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = buf.size()
	return w


# --- Mood composition -----------------------------------------------------------------------------

## Compose and render a track definition to mono samples (-1..1, loudness-normalised). Thread-safe.
static func render_song(def: Dictionary) -> PackedFloat32Array:
	var song := Song.new(def, SCALES, INSTRUMENTS, DRUM_STYLES, RATE)
	return song.render(TARGET_RMS)


## The composer: builds bars from the chord form, generates the melody (motifs repeated and varied per
## section), bass line, chord voicings, arpeggios and drum grooves, then renders every note (cached per
## pitch and length) into dry, lead and reverb buses.
class Song extends RefCounted:
	const RHYTHM_CELLS := {
		"lyrical": [[[0, 4]], [[0, 2], [2, 2]], [[0, 3], [3, 1]], [[0, 2]], [[0, 8]], [[0, 6], [6, 2]], [[0, 4]], [[0, 2], [2, 2]]],
		"driving": [[[0, 2], [2, 2]], [[0, 1], [1, 1], [2, 2]], [[0, 2], [2, 1], [3, 1]], [[0, 3], [3, 3], [6, 2]], [[0, 4]], [[0, 2], [2, 2]]],
		"bouncy": [[[0, 2]], [[0, 1], [2, 2]], [[1, 2], [3, 1]], [[0, 3], [3, 1]], [[0, 2], [2, 2]], [[0, 2]]],
		"march": [[[0, 4]], [[0, 3], [3, 1]], [[0, 2], [2, 2]], [[0, 8]], [[0, 6], [6, 2]], [[0, 3], [3, 1]]],
		"sparse": [[[0, 8]], [[0, 4]], [[0, 12]], [[0, 6], [6, 2]], [[2, 6]]],
		"waltz": [[[0, 4]], [[0, 8]], [[0, 6], [6, 2]], [[0, 12]], [[0, 2], [2, 2]]],
	}
	const CONTOUR_STEPS := [-3, -2, -1, 0, 1, 2, 3]
	const CONTOUR_WEIGHTS := [0.3, 1.0, 2.5, 0.8, 2.5, 1.0, 0.3]
	const DRUM_LEVEL := {"k": 0.9, "s": 0.6, "r": 0.35, "h": 0.22, "oh": 0.25, "c": 0.5, "sh": 0.15, "b": 0.35,
		"ride": 0.22, "t1": 0.6, "t2": 0.6, "cr": 0.35, "ti": 0.8}

	var d: Dictionary
	var scales: Dictionary
	var insts: Dictionary
	var grooves: Dictionary
	var rate := 22050
	var bpm := 110.0
	var beats := 4
	var spb := 16
	var key := 60
	var scale: Array = []
	var swing := 0.0
	var looped := true
	var step_sec := 0.1
	var bars: Array = []
	var n := 0
	var mix := PackedFloat32Array()
	var lead_bus := PackedFloat32Array()
	var wet := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var note_cache := {}
	var kit := {}

	func _init(def: Dictionary, scale_table: Dictionary, inst_table: Dictionary, groove_table: Dictionary, sample_rate: int) -> void:
		d = def
		scales = scale_table
		insts = inst_table
		grooves = groove_table
		rate = sample_rate
		bpm = float(def.get("bpm", 110.0))
		beats = clampi(int(def.get("beats", 4)), 2, 7)
		spb = beats * 4
		key = int(def.get("key", 60))
		var sc: Array = scales.get(str(def.get("scale", "major")), scales["major"])
		scale = sc
		swing = clampf(float(def.get("swing", 0.0)), 0.0, 1.0)
		looped = bool(def.get("loop", true))
		step_sec = 60.0 / bpm / 4.0
		rng.seed = int(def.get("seed", 1))
		_build_bars()
		var loop_n := int(bars.size() * spb * step_sec * rate)
		n = loop_n + (0 if looped else int(float(def.get("tail", 2.0)) * rate))
		mix.resize(n)
		lead_bus.resize(n)
		wet.resize(n)

	func render(target_rms: float) -> PackedFloat32Array:
		var lead_cfg: Dictionary = d.get("lead", {})
		var melody := gen_melody()
		play_notes(melody, lead_cfg, lead_bus, 0.0)
		var lead_echo: Array = lead_cfg.get("echo", [])
		if lead_echo.size() >= 3:
			echo(lead_bus, int(float(lead_echo[0]) * 4.0 * step_sec * rate), float(lead_echo[1]), float(lead_echo[2]))
		var lead_send := 0.6
		for i in n:
			var v := lead_bus[i]
			mix[i] += v
			wet[i] += v * lead_send
		var bass_cfg: Dictionary = d.get("bass", {})
		play_notes(gen_bass(), bass_cfg, mix, 0.0)
		var pad_cfg: Dictionary = d.get("pad", {})
		play_notes(gen_pad(), pad_cfg, mix, 0.8)
		var arp_cfg: Dictionary = d.get("arp", {})
		play_notes(gen_arp(), arp_cfg, mix, 0.7)
		gen_drums()
		reverb(float(d.get("reverb", 0.0)))
		return master(target_rms)

	# --- Harmony helpers ---

	func _build_bars() -> void:
		var parts: Dictionary = d.get("parts", {})
		var form: Array = d.get("form", [])
		if d.has("chords"):
			parts = {"A": d["chords"]}
			form = ["A"]
		if form.is_empty():
			form = parts.keys()
		if parts.is_empty():
			parts = {"A": ["I"]}
			form = ["A"]
		var seen := {}
		for sec in form:
			var chords: Array = parts.get(sec, ["I"])
			var rep := int(seen.get(sec, 0))
			seen[sec] = rep + 1
			for i in chords.size():
				bars.append({"chord": parse_chord(str(chords[i])), "sec": str(sec), "i": i, "len": chords.size(), "rep": rep})

	## "bVII7" -> {"root": 10, "tones": [0, 4, 7, 10]} (semitones; root relative to the key).
	func parse_chord(sym: String) -> Dictionary:
		var s := sym.strip_edges()
		var acc := 0
		if s.begins_with("b"):
			acc = -1
			s = s.substr(1)
		elif s.begins_with("#"):
			acc = 1
			s = s.substr(1)
		var low := s.to_lower()
		var numerals := ["vii", "iii", "iv", "vi", "ii", "v", "i"]
		var degree := {"i": 0, "ii": 1, "iii": 2, "iv": 3, "v": 4, "vi": 5, "vii": 6}
		var major_steps := [0, 2, 4, 5, 7, 9, 11]
		var num := "i"
		for cand in numerals:
			if low.begins_with(str(cand)):
				num = str(cand)
				break
		var head := s.substr(0, num.length())
		var upper := head == head.to_upper()
		var rest := low.substr(num.length())
		var root: int = int(major_steps[int(degree[num])]) + acc
		var tones: Array = [0, 4, 7] if upper else [0, 3, 7]
		if rest.contains("dim") or rest.begins_with("o"):
			tones = [0, 3, 6]
		elif rest.contains("aug") or rest.begins_with("+"):
			tones = [0, 4, 8]
		elif rest.contains("sus4"):
			tones = [0, 5, 7]
		elif rest.contains("sus2"):
			tones = [0, 2, 7]
		if rest.contains("maj7"):
			tones.append(11)
		elif rest.contains("7"):
			tones.append(9 if tones == [0, 3, 6] and rest.contains("dim7") else 10)
		elif rest.contains("6"):
			tones.append(9)
		return {"root": posmod(root, 12), "tones": tones}

	func pcs_of(ch: Dictionary) -> Array:
		var out: Array = []
		var tones: Array = ch["tones"]
		for t in tones:
			out.append(posmod(int(ch["root"]) + int(t), 12))
		return out

	## The key's scale with any chord tone outside it swapped in (V major in a minor key, bVII in major).
	func bar_scale(ch: Dictionary) -> Array:
		var out: Array = scale.duplicate()
		for pc in pcs_of(ch):
			if not out.has(pc):
				for k in range(out.size() - 1, -1, -1):
					var diff := absi(int(out[k]) - int(pc))
					if diff == 1 or diff == 11:
						out.remove_at(k)
				out.append(pc)
		return out

	func in_pcs(pcs: Array, m: int) -> bool:
		return pcs.has(posmod(m - key, 12))

	func nearest(pcs: Array, target: int) -> int:
		for off in 7:
			if in_pcs(pcs, target - off):
				return target - off
			if in_pcs(pcs, target + off):
				return target + off
		return target

	func step_in(pcs: Array, from: int, steps: int) -> int:
		var m := nearest(pcs, from)
		var dir := 1 if steps > 0 else -1
		var left := absi(steps)
		var guard := 0
		while left > 0 and guard < 48:
			m += dir
			guard += 1
			if in_pcs(pcs, m):
				left -= 1
		return m

	## Seconds at a 16th-note step (with swing on the off-beats).
	func t_of(step: int) -> float:
		var beat := floori(step / 4.0)
		var sub := step - beat * 4
		var off := float(sub)
		if swing > 0.0:
			if sub == 2:
				off += swing * 0.667
			elif sub != 0:
				off += swing * 0.333
		return (beat * 4.0 + off) * step_sec

	# --- Melody ---

	func gen_melody() -> Array:
		var out: Array = []
		var cfg: Dictionary = d.get("lead", {})
		if str(cfg.get("inst", "none")) == "none":
			return out
		var oct := int(cfg.get("oct", 12))
		if d.has("melody"):
			var mel: Array = d["melody"]
			for m in mel:
				var e: Array = m
				var vel := float(e[3]) if e.size() > 3 else 1.0
				out.append([float(e[0]) * 4.0 * step_sec, float(e[1]) * 4.0 * step_sec, key + oct + int(e[2]), vel])
			return out
		var style := str(cfg.get("style", "lyrical"))
		var density := float(cfg.get("density", 0.8))
		var legato := float(cfg.get("legato", 0.92))
		var harmony := bool(cfg.get("harmony", false))
		var center := key + oct
		var lo := center - 7
		var hi := center + 8
		var motifs := {}
		var first: Dictionary = bars[0]["chord"]
		var prev := nearest(pcs_of(first), center)
		for b in bars.size():
			var bar: Dictionary = bars[b]
			var sec := str(bar["sec"])
			if not motifs.has(sec):
				motifs[sec] = make_motif(style, density)
			var mo: Dictionary = motifs[sec]
			var i := int(bar["i"])
			var blen := int(bar["len"])
			var rep := int(bar["rep"])
			var ch: Dictionary = bar["chord"]
			var chord_pcs := pcs_of(ch)
			var sc_pcs := bar_scale(ch)
			var phrase_pos := i % 4
			var sec_end := i == blen - 1
			var cadence := phrase_pos == 3 or sec_end
			var rhythm: Array
			var contour: Array
			if cadence:
				rhythm = cadence_rhythm(style)
				contour = gen_contour(rhythm.size())
			else:
				var rr: Array = mo["r"]
				var cc: Array = mo["c"]
				rhythm = rr[phrase_pos % 2]
				contour = cc[phrase_pos % 2]
				if rep > 0 and rng.randf() < 0.35:
					rhythm = vary_rhythm(rhythm)
					contour = contour.duplicate()
					while contour.size() < rhythm.size():
						contour.append(1 if rng.randf() < 0.5 else -1)
			for k in rhythm.size():
				var cell: Array = rhythm[k]
				var s := int(cell[0])
				var ln := int(cell[1])
				if s >= spb:
					continue
				ln = mini(ln, spb - s)
				var c := int(contour[k]) if k < contour.size() else 0
				var target := step_in(sc_pcs, prev, c) if c != 0 else nearest(sc_pcs, prev)
				if target > hi:
					target = step_in(sc_pcs, prev, -absi(c) - 1)
				elif target < lo:
					target = step_in(sc_pcs, prev, absi(c) + 1)
				var strong := s % (8 if beats % 2 == 0 else spb) == 0
				var last := k == rhythm.size() - 1
				var pitch := target
				if strong or (cadence and last):
					pitch = nearest(chord_pcs, target)
				if cadence and last and sec_end:
					pitch = nearest([int(ch["root"])], prev)
				pitch = clampi(pitch, lo - 2, hi + 2)
				var step := b * spb + s
				var t0 := t_of(step)
				var t1 := t_of(step + ln)
				var vel := (1.0 if strong else 0.82) * rng.randf_range(0.9, 1.0)
				out.append([t0, (t1 - t0) * legato, pitch, vel])
				if harmony and rep > 0 and (strong or ln >= 4):
					var h := pitch - 3
					var guard := 0
					while not in_pcs(chord_pcs, h) and guard < 6:
						h -= 1
						guard += 1
					out.append([t0, (t1 - t0) * legato, h, vel * 0.55])
				prev = pitch
		return out

	func make_motif(style: String, density: float) -> Dictionary:
		var r0 := gen_rhythm(style, density)
		var r1 := gen_rhythm(style, density)
		return {"r": [r0, r1], "c": [gen_contour(r0.size()), gen_contour(r1.size())]}

	func cell_span(cell: Array) -> int:
		var end := 0
		for e in cell:
			var a: Array = e
			end = maxi(end, int(a[0]) + int(a[1]))
		return maxi(1, ceili(end / 4.0))

	func gen_rhythm(style: String, density: float) -> Array:
		var cells: Array = RHYTHM_CELLS.get(style, RHYTHM_CELLS["lyrical"])
		var out: Array = []
		var beat := 0
		var tries := 0
		while beat < beats:
			var cell: Array = cells[rng.randi() % cells.size()]
			var span := cell_span(cell)
			if beat + span > beats:
				tries += 1
				if tries > 12:
					out.append([beat * 4, (beats - beat) * 4])
					break
				continue
			if beat > 0 and rng.randf() > density:
				beat += 1
				continue
			for e in cell:
				var a: Array = e
				out.append([beat * 4 + int(a[0]), int(a[1])])
			beat += span
		if out.size() < 2:
			out.append([spb - 4, 4])
		return out

	func cadence_rhythm(style: String) -> Array:
		var opts: Array
		if beats == 3:
			opts = [[[0, 4], [4, 8]], [[0, 12]], [[0, 2], [2, 2], [4, 8]]]
		elif style == "driving":
			opts = [[[0, 2], [2, 2], [4, 2], [6, 2], [8, 8]], [[0, 3], [3, 3], [6, 10]], [[0, 4], [4, 12]]]
		elif style == "sparse":
			opts = [[[0, 16]], [[0, 8], [8, 8]]]
		else:
			opts = [[[0, 4], [4, 12]], [[0, 2], [2, 2], [4, 12]], [[0, 6], [6, 2], [8, 8]], [[0, 4], [4, 4], [8, 8]]]
		var pick: Array = opts[rng.randi() % opts.size()]
		var out: Array = []
		for e in pick:
			var a: Array = e
			if int(a[0]) < spb:
				out.append([int(a[0]), mini(int(a[1]), spb - int(a[0]))])
		return out

	func vary_rhythm(r: Array) -> Array:
		var out: Array = []
		var split := false
		for e in r:
			var a: Array = e
			var ln := int(a[1])
			if not split and ln >= 4 and ln % 2 == 0:
				out.append([int(a[0]), ln / 2])
				out.append([int(a[0]) + ln / 2, ln / 2])
				split = true
			else:
				out.append([int(a[0]), ln])
		return out

	func gen_contour(count: int) -> Array:
		var out: Array = []
		var total := 0.0
		for w in CONTOUR_WEIGHTS:
			total += float(w)
		for k in count:
			var r := rng.randf() * total
			var pick := 0
			for j in CONTOUR_WEIGHTS.size():
				r -= float(CONTOUR_WEIGHTS[j])
				if r <= 0.0:
					pick = int(CONTOUR_STEPS[j])
					break
			out.append(pick)
		return out

	# --- Bass, chords, arpeggios ---

	func bass_root(ch: Dictionary, oct: int) -> int:
		var m := 36 + posmod(key + int(ch["root"]), 12)
		if m > 45:
			m -= 12
		return m + oct

	func gen_bass() -> Array:
		var out: Array = []
		var cfg: Dictionary = d.get("bass", {})
		if str(cfg.get("inst", "none")) == "none":
			return out
		var pat := str(cfg.get("pattern", "root"))
		var oct := int(cfg.get("oct", 0))
		var half := spb / 2
		for b in bars.size():
			var bar: Dictionary = bars[b]
			var ch: Dictionary = bar["chord"]
			var nxt: Dictionary = bars[(b + 1) % bars.size()]["chord"]
			var tones: Array = ch["tones"]
			var r := bass_root(ch, oct)
			var third := r + int(tones[1])
			var fifth := r + int(tones[2])
			var octv := r + 12
			var nr := bass_root(nxt, oct)
			var ev: Array = []
			match pat:
				"long":
					ev = [[0, spb, r, 1.0]]
				"drone":
					ev = [[0, spb, r, 1.0], [0, spb, fifth, 0.6]]
				"octave":
					for s in range(0, spb, 2):
						ev.append([s, 2, r if (s / 2) % 2 == 0 else octv, 0.95 if s % 4 == 0 else 0.75])
				"pulse8":
					for s in range(0, spb, 2):
						ev.append([s, 2, r, 1.0 if s % 4 == 0 else 0.7])
				"gallop":
					for bt in beats:
						ev.append([bt * 4, 2, r, 1.0])
						ev.append([bt * 4 + 2, 1, r, 0.7])
						ev.append([bt * 4 + 3, 1, fifth if bt == beats - 1 else r, 0.75])
				"walking":
					var line: Array = [r, third if rng.randf() < 0.5 else fifth, fifth if rng.randf() < 0.6 else octv]
					var approach := nr - 1 if rng.randf() < 0.6 else nr + 1
					for bt in beats:
						var m: int = approach if bt == beats - 1 else int(line[mini(bt, line.size() - 1)])
						ev.append([bt * 4, 4, m, 1.0 if bt == 0 else 0.82])
				"root5":
					ev = [[0, 6, r, 1.0], [6, 2, r, 0.7], [8, 6, fifth, 0.9], [14, 2, third, 0.7]]
				"bossa":
					ev = [[0, 6, r, 1.0], [6, 2, fifth, 0.75], [8, 6, fifth, 0.9], [14, 2, r, 0.7]]
				"syncop":
					ev = [[0, 3, r, 1.0], [3, 3, octv, 0.8], [6, 2, r, 0.8], [8, 2, fifth, 0.9], [10, 3, r, 0.8], [13, 3, octv, 0.75]]
				"waltz":
					ev = [[0, 6, r, 1.0]]
					if b % 2 == 1:
						ev.append([8, 4, fifth, 0.7])
				_:
					ev = [[0, half, r, 1.0], [half, spb - half, fifth, 0.85]]
			if not looped and b == bars.size() - 1:
				ev = [[0, spb, r, 1.0]]  # a jingle's last bar rings on the root
			for e in ev:
				var a: Array = e
				var s := int(a[0])
				if s >= spb:
					continue
				var ln := mini(int(a[1]), spb - s)
				var t0 := t_of(b * spb + s)
				out.append([t0, (t_of(b * spb + s + ln) - t0) * 0.92, int(a[2]), float(a[3])])
		return out

	func gen_pad() -> Array:
		var out: Array = []
		var cfg: Dictionary = d.get("pad", {})
		if str(cfg.get("inst", "none")) == "none":
			return out
		var style := str(cfg.get("style", "sustain"))
		var lo := key - 3 + int(cfg.get("oct", 0))
		var hits: Array
		match style:
			"comp":
				hits = [[4, 4], [8, 4]] if beats == 3 else [[0, 4], [6, 2], [10, 4]]
			"stabs":
				hits = [[0, 2], [6, 2]] if beats == 3 else [[0, 2], [3, 2], [8, 2], [11, 2]]
			"waltz":
				hits = [[4, 4], [8, 4]] if beats == 3 else [[4, 4], [12, 4]]
			"halves":
				hits = [[0, spb / 2], [spb / 2, spb - spb / 2]]
			"offbeat":
				hits = []
				for bt in beats:
					hits.append([bt * 4 + 2, 1])
			_:
				hits = [[0, spb]]
		var prev: Array = []
		for b in bars.size():
			var ch: Dictionary = bars[b]["chord"]
			var notes: Array = []
			var tones: Array = ch["tones"]
			for t in tones:
				var m := key + int(ch["root"]) + int(t)
				while m < lo:
					m += 12
				while m >= lo + 12:
					m -= 12
				notes.append(m)
			notes.sort()
			var best := notes
			var best_cost := voicing_cost(notes, prev)
			var cand := notes.duplicate()
			for k in notes.size():
				cand = cand.duplicate()
				var low: int = cand.pop_front()
				cand.append(low + 12)
				if int(cand.back()) > lo + 19:
					break
				var c := voicing_cost(cand, prev)
				if c < best_cost:
					best = cand
					best_cost = c
			prev = best
			for h in hits:
				var a: Array = h
				var s := int(a[0])
				if s >= spb:
					continue
				var ln := mini(int(a[1]), spb - s)
				var t0 := t_of(b * spb + s)
				var dur := t_of(b * spb + s + ln) - t0
				for m in best:
					out.append([t0, dur * (0.98 if style == "sustain" else 0.8), int(m), 0.9])
		return out

	func voicing_cost(a: Array, prev: Array) -> float:
		if prev.is_empty():
			var mid := 0.0
			for m in a:
				mid += float(m)
			return absf(mid / a.size() - float(key + 4))
		var c := 0.0
		for i in a.size():
			c += absf(float(a[i]) - float(prev[mini(i, prev.size() - 1)]))
		return c

	func gen_arp() -> Array:
		var out: Array = []
		var cfg: Dictionary = d.get("arp", {})
		if str(cfg.get("inst", "none")) == "none":
			return out
		var rate_steps := maxi(1, int(cfg.get("rate", 2)))
		var pattern := str(cfg.get("pattern", "up"))
		var base := key + int(cfg.get("oct", 12))
		var seq: Array
		match pattern:
			"updown":
				seq = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]
			"broken":
				seq = [0, 2, 1, 2, 0, 2, 1, 2]
			"random":
				seq = []
				for k in 16:
					seq.append(rng.randi() % 6)
			_:
				seq = [0, 1, 2, 3, 4, 5]
		for b in bars.size():
			var ch: Dictionary = bars[b]["chord"]
			var tones: Array = ch["tones"]
			var root := base + int(ch["root"])
			while root > base + 6:
				root -= 12
			var pool: Array = []
			for o in 2:
				for k in 3:
					pool.append(root + int(tones[k]) + 12 * o)
			var k := 0
			for s in range(0, spb, rate_steps):
				var t0 := t_of(b * spb + s)
				var t1 := t_of(b * spb + mini(s + rate_steps, spb))
				var idx := int(seq[k % seq.size()])
				out.append([t0, (t1 - t0) * 0.9, int(pool[idx]), 0.95 if s % 4 == 0 else 0.72])
				k += 1
		return out

	# --- Rendering notes ---

	func play_notes(list: Array, cfg: Dictionary, dest: PackedFloat32Array, send: float) -> void:
		var inst := str(cfg.get("inst", "none"))
		if inst == "none" or list.is_empty():
			return
		var vol := float(cfg.get("vol", 0.2))
		for e in list:
			var a: Array = e
			var t0 := float(a[0])
			var gate := maxi(64, int(roundf(float(a[1]) * 100.0)) * rate / 100)
			var midi := int(a[2])
			var vel := float(a[3])
			var ck := "%s|%d|%d" % [inst, midi, gate]
			var nb: PackedFloat32Array
			if note_cache.has(ck):
				nb = note_cache[ck]
			else:
				nb = render_note(inst, midi, gate)
				note_cache[ck] = nb
			var start := int(t0 * rate)
			mix_into(dest, start, nb, vel * vol)
			if send > 0.0:
				mix_into(wet, start, nb, vel * vol * send)

	func mix_into(dest: PackedFloat32Array, start: int, src: PackedFloat32Array, g: float) -> void:
		var size := dest.size()
		var idx := start
		if idx >= size:
			if not looped:
				return
			idx -= size
		for i in src.size():
			if idx >= size:
				if not looped:
					return
				idx -= size
			dest[idx] += src[i] * g
			idx += 1

	func render_note(inst: String, midi: int, gate: int) -> PackedFloat32Array:
		var p: Dictionary = insts.get(inst, insts["sine"])
		var f := 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
		var inv := 1.0 / rate
		var rel := maxi(16, int(float(p.get("r", 0.08)) * rate))
		var total := gate + rel
		var g := float(p.get("g", 1.0))
		var out := PackedFloat32Array()
		if p.has("ks"):
			out.resize(total)
			var period := float(rate) / f
			var size := maxi(2, int(period - 0.5))
			var ring := PackedFloat32Array()
			ring.resize(size)
			var r := RandomNumberGenerator.new()
			r.seed = midi * 131 + 7
			var bright := float(p.get("bright", 0.5))
			var lpv := 0.0
			var mean := 0.0
			for k in size:
				lpv += (r.randf() * 2.0 - 1.0 - lpv) * bright
				ring[k] = lpv
				mean += lpv
			mean /= size
			for k in size:
				ring[k] -= mean
			var damp := float(p.get("ks", 0.996)) * 0.5
			var pos := 0
			for i in total:
				var cur := ring[pos]
				var nx := ring[pos + 1] if pos + 1 < size else ring[0]
				ring[pos] = (cur + nx) * damp
				var env := 1.0 if i < gate else 1.0 - float(i - gate) / rel
				if i < 24:
					env *= i / 24.0
				out[i] = cur * env * g * 1.6
				pos += 1
				if pos >= size:
					pos = 0
			return out
		if p.has("fm"):
			var fmp: Array = p["fm"]
			var ratio := float(fmp[0])
			var index := float(fmp[1])
			var idec := float(fmp[2])
			var decay := float(p.get("decay", 2.0))
			total = mini(total, int(7.0 / decay * rate) + rel)
			out.resize(total)
			var ph := 0.0
			var mph := 0.0
			for i in total:
				var t := i * inv
				var env := minf(1.0, t * 250.0) * exp(-decay * t)
				if i >= gate:
					env *= maxf(0.0, 1.0 - float(i - gate) / rel)
				ph += f * inv
				if ph >= 1.0:
					ph -= 1.0
				mph += f * ratio * inv
				if mph >= 1.0:
					mph -= floorf(mph)
				out[i] = sin(TAU * ph + index * exp(-idec * t) * sin(TAU * mph)) * env * g
			return out
		out.resize(total)
		var osc := str(p.get("osc", "sine"))
		var oi := 0
		match osc:
			"tri":
				oi = 1
			"square":
				oi = 2
			"saw":
				oi = 3
			"organ":
				oi = 4
			"flute":
				oi = 5
			"sub":
				oi = 6
		var a := maxf(float(p.get("a", 0.01)), 0.001)
		var dcy := maxf(float(p.get("d", 0.3)), 0.01)
		var sus := float(p.get("s", 0.7))
		var duty := float(p.get("duty", 0.5))
		var det := float(p.get("det", 0.0))
		var lpf := float(p.get("lp", 0.0))
		var lpe := float(p.get("lpenv", 0.0))
		var vib: Array = p.get("vib", [])
		var vr := float(vib[0]) if vib.size() >= 3 else 0.0
		var vd := float(vib[1]) * 0.0578 if vib.size() >= 3 else 0.0
		var vdel := float(vib[2]) if vib.size() >= 3 else 0.0
		var breath := float(p.get("breath", 0.0))
		var gate_t := gate * inv
		var env_g := gate_t / a if gate_t < a else sus + (1.0 - sus) * exp(-(gate_t - a) / dcy)
		var nr := RandomNumberGenerator.new()
		nr.seed = midi * 7919 + gate
		var ph := 0.0
		var ph2 := 0.37
		var lpv := 0.0
		for i in total:
			var t := i * inv
			var env := 0.0
			if i < gate:
				env = t / a if t < a else sus + (1.0 - sus) * exp(-(t - a) / dcy)
			else:
				env = env_g * (1.0 - float(i - gate) / rel)
			var ff := f
			if vr > 0.0 and t > vdel:
				ff *= 1.0 + sin(TAU * vr * t) * vd * minf(1.0, (t - vdel) * 4.0)
			ph += ff * inv
			if ph >= 1.0:
				ph -= 1.0
			var s := 0.0
			if oi == 0:
				s = sin(TAU * ph)
			elif oi == 1:
				s = absf(ph * 4.0 - 2.0) - 1.0
			elif oi == 2:
				s = 1.0 if ph < duty else -1.0
			elif oi == 3:
				s = ph * 2.0 - 1.0
			elif oi == 4:
				s = sin(TAU * ph) + 0.5 * sin(TAU * 2.0 * ph) + 0.3 * sin(TAU * 3.0 * ph)
			elif oi == 5:
				s = sin(TAU * ph) + 0.18 * sin(TAU * 2.0 * ph)
			else:
				s = sin(TAU * ph) + 0.22 * sin(TAU * 2.0 * ph)
			if det > 0.0:
				ph2 += ff * (1.0 + det) * inv
				if ph2 >= 1.0:
					ph2 -= 1.0
				var s2 := 0.0
				if oi == 1:
					s2 = absf(ph2 * 4.0 - 2.0) - 1.0
				elif oi == 2:
					s2 = 1.0 if ph2 < duty else -1.0
				elif oi == 3:
					s2 = ph2 * 2.0 - 1.0
				else:
					s2 = sin(TAU * ph2)
				s = (s + s2) * 0.5
			if lpf > 0.0:
				var cut := lpf + lpe * exp(-t * 7.0) if lpe > 0.0 else lpf
				lpv += (s - lpv) * minf(1.0, TAU * cut * inv)
				s = lpv
			if breath > 0.0:
				s += (nr.randf() * 2.0 - 1.0) * breath * exp(-t * 10.0)
			out[i] = s * env * g
		return out

	# --- Drums ---

	func drum(kind: String) -> PackedFloat32Array:
		if kit.has(kind):
			var cached: PackedFloat32Array = kit[kind]
			return cached
		var lens := {"k": 0.35, "s": 0.25, "r": 0.06, "h": 0.07, "oh": 0.35, "c": 0.2, "sh": 0.08, "b": 0.22,
			"ride": 0.7, "t1": 0.35, "t2": 0.4, "cr": 1.6, "ti": 1.2}
		var count := int(float(lens.get(kind, 0.2)) * rate)
		var out := PackedFloat32Array()
		out.resize(count)
		var r := RandomNumberGenerator.new()
		r.seed = kind.hash()
		var inv := 1.0 / rate
		var ph := 0.0
		var lpv := 0.0
		var lp2 := 0.0
		var timp_f := 440.0 * pow(2.0, (float(36 + posmod(key, 12)) - 69.0) / 12.0)
		for i in count:
			var t := i * inv
			var w := r.randf() * 2.0 - 1.0
			var v := 0.0
			match kind:
				"k":
					ph += (45.0 + 75.0 * exp(-t * 30.0)) * inv
					v = sin(TAU * ph) * exp(-t * 9.0) + w * 0.25 * exp(-t * 300.0)
				"s":
					lpv += (w - lpv) * 0.12
					v = sin(TAU * 185.0 * t) * 0.5 * exp(-t * 25.0) + (w - lpv) * 0.8 * exp(-t * 18.0)
				"r":
					v = sin(TAU * 1700.0 * t) * exp(-t * 90.0) + w * 0.3 * exp(-t * 150.0)
				"h", "oh", "cr":
					lpv += (w - lpv) * 0.75
					var hi := w - lpv
					var dk := 60.0 if kind == "h" else (9.0 if kind == "oh" else 2.2)
					v = hi * exp(-t * dk)
				"c":
					lpv += (w - lpv) * 0.5
					lp2 += (lpv - lp2) * 0.15
					var burst := exp(-fmod(t, 0.011) * 300.0) if t < 0.033 else exp(-(t - 0.033) * 20.0)
					v = (lpv - lp2) * burst * 1.4
				"sh":
					lpv += (w - lpv) * 0.7
					v = (w - lpv) * minf(1.0, t * 80.0) * exp(-t * 40.0)
				"b":
					lpv += (w - lpv) * 0.4
					v = lpv * minf(1.0, t * 60.0) * exp(-t * 12.0)
				"ride":
					lpv += (w - lpv) * 0.75
					v = (w - lpv) * 0.5 * exp(-t * 6.0) + sin(TAU * 520.0 * t + 3.0 * exp(-t * 5.0) * sin(TAU * 1196.0 * t)) * 0.25 * exp(-t * 5.0)
				"t1", "t2":
					var f0 := 220.0 if kind == "t1" else 150.0
					ph += f0 * (0.68 + 0.32 * exp(-t * 12.0)) * inv
					v = sin(TAU * ph) * exp(-t * 10.0)
				"ti":
					ph += timp_f * (0.97 + 0.03 * exp(-t * 4.0)) * inv
					v = (sin(TAU * ph) + 0.35 * sin(TAU * ph * 1.5)) * exp(-t * 3.5) + w * 0.2 * exp(-t * 60.0)
			out[i] = v
		kit[kind] = out
		return out

	func hit(kind: String, t0: float, g: float) -> void:
		mix_into(mix, int(t0 * rate), drum(kind), g * float(DRUM_LEVEL.get(kind, 0.5)))

	func gen_drums() -> void:
		var cfg: Dictionary = d.get("drums", {})
		var vol := float(cfg.get("vol", 0.5))
		var st: Dictionary = grooves.get(str(cfg.get("style", "none")), {})
		var vels := {"X": 1.0, "x": 0.75, "o": 0.4}
		for b in bars.size():
			var bar: Dictionary = bars[b]
			var first := int(bar["i"]) == 0
			var fill := str(st.get("fill", ""))
			var fill_bar := int(bar["i"]) == int(bar["len"]) - 1 and fill != "" and spb >= 8
			var fill_from := spb - 4
			for part in st:
				var pname := str(part)
				if pname in ["fill", "crash", "timp", "k2"]:
					continue
				var pat := str(st[part])
				if pname == "k" and b % 2 == 1 and st.has("k2"):
					pat = str(st["k2"])
				for s in mini(spb, pat.length()):
					var c := pat[s]
					if c == ".":
						continue
					if fill_bar and s >= fill_from and pname != "k":
						continue
					hit(pname, t_of(b * spb + s), float(vels.get(c, 0.75)) * vol)
			if fill_bar:
				for k in 4:
					var kind := "s"
					if fill == "toms":
						kind = "t1" if k < 2 else "t2"
					hit(kind, t_of(b * spb + fill_from + k), (0.5 + 0.15 * k) * vol)
			if first and bool(st.get("crash", false)):
				hit("cr", t_of(b * spb), 0.9 * vol)
			if first and bool(st.get("timp", false)):
				hit("ti", t_of(b * spb), 0.8 * vol)
		var hvol := float(cfg.get("vol", 0.5))
		var hits: Array = d.get("hits", [])
		for h in hits:
			var a: Array = h
			hit(str(a[1]), float(a[0]) * 4.0 * step_sec, float(a[2]) * hvol)
		if d.has("roll"):
			var roll: Array = d["roll"]
			var s0 := int(float(roll[0]) * 4.0)
			var s1 := int(float(roll[1]) * 4.0)
			for s in range(s0, s1):
				var u := float(s - s0) / maxf(1.0, float(s1 - s0))
				hit("s", s * step_sec, (0.35 + 0.6 * u) * hvol)
				hit("s", (s + 0.5) * step_sec, (0.3 + 0.55 * u) * hvol)

	# --- Effects and master ---

	## Feedback echo on a bus (circular for loops so the tail wraps into the start).
	func echo(buf: PackedFloat32Array, delay: int, fb: float, amount: float) -> void:
		if delay <= 0 or delay >= n:
			return
		var e := PackedFloat32Array()
		e.resize(n)
		var passes := 2 if looped else 1
		for pass_i in passes:
			var upto := n if pass_i == 0 else mini(n, delay * 10)
			for i in upto:
				var j := i - delay
				if j < 0:
					if not looped:
						continue
					j += n
				e[i] = buf[j] + e[j] * fb
		for i in n:
			buf[i] += e[i] * amount

	## A small Schroeder-style room (3 combs + damping) from the wet bus into the mix.
	func reverb(amount: float) -> void:
		if amount <= 0.0:
			return
		var d1 := 1307
		var d2 := 1601
		var d3 := 1867
		var r1 := PackedFloat32Array()
		r1.resize(d1)
		var r2 := PackedFloat32Array()
		r2.resize(d2)
		var r3 := PackedFloat32Array()
		r3.resize(d3)
		var p1 := 0
		var p2 := 0
		var p3 := 0
		var g := 0.8
		var damp := 0.0
		var pre := mini(n, int(1.5 * rate)) if looped else 0
		for j in range(-pre, n):
			var i := j if j >= 0 else n + j
			var x := wet[i]
			var a := r1[p1]
			r1[p1] = x + a * g
			p1 += 1
			if p1 >= d1:
				p1 = 0
			var b := r2[p2]
			r2[p2] = x + b * g
			p2 += 1
			if p2 >= d2:
				p2 = 0
			var c := r3[p3]
			r3[p3] = x + c * g
			p3 += 1
			if p3 >= d3:
				p3 = 0
			damp += ((a + b + c) * 0.33 - damp) * 0.35
			if j >= 0:
				mix[i] += damp * amount

	## Loudness-normalise to the target RMS with a soft limiter, so every mood plays at the same level.
	func master(target_rms: float) -> PackedFloat32Array:
		var sum := 0.0
		for v in mix:
			sum += v * v
		var rms := sqrt(sum / maxf(1.0, float(n)))
		var gain := target_rms / maxf(rms, 0.00001)
		for i in n:
			var v := mix[i] * gain
			var av := absf(v)
			if av > 0.6:
				v = signf(v) * (0.6 + 0.38 * tanh((av - 0.6) / 0.38))
			mix[i] = v
		if not looped:
			var fade := mini(n, int(0.05 * rate))
			for i in fade:
				mix[n - 1 - i] *= float(i) / fade
		return mix
