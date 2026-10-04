extends Node
## Headless bot for Kart Race. Every kart this machine drives follows the track on autopilot,
## picks up item boxes, uses its items and its boost; then the bot presses "continue" on the results.
## BOT_PLAYERS=N: TV-side karts (local split screen: P1 + up to 5 more; TV machine: up to 6).
## BOT_FAKE_VR=1 (local): P1 is driven through the VR cockpit with fake hands on the steering wheel
## (both hands, then one hand gripping at an odd "2 o'clock" spot, then hands off), right trigger and
## A, to test the wheel maths without a headset: steering must follow the hands relative to the grip,
## never a rest pose. It also checks the VR comfort limits (no speed jolts, gentle seat height).
## Every kart also tries a rocket start, drifts (CPU / bot auto-drift), and uses the new items; the
## run goes through a whole 3-race cup (BOT_CUP=1 forces it in a short test) to the trophies.
## BOT_FULL=1: full 3-lap races (default: short races so the test finishes in time).
## Local mode also joins one kart by pressing A on a fake controller, and checks Start does NOT join.
## SIMPLE_MODE (main.gd): the run starts with the practice rings (the autopilot drives through them),
## then races on the next track each time; checks the boxes stay away in race 1 (only instant ZOOM /
## STAR effects later), no drift turbos and no rocket starts, and that a ghost-hands demo appears on
## the VR wheel when the fake hands let go.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var join_time := 0.0
var report_t := 0.0
var cont_t := 0.0
var races := 0
var was_results := false
var fake_err := 0.0
var fake_n := 0
var a_t := 0.0
var hand_ang := 0.0  # where the fake hands are on the rim (relative to the grip)
var phase_was := ""
var max_dv := 0.0  # biggest per-second speed change of the VR kart
var max_dy := 0.0  # biggest per-second seat height change
var last_speed := 0.0
var last_seat_y := 0.0
var turbos := 0
var rockets := 0
var items_seen := {}
var cups_done := 0
var practice_seen := false
var practice_rings := 0
var boxes_in_race1 := false
var ghost_seen := false
var max_vr_lines := 0  # simple mode: the most lines of text on any VR label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/kart_race/main.tscn").instantiate()
	add_child(main)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _want_players() -> int:
	return int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 2


func _process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not has_meta("fast") and mode != "client":
		set_meta("fast", true)
		if not OS.has_environment("BOT_FULL"):
			var frac := 0.45 if (mode == "host" or _want_players() >= 4) else 1.0
			if OS.has_environment("BOT_CUP"):
				frac = 0.3
			main.debug_fast(1, frac)
			print("BOT: short races: 1 lap, finish at %.0f%%" % (frac * 100.0))
			if mode == "local" and not main.SIMPLE_MODE:
				main._start_race(main.cup_track())
	if OS.has_environment("BOT_FAKE_VR") and mode == "local" and main.cockpit == null:
		main.debug_fake_vr()
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
	if mode == "local" and joined and t > join_time + 0.3 and not has_meta("start_checked"):
		set_meta("start_checked", true)
		print("BOT: Start on a new controller: joined=%s, menu opened=%s" % [main.joy_owner.has(FAKE_PAD + 1), get_tree().paused])
		if get_tree().paused:
			_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # close the menu again
	if get_tree().paused:
		return
	if has_meta("pad_join") and t > join_time + 0.5:
		remove_meta("pad_join")
		_pad_press(FAKE_PAD, JOY_BUTTON_A)
	if mode == "local" and joined and t > join_time + 0.8 and not has_meta("pad_checked"):
		set_meta("pad_checked", true)
		print("BOT: fake controller %d drives P%d" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1])
	for k in main.players:
		if k.active and k.is_sim() and k.cockpit == null:
			k.bot = true
	if main.cockpit != null and main.cockpit.fake:
		_drive_fake_vr(delta)
	for k in main.karts:
		if k.active and k.item != "":
			items_seen[k.item] = true
	if main.SIMPLE_MODE:
		_simple_checks()
	var res: bool = main.state == "results"
	if res and not was_results:
		races += 1
		if main.cup_race >= 2 and not main.SIMPLE_MODE:
			cups_done += 1
			print("BOT %s: CUP FINISHED (%s), trophies for %s" % [mode, main.cup_info()["name"], str(main.trophy_karts)])
		var uses := 0
		for k in main.karts:
			uses += int(k.get_meta("uses", 0))
		print("BOT %s: RACE %d FINISHED on %s (items used %d)" % [mode, races, main.track.track_name(main.track_i), uses])
	was_results = res
	if res and main.state_t > 2.5:
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var cap := 5 if mode == "local" else 6
	var target := clampi(_want_players(), 1, cap)
	var extra := target - 1
	print("BOT: %s mode, joining %d extra karts" % [mode, extra])
	if mode == "local":
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


## Put the fake hands on the wheel where a person would, and turn them the way the autopilot wants.
## The wheel follows the hands relative to how they grabbed it, so the bot moves its hands from where
## they are (like a person) rather than to absolute positions.
func _drive_fake_vr(delta: float) -> void:
	var c = main.cockpit
	var k = c.kart
	k.auto_inputs(delta)
	var want_steer: float = k.steer
	var want_ang: float = -want_steer * c.FULL_LOCK
	var b: Basis = c.wheel_basis()
	var up: Vector3 = b * Vector3(0, 0, -1)
	var ctr: Vector3 = c.wheel_center()
	var r: float = c.WHEEL_R
	var cyc := fmod(t, 14.0)
	var phase := "both" if cyc < 8.0 else ("one" if cyc < 12.5 else "off")
	if phase != phase_was:
		phase_was = phase
		hand_ang = c.wheel_angle  # regrip where the wheel is now
	# Turn the hands towards the wanted wheel angle at a human-ish speed.
	hand_ang = move_toward(hand_ang, want_ang, 4.0 * delta)
	var wob := sin(t * 7.0) * 0.008
	var lap := ctr + Vector3(-0.4, -0.5, 0.3)  # resting on the lap: off the wheel
	match phase:
		"both":
			c.fake_r = ctr + b.x * (r * cos(hand_ang) + wob) + up * (r * sin(hand_ang))
			c.fake_l = ctr + b.x * (r * cos(hand_ang + PI)) + up * (r * sin(hand_ang + PI) + wob)
		"one":
			# One hand only, gripping near 2 o'clock: must NOT steer by itself.
			var a2 := hand_ang + 0.6
			c.fake_r = ctr + b.x * (r * cos(a2) + wob) + up * (r * sin(a2))
			c.fake_l = lap
		_:
			c.fake_r = lap + Vector3(0.8, 0, 0)
			c.fake_l = lap
	c.fake_trigger = 0.0 if k.reverse_t > 0.0 else 1.0
	c.fake_stick = Vector2(0, -1) if k.reverse_t > 0.0 else Vector2.ZERO
	if phase == "off":
		c.fake_stick.x = clampf(want_steer, -1.0, 1.0)  # hands off: the left stick steers
	if main.state == "countdown":
		c.fake_trigger = 1.0 if main.lights >= 3 else 0.0  # rocket start timing
	a_t += delta
	c.fake_a = (k.item != "" or k.charge >= 1.0) and fmod(a_t, 0.5) < 0.1 and a_t > 1.0
	if main.state == "race" and phase != "off":
		fake_err += absf(-c.wheel_angle / c.FULL_LOCK - want_steer)
		fake_n += 1
	# Comfort checks: speed and seat height must change smoothly.
	if main.state == "race" and delta > 0.0:
		max_dv = maxf(max_dv, absf(k.speed - last_speed) / delta)
		var sy: float = c.seat.global_position.y
		max_dy = maxf(max_dy, absf(sy - last_seat_y) / delta)
	last_speed = k.speed
	last_seat_y = c.seat.global_position.y


func _simple_checks() -> void:
	if main.state == "wait" and main.practice_gate >= 0:
		practice_seen = true
		practice_rings = maxi(practice_rings, main.practice_gate)
	if main.state == "race" and main.round_n == 1 and main.track.boxes_on:
		boxes_in_race1 = true
	var c = main.cockpit
	if c != null and c.ghost_l != null and c.ghost_l.visible:
		ghost_seen = true
	if c != null:
		for l in [c.panel_l, c.panel_r, c.panel_hint, main.vr_center]:
			if l != null and l.visible and str(l.text) != "":
				max_vr_lines = maxi(max_vr_lines, str(l.text).split("\n").size())


func _exit_tree() -> void:
	if main == null:
		return
	if main.SIMPLE_MODE:
		print("BOT SIMPLE: mode=%s practice_seen=%s rings=%d boxes_in_race1=%s box_effects=%s ghost_hands=%s max_vr_lines=%d" % [
			main.net.mode, practice_seen, practice_rings, boxes_in_race1, ",".join(PackedStringArray(main.items_given.keys())),
			ghost_seen, max_vr_lines])
	print("BOT SUMMARY: mode=%s races=%d cups=%d items_seen=%s turbos=%d fake_vr_err=%.3f max_dv=%.1f max_seat_dy=%.1f" % [
		main.net.mode, races, cups_done, ",".join(PackedStringArray(items_seen.keys())), _turbos(),
		fake_err / maxf(1.0, float(fake_n)), max_dv, max_dy])


func _turbos() -> int:
	var n := 0
	for k in main.karts:
		n += k.st_turbo
	return n


func _report(mode: String) -> void:
	var act: Array[String] = []
	for k in main.karts:
		if k.active:
			act.append("%s:%s %.0fm%s%s" % [k.kart_name, main.ordinal(k.place), k.total, " " + str(k.item) if k.item != "" else "",
				" FIN" if k.finished else ""])
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var synced := 0
	for p in main.players:
		if p.remote and p.active and p.net_started:
			synced += 1
	var extra := ""
	if main.cockpit != null and main.cockpit.fake and fake_n > 0:
		extra = " fakeVR(steer err %.2f, held L=%s R=%s grip=%s, max dv %.1f m/s/s, max seat dy %.1f m/s)" % [fake_err / fake_n,
			main.cockpit.held_l, main.cockpit.held_r, main.cockpit.grip, max_dv, max_dy]
	var turbo := 0
	for k in main.karts:
		turbo += k.st_turbo
	extra += " cup=%s r%d pts=%s turbos=%d items_seen=%s lights=%d" % [main.cup_info()["name"], main.cup_race + 1,
		str(main.cup_pts), turbo, ",".join(PackedStringArray(items_seen.keys())), main.lights]
	print("BOT %s t=%.0f race=%d state=%s race_t=%.0f track=%s views=%d remote_synced=%d bananas=%d races_done=%d%s [%s]" % [
		mode, t, main.round_n, main.state, main.race_t, main.track.track_name(main.track_i), views, synced,
		main.bananas.size(), races, extra, ", ".join(act)])
