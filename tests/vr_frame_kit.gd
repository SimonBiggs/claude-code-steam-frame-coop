extends SceneTree
## VR FRAME: a game in fake VR (BOT_VR=1, its own bot playing) must not waste work every frame. 2026-11-19 on the
## Steam Frame (90 Hz = 11.1 ms a frame for everything): Sky Bots ran ~22 fps, Rhythm Band 6-7 fps, the arcade hub
## 7-11 fps (its still pictures redrew every frame). Godot's process-time readout swings 5-190 ms on the shared test
## threads headless, so this counts the waste instead, over SAMPLE_FRAMES frames once the bot is WARM_S into play:
##  - canvas items redrawing a frame (`draw` signals): a 2D picture / HUD / SubViewport label redrawing for nothing
##    re-triangulates its polygons every frame;
##  - nodes created a frame (`node_added`): per-frame spawns / rebuilt meshes, labels, shapes;
##  - nodes running _process / _physics_process (most at any sample);
##  - 2D-only SubViewports (pictures on pick orbs / VR cards / signs) rendered every frame instead of when they change
##    (StoryCard.redraw_only): each is a render pass the headset pays for at 90 Hz.
## Each game's test (tests/<game>_vr_frame_test.gd) extends this with its own budgets: set GAME + the MAX_* vars in
## _setup(). The worst offenders (by script / node name) are printed so the cause is one look away.
##   godot-test --headless --path . -s res://tests/<game>_vr_frame_test.gd   -> VR FRAME <game>: PASS/FAIL
##   Probe any game: VR_FRAME_GAME=<id> [VR_FRAME_WARM=secs] godot-test --headless --path . -s res://tests/vr_frame_kit.gd

var GAME := ""
var BOT_SCENE := ""
var WARM_S := 14.0
var SAMPLE_FRAMES := 120
var MAX_REDRAWS := 40.0  # canvas item redraws a frame (averaged)
var MAX_ADDED := 4.0  # nodes created a frame (averaged)
var MAX_PROCESSING := 60  # nodes with _process on
var MAX_PHYSICS := 60  # nodes with _physics_process on
var MAX_VP2D := 0  # 2D-only SubViewports re-rendered every frame (UPDATE_ALWAYS / WHEN_*): use StoryCard.redraw_only
var EXTRA_ENV := {}

var frames := 0
var sample_from := -1
var redraws := 0
var added := 0
var by_draw := {}
var by_added := {}
var max_proc := 0
var max_phys := 0
var max_vp2d := 0
var vp2d_top := {}
var proc_top := {}
var phys_top := {}
var fails := 0
var frame_us: Array[int] = []
var last_us := 0
var game_t := 0.0


func _setup() -> void:  # a game's test overrides this; run the kit itself with VR_FRAME_GAME=<id> to probe any game
	GAME = OS.get_environment("VR_FRAME_GAME")
	if OS.has_environment("VR_FRAME_WARM"):
		WARM_S = float(OS.get_environment("VR_FRAME_WARM"))


func _initialize() -> void:
	_setup()
	if BOT_SCENE == "":
		BOT_SCENE = "res://tests/%s_bot.tscn" % GAME
	Engine.set_meta("save_test_mode", true)
	Engine.max_fps = 60  # landings run -s without --fixed-fps: frames at a headset-like pace, warm-up in game time
	OS.set_environment("BOT_VR", "1")
	if not OS.has_environment("DUO_PORT"):
		OS.set_environment("DUO_PORT", str(20000 + randi() % 10000))
	for k in EXTRA_ENV:
		if not OS.has_environment(k):
			OS.set_environment(k, str(EXTRA_ENV[k]))
	root.add_child.call_deferred(load(BOT_SCENE).instantiate())
	node_added.connect(_on_added)


func _key(n: Node) -> String:
	var s: Script = n.get_script()
	var who: String = n.get_class()
	if s != null:  # an inner class (StoryCard's Picture) has no path of its own: name it by its parent's script
		who = s.resource_path.get_file() if s.resource_path != "" else "%s<%s>" % [_inner_name(s, n), _key(n.get_parent()) if n.get_parent() != null else "?"]
	return "%s:%s" % [who, n.name.rstrip("0123456789@").left(24)]


## An inner class (no path of its own): its first own script variable names it well enough (Picture: kind).
func _inner_name(s: Script, n: Node) -> String:
	var vars: Array[String] = []
	for p in s.get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			vars.append(String(p.name))
	return "%s{%s}" % [n.get_class(), ",".join(vars.slice(0, 3))]


func _on_added(n: Node) -> void:
	if sample_from < 0:
		return
	added += 1
	var k := _key(n.get_parent()) + "/" + n.get_class() if n.get_parent() != null else n.get_class()
	by_added[k] = int(by_added.get(k, 0)) + 1
	if n is CanvasItem:
		_hook(n)


func _hook(n: CanvasItem) -> void:
	if not n.draw.is_connected(_on_draw):
		n.draw.connect(_on_draw.bind(n))


func _on_draw(n: CanvasItem) -> void:
	redraws += 1
	if is_instance_valid(n):
		var k := _key(n)
		by_draw[k] = int(by_draw.get(k, 0)) + 1


func _count_processing() -> void:
	var p := 0
	var ph := 0
	var tp := {}
	var tph := {}
	for n in root.find_children("*", "", true, false):
		if n.is_processing():
			p += 1
			var k := _key(n)
			tp[k] = int(tp.get(k, 0)) + 1
		if n.is_physics_processing():
			ph += 1
			var k2 := _key(n)
			tph[k2] = int(tph.get(k2, 0)) + 1
	var v2 := 0
	var tv := {}
	for v in root.find_children("*", "SubViewport", true, false):
		var sv := v as SubViewport
		if sv.render_target_update_mode == SubViewport.UPDATE_DISABLED or sv.render_target_update_mode == SubViewport.UPDATE_ONCE:
			continue
		if sv.disable_3d or sv.find_children("*", "Camera3D", true, false).is_empty() and sv.world_3d == null and not sv.own_world_3d:
			v2 += 1
			var kv := _key(sv.get_parent()) if sv.get_parent() != null else "?"
			tv[kv] = int(tv.get(kv, 0)) + 1
	if v2 > max_vp2d:
		max_vp2d = v2
		vp2d_top = tv
	if p > max_proc:
		max_proc = p
		proc_top = tp
	if ph > max_phys:
		max_phys = ph
		phys_top = tph


func _top(d: Dictionary, per: float, n := 6) -> String:
	var ks := d.keys()
	ks.sort_custom(func(a, b): return d[a] > d[b])
	var out: Array[String] = []
	for k in ks.slice(0, n):
		out.append("%s x%.1f" % [k, d[k] / per])
	return ", ".join(out)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("VR FRAME %s: FAIL %s" % [GAME, what])


func _process(delta: float) -> bool:
	frames += 1
	game_t += delta
	var now := Time.get_ticks_usec()
	if sample_from >= 0 and last_us > 0:
		frame_us.append(now - last_us)
	last_us = now
	if sample_from < 0:
		if game_t >= WARM_S:
			sample_from = frames
			for n in root.find_children("*", "CanvasItem", true, false):
				_hook(n)
			redraws = 0
		return false
	var k := frames - sample_from
	if k % 30 == 0:
		_count_processing()
	if k < SAMPLE_FRAMES:
		return false
	var per := float(SAMPLE_FRAMES)
	frame_us.sort()
	var med_ms := frame_us[frame_us.size() / 2] / 1000.0 if not frame_us.is_empty() else 0.0
	print("VR FRAME %s: %.1f redraws/frame [%s]" % [GAME, redraws / per, _top(by_draw, per)])
	print("VR FRAME %s: %.1f nodes added/frame [%s]" % [GAME, added / per, _top(by_added, per)])
	print("VR FRAME %s: %d processing [%s]" % [GAME, max_proc, _top(proc_top, 1.0, 8)])
	print("VR FRAME %s: %d physics-processing [%s]" % [GAME, max_phys, _top(phys_top, 1.0, 8)])
	print("VR FRAME %s: %d 2D viewports rendering every frame [%s]" % [GAME, max_vp2d, _top(vp2d_top, 1.0, 8)])
	print("VR FRAME %s: median frame %.1f ms headless (info only: shared idle test threads)" % [GAME, med_ms])
	_expect(redraws / per <= MAX_REDRAWS, "%.1f canvas items redraw a frame (max %.0f): 2D pictures / labels redrawing for nothing?" % [redraws / per, MAX_REDRAWS])
	_expect(added / per <= MAX_ADDED, "%.1f nodes created a frame (max %.0f): per-frame spawns / rebuilt meshes or labels?" % [added / per, MAX_ADDED])
	_expect(max_proc <= MAX_PROCESSING, "%d nodes run _process (max %d)" % [max_proc, MAX_PROCESSING])
	_expect(max_phys <= MAX_PHYSICS, "%d nodes run _physics_process (max %d)" % [max_phys, MAX_PHYSICS])
	_expect(max_vp2d <= MAX_VP2D, "%d 2D-only SubViewports render every frame (max %d): StoryCard.redraw_only(vp, items) renders them when they change" % [max_vp2d, MAX_VP2D])
	print("VR FRAME %s: %s (%.1f redraws, %.1f added, %d proc, %d phys, %d 2D viewports)" % [GAME, "PASS" if fails == 0 else "FAIL", redraws / per, added / per, max_proc, max_phys, max_vp2d])
	_silence_bot()
	quit(1 if fails else 0)
	return true


## The bot is cut off mid-game on purpose: drop its scripts first so its end-of-run checks ("BOT ASSERT FAILED: got
## past the first round") don't print SCRIPT ERRORs that aren't this test's verdict.
func _silence_bot() -> void:
	for n in root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.begins_with("res://tests/"):
			n.set_process(false)
			n.set_physics_process(false)
			n.set_script(null)
