extends Node
## Procedurally generated sound effects, so the game needs no audio files.
##
## Add one per scene: `sfx = SfxScript.new(); add_child(sfx)` (const SfxScript := preload("res://core/sfx.gd")).
##   sfx.play("coin")                          one-shot (UI sounds go to the "UI" bus, the rest to "SFX")
##   sfx.play_at("sword_hit", enemy.global_position)   positional 3D one-shot
##   sfx.play_loop("rain", -6.0) / sfx.stop_loop("rain")   seamless ambience loops
##   sfx.add_sound("boop", [0.09, 620.0, 900.0, 0.3, "sine", 0.0])   the classic 6-value sweep format
##   sfx.add_recipe("zing", {"len": 0.3, "layers": [{"w": "tri", "f": 880.0, "f1": 1760.0, "len": 0.25, "dec": 8.0}]})
##   SfxScript.list_sounds() / SfxScript.list_loops()   every built-in name
##
## Every sound is synthesised once on first use (or up front with warm()) and cached for the whole
## session (core/res_cache.gd), so later scenes and other sfx nodes reuse it.
##
## RECIPE FORMAT (built-ins and add_recipe/add_loop): {"len": seconds, "layers": [layer, ...], plus optional
##   "peak": loudness 0..1 (the result is normalised to this peak, default 0.6), "echo": [delay s, feedback],
##   "fade_in"/"fade_out": seconds (whole-sound envelope), "jit": random pitch jitter per play (default 0.03),
##   "rate": sample rate (default 32000), "loop": crossfade seconds (loops only; 0 = already seamless)}.
## A layer is one voice: {"w": "sine"|"tri"|"square"|"saw"|"noise", "f": Hz, "f1": end Hz (sweep, exponential
##   unless "lin": true), "at": start s, "len": s (loops: defaults to the whole loop), "vol": 0..1,
##   "atk": attack s, "dec": exponential decay per second, "rel": fade-out s, "duty": square duty,
##   "vib": [Hz, semitones], "trem": [Hz, depth 0..1], "fm": [ratio, index, index decay /s] (bells, metal),
##   "lp": low-pass Hz, "lp1": low-pass at the end (sweep), "lpm": [Hz, depth Hz] (low-pass wobble), "hp": high-pass Hz,
##   "hold": noise sample-and-hold Hz (crunchy), "notes": [semitones] + "step": s (arpeggio),
##   "every": s + "jit" 0..1 + "fr": [min, max] pitch range + "vr": [min, max] volume range + "grow": pitch
##   multiplier per repeat + "until": s (rattles, raindrops, crackles, bubbles)}.

const ResCache := preload("res://core/res_cache.gd")

const RATE := 22050
const VOICES := 24
const VOICES_3D := 12
const CACHE_VERSION := "r1"
const BUSES: Array[String] = ["Music", "SFX", "UI"]

var streams := {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var voices_3d: Array[AudioStreamPlayer3D] = []
var next_voice_3d := 0
## Active loops: name -> AudioStreamPlayer.
var loops := {}
## Optional: where the listener is when no 3D camera is current (split-screen SubViewports), so
## play_at() can still fade sounds with distance.
var listener: Node3D

var _builtin := {}  # names in `streams` that came from built-in recipes (add_sound may replace them)
var _custom := {}  # add_recipe(): name -> recipe
var _custom_loops := {}  # add_loop(): name -> recipe
var _bg_task := -1
var _bg_jobs: Array = []  # [cache key, recipe, seed] being rendered in the background
var _bg_out: Array = []  # rendered PackedFloat32Array per job (written by the worker)
var _bg_done := 0  # jobs the worker has finished (only the worker writes it while it runs)
var _bg_applied := 0  # jobs the main thread has put in the cache


func _ready() -> void:
	ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		voices.append(p)
	set_process(_bg_task >= 0)


func _exit_tree() -> void:
	if _bg_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bg_task)
		_bg_task = -1


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

## Built-in layered sounds (see RECIPE FORMAT above). Grouped: UI, RPG, sports, sci-fi, quiz, party.
const RECIPES := {
	# --- UI (routed to the "UI" bus) ---
	"ui_move": {"len": 0.07, "peak": 0.28, "jit": 0.02, "layers": [
		{"w": "sine", "f": 1250.0, "f1": 1120.0, "len": 0.05, "dec": 55.0, "vol": 0.8},
		{"w": "tri", "f": 2500.0, "len": 0.02, "dec": 120.0, "vol": 0.25}]},
	"ui_select": {"len": 0.24, "peak": 0.38, "jit": 0.0, "layers": [
		{"w": "tri", "f": 880.0, "len": 0.07, "dec": 25.0, "vol": 0.7},
		{"w": "tri", "f": 1318.5, "at": 0.055, "len": 0.17, "dec": 16.0, "vol": 0.8},
		{"w": "sine", "f": 2637.0, "at": 0.055, "len": 0.1, "dec": 30.0, "vol": 0.15}]},
	"ui_back": {"len": 0.22, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "tri", "f": 987.8, "len": 0.06, "dec": 25.0, "vol": 0.7},
		{"w": "tri", "f": 659.3, "at": 0.05, "len": 0.15, "dec": 18.0, "vol": 0.7}]},
	"ui_error": {"len": 0.3, "peak": 0.36, "jit": 0.0, "layers": [
		{"w": "square", "f": 196.0, "len": 0.11, "lp": 1400.0, "vol": 0.5, "notes": [0, 0], "step": 0.14},
		{"w": "square", "f": 207.7, "len": 0.11, "lp": 1400.0, "vol": 0.35, "notes": [0, 0], "step": 0.14}]},
	"ui_open": {"len": 0.27, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "sine", "f": 420.0, "f1": 980.0, "len": 0.14, "atk": 0.01, "dec": 8.0, "vol": 0.6},
		{"w": "noise", "len": 0.14, "atk": 0.06, "hp": 2500.0, "lp": 8000.0, "vol": 0.15},
		{"w": "tri", "f": 1568.0, "at": 0.1, "len": 0.15, "dec": 20.0, "vol": 0.35}]},
	"ui_close": {"len": 0.2, "peak": 0.28, "jit": 0.0, "layers": [
		{"w": "sine", "f": 980.0, "f1": 420.0, "len": 0.13, "dec": 10.0, "vol": 0.6},
		{"w": "noise", "len": 0.1, "hp": 2500.0, "dec": 20.0, "vol": 0.12}]},
	"ui_tick": {"len": 0.035, "peak": 0.22, "jit": 0.03, "layers": [
		{"w": "noise", "len": 0.012, "hp": 3000.0, "dec": 200.0, "vol": 0.6},
		{"w": "sine", "f": 2100.0, "len": 0.02, "dec": 150.0, "vol": 0.5}]},
	"ui_toggle": {"len": 0.1, "peak": 0.3, "jit": 0.0, "layers": [
		{"w": "sine", "f": 1500.0, "len": 0.025, "dec": 90.0, "vol": 0.7},
		{"w": "sine", "f": 2000.0, "at": 0.045, "len": 0.035, "dec": 70.0, "vol": 0.7}]},
	"ui_notify": {"len": 0.8, "peak": 0.36, "jit": 0.0, "layers": [
		{"w": "sine", "f": 783.99, "len": 0.55, "dec": 7.0, "fm": [3.0, 1.2, 10.0], "vol": 0.6},
		{"w": "sine", "f": 1046.5, "at": 0.11, "len": 0.65, "dec": 6.0, "fm": [3.0, 1.2, 10.0], "vol": 0.7}]},
	"type": {"len": 0.04, "peak": 0.18, "jit": 0.06, "layers": [
		{"w": "square", "f": 1100.0, "len": 0.03, "dec": 90.0, "lp": 3500.0, "vol": 0.7},
		{"w": "noise", "len": 0.008, "hp": 4000.0, "vol": 0.3}]},
	# --- RPG ---
	"sword": {"len": 0.3, "peak": 0.5, "jit": 0.08, "layers": [
		{"w": "noise", "len": 0.26, "atk": 0.07, "dec": 9.0, "lp": 900.0, "lp1": 5000.0, "hp": 500.0, "vol": 1.0},
		{"w": "sine", "f": 260.0, "f1": 140.0, "len": 0.2, "atk": 0.06, "dec": 10.0, "vol": 0.25}]},
	"sword_hit": {"len": 0.6, "peak": 0.62, "jit": 0.06, "layers": [
		{"w": "noise", "len": 0.05, "dec": 60.0, "hp": 1800.0, "vol": 0.9},
		{"w": "sine", "f": 1240.0, "len": 0.5, "dec": 9.0, "fm": [2.76, 2.5, 14.0], "vol": 0.45},
		{"w": "sine", "f": 1830.0, "len": 0.35, "dec": 14.0, "vol": 0.15},
		{"w": "sine", "f": 170.0, "f1": 80.0, "len": 0.12, "dec": 25.0, "vol": 0.6}]},
	"magic": {"len": 0.95, "peak": 0.48, "echo": [0.09, 0.35], "layers": [
		{"w": "tri", "f": 880.0, "notes": [0, 4, 7, 11, 14, 19], "step": 0.045, "len": 0.18, "dec": 14.0, "vib": [7.0, 0.15], "vol": 0.55},
		{"w": "sine", "f": 1760.0, "notes": [0, 4, 7, 11, 14, 19], "step": 0.045, "at": 0.02, "len": 0.12, "dec": 20.0, "vol": 0.2},
		{"w": "noise", "len": 0.5, "atk": 0.15, "dec": 5.0, "hp": 5000.0, "vol": 0.12}]},
	"fire": {"len": 0.85, "peak": 0.58, "layers": [
		{"w": "noise", "len": 0.75, "atk": 0.04, "dec": 4.0, "lp": 2200.0, "lp1": 500.0, "vol": 0.9},
		{"w": "sine", "f": 110.0, "f1": 55.0, "len": 0.5, "atk": 0.02, "dec": 5.0, "vol": 0.5},
		{"w": "noise", "len": 0.006, "hp": 2500.0, "vol": 0.6, "every": 0.035, "jit": 0.9, "vr": [0.2, 1.0], "until": 0.6}]},
	"ice": {"len": 0.95, "peak": 0.48, "echo": [0.07, 0.3], "layers": [
		{"w": "noise", "len": 0.06, "hp": 4000.0, "dec": 40.0, "vol": 0.7},
		{"w": "sine", "f": 1568.0, "notes": [0, 7, 12, 19, 24], "step": 0.035, "len": 0.3, "dec": 10.0, "fm": [3.5, 1.5, 12.0], "vol": 0.45},
		{"w": "sine", "f": 3136.0, "len": 0.5, "atk": 0.05, "dec": 6.0, "trem": [22.0, 0.5], "vol": 0.12}]},
	"heal": {"len": 1.15, "peak": 0.42, "jit": 0.0, "echo": [0.11, 0.3], "layers": [
		{"w": "sine", "f": 659.25, "notes": [0, 4, 7, 12, 16], "step": 0.08, "len": 0.35, "atk": 0.015, "dec": 6.0, "vol": 0.5},
		{"w": "tri", "f": 523.25, "f1": 659.25, "len": 0.7, "atk": 0.15, "dec": 2.5, "vib": [5.0, 0.1], "vol": 0.25},
		{"w": "noise", "len": 0.6, "atk": 0.2, "dec": 4.0, "hp": 6000.0, "vol": 0.08}]},
	"level_up": {"len": 1.35, "peak": 0.52, "jit": 0.0, "echo": [0.12, 0.25], "layers": [
		{"w": "square", "f": 523.25, "notes": [0, 4, 7, 12], "step": 0.085, "len": 0.09, "lp": 4000.0, "dec": 4.0, "vol": 0.45},
		{"w": "square", "f": 1046.5, "at": 0.34, "len": 0.75, "duty": 0.25, "lp": 5000.0, "vib": [6.0, 0.12], "dec": 2.0, "vol": 0.4},
		{"w": "square", "f": 1318.5, "at": 0.34, "len": 0.75, "duty": 0.25, "lp": 5000.0, "vib": [6.0, 0.12], "dec": 2.0, "vol": 0.3},
		{"w": "tri", "f": 261.6, "at": 0.34, "len": 0.6, "dec": 3.0, "vol": 0.4}]},
	"crit": {"len": 0.6, "peak": 0.78, "layers": [
		{"w": "noise", "len": 0.12, "dec": 25.0, "lp": 4000.0, "vol": 0.9},
		{"w": "sine", "f": 120.0, "f1": 40.0, "len": 0.35, "dec": 8.0, "vol": 0.9},
		{"w": "square", "f": 1760.0, "f1": 2640.0, "len": 0.14, "dec": 12.0, "lp": 6000.0, "vol": 0.25},
		{"w": "sine", "f": 2093.0, "at": 0.05, "len": 0.4, "dec": 8.0, "fm": [2.0, 1.0, 10.0], "vol": 0.2}]},
	"potion": {"len": 0.65, "peak": 0.42, "layers": [
		{"w": "sine", "f": 330.0, "f1": 700.0, "len": 0.05, "dec": 30.0, "vol": 0.7, "every": 0.065, "jit": 0.35, "fr": [0.85, 1.15], "grow": 1.07, "until": 0.42},
		{"w": "sine", "f": 500.0, "f1": 1500.0, "at": 0.48, "len": 0.08, "dec": 20.0, "vol": 0.6}]},
	"coin": {"len": 0.45, "peak": 0.42, "jit": 0.0, "layers": [
		{"w": "square", "f": 987.77, "len": 0.075, "lp": 7000.0, "vol": 0.5},
		{"w": "square", "f": 1318.5, "at": 0.07, "len": 0.36, "lp": 7000.0, "dec": 7.0, "vol": 0.5}]},
	"chest": {"len": 1.25, "peak": 0.48, "jit": 0.0, "echo": [0.1, 0.3], "layers": [
		{"w": "saw", "f": 90.0, "f1": 150.0, "len": 0.35, "lp": 700.0, "vib": [18.0, 1.5], "atk": 0.03, "trem": [25.0, 0.5], "vol": 0.45},
		{"w": "sine", "f": 1046.5, "notes": [0, 4, 7, 12, 16], "step": 0.06, "at": 0.35, "len": 0.4, "dec": 6.0, "fm": [3.0, 1.0, 8.0], "vol": 0.45},
		{"w": "noise", "at": 0.35, "len": 0.5, "atk": 0.1, "dec": 5.0, "hp": 6000.0, "vol": 0.1}]},
	"door": {"len": 0.8, "peak": 0.52, "layers": [
		{"w": "saw", "f": 70.0, "f1": 120.0, "len": 0.55, "lp": 500.0, "vib": [9.0, 2.0], "trem": [30.0, 0.6], "atk": 0.05, "vol": 0.5},
		{"w": "noise", "at": 0.55, "len": 0.12, "lp": 350.0, "dec": 25.0, "vol": 0.9},
		{"w": "sine", "f": 90.0, "f1": 60.0, "at": 0.55, "len": 0.15, "dec": 20.0, "vol": 0.8}]},
	"footstep": {"len": 0.09, "peak": 0.28, "jit": 0.12, "layers": [
		{"w": "noise", "len": 0.06, "lp": 600.0, "dec": 45.0, "vol": 1.0},
		{"w": "sine", "f": 130.0, "f1": 70.0, "len": 0.06, "dec": 40.0, "vol": 0.6}]},
	"block": {"len": 0.35, "peak": 0.58, "layers": [
		{"w": "noise", "len": 0.04, "hp": 800.0, "lp": 3000.0, "dec": 60.0, "vol": 0.8},
		{"w": "sine", "f": 620.0, "len": 0.3, "dec": 14.0, "fm": [1.41, 2.0, 20.0], "vol": 0.5},
		{"w": "sine", "f": 160.0, "f1": 110.0, "len": 0.1, "dec": 30.0, "vol": 0.6}]},
	"miss": {"len": 0.2, "peak": 0.3, "jit": 0.08, "layers": [
		{"w": "noise", "len": 0.17, "atk": 0.04, "dec": 12.0, "lp": 2500.0, "lp1": 500.0, "hp": 300.0, "vol": 1.0}]},
	"faint": {"len": 1.35, "peak": 0.42, "jit": 0.0, "echo": [0.15, 0.25], "layers": [
		{"w": "tri", "f": 392.0, "notes": [7, 5, 3, 0], "step": 0.17, "len": 0.22, "vib": [5.0, 0.2], "dec": 3.0, "vol": 0.6},
		{"w": "tri", "f": 261.6, "f1": 130.8, "at": 0.68, "len": 0.55, "vib": [4.0, 0.3], "dec": 2.0, "vol": 0.5}]},
	"explosion": {"len": 1.3, "peak": 0.85, "jit": 0.08, "layers": [
		{"w": "noise", "len": 1.2, "dec": 3.5, "lp": 2500.0, "lp1": 200.0, "vol": 1.0},
		{"w": "sine", "f": 80.0, "f1": 28.0, "len": 0.8, "dec": 4.0, "vol": 0.9},
		{"w": "noise", "len": 0.05, "dec": 50.0, "hp": 1500.0, "vol": 0.5}]},
	"jump": {"len": 0.2, "peak": 0.33, "layers": [
		{"w": "square", "f": 280.0, "f1": 720.0, "len": 0.16, "duty": 0.25, "lp": 3000.0, "dec": 8.0, "vol": 0.6}]},
	"land": {"len": 0.12, "peak": 0.33, "jit": 0.1, "layers": [
		{"w": "noise", "len": 0.08, "lp": 450.0, "dec": 35.0, "vol": 1.0},
		{"w": "sine", "f": 100.0, "f1": 55.0, "len": 0.1, "dec": 25.0, "vol": 0.7}]},
	"bow": {"len": 0.42, "peak": 0.42, "layers": [
		{"w": "tri", "f": 196.0, "f1": 185.0, "len": 0.35, "dec": 10.0, "fm": [2.0, 1.5, 15.0], "vol": 0.6},
		{"w": "noise", "at": 0.02, "len": 0.15, "lp": 3000.0, "lp1": 800.0, "hp": 600.0, "dec": 12.0, "vol": 0.4}]},
	"buff": {"len": 0.75, "peak": 0.4, "jit": 0.0, "echo": [0.08, 0.3], "layers": [
		{"w": "saw", "f": 220.0, "f1": 880.0, "len": 0.5, "lp": 1200.0, "lp1": 4000.0, "atk": 0.1, "dec": 3.0, "vib": [8.0, 0.2], "vol": 0.4},
		{"w": "sine", "f": 880.0, "notes": [0, 7, 12, 19], "step": 0.1, "at": 0.1, "len": 0.2, "dec": 10.0, "vol": 0.4}]},
	"debuff": {"len": 0.7, "peak": 0.4, "jit": 0.0, "layers": [
		{"w": "saw", "f": 660.0, "f1": 160.0, "len": 0.55, "lp": 1500.0, "lp1": 500.0, "dec": 3.0, "vib": [6.0, 0.4], "vol": 0.5},
		{"w": "square", "f": 233.0, "f1": 110.0, "at": 0.1, "len": 0.4, "duty": 0.25, "lp": 900.0, "dec": 4.0, "vol": 0.3}]},
	"equip": {"len": 0.28, "peak": 0.4, "layers": [
		{"w": "noise", "len": 0.03, "hp": 2000.0, "dec": 80.0, "vol": 0.7},
		{"w": "sine", "f": 1800.0, "len": 0.2, "dec": 18.0, "fm": [1.5, 1.5, 25.0], "vol": 0.4},
		{"w": "sine", "f": 2400.0, "at": 0.05, "len": 0.15, "dec": 20.0, "fm": [1.5, 1.0, 25.0], "vol": 0.3}]},
	"kaching": {"len": 0.9, "peak": 0.48, "jit": 0.0, "layers": [
		{"w": "noise", "len": 0.05, "hp": 3000.0, "dec": 60.0, "vol": 0.6},
		{"w": "square", "f": 1318.5, "len": 0.06, "lp": 6000.0, "vol": 0.4},
		{"w": "square", "f": 1975.5, "at": 0.06, "len": 0.3, "lp": 6000.0, "dec": 8.0, "vol": 0.4},
		{"w": "sine", "f": 2637.0, "at": 0.08, "len": 0.75, "dec": 5.0, "fm": [3.0, 1.5, 6.0], "vol": 0.35}]},
	# --- Sports ---
	"kick": {"len": 0.2, "peak": 0.58, "jit": 0.06, "layers": [
		{"w": "sine", "f": 170.0, "f1": 55.0, "len": 0.15, "dec": 18.0, "vol": 1.0},
		{"w": "noise", "len": 0.03, "lp": 2500.0, "dec": 70.0, "vol": 0.6}]},
	"ball_hit": {"len": 0.2, "peak": 0.52, "jit": 0.06, "layers": [
		{"w": "noise", "len": 0.025, "hp": 1200.0, "dec": 90.0, "vol": 1.0},
		{"w": "tri", "f": 720.0, "f1": 420.0, "len": 0.08, "dec": 40.0, "vol": 0.6},
		{"w": "sine", "f": 200.0, "f1": 120.0, "len": 0.1, "dec": 30.0, "vol": 0.5}]},
	"bounce": {"len": 0.12, "peak": 0.35, "jit": 0.08, "layers": [
		{"w": "sine", "f": 240.0, "f1": 140.0, "len": 0.09, "dec": 35.0, "vol": 1.0},
		{"w": "noise", "len": 0.015, "lp": 1500.0, "dec": 120.0, "vol": 0.3}]},
	"swish": {"len": 0.3, "peak": 0.32, "jit": 0.05, "layers": [
		{"w": "noise", "len": 0.27, "atk": 0.05, "dec": 10.0, "hp": 2000.0, "lp": 6000.0, "vol": 1.0}]},
	"cheer": {"len": 2.4, "peak": 0.55, "jit": 0.04, "fade_out": 0.8, "layers": [
		{"w": "noise", "len": 2.3, "atk": 0.35, "dec": 1.0, "hp": 500.0, "lp": 2600.0, "trem": [6.5, 0.25], "vol": 0.7},
		{"w": "noise", "len": 2.0, "atk": 0.25, "dec": 1.3, "hp": 900.0, "lp": 3500.0, "trem": [9.3, 0.3], "vol": 0.4},
		{"w": "saw", "f": 420.0, "f1": 760.0, "len": 0.25, "atk": 0.05, "lp": 1400.0, "vib": [6.0, 0.5], "vol": 0.12, "every": 0.07, "jit": 0.9, "fr": [0.7, 1.5], "vr": [0.3, 1.0], "until": 1.6}]},
	"whistle": {"len": 0.6, "peak": 0.48, "jit": 0.01, "layers": [
		{"w": "sine", "f": 2900.0, "len": 0.5, "atk": 0.02, "rel": 0.05, "vib": [32.0, 0.45], "vol": 0.8},
		{"w": "noise", "len": 0.5, "atk": 0.02, "hp": 2500.0, "lp": 5000.0, "trem": [32.0, 0.6], "vol": 0.18}]},
	"applause": {"len": 2.6, "peak": 0.48, "jit": 0.0, "fade_in": 0.15, "fade_out": 1.4, "layers": [
		{"w": "noise", "len": 0.012, "hp": 1200.0, "lp": 7000.0, "dec": 250.0, "vol": 1.0, "every": 0.011, "jit": 0.9, "vr": [0.2, 1.0], "until": 2.5}]},
	"crowd_oh": {"len": 1.45, "peak": 0.5, "jit": 0.03, "fade_out": 0.5, "layers": [
		{"w": "saw", "f": 233.0, "f1": 180.0, "len": 1.2, "atk": 0.15, "dec": 1.5, "lp": 800.0, "vib": [5.0, 0.3], "vol": 0.3},
		{"w": "saw", "f": 247.0, "f1": 175.0, "len": 1.2, "atk": 0.18, "dec": 1.5, "lp": 750.0, "vib": [4.3, 0.3], "vol": 0.3},
		{"w": "saw", "f": 196.0, "f1": 165.0, "len": 1.2, "atk": 0.2, "dec": 1.5, "lp": 700.0, "vib": [5.6, 0.3], "vol": 0.3},
		{"w": "saw", "f": 294.0, "f1": 220.0, "len": 1.1, "atk": 0.15, "dec": 1.5, "lp": 900.0, "vib": [4.8, 0.3], "vol": 0.2},
		{"w": "noise", "len": 1.2, "atk": 0.2, "dec": 1.5, "hp": 300.0, "lp": 1500.0, "vol": 0.25}]},
	"horn": {"len": 1.1, "peak": 0.52, "jit": 0.0, "layers": [
		{"w": "saw", "f": 233.0, "len": 1.0, "atk": 0.02, "rel": 0.1, "lp": 2200.0, "vol": 0.4},
		{"w": "saw", "f": 293.7, "len": 1.0, "atk": 0.02, "rel": 0.1, "lp": 2200.0, "vol": 0.35},
		{"w": "saw", "f": 349.2, "len": 1.0, "atk": 0.02, "rel": 0.1, "lp": 2200.0, "vol": 0.3}]},
	# --- Sci-fi ---
	"laser": {"len": 0.22, "peak": 0.42, "jit": 0.06, "layers": [
		{"w": "square", "f": 1900.0, "f1": 260.0, "len": 0.18, "lp": 5000.0, "dec": 8.0, "vol": 0.6},
		{"w": "sine", "f": 2400.0, "f1": 350.0, "len": 0.16, "dec": 10.0, "vol": 0.4}]},
	"warp": {"len": 1.45, "peak": 0.52, "jit": 0.0, "echo": [0.13, 0.35], "layers": [
		{"w": "saw", "f": 80.0, "f1": 1800.0, "len": 1.0, "lp": 400.0, "lp1": 6000.0, "atk": 0.3, "vib": [7.0, 0.3], "vol": 0.5},
		{"w": "noise", "len": 1.0, "atk": 0.6, "lp": 1000.0, "lp1": 8000.0, "rel": 0.1, "vol": 0.3},
		{"w": "sine", "f": 2000.0, "f1": 200.0, "at": 0.95, "len": 0.3, "dec": 8.0, "vol": 0.4}]},
	"alarm": {"len": 0.95, "peak": 0.45, "jit": 0.0, "layers": [
		{"w": "square", "f": 880.0, "len": 0.2, "lp": 3000.0, "vol": 0.5, "notes": [0, -5, 0, -5], "step": 0.22}]},
	"beep": {"len": 0.12, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "square", "f": 1000.0, "len": 0.09, "lp": 4000.0, "vol": 0.5},
		{"w": "sine", "f": 2000.0, "len": 0.09, "vol": 0.2}]},
	"power_up": {"len": 0.7, "peak": 0.48, "jit": 0.0, "layers": [
		{"w": "square", "f": 330.0, "notes": [0, 4, 7, 12, 16, 19, 24], "step": 0.05, "len": 0.07, "duty": 0.25, "lp": 5000.0, "vol": 0.5},
		{"w": "saw", "f": 220.0, "f1": 880.0, "len": 0.45, "lp": 1500.0, "lp1": 4000.0, "atk": 0.05, "dec": 3.0, "vol": 0.3}]},
	"power_down": {"len": 0.9, "peak": 0.48, "jit": 0.0, "layers": [
		{"w": "saw", "f": 880.0, "f1": 55.0, "len": 0.8, "lp": 3000.0, "lp1": 300.0, "vib": [9.0, 0.6], "dec": 1.5, "vol": 0.6}]},
	"teleport": {"len": 0.85, "peak": 0.44, "jit": 0.0, "echo": [0.07, 0.4], "layers": [
		{"w": "sine", "f": 300.0, "f1": 3000.0, "len": 0.5, "fm": [1.5, 3.0, 4.0], "trem": [28.0, 0.7], "dec": 2.0, "vol": 0.6},
		{"w": "noise", "len": 0.4, "hp": 4000.0, "atk": 0.1, "dec": 6.0, "vol": 0.15}]},
	"computer": {"len": 0.6, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "square", "f": 1200.0, "len": 0.045, "lp": 4000.0, "vol": 0.5, "every": 0.06, "fr": [0.6, 1.7], "until": 0.5}]},
	# --- Quiz show ---
	"buzzer": {"len": 0.45, "peak": 0.52, "jit": 0.0, "layers": [
		{"w": "square", "f": 523.25, "len": 0.4, "lp": 3500.0, "dec": 2.0, "vol": 0.45},
		{"w": "square", "f": 659.25, "len": 0.4, "lp": 3500.0, "dec": 2.0, "vol": 0.4},
		{"w": "square", "f": 783.99, "len": 0.4, "lp": 3500.0, "dec": 2.0, "vol": 0.35}]},
	"correct": {"len": 0.95, "peak": 0.48, "jit": 0.0, "echo": [0.1, 0.2], "layers": [
		{"w": "sine", "f": 1046.5, "len": 0.5, "dec": 6.0, "fm": [2.0, 1.2, 10.0], "vol": 0.6},
		{"w": "sine", "f": 1318.5, "at": 0.11, "len": 0.7, "dec": 5.0, "fm": [2.0, 1.2, 10.0], "vol": 0.6},
		{"w": "sine", "f": 1568.0, "at": 0.22, "len": 0.65, "dec": 5.0, "fm": [2.0, 1.0, 10.0], "vol": 0.5}]},
	"wrong": {"len": 0.75, "peak": 0.52, "jit": 0.0, "layers": [
		{"w": "saw", "f": 146.8, "len": 0.26, "lp": 1100.0, "rel": 0.04, "vol": 0.5, "notes": [0, 0], "step": 0.34},
		{"w": "saw", "f": 155.6, "len": 0.26, "lp": 1100.0, "rel": 0.04, "vol": 0.45, "notes": [0, 0], "step": 0.34},
		{"w": "square", "f": 73.4, "len": 0.26, "lp": 600.0, "rel": 0.04, "vol": 0.4, "notes": [0, 0], "step": 0.34}]},
	"tick": {"len": 0.05, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "sine", "f": 1600.0, "len": 0.03, "dec": 120.0, "vol": 0.8},
		{"w": "noise", "len": 0.01, "hp": 3000.0, "dec": 300.0, "vol": 0.5}]},
	"tock": {"len": 0.06, "peak": 0.33, "jit": 0.0, "layers": [
		{"w": "sine", "f": 1050.0, "len": 0.045, "dec": 90.0, "vol": 0.8},
		{"w": "noise", "len": 0.012, "hp": 1500.0, "lp": 4000.0, "dec": 250.0, "vol": 0.4}]},
	"countdown": {"len": 0.25, "peak": 0.42, "jit": 0.0, "layers": [
		{"w": "square", "f": 660.0, "len": 0.15, "lp": 3500.0, "rel": 0.03, "vol": 0.5},
		{"w": "sine", "f": 1320.0, "len": 0.15, "vol": 0.15}]},
	"go": {"len": 0.75, "peak": 0.48, "jit": 0.0, "layers": [
		{"w": "square", "f": 1320.0, "len": 0.6, "lp": 4000.0, "dec": 1.5, "vol": 0.5},
		{"w": "sine", "f": 2640.0, "len": 0.5, "dec": 3.0, "vol": 0.15}]},
	"time_up": {"len": 1.4, "peak": 0.52, "jit": 0.0, "layers": [
		{"w": "square", "f": 880.0, "notes": [0, 0, 0], "step": 0.18, "len": 0.12, "lp": 3500.0, "vol": 0.5},
		{"w": "saw", "f": 440.0, "f1": 415.0, "at": 0.54, "len": 0.8, "lp": 1800.0, "vib": [5.0, 0.2], "dec": 1.5, "vol": 0.5}]},
	"fanfare": {"len": 1.45, "peak": 0.52, "jit": 0.0, "echo": [0.12, 0.2], "layers": [
		{"w": "saw", "f": 392.0, "notes": [0, 0, 0], "step": 0.1, "len": 0.08, "lp": 2600.0, "vol": 0.45},
		{"w": "saw", "f": 523.25, "at": 0.3, "len": 0.9, "lp": 2600.0, "atk": 0.02, "vib": [5.5, 0.15], "dec": 1.2, "vol": 0.45},
		{"w": "saw", "f": 659.25, "at": 0.3, "len": 0.9, "lp": 2600.0, "atk": 0.02, "vib": [5.2, 0.15], "dec": 1.2, "vol": 0.35},
		{"w": "saw", "f": 783.99, "at": 0.3, "len": 0.9, "lp": 2600.0, "atk": 0.02, "vib": [5.8, 0.15], "dec": 1.2, "vol": 0.3},
		{"w": "sine", "f": 130.8, "at": 0.3, "len": 0.8, "dec": 3.0, "vol": 0.5}]},
	"reveal": {"len": 1.3, "peak": 0.45, "jit": 0.0, "echo": [0.1, 0.3], "layers": [
		{"w": "noise", "len": 0.7, "atk": 0.6, "rel": 0.02, "lp": 600.0, "lp1": 7000.0, "hp": 200.0, "vol": 0.5},
		{"w": "sine", "f": 1568.0, "at": 0.7, "len": 0.55, "dec": 4.0, "fm": [3.5, 2.0, 6.0], "vol": 0.6},
		{"w": "sine", "f": 2093.0, "at": 0.7, "len": 0.5, "dec": 5.0, "fm": [3.5, 1.5, 6.0], "vol": 0.4}]},
	"drumroll": {"len": 2.8, "peak": 0.5, "jit": 0.0, "fade_in": 1.6, "layers": [
		{"w": "noise", "len": 0.03, "hp": 1500.0, "lp": 7000.0, "dec": 60.0, "vol": 1.0, "every": 0.032, "jit": 0.15, "vr": [0.6, 1.0], "until": 1.75},
		{"w": "sine", "f": 190.0, "len": 0.03, "dec": 60.0, "vol": 0.3, "every": 0.032, "until": 1.75},
		{"w": "noise", "at": 1.8, "len": 1.0, "hp": 3500.0, "dec": 3.0, "vol": 0.8},
		{"w": "sine", "f": 110.0, "f1": 50.0, "at": 1.8, "len": 0.3, "dec": 10.0, "vol": 0.8}]},
	"crash": {"len": 1.6, "peak": 0.48, "jit": 0.03, "layers": [
		{"w": "noise", "len": 1.5, "hp": 3500.0, "dec": 2.5, "vol": 1.0},
		{"w": "sine", "f": 620.0, "len": 1.0, "fm": [2.3, 4.0, 3.0], "dec": 4.0, "vol": 0.15}]},
	# --- Party ---
	"dice": {"len": 0.6, "peak": 0.42, "jit": 0.05, "fade_out": 0.3, "layers": [
		{"w": "noise", "len": 0.012, "hp": 1800.0, "lp": 6000.0, "dec": 200.0, "vol": 0.9, "every": 0.045, "jit": 0.7, "vr": [0.3, 1.0], "until": 0.5},
		{"w": "tri", "f": 2200.0, "len": 0.015, "dec": 150.0, "vol": 0.35, "every": 0.06, "jit": 0.8, "fr": [0.7, 1.4], "until": 0.45}]},
	"card": {"len": 0.1, "peak": 0.33, "jit": 0.08, "layers": [
		{"w": "noise", "len": 0.07, "hp": 2500.0, "lp": 9000.0, "lp1": 3000.0, "atk": 0.005, "dec": 40.0, "vol": 1.0}]},
	"pop": {"len": 0.12, "peak": 0.42, "jit": 0.1, "layers": [
		{"w": "sine", "f": 380.0, "f1": 1500.0, "len": 0.07, "dec": 30.0, "vol": 1.0},
		{"w": "noise", "len": 0.01, "hp": 2000.0, "dec": 300.0, "vol": 0.4}]},
	"boing": {"len": 0.6, "peak": 0.42, "jit": 0.05, "layers": [
		{"w": "sine", "f": 180.0, "f1": 420.0, "len": 0.55, "vib": [14.0, 3.5], "dec": 5.0, "vol": 0.8},
		{"w": "tri", "f": 360.0, "f1": 840.0, "len": 0.4, "vib": [14.0, 3.5], "dec": 7.0, "vol": 0.2}]},
	"ding": {"len": 1.6, "peak": 0.45, "jit": 0.0, "layers": [
		{"w": "sine", "f": 1318.5, "len": 1.5, "dec": 3.0, "fm": [3.5, 2.0, 5.0], "vol": 0.7},
		{"w": "sine", "f": 2637.0, "len": 0.8, "dec": 6.0, "vol": 0.15}]},
	"bell": {"len": 2.2, "peak": 0.45, "jit": 0.0, "layers": [
		{"w": "sine", "f": 523.25, "len": 2.1, "dec": 2.0, "fm": [1.4, 3.0, 2.0], "vol": 0.7},
		{"w": "sine", "f": 1046.5, "len": 1.2, "dec": 3.5, "fm": [2.76, 1.0, 4.0], "vol": 0.25}]},
	"whoosh": {"len": 0.45, "peak": 0.38, "jit": 0.06, "layers": [
		{"w": "noise", "len": 0.4, "atk": 0.15, "dec": 5.0, "lp": 500.0, "lp1": 4000.0, "hp": 250.0, "vol": 1.0}]},
	"splash": {"len": 0.75, "peak": 0.48, "jit": 0.06, "layers": [
		{"w": "noise", "len": 0.6, "dec": 5.0, "lp": 3500.0, "lp1": 600.0, "vol": 1.0},
		{"w": "sine", "f": 400.0, "f1": 1000.0, "len": 0.04, "dec": 40.0, "vol": 0.35, "every": 0.05, "jit": 0.8, "fr": [0.7, 1.6], "vr": [0.3, 1.0], "until": 0.55}]},
	"honk": {"len": 0.35, "peak": 0.42, "jit": 0.04, "layers": [
		{"w": "saw", "f": 330.0, "len": 0.3, "lp": 1600.0, "vib": [7.0, 0.3], "vol": 0.5},
		{"w": "square", "f": 335.0, "len": 0.3, "duty": 0.3, "lp": 1200.0, "vol": 0.3}]},
	"party_horn": {"len": 0.8, "peak": 0.42, "jit": 0.04, "layers": [
		{"w": "saw", "f": 440.0, "f1": 470.0, "len": 0.7, "atk": 0.03, "lp": 2500.0, "trem": [18.0, 0.4], "vol": 0.6},
		{"w": "noise", "len": 0.7, "hp": 2000.0, "lp": 5000.0, "atk": 0.03, "vol": 0.1}]},
	"clap": {"len": 0.16, "peak": 0.42, "jit": 0.05, "layers": [
		{"w": "noise", "len": 0.012, "hp": 900.0, "lp": 5000.0, "dec": 200.0, "vol": 1.0, "notes": [0, 0, 0], "step": 0.011},
		{"w": "noise", "at": 0.03, "len": 0.1, "hp": 900.0, "lp": 4000.0, "dec": 35.0, "vol": 0.6}]},
	"sparkle": {"len": 0.85, "peak": 0.33, "jit": 0.0, "echo": [0.06, 0.35], "layers": [
		{"w": "sine", "f": 2000.0, "len": 0.08, "dec": 30.0, "fm": [2.0, 1.0, 20.0], "vol": 0.5, "every": 0.05, "jit": 0.6, "fr": [0.8, 1.6], "vr": [0.4, 1.0], "until": 0.4}]},
	"win": {"len": 1.2, "peak": 0.5, "jit": 0.0, "echo": [0.1, 0.25], "layers": [
		{"w": "square", "f": 523.25, "notes": [0, 4, 7, 12, 7, 12], "step": 0.09, "len": 0.1, "duty": 0.25, "lp": 5000.0, "vol": 0.45},
		{"w": "tri", "f": 1046.5, "at": 0.55, "len": 0.6, "dec": 3.0, "vib": [6.0, 0.15], "vol": 0.5},
		{"w": "tri", "f": 1318.5, "at": 0.55, "len": 0.6, "dec": 3.0, "vib": [6.0, 0.15], "vol": 0.35}]},
	"sad_trombone": {"len": 2.0, "peak": 0.5, "jit": 0.0, "layers": [
		{"w": "saw", "f": 293.7, "notes": [0, -1, -2], "step": 0.42, "len": 0.38, "atk": 0.03, "lp": 1300.0, "rel": 0.06, "vol": 0.55},
		{"w": "saw", "f": 246.9, "at": 1.26, "len": 0.7, "atk": 0.03, "lp": 1300.0, "vib": [6.0, 0.6], "rel": 0.15, "vol": 0.55}]},
	"achievement": {"len": 1.3, "peak": 0.48, "jit": 0.0, "echo": [0.1, 0.3], "layers": [
		{"w": "tri", "f": 783.99, "notes": [0, 5, 9, 12], "step": 0.07, "len": 0.12, "dec": 10.0, "vol": 0.5},
		{"w": "sine", "f": 1568.0, "at": 0.28, "len": 0.9, "dec": 3.5, "fm": [3.0, 1.5, 6.0], "vol": 0.55},
		{"w": "sine", "f": 2093.0, "at": 0.28, "len": 0.8, "dec": 4.0, "fm": [3.0, 1.0, 6.0], "vol": 0.3}]},
}

## Built-in seamless loops for play_loop() (layers without "len" last the whole loop).
const LOOPS := {
	"alarm": {"len": 1.0, "loop": 0.0, "peak": 0.42, "rate": 22050, "layers": [
		{"w": "square", "f": 880.0, "len": 0.48, "atk": 0.01, "rel": 0.02, "lp": 2800.0, "vol": 0.5},
		{"w": "square", "f": 660.0, "at": 0.5, "len": 0.48, "atk": 0.01, "rel": 0.02, "lp": 2800.0, "vol": 0.5}]},
	"hum": {"len": 2.0, "loop": 0.2, "peak": 0.38, "rate": 22050, "layers": [
		{"w": "saw", "f": 55.0, "lp": 350.0, "trem": [3.0, 0.12], "vol": 0.6},
		{"w": "sine", "f": 110.0, "vol": 0.4},
		{"w": "sine", "f": 165.0, "trem": [1.5, 0.3], "vol": 0.15},
		{"w": "noise", "lp": 200.0, "vol": 0.2}]},
	"engine": {"len": 1.0, "loop": 0.15, "peak": 0.45, "rate": 22050, "layers": [
		{"w": "saw", "f": 46.0, "lp": 300.0, "trem": [23.0, 0.35], "vol": 0.7},
		{"w": "square", "f": 92.0, "duty": 0.3, "lp": 500.0, "vol": 0.25},
		{"w": "noise", "lp": 400.0, "trem": [23.0, 0.5], "vol": 0.3}]},
	"rain": {"len": 4.0, "loop": 0.4, "peak": 0.4, "rate": 22050, "layers": [
		{"w": "noise", "hp": 700.0, "lp": 5500.0, "vol": 0.45},
		{"w": "noise", "lp": 400.0, "vol": 0.25},
		{"w": "sine", "f": 3000.0, "f1": 1800.0, "len": 0.012, "dec": 200.0, "vol": 0.4, "every": 0.025, "jit": 1.0, "fr": [0.6, 1.6], "vr": [0.1, 1.0]}]},
	"wind": {"len": 8.0, "loop": 1.0, "peak": 0.4, "rate": 22050, "layers": [
		{"w": "noise", "lp": 700.0, "lpm": [0.25, 450.0], "hp": 120.0, "trem": [0.125, 0.45], "vol": 0.8},
		{"w": "noise", "lp": 1800.0, "lpm": [0.375, 900.0], "hp": 900.0, "trem": [0.25, 0.6], "vol": 0.25}]},
	"crowd": {"len": 4.0, "loop": 0.5, "peak": 0.4, "rate": 22050, "layers": [
		{"w": "noise", "hp": 350.0, "lp": 1800.0, "trem": [2.5, 0.2], "vol": 0.6},
		{"w": "noise", "hp": 700.0, "lp": 2800.0, "trem": [3.25, 0.25], "vol": 0.3},
		{"w": "saw", "f": 160.0, "f1": 150.0, "len": 0.22, "atk": 0.04, "lp": 800.0, "vib": [5.0, 0.4], "vol": 0.12, "every": 0.05, "jit": 1.0, "fr": [0.8, 1.9], "vr": [0.2, 1.0]}]},
	"fire": {"len": 4.0, "loop": 0.3, "peak": 0.42, "rate": 22050, "layers": [
		{"w": "noise", "lp": 350.0, "trem": [1.5, 0.2], "vol": 0.7},
		{"w": "noise", "lp": 1200.0, "hp": 300.0, "vol": 0.15},
		{"w": "noise", "len": 0.004, "hp": 2000.0, "vol": 0.8, "every": 0.03, "jit": 1.0, "vr": [0.1, 1.0]},
		{"w": "noise", "len": 0.02, "lp": 1500.0, "dec": 100.0, "vol": 0.6, "every": 0.22, "jit": 1.0, "vr": [0.3, 1.0]}]},
	"clock": {"len": 1.0, "loop": 0.0, "peak": 0.3, "rate": 22050, "layers": [
		{"w": "sine", "f": 1600.0, "len": 0.03, "dec": 120.0, "vol": 0.8},
		{"w": "noise", "len": 0.01, "hp": 3000.0, "dec": 300.0, "vol": 0.5},
		{"w": "sine", "f": 1050.0, "at": 0.5, "len": 0.045, "dec": 90.0, "vol": 0.8},
		{"w": "noise", "at": 0.5, "len": 0.012, "hp": 1500.0, "lp": 4000.0, "dec": 250.0, "vol": 0.4}]},
	"bubbles": {"len": 4.0, "loop": 0.3, "peak": 0.38, "rate": 22050, "layers": [
		{"w": "noise", "lp": 220.0, "vol": 0.6},
		{"w": "sine", "f": 350.0, "f1": 900.0, "len": 0.05, "dec": 40.0, "vol": 0.4, "every": 0.18, "jit": 1.0, "fr": [0.6, 1.8], "vr": [0.3, 1.0]}]},
	"space": {"len": 8.0, "loop": 1.0, "peak": 0.38, "rate": 22050, "layers": [
		{"w": "sine", "f": 55.0, "trem": [0.125, 0.3], "vol": 0.5},
		{"w": "sine", "f": 82.5, "trem": [0.25, 0.4], "vol": 0.3},
		{"w": "tri", "f": 110.0, "vol": 0.12},
		{"w": "noise", "lp": 500.0, "lpm": [0.125, 350.0], "vol": 0.25},
		{"w": "sine", "f": 880.0, "trem": [0.375, 0.9], "vol": 0.04},
		{"w": "sine", "f": 1320.0, "trem": [0.25, 0.9], "vol": 0.03}]},
	"waves": {"len": 8.0, "loop": 1.0, "peak": 0.4, "rate": 22050, "layers": [
		{"w": "noise", "lp": 900.0, "lpm": [0.125, 600.0], "trem": [0.125, 0.8], "vol": 0.8},
		{"w": "noise", "hp": 1500.0, "lp": 4000.0, "trem": [0.125, 0.9], "vol": 0.15}]},
	"birds": {"len": 8.0, "loop": 0.5, "peak": 0.3, "rate": 22050, "layers": [
		{"w": "noise", "lp": 900.0, "lpm": [0.25, 400.0], "hp": 150.0, "vol": 0.15},
		{"w": "sine", "f": 2600.0, "f1": 3600.0, "len": 0.07, "atk": 0.01, "dec": 20.0, "vib": [30.0, 1.0], "vol": 0.5, "every": 0.55, "jit": 0.9, "fr": [0.8, 1.3], "vr": [0.3, 1.0]},
		{"w": "sine", "f": 3400.0, "f1": 2500.0, "len": 0.05, "dec": 25.0, "vol": 0.35, "every": 0.9, "jit": 1.0, "fr": [0.85, 1.2], "vr": [0.3, 1.0]}]},
	"heartbeat": {"len": 1.0, "loop": 0.0, "peak": 0.5, "rate": 22050, "layers": [
		{"w": "sine", "f": 60.0, "f1": 40.0, "len": 0.12, "dec": 25.0, "vol": 1.0},
		{"w": "sine", "f": 55.0, "f1": 38.0, "at": 0.22, "len": 0.12, "dec": 25.0, "vol": 0.7}]},
}


# --- Playing ---------------------------------------------------------------------

## Register a game-specific sound: def = [seconds, start Hz, end Hz, volume, wave, noise mix]
## (wave: "square", "saw", "tri" or "sine"). Safe to call repeatedly. Replaces a built-in of the same name.
func add_sound(sound: String, def: Array) -> void:
	if not streams.has(sound) or _builtin.has(sound):
		_builtin.erase(sound)
		var key := "sfx_o_%s" % str(def)
		streams[sound] = ResCache.get_or_make(key, func() -> Resource: return _make(def[0], def[1], def[2], def[3], def[4], def[5]))


## Register a layered sound in the RECIPE FORMAT (see the header). Replaces any older sound of that name.
func add_recipe(sound: String, recipe: Dictionary) -> void:
	_custom[sound] = recipe
	streams.erase(sound)
	_builtin.erase(sound)


## Play a one-shot sound (built-in, DEFS, add_sound or add_recipe name). Unknown names are ignored.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var st := get_stream(sound)
	if st == null or voices.is_empty():
		return
	var p := voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	p.stream = st
	p.bus = bus_for(sound)
	p.volume_db = volume_db
	var jit := _jitter(sound)
	p.pitch_scale = maxf(0.01, pitch * randf_range(1.0 - jit, 1.0 + jit))
	p.play()


## Play a one-shot at a world position (3D panning and distance fade). In split-screen SubViewport
## setups (no 3D camera on the main viewport) it falls back to a flat sound faded by the distance to
## `listener` when set.
func play_at(sound: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var st := get_stream(sound)
	if st == null or not is_inside_tree():
		return
	if get_viewport().get_camera_3d() == null:
		var db := volume_db
		if listener != null and is_instance_valid(listener) and listener.is_inside_tree():
			var d := listener.global_position.distance_to(position)
			db -= 20.0 * log(maxf(1.0, d / 4.0)) / log(10.0)
		play(sound, db, pitch)
		return
	if voices_3d.is_empty():
		for i in VOICES_3D:
			var v := AudioStreamPlayer3D.new()
			v.unit_size = 4.0
			v.max_distance = 70.0
			v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			v.bus = "SFX"
			add_child(v)
			voices_3d.append(v)
	var p := voices_3d[next_voice_3d]
	next_voice_3d = (next_voice_3d + 1) % VOICES_3D
	p.stream = st
	p.bus = bus_for(sound)
	p.global_position = position
	p.volume_db = volume_db
	var jit := _jitter(sound)
	p.pitch_scale = maxf(0.01, pitch * randf_range(1.0 - jit, 1.0 + jit))
	p.play()


## The cached AudioStream for a sound name (synthesising it now if needed), or null if unknown.
func get_stream(sound: String) -> AudioStream:
	if streams.has(sound):
		var s: AudioStream = streams[sound]
		return s
	if DEFS.has(sound):
		var d: Array = DEFS[sound]
		add_sound(sound, d)
		var made: AudioStream = streams[sound]
		return made
	if _custom.has(sound):
		var rc: Dictionary = _custom[sound]
		var key := "sfx_c_%s_%d" % [sound, str(rc).hash()]
		var cs: AudioStream = ResCache.get_or_make(key, func() -> Resource: return _bake(rc, sound))
		streams[sound] = cs
		return cs
	if RECIPES.has(sound):
		var r: Dictionary = RECIPES[sound]
		var bs: AudioStream = ResCache.get_or_make(_key(sound), func() -> Resource: return _bake(r, sound))
		streams[sound] = bs
		_builtin[sound] = true
		return bs
	return null


## Which bus a sound plays on: "UI" for ui_* and "type", otherwise "SFX".
static func bus_for(sound: String) -> String:
	return "UI" if sound.begins_with("ui_") or sound == "type" else "SFX"


## Every built-in one-shot name (old DEFS + layered recipes).
static func list_sounds() -> PackedStringArray:
	var out := PackedStringArray()
	for k in DEFS:
		out.append(str(k))
	for k in RECIPES:
		out.append(str(k))
	return out


## Every built-in loop name for play_loop().
static func list_loops() -> PackedStringArray:
	var out := PackedStringArray()
	for k in LOOPS:
		out.append(str(k))
	return out


## Pre-synthesise sounds and loops (names; empty = every built-in) so their first play has no hitch.
## background = true renders on a worker thread (they become ready a moment later).
func warm(names: Array = [], background: bool = false) -> void:
	var list: Array = names.duplicate()
	if list.is_empty():
		list.append_array(Array(list_sounds()))
		list.append_array(Array(list_loops()))
	if not background:
		for n in list:
			var s := str(n)
			if get_stream(s) == null:
				get_loop_stream(s)
		return
	if _bg_task >= 0:
		return  # one batch at a time; whatever is left synthesises on first use
	_bg_jobs.clear()
	for n in list:
		var s := str(n)
		var key := ""
		var def: Dictionary = {}
		if RECIPES.has(s):
			key = _key(s)
			def = RECIPES[s]
		elif LOOPS.has(s):
			key = _loop_key(s)
			def = LOOPS[s]
		if key != "" and not ResCache.has(key):
			_bg_jobs.append([key, def, s.hash()])
	if _bg_jobs.is_empty():
		return
	_bg_out.clear()
	_bg_out.resize(_bg_jobs.size())
	_bg_done = 0
	_bg_applied = 0
	_bg_task = WorkerThreadPool.add_task(_render_jobs)
	set_process(true)


func _render_jobs() -> void:
	for i in _bg_jobs.size():
		var job: Array = _bg_jobs[i]
		_bg_out[i] = render(job[1], int(job[2]))
		_bg_done = i + 1  # the main thread hands each sound over as soon as it is ready


## Hand finished background sounds to the cache as they come (not only when the whole batch is done:
## a big batch takes many seconds on the Frame, and every sound played meanwhile was synthesised again
## on the main thread, which hitched).
func _process(_delta: float) -> void:
	if _bg_task < 0:
		return
	var done := _bg_done
	var finished := WorkerThreadPool.is_task_completed(_bg_task)
	if finished:
		WorkerThreadPool.wait_for_task_completion(_bg_task)
		_bg_task = -1
		done = _bg_jobs.size()
	for i in range(_bg_applied, mini(done, _bg_jobs.size())):
		var job: Array = _bg_jobs[i]
		var def: Dictionary = job[1]
		var buf: PackedFloat32Array = _bg_out[i]
		if not ResCache.has(str(job[0])):
			ResCache.put(str(job[0]), to_wav(buf, int(def.get("rate", 32000)), def.has("loop")))
	_bg_applied = maxi(_bg_applied, done)
	if finished:
		_bg_jobs.clear()
		_bg_out.clear()
		_bg_done = 0
		_bg_applied = 0
		set_process(false)


# --- Loops -------------------------------------------------------------------------

## Register a custom loop in the RECIPE FORMAT (set "loop": crossfade seconds; layers without "len" last
## the whole loop; use whole-number cycles per loop for steady tones so the seam is invisible).
func add_loop(sound: String, recipe: Dictionary) -> void:
	var r := recipe.duplicate()
	if not r.has("loop"):
		r["loop"] = 0.25
	_custom_loops[sound] = r


## The cached looping AudioStreamWAV for a loop name, or null if unknown.
func get_loop_stream(sound: String) -> AudioStream:
	if _custom_loops.has(sound):
		var rc: Dictionary = _custom_loops[sound]
		var ck := "sfx_cl_%s_%d" % [sound, str(rc).hash()]
		var cs: AudioStream = ResCache.get_or_make(ck, func() -> Resource: return _bake(rc, sound))
		return cs
	if LOOPS.has(sound):
		var r: Dictionary = LOOPS[sound]
		var s: AudioStream = ResCache.get_or_make(_loop_key(sound), func() -> Resource: return _bake(r, sound))
		return s
	return null


## Start (or fade back up) a seamless loop. Calling it again just retargets the volume.
func play_loop(sound: String, volume_db: float = 0.0, fade: float = 0.3) -> void:
	var st := get_loop_stream(sound)
	if st == null:
		push_warning("sfx: unknown loop '%s'" % sound)
		return
	var p: AudioStreamPlayer = null
	if loops.has(sound):
		var existing: Object = loops[sound]
		if is_instance_valid(existing):
			p = existing as AudioStreamPlayer
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = "Loop_" + sound
		p.stream = st
		p.bus = "SFX"
		p.volume_db = -60.0 if fade > 0.0 else volume_db
		add_child(p)
		loops[sound] = p
		p.play()
	elif not p.playing:
		p.play()
	_fade_player(p, volume_db, fade, false)


## Fade a loop out and remove it.
func stop_loop(sound: String, fade: float = 0.5) -> void:
	if not loops.has(sound):
		return
	var obj: Object = loops[sound]
	loops.erase(sound)
	if is_instance_valid(obj):
		_fade_player(obj as AudioStreamPlayer, -60.0, fade, true)


## Fade every loop out.
func stop_all_loops(fade: float = 0.5) -> void:
	for k in loops.keys():
		stop_loop(str(k), fade)


## True while a loop is playing (and not fading out).
func is_looping(sound: String) -> bool:
	return loops.has(sound)


## Change a running loop's volume (smoothly over `fade` seconds).
func set_loop_volume(sound: String, volume_db: float, fade: float = 0.2) -> void:
	if loops.has(sound):
		var obj: Object = loops[sound]
		if is_instance_valid(obj):
			_fade_player(obj as AudioStreamPlayer, volume_db, fade, false)


## Change a running loop's pitch (e.g. an engine revving with speed).
func set_loop_pitch(sound: String, pitch: float) -> void:
	if loops.has(sound):
		var obj: Object = loops[sound]
		if is_instance_valid(obj):
			(obj as AudioStreamPlayer).pitch_scale = maxf(0.01, pitch)


## A positional loop attached to a 3D node (a kart's engine, a crackling campfire). Returns the player;
## it is freed with the node, or call stop_loop_at().
func play_loop_at(sound: String, parent: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var st := get_loop_stream(sound)
	if st == null or parent == null:
		return null
	var nm := "SfxLoop_" + sound
	var p := parent.get_node_or_null(nm) as AudioStreamPlayer3D
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.name = nm
		p.stream = st
		p.unit_size = 4.0
		p.max_distance = 60.0
		p.bus = "SFX"
		parent.add_child(p)
	p.volume_db = volume_db
	if not p.playing:
		p.play()
	return p


## Stop a positional loop started with play_loop_at().
func stop_loop_at(parent: Node3D, sound: String) -> void:
	if parent == null:
		return
	var p := parent.get_node_or_null("SfxLoop_" + sound)
	if p != null:
		p.queue_free()


func _fade_player(p: AudioStreamPlayer, to_db: float, fade: float, free_after: bool) -> void:
	if p.has_meta("fade_tw"):
		var old: Object = p.get_meta("fade_tw")
		if is_instance_valid(old):
			(old as Tween).kill()
	if fade <= 0.0:
		p.volume_db = to_db
		if free_after:
			p.queue_free()
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", to_db, fade).set_trans(Tween.TRANS_SINE)
	if free_after:
		tw.tween_callback(p.queue_free)
	p.set_meta("fade_tw", tw)


# --- Buses ---------------------------------------------------------------------------

## Make sure the "Music", "SFX" and "UI" buses exist (each sends to Master). Safe to call any time.
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")


## Set a bus volume as a linear gain (0 = silent, 1 = normal); mutes at 0.
static func set_bus_volume(bus: String, linear: float) -> void:
	ensure_buses()
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.0001)


## A bus volume as a linear gain (1 = normal).
static func get_bus_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


# --- Synthesis ------------------------------------------------------------------------

func _jitter(sound: String) -> float:
	if _builtin.has(sound) and RECIPES.has(sound):
		var r: Dictionary = RECIPES[sound]
		return float(r.get("jit", 0.03))
	if _custom.has(sound):
		var c: Dictionary = _custom[sound]
		return float(c.get("jit", 0.03))
	return 0.06  # the classic sounds (DEFS / add_sound): 0.94 .. 1.06


static func _key(sound: String) -> String:
	return "sfx_%s_%s" % [CACHE_VERSION, sound]


static func _loop_key(sound: String) -> String:
	return "sfx_loop_%s_%s" % [CACHE_VERSION, sound]


static func _bake(recipe: Dictionary, sound: String) -> AudioStreamWAV:
	return to_wav(render(recipe, sound.hash()), int(recipe.get("rate", 32000)), recipe.has("loop"))


## Render a recipe (RECIPE FORMAT) to mono samples in -1..1. Thread-safe (no scene access).
static func render(recipe: Dictionary, seed_value: int = 1) -> PackedFloat32Array:
	var rate := int(recipe.get("rate", 32000))
	var length := float(recipe.get("len", 0.5))
	var is_loop := recipe.has("loop")
	var xfade := float(recipe.get("loop", 0.0)) if is_loop else 0.0
	var total := length + xfade
	var n := maxi(16, int(total * rate))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layers: Array = recipe.get("layers", [])
	for layer in layers:
		var L: Dictionary = layer
		var at := float(L.get("at", 0.0))
		if L.has("every"):
			var every := maxf(0.003, float(L["every"]))
			var jit := float(L.get("jit", 0.0))
			var ev_len := float(L.get("len", 0.05))
			var until := float(L.get("until", total - ev_len))
			var fr: Array = L.get("fr", [1.0, 1.0])
			var vr: Array = L.get("vr", [1.0, 1.0])
			var grow := float(L.get("grow", 1.0))
			var g := 1.0
			var t := at
			while t < until:
				var fm := rng.randf_range(float(fr[0]), float(fr[1])) * g
				var vm := rng.randf_range(float(vr[0]), float(vr[1]))
				_voice(buf, rate, L, t, fm, vm, rng, is_loop, total)
				t += maxf(every * 0.1, every * (1.0 + jit * rng.randf_range(-1.0, 1.0)))
				g *= grow
		elif L.has("notes"):
			var notes: Array = L["notes"]
			var step := float(L.get("step", 0.08))
			for k in notes.size():
				_voice(buf, rate, L, at + k * step, pow(2.0, float(notes[k]) / 12.0), 1.0, rng, is_loop, total)
		else:
			_voice(buf, rate, L, at, 1.0, 1.0, rng, is_loop, total)
	if recipe.has("echo"):
		var e: Array = recipe["echo"]
		var d := maxi(1, int(float(e[0]) * rate))
		var fb := float(e[1])
		for i in range(d, n):
			buf[i] += buf[i - d] * fb
	var fade_in := float(recipe.get("fade_in", 0.0))
	var fade_out := float(recipe.get("fade_out", 0.0))
	if fade_in > 0.0 or fade_out > 0.0:
		var fi := maxi(1, int(fade_in * rate))
		var fo := maxi(1, int(fade_out * rate))
		for i in n:
			var g := 1.0
			if fade_in > 0.0 and i < fi:
				g = float(i) / fi
			if fade_out > 0.0 and i > n - fo:
				g *= float(n - i) / fo
			buf[i] *= g
	if is_loop:
		buf = _seam(buf, int(length * rate), int(xfade * rate))
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	if peak > 0.000001:
		var gain := float(recipe.get("peak", 0.6)) / peak
		for i in buf.size():
			buf[i] *= gain
	if not is_loop:
		var tail := mini(buf.size(), int(0.004 * rate))  # no click at the very end
		for i in tail:
			buf[buf.size() - 1 - i] *= float(i) / tail
	return buf


## Fold the crossfade tail over the head so the loop point is seamless (equal-power for noise beds).
static func _seam(buf: PackedFloat32Array, n: int, xn: int) -> PackedFloat32Array:
	var out := buf.slice(0, n)
	if xn <= 0:
		return out
	for i in mini(xn, buf.size() - n):
		var w := float(i) / xn
		out[i] = buf[i] * sqrt(w) + buf[n + i] * sqrt(1.0 - w)
	return out


## One voice of a recipe, mixed into buf starting at t0 seconds (fmul / vmul scale pitch / volume).
static func _voice(buf: PackedFloat32Array, rate: int, L: Dictionary, t0: float, fmul: float, vmul: float,
		rng: RandomNumberGenerator, wrap: bool, whole: float) -> void:
	var wave := str(L.get("w", "sine"))
	var dur := float(L.get("len", whole - float(L.get("at", 0.0))))
	var count := int(dur * rate)
	if count <= 0:
		return
	var n := buf.size()
	var s0 := int(t0 * rate)
	var f0 := float(L.get("f", 440.0)) * fmul
	var f1 := float(L.get("f1", L.get("f", 440.0))) * fmul
	var lin := bool(L.get("lin", false))
	var vol := float(L.get("vol", 0.5)) * vmul
	var full := not L.has("len")  # loop beds: no attack / release so the seam stays flat
	var atk := maxf(float(L.get("atk", 0.0 if full else 0.003)), 1.0 / rate)
	var dec := float(L.get("dec", 0.0))
	var rel := minf(float(L.get("rel", 0.0 if full else 0.02)), dur * 0.5)
	var duty := float(L.get("duty", 0.5))
	var vib: Array = L.get("vib", [])
	var vib_r := float(vib[0]) if vib.size() > 1 else 0.0
	var vib_d := float(vib[1]) * 0.0578 if vib.size() > 1 else 0.0  # semitones -> frequency ratio
	var trem: Array = L.get("trem", [])
	var trem_r := float(trem[0]) if trem.size() > 1 else 0.0
	var trem_d := float(trem[1]) if trem.size() > 1 else 0.0
	var fm: Array = L.get("fm", [])
	var fm_ratio := float(fm[0]) if fm.size() > 2 else 0.0
	var fm_index := float(fm[1]) if fm.size() > 2 else 0.0
	var fm_dec := float(fm[2]) if fm.size() > 2 else 0.0
	var lp := float(L.get("lp", 0.0))
	var lp1 := float(L.get("lp1", lp))
	var lpm: Array = L.get("lpm", [])
	var lpm_r := float(lpm[0]) if lpm.size() > 1 else 0.0
	var lpm_d := float(lpm[1]) if lpm.size() > 1 else 0.0
	var hp := float(L.get("hp", 0.0))
	var hold := float(L.get("hold", 0.0))
	var hold_n := maxi(1, int(rate / hold)) if hold > 0.0 else 1
	var hp_a := 1.0 - exp(-TAU * hp / rate) if hp > 0.0 else 0.0
	var lp_state := 0.0
	var hp_state := 0.0
	var phase := 0.0
	var mphase := 0.0
	var held := 0.0
	var ratio := f1 / f0 if f0 > 0.0 else 1.0
	var is_noise := wave == "noise"
	var shape := 0  # 0 sine, 1 square, 2 saw, 3 tri
	match wave:
		"square":
			shape = 1
		"saw":
			shape = 2
		"tri":
			shape = 3
	var inv_rate := 1.0 / rate
	for i in count:
		var t := i * inv_rate
		var u := float(i) / count
		var s := 0.0
		if is_noise:
			if i % hold_n == 0:
				held = rng.randf() * 2.0 - 1.0
			s = held
		else:
			var f := lerpf(f0, f1, u) if lin else f0 * pow(ratio, u)
			if vib_r > 0.0:
				f *= 1.0 + sin(t * vib_r * TAU) * vib_d
			phase += f * inv_rate
			if phase >= 1.0:
				phase -= floorf(phase)
			if fm_ratio > 0.0:
				mphase += f * fm_ratio * inv_rate
				s = sin(phase * TAU + fm_index * exp(-fm_dec * t) * sin(mphase * TAU))
			elif shape == 0:
				s = sin(phase * TAU)
			elif shape == 1:
				s = 1.0 if phase < duty else -1.0
			elif shape == 2:
				s = phase * 2.0 - 1.0
			else:
				s = absf(phase * 4.0 - 2.0) - 1.0
		if lp > 0.0:
			var c := lerpf(lp, lp1, u)
			if lpm_r > 0.0:
				c = maxf(30.0, c + sin(t * lpm_r * TAU) * lpm_d)
			lp_state += (s - lp_state) * minf(1.0, TAU * c * inv_rate)
			s = lp_state
		if hp > 0.0:
			hp_state += (s - hp_state) * hp_a
			s -= hp_state
		var env := minf(1.0, t / atk)
		if dec > 0.0:
			env *= exp(-dec * t)
		if rel > 0.0:
			env *= minf(1.0, (dur - t) / rel)
		if trem_r > 0.0:
			env *= 1.0 - trem_d * (0.5 + 0.5 * sin(t * trem_r * TAU))
		var idx := s0 + i
		if idx >= n:
			if not wrap:
				break
			idx -= n
		buf[idx] += s * env * vol


## Samples (-1..1) to a 16-bit AudioStreamWAV, looping the whole buffer when `looped`.
static func to_wav(buf: PackedFloat32Array, rate: int, looped: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


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
