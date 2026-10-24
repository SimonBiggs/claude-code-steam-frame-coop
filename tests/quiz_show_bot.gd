extends Node
## Headless bot for games/quiz_show. Plays a short show (level vote, one question of each round,
## the final), checks the results, starts a second show. Also validates the whole question bank.
## BOT_PLAYERS=n: TV players with virtual pads (default 2). BOT_VR=1 (local / host): a fake VR player
## slaps the desk buttons. DUO_FLAT_HOST=1 on the host: one bot pad plays slot 0 there.
## Local:      godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/quiz_show_bot.tscn
## Networked:  DUO_PORT=7995 DUO_HOST=1 ... & DUO_PORT=7995 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const QuestionBank := preload("res://games/quiz_show/question_bank.gd")
const Pictures := preload("res://games/quiz_show/pictures.gd")

var kit: BotKit
var main: Node
var want := 2
var answered_q := {}  # slot -> question key answered
var answer_at := {}  # slot -> seconds to wait before answering this question
var vr_target := -1
var saw_results := 0
var saw_kinds := {}
var saw_picture := false
var vr_answers := 0
var last_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/quiz_show/main.tscn").instantiate()
	main.set("show_length", "short")
	main.set("reveal_time", 1.8)
	main.set("intro_time", 1.6)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	if not client and not host:
		_validate_bank()
	kit.at(3.0 if client else 1.0, "%d TV players press A on their pads" % want, _join)
	kit.every(2.0, _report)
	kit.every(0.25, _continue_results)
	if host:  # check while the TV machine is still connected (it finishes at 48 s, ~51 s here), then finish
		kit.at(45.0, "host checks", _checks)
		kit.at(52.0, "finish", kit.finish)
	else:
		kit.at(48.0 if client else 52.0, "finish", func() -> void:
			_checks()
			kit.finish())


func _validate_bank() -> void:
	var r: Dictionary = QuestionBank.validate()
	kit.info("bank: %d questions, %d true/false, %d pictures" % [int(r.mc), int(r.tf), int(r.pictures)])
	var errors: Array = r.errors
	for e in errors:
		kit.info("bank error: %s" % e)
	kit.assert_true(errors.is_empty(), "the question bank validates")
	var empty := 0
	for it in Pictures.ITEMS:
		var n := Pictures.build(String(it[0]))
		if n.get_child_count() == 0:
			empty += 1
			kit.info("picture %s builds nothing" % it[0])
		n.free()
	kit.assert_eq(empty, 0, "every picture builds")


func _join() -> void:
	if main.net.mode == "host":
		if main.flat_host:
			kit.join_bot(main.party)
		return
	for i in want:
		kit.join_bot(main.party)


func _continue_results() -> String:
	if main.results_showing():
		if saw_results == 0 or not bool(get_meta("in_results", false)):
			saw_results += 1
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		set_meta("in_results", true)
		var slots: Array[int] = main.party.local_slots()
		if not slots.is_empty():
			kit.slot_press(main.party, slots[0], "accept")
		if main.vr_rig != null:
			kit.vr_trigger(main.vr_rig, 1.0 if Engine.get_process_frames() % 20 < 10 else 0.0)
	else:
		set_meta("in_results", false)
	return ""


func _process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	var q: Dictionary = main.net.state_get("q", {})
	var key := "%s:%d:%d" % [String(main.net.state_get("phase", "")), int(q.get("id", 0)), int(main.net.state_get("qn", 0))]
	if key != last_key:
		last_key = key
		answer_at.clear()
		vr_target = -1
	if String(main.net.state_get("phase", "")) != "ask":
		if main.vr_rig != null:
			kit.vr_idle(main.vr_rig)
		return
	var kind := String(q.get("kind", ""))
	saw_kinds[kind] = true
	if kind == "picture" and main.pic_root.visible and main.pic_root.get_child_count() > 0:
		saw_picture = true
	var n: int = (q.get("answers", []) as Array).size()
	for slot in main.party.local_slots():
		if not answer_at.has(slot):
			answer_at[slot] = 0.4 + randf() * 0.8
		answer_at[slot] = float(answer_at[slot]) - delta
		if float(answer_at[slot]) <= 0.0 and answered_q.get(slot, "") != key:
			answered_q[slot] = key
			kit.slot_press(main.party, slot, ["a", "b", "x", "y"][_choice(n)])
	if main.vr_rig != null:
		_drive_vr(delta, n)


## Mostly right on the host (it knows the answer), random on a TV machine.
func _choice(n: int) -> int:
	var c: int = main.current_correct() if main.net.mode != "client" else -1
	if c >= 0 and randf() < 0.7:
		return c
	return randi() % maxi(n, 1)


## Fake VR: reach for one desk button with the right glove.
func _drive_vr(delta: float, n: int) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	var locked: Dictionary = main.net.state_get("locked", {})
	if locked.has(0):
		kit.vr_idle(rig)
		return
	if vr_target < 0:
		vr_target = _choice(n)
	var b: Node3D = main.desk_buttons[vr_target]
	if kit.vr_reach(rig, 1, b.global_position + Vector3.UP * 0.03, 2.5, delta):
		vr_answers += 1


func _report() -> String:
	return "BOT %s: contestants %s, phase %s, round %s, scores %s" % [main.net.mode, str(main.contestants()),
		String(main.net.state_get("phase", "")), String(main.net.state_get("round", "")), str(main.net.state_get("scores", {}))]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_true(main.party.local_slots().size() == want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(main.party.player_count(), want + host_p, "%s: all players are seated" % mode)
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.contestants().has(0), "flat host: slot 0 plays here")
	for k in ["level", "warmup", "picture", "lightning", "final"]:
		kit.assert_true(saw_kinds.has(k), "%s: saw a %s question" % [mode, k])
	kit.assert_true(saw_picture, "%s: the picture round shows a picture" % mode)
	kit.assert_true(saw_results >= 1, "%s: the show ended with results" % mode)
	kit.assert_true(int(main.net.state_get("show", 0)) >= 2, "%s: a second show started" % mode)
	if main.vr_rig != null:
		kit.assert_true(vr_answers > 0, "the fake VR player answered on the desk")
	var scores: Dictionary = main.net.state_get("scores", {})
	kit.assert_true(int(main.net.state_get("best", 0)) > 0 or not scores.is_empty(), "%s: someone scored" % mode)
