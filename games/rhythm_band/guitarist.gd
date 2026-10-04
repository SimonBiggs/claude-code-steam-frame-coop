extends Node
## A TV player (P2-P7): plays the 3-lane note highway on their own split-screen view.
## Lanes: X / A / B or D-pad left / down / right (keyboard: arrows; the TV machine's P2 also A S D
## or J K L). Y (or Up / W / I) sets off STAR POWER when the band's star meter is full.
## Everyone picks their own level in the SETLIST menu (left / right: EASY - NORMAL - ROCK, A: ready):
## EASY shows only the big on-beat notes and gives a wider timing window, ROCK adds extra notes.
## Each machine judges its own players against the song clock it hears, then tells the host (which
## owns the band's crowd meter, combo, star meter and score). Pressing with no note near is free.

const NO_KEYS := 99

var index := 1
var main
var color := Color.WHITE
var remote := false
var ghost := false
var vr := false
var fake_vr := false
var active := false
var joy := -1
var key_set := NO_KEYS  # 0: arrows (local P2), 1: arrows + A S D / J K L (TV machine P2)
var camera: Camera3D
var hud: Control
var hud_label: Label
var highway: Control
var pad_lost_t := -1.0

var level := 1  # 0 EASY, 1 NORMAL, 2 ROCK
var menu_ready := false  # SETLIST menu: this player is ready to rock
var judged := PackedByteArray()  # per note: 0 open, 1 perfect, 2 good, 3 missed, 4 skipped (other level / joined late)
var judged_serial := -1
var judged_level := -1
var next_idx := 0
var streak := 0
var hits := 0
var misses := 0
var perfects := 0
var miss_run := 0
var tour := {}
var lane_flash := PackedFloat32Array([0.0, 0.0, 0.0])
var judge_text := ""
var judge_t := 0.0
var judge_col := Color.WHITE


func _ready() -> void:
	reset_tour()


func set_active(on: bool) -> void:
	active = on
	if not on:
		menu_ready = false


func is_local() -> bool:
	return not remote and not ghost


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


## New song (or joined mid-song, or changed level): notes that already went by, and notes above your
## level, don't count against you.
func reset_for_song() -> void:
	var g = main.song
	judged = PackedByteArray()
	judged_serial = main.song_serial
	judged_level = level
	next_idx = 0
	streak = 0
	hits = 0
	misses = 0
	perfects = 0
	miss_run = 0
	if g == null:
		return
	judged.resize(g.g_t.size())
	var st: float = main.song_t
	for i in judged.size():
		if int(g.g_lvl[i]) > level or (float(g.g_t[i]) < st + 0.3 and main.state == "play"):
			judged[i] = 4


func reset_tour() -> void:
	tour = {"hits": 0, "misses": 0, "perfects": 0, "best_streak": 0, "stars": 0}


func key_hint(lane: int) -> String:
	if key_set == 0:
		return ["Left", "Down", "Right"][lane]
	if key_set == 1:
		return ["Left / A / J", "Down / S / K", "Right / D / L"][lane]
	return ""


func _input(event: InputEvent) -> void:
	if not active or not is_local() or get_tree().paused:
		return
	var lane := _lane_for(event)
	var up := _up_for(event)
	if main.state == "menu":
		if lane == 0:
			set_level(level - 1)
		elif lane == 2 or up:
			set_level((level + 1) % 3 if up else level + 1)
		elif lane == 1:
			set_ready(not menu_ready)
		return
	if up:
		main.request_star(self)
	if lane >= 0:
		press(lane)


func set_level(l: int) -> void:
	l = clampi(l, 0, 2)
	if l == level:
		return
	level = l
	main.inst.chime(0.8 + 0.25 * l)
	main.player_level_changed(self)


func set_ready(r: bool) -> void:
	menu_ready = r
	main.inst.click(r)
	main.player_ready_changed(self)


func _lane_for(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		var kc := k.physical_keycode
		if key_set == 0 or key_set == 1:
			if kc == KEY_LEFT:
				return 0
			if kc == KEY_DOWN:
				return 1
			if kc == KEY_RIGHT:
				return 2
		if key_set == 1:
			if kc == KEY_A or kc == KEY_J:
				return 0
			if kc == KEY_S or kc == KEY_K:
				return 1
			if kc == KEY_D or kc == KEY_L:
				return 2
	var b := event as InputEventJoypadButton
	if b and b.pressed and joy >= 0 and b.device == joy:
		match b.button_index:
			JOY_BUTTON_X, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
				return 0
			JOY_BUTTON_A, JOY_BUTTON_DPAD_DOWN:
				return 1
			JOY_BUTTON_B, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
				return 2
	return -1


## Y / D-pad up (keyboard: Up, or W / I on the TV machine): STAR POWER (in the menu: next level).
func _up_for(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		var kc := k.physical_keycode
		if (key_set == 0 or key_set == 1) and kc == KEY_UP:
			return true
		if key_set == 1 and (kc == KEY_W or kc == KEY_I):
			return true
	var b := event as InputEventJoypadButton
	if b and b.pressed and joy >= 0 and b.device == joy:
		return b.button_index == JOY_BUTTON_Y or b.button_index == JOY_BUTTON_DPAD_UP
	return false


## A lane button: hit the nearest open note in that lane inside the timing window.
func press(lane: int) -> void:
	lane_flash[lane] = 1.0
	var g = main.song
	if main.state != "play" or g == null:
		main.free_strum(self, lane)
		return
	if judged_serial != main.song_serial or judged.size() != g.g_t.size() or judged_level != level:
		reset_for_song()
	var st: float = main.song_t
	var win: Vector2 = main.window(level)
	var good: float = win.y
	var best := -1
	var bdt := 99.0
	var i := maxi(0, next_idx - 3)
	var n: int = g.g_t.size()
	while i < n:
		var t: float = g.g_t[i]
		if t > st + good:
			break
		if judged[i] == 0 and int(g.g_lane[i]) == lane:
			var dt := absf(t - st)
			if dt <= good and dt < bdt:
				bdt = dt
				best = i
		i += 1
	if best < 0:
		main.free_strum(self, lane)
		return
	var q := 0 if bdt <= win.x else 1
	judged[best] = q + 1
	record(q, g.g_star[best] == 1)
	main.guitar_result(self, best, q)


func _process(delta: float) -> void:
	for l in 3:
		lane_flash[l] = maxf(0.0, lane_flash[l] - delta * 5.0)
	judge_t = maxf(0.0, judge_t - delta)
	var g = main.song
	if not active or not is_local() or main.state != "play" or g == null:
		return
	if judged_serial != main.song_serial or judged.size() != g.g_t.size() or judged_level != level:
		reset_for_song()
	var win: Vector2 = main.window(level)
	var late: float = main.song_t - win.y - 0.02
	var n: int = g.g_t.size()
	while next_idx < n and float(g.g_t[next_idx]) < late:
		if judged[next_idx] == 0:
			judged[next_idx] = 3
			record(2)
			main.guitar_result(self, next_idx, 2)
		next_idx += 1


func record(q: int, star: bool = false) -> void:
	if q < 2:
		hits += 1
		streak += 1
		miss_run = 0
		tour["hits"] = int(tour["hits"]) + 1
		if q == 0:
			perfects += 1
			tour["perfects"] = int(tour["perfects"]) + 1
		if star:
			tour["stars"] = int(tour["stars"]) + 1
		tour["best_streak"] = maxi(int(tour["best_streak"]), streak)
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.15, 0.35, 0.05)
	else:
		misses += 1
		streak = 0
		miss_run += 1
		tour["misses"] = int(tour["misses"]) + 1
	if is_local():
		judge_text = ["PERFECT!", "GOOD", "MISS"][q]
		judge_col = [Color(1.0, 0.9, 0.3), Color(0.5, 1.0, 0.6), Color(1.0, 0.45, 0.45)][q]
		if star and q < 2:
			judge_text = "STAR!"
			judge_col = Color(1.0, 0.82, 0.25)
		judge_t = 0.8


## Continue button on the end screens: A (or Enter / Space on the keyboard player).
func action_pressed() -> bool:
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set != NO_KEYS and Input.is_physical_key_pressed(KEY_SPACE)
