extends Node
## VR view watch (a service, core/services.gd): in fake-VR bot runs (BOT_VR=1, every VR bot) it runs
## core/vr_view_check.gd every 0.5 s and reports each new problem once as "SCRIPT ERROR: BOT ASSERT FAILED: VR view: ..." (fails the
## bot's own BOT RESULT, tools/multibot.ts and dev.bots). A problem has to last 3 s (cards fade in, glide into place, a blink teleport);
## panels drawn over each other only SHORT_S (a 2.5 s NIGHT banner over a story card is gone before 3 s, but the
## player still couldn't read either: Ghost Lantern 2026-11-11). Does nothing
## without BOT_VR, so real headsets and flat machines never pay for it. VR_VIEW_WARN=1 prints "VR VIEW: ..." instead.

const VrViewCheck := preload("res://core/vr_view_check.gd")

var t := 0.0
var seen := {}  # problem -> first seen (s)
var told := {}
var on := OS.has_environment("BOT_VR")
var clock := 0.0
const HOLD_S := 3.0
const SHORT_S := 1.0


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
			seen.erase(k)


## How long a problem may last before it fails the bot.
static func hold(p: String) -> float:
	# (a card gliding clear of a pick orb that just popped up keeps the long hold: UiKit.vr_dodge moves it in time)
	return SHORT_S if p.contains(": drawn over ") and not p.contains("drawn over the pick") else HOLD_S


## Numbers change frame to frame (distances): the problem's kind + node name is the key.
func _key(p: String) -> String:
	var r := RegEx.create_from_string("[-0-9.]+ ?(m|deg)?")
	return r.sub(p, "#", true)
