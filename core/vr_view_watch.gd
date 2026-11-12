extends Node
## VR view watch (a service, core/services.gd): in fake-VR bot runs (BOT_VR=1, every VR bot) it runs
## core/vr_view_check.gd every 0.5 s and reports each new problem once as "SCRIPT ERROR: BOT ASSERT FAILED: VR view: ..." (fails the
## bot's own BOT RESULT, tools/multibot.ts and dev.bots). A problem has to last 3 s (cards fade in, glide into place, a blink teleport);
## panels drawn over each other only SHORT_S (a 2.5 s NIGHT banner over a story card is gone before 3 s, but the
## player still couldn't read either: Ghost Lantern 2026-11-11), a panel over a pick PICK_CLEAR_S. Does nothing
## without BOT_VR, so real headsets and flat machines never pay for it. VR_VIEW_WARN=1 prints "VR VIEW: ..." instead.
## VR_VIEW_TRACE=1 prints every problem as it starts and how long it lasted when it ends (any length, for tuning).

const VrViewCheck := preload("res://core/vr_view_check.gd")

var t := 0.0
var seen := {}  # problem -> first seen (s)
var told := {}
var on := OS.has_environment("BOT_VR")
var clock := 0.0
const HOLD_S := 3.0
const SHORT_S := 1.0
## A card over a pick orb gets this long to glide clear (UiKit.vr_dodge + vr_follow); tests/vr_view_check_test.gd
## holds the shared layer to it.
const PICK_CLEAR_S := 1.0


func _process(delta: float) -> void:
	if not on:
		return
	clock += delta
	t += delta
	if t < 0.5:
		return
	t = 0.0
	var now := {}
	for p in VrViewCheck.problems(get_tree().root):
		var key := _key(p)
		now[key] = true
		if not seen.has(key):
			seen[key] = clock
			if OS.has_environment("VR_VIEW_TRACE"):
				print("VR VIEW TRACE: %.2f s new: %s" % [clock, p])
		elif clock - float(seen[key]) >= hold(p) and not told.has(key):
			told[key] = true
			if OS.has_environment("VR_VIEW_WARN"):
				print("VR VIEW: %s" % p)
			else:
				# SCRIPT ERROR + a count the bot's own verdict adds (tests/bot_kit.gd finish): a VR view problem used to
				# print here while the bot still said "BOT RESULT: PASS", so a landing's solo-VR run missed it
				# (2026-11-12: Roller Coaster's head at 28.8 m).
				printerr("SCRIPT ERROR: BOT ASSERT FAILED: VR view: %s (core/vr_view_check.gd)" % p)
				Engine.set_meta("vr_view_failures", int(Engine.get_meta("vr_view_failures", 0)) + 1)
	for k in seen.keys():
		if not now.has(k):
			if OS.has_environment("VR_VIEW_TRACE"):
				print("VR VIEW TRACE: %.2f s gone after %.2f s: %s" % [clock, clock - float(seen[k]), k])
			seen.erase(k)


## How long a problem may last before it fails the bot.
static func hold(p: String) -> float:
	# A card over a pick: UiKit.vr_spot / vr_dodge / vr_glide clear it within ~0.7 s of the picks coming (a fresh spot
	# the moment they change, a quick glide). It had the 3 s hold "to glide clear in time", so Nova's card over Duo
	# Arena's middle orb for 2.6 s never failed a bot (2026-11-12): a glide that takes longer is itself the bug.
	if p.contains(": drawn over the pick "):
		return PICK_CLEAR_S
	# A pick hidden behind scenery: bots pick within a few seconds, so a 3 s hold never saw it (Rhythm Band's HARD behind
	# the green cymbal, 2026-11-12); the orbs' pop-in is over well within SHORT_S.
	if p.contains(" of the pick ") and p.contains(": hidden behind "):
		return SHORT_S
	return SHORT_S if p.contains(": drawn over ") else HOLD_S


## Numbers change frame to frame (distances): the problem's kind + node name is the key.
func _key(p: String) -> String:
	var r := RegEx.create_from_string("[-0-9.]+ ?(m|deg)?")
	return r.sub(p.split(" [card ")[0], "#", true)
