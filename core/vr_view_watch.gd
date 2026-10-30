extends Node
## VR view watch (a service, core/services.gd): in fake-VR bot runs (BOT_VR=1, every VR bot) it runs
## core/vr_view_check.gd once a second and reports each new problem once as "BOT ASSERT FAILED: VR view: ..." (fails the
## bot in tools/multibot.ts / dev.bots). A problem has to last 1.5 s (cards fade in and glide into place). Does nothing
## without BOT_VR, so real headsets and flat machines never pay for it. VR_VIEW_WARN=1 prints "VR VIEW: ..." instead.

const VrViewCheck := preload("res://core/vr_view_check.gd")

var t := 0.0
var seen := {}  # problem -> first seen (s)
var told := {}
var on := OS.has_environment("BOT_VR")
var clock := 0.0


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
		elif clock - float(seen[key]) >= 1.5 and not told.has(key):
			told[key] = true
			if OS.has_environment("VR_VIEW_WARN"):
				print("VR VIEW: %s" % p)
			else:
				print("BOT ASSERT FAILED: VR view: %s (core/vr_view_check.gd)" % p)
	for k in seen.keys():
		if not now.has(k):
			seen.erase(k)


## Numbers change frame to frame (distances): the problem's kind + node name is the key.
func _key(p: String) -> String:
	var r := RegEx.create_from_string("[-0-9.]+ ?(m|deg)?")
	return r.sub(p, "#", true)
