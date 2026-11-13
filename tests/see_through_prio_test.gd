extends SceneTree
## See-through scenery (water, glass, mist, ghosts, beams, bubbles) must draw UNDER VR cards: VR panels sit at
## UiKit.VR_PRIO_PANEL (-4), so a blended material at the default priority 0 behind a card is blended OVER it and
## washes it out (core/vr_view_check.gd "washed out by a see-through mesh"). Fishing Lake had 11 of these, found only
## at runtime on a late-join VR bot (2026-11-13). The one way to make a see-through material is
## UiKit.see_through(mat) (core/ui_kit.gd): alpha-blended + UiKit.VR_PRIO_UNDER_UI in one call.
## Fails, in games/, core/ and arcade/:
##   - a script setting `transparency` to TRANSPARENCY_ALPHA / TRANSPARENCY_ALPHA_DEPTH_PRE_PASS (or 1 / 4) by hand;
##   - a spatial shader in a script that blends by ALPHA (blend_mix, not blend_add / ALPHA_SCISSOR) whose material
##     never goes through UiKit.see_through (the functions using the shader, or a helper they call, must call it);
##   - a StandardMaterial3D / ORMMaterial3D in a .tscn / .tres with alpha transparency and no priority under the UI;
##   - a NODE faded by its own transparency float (`node.transparency = x`, `tween_property(node, "transparency", ...)`,
##     `set_transparency(`) outside UiKit.fade3d: the float sends the mesh into the blended pass at its material's priority
##     (usually 0), over the cards, whatever the material says (Party Board's arrows, Tiny Town's rainbow, 2026-11-13);
##   - `# see-through-ok` without a reason.
## Opt out a real overlay (a fade or hurt sphere round the head, the VR card panel itself) with
## `# see-through-ok: why` on that line or the line above (for a shader: above the line that opens its """).
## ALPHA_HASH / ALPHA_SCISSOR and additive (blend_add) materials don't wash a card out, so they're fine.
##   godot-test --headless --path . -s res://tests/see_through_prio_test.gd   -> SEE-THROUGH PRIO: PASS / FAIL

const UiKit := preload("res://core/ui_kit.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")
const ROOTS := ["res://games", "res://core", "res://arcade"]
const USE := "use UiKit.see_through(mat) (core/ui_kit.gd: alpha + UiKit.VR_PRIO_UNDER_UI, so it never washes out a VR card)"
const USE_FADE := "use UiKit.fade3d(node, amount) (core/ui_kit.gd: sets the float AND drops the node's materials to UiKit.VR_PRIO_UNDER_UI; tweens: tween_method(func(v): UiKit.fade3d(node, v), ...))"
const OPT_OUT := "or, for a real overlay meant to cover the cards too, mark it `# see-through-ok: why`"
## .tscn / .tres materials allowed to stay over the UI ("res://path::sub_resource id"), with the reason.
const RESOURCE_OK := {}

var fails: Array[String] = []
var raw_re := RegEx.create_from_string("\\.transparency\\s*=(?!=)\\s*(.*\\bTRANSPARENCY_ALPHA(_DEPTH_PRE_PASS)?\\b|[14]\\s*(#|$))|set\\(\\s*\"transparency\"")
var node_re := RegEx.create_from_string("(\\.|^\\s*)transparency\\s*[-+*/]?=(?!=)|\\btween_property\\([^,]+,\\s*\"transparency\"|\\bset_transparency\\(")
var alpha_re := RegEx.create_from_string("\\bALPHA\\s*[-+*/]?=[^=]")
var func_re := RegEx.create_from_string("^\\s*(static\\s+)?func\\s+(\\w+)")
var const_re := RegEx.create_from_string("^\\s*(const|var)\\s+(\\w+)[^=]*=\\s*\"\"\"")


func _initialize() -> void:
	_self_test()
	_runtime()
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	var n := 0
	for path in files:
		n += 1
		if path.ends_with(".gd"):
			_scan_script(path, FileAccess.get_file_as_string(path))
		else:
			_scan_resource(path, FileAccess.get_file_as_string(path))
	for f in fails:
		print("  FAIL ", f)
	print("SEE-THROUGH PRIO: %s (%d files scanned)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), n])
	quit(0 if fails.is_empty() else 1)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir + "/" + d, out)


static func _ok_mark(lines: PackedStringArray, i: int) -> String:
	## "" = no mark; "bad" = a mark with no reason; "ok" otherwise. On line i or the line above.
	for j in [i, i - 1]:
		if j < 0 or j >= lines.size():
			continue
		var k := lines[j].find("see-through-ok")
		if k < 0:
			continue
		var rest := lines[j].substr(k + "see-through-ok".length()).strip_edges()
		return "ok" if rest.begins_with(":") and rest.substr(1).strip_edges().length() >= 3 else "bad"
	return ""


## Returns failure strings for one script (so the self-test can feed it samples).
func _check_script(path: String, text: String) -> Array[String]:
	var out: Array[String] = []
	var lines := text.split("\n")
	# --- shader blocks ("""...""") and the code outside them
	var in_str := false
	var blocks: Array = []  # {open, name, body}
	var cur := {}
	for i in lines.size():
		var l := lines[i]
		var q := l.count("\"\"\"")
		if not in_str:
			if q == 1:
				in_str = true
				var m := const_re.search(l)
				cur = {"open": i, "name": m.get_string(2) if m != null and m.get_string(1) == "const" else "", "body": l.substr(l.find("\"\"\"") + 3)}
				continue
			if q >= 2:
				continue  # a one-line """...""" string
			var code := l
			var hp := code.find("#")
			var probe := code if hp < 0 else code.substr(0, hp)
			if raw_re.search(probe) != null:
				var mark := _ok_mark(lines, i)
				if mark != "ok":
					out.append("%s:%d sets a see-through material by hand (`%s`): %s, %s" % [path, i + 1, l.strip_edges(), USE, OPT_OUT])
			elif node_re.search(probe) != null and not probe.contains("TRANSPARENCY_"):
				if _ok_mark(lines, i) != "ok":
					out.append("%s:%d fades a node by its transparency float by hand (`%s`): it draws over VR cards at its material's priority; %s, %s" % [path, i + 1, l.strip_edges(), USE_FADE, OPT_OUT])
			if l.find("see-through-ok") >= 0 and _ok_mark(lines, i) == "bad":
				out.append("%s:%d `see-through-ok` needs a reason: `# see-through-ok: why it must draw over VR cards`" % [path, i + 1])
		else:
			if q >= 1:
				in_str = false
				cur.body += "\n" + l.substr(0, l.find("\"\"\""))
				blocks.append(cur)
			else:
				cur.body += "\n" + l
	# --- functions: name -> [first line, last line]; and which call see_through
	var funcs := {}
	var order: Array = []
	for i in lines.size():
		var m := func_re.search(lines[i])
		if m != null:
			order.append([m.get_string(2), i])
	for k in order.size():
		var a: int = order[k][1]
		var b: int = order[k + 1][1] if k + 1 < order.size() else lines.size()
		var body := "\n".join(lines.slice(a, b))
		funcs[order[k][0]] = {"a": a, "b": b, "st": body.contains("see_through("), "stn": body.count("see_through("), "body": body}
	# each see_through call covers ONE material: a call to a helper of this script that calls it counts as one too
	for f in funcs:
		for h in funcs:
			if h != f and funcs[h].st:
				funcs[f].stn += RegEx.create_from_string("\\b%s\\(" % h).search_all(funcs[f].body).size()
	var cands: Array = []  # [blk, users, via_helper]
	for blk in blocks:
		var body: String = blk.body
		if not body.contains("shader_type spatial") or alpha_re.search(body) == null:
			continue
		var mode := ""
		for bl in body.split("\n"):
			if bl.strip_edges().begins_with("render_mode"):
				mode = bl
		if mode.contains("blend_add") or mode.contains("blend_sub") or mode.contains("blend_mul") or body.contains("ALPHA_SCISSOR"):
			continue
		var open: int = blk.open
		var mark := _ok_mark(lines, open)
		if mark == "ok":
			continue
		cands.append(_shader_users(lines, funcs, blk))
	# per material: a function using N blended shaders (not handed to a see_through helper) needs N see_through calls
	var need := {}
	for c in cands:
		if not c[2]:
			for u in c[1]:
				need[u] = int(need.get(u, 0)) + 1
	for c in cands:
		if c[2]:
			continue
		var blk: Dictionary = c[0]
		var ok := false
		var short := ""
		for u in c[1]:
			if funcs[u].stn >= int(need[u]):
				ok = true
			elif funcs[u].stn > 0:
				short = "%s() uses %d see-through shaders but calls see_through only %d time(s)" % [u, need[u], funcs[u].stn]
		if ok:
			continue
		var what := "shader %s" % blk.name if blk.name != "" else "the shader opened here"
		if short != "":
			out.append("%s:%d %s blends by ALPHA but its material may not go through UiKit.see_through: %s (one call per material, or pass each shader to a helper that calls it), %s (above the line that opens the shader)" % [path, int(blk.open) + 1, what, short, OPT_OUT])
		else:
			out.append("%s:%d %s blends by ALPHA but its material never goes through UiKit.see_through: call UiKit.see_through(shader_material) where it's made (it sets VR_PRIO_UNDER_UI), %s (above the line that opens the shader)" % [path, int(blk.open) + 1, what, OPT_OUT])
	return out


## [blk, the functions using the shader (or making it inline), passed straight into a helper of this script that calls
## see_through (Ghost Lantern's shader_mat(code): each call makes its own material)]. A shader is fine when handed to
## such a helper, or when a function using it calls see_through at least once per blended shader it uses.
func _shader_users(lines: PackedStringArray, funcs: Dictionary, blk: Dictionary) -> Array:
	var users: Array[String] = []
	var nm: String = blk.name
	if nm == "":
		users.append(_func_at(funcs, blk.open))
	else:
		var re := RegEx.create_from_string("\\b%s\\b" % nm)
		for i in lines.size():
			if i != blk.open and re.search(lines[i]) != null:
				users.append(_func_at(funcs, i))
				# passed straight into a helper of this script: shader_mat(GHOST_SHADER)
				var cm := RegEx.create_from_string("(\\w+)\\([^()]*\\b%s\\b" % nm).search(lines[i])
				if cm != null and funcs.has(cm.get_string(1)) and funcs[cm.get_string(1)].st:
					return [blk, [], true]
	var uniq: Array[String] = []
	for u in users:
		if u != "" and funcs.has(u) and not uniq.has(u):
			uniq.append(u)
	return [blk, uniq, false]


func _func_at(funcs: Dictionary, line: int) -> String:
	for n in funcs:
		if line >= funcs[n].a and line < funcs[n].b:
			return n
	return ""


func _scan_script(path: String, text: String) -> void:
	if path == "res://tests/see_through_prio_test.gd":
		return
	fails.append_array(_check_script(path, text))


## [sub_resource type="StandardMaterial3D" id=...] / [resource] sections with alpha transparency need a priority under
## the UI (resources can't call UiKit.see_through; -5 or lower is under the panels).
func _scan_resource(path: String, text: String) -> void:
	var sec := ""
	var is_mat := false
	var alpha := false
	var prio := 0
	var start := 0
	var lines := text.split("\n")
	for i in lines.size() + 1:
		var l := lines[i] if i < lines.size() else "["
		if l.begins_with("["):
			if is_mat and alpha and prio > UiKit.VR_PRIO_PANEL - 1 and not RESOURCE_OK.has("%s::%s" % [path, sec]):
				fails.append("%s:%d a see-through material (%s) at render_priority %d draws over VR cards: set render_priority = %d (UiKit.VR_PRIO_UNDER_UI), or list it in RESOURCE_OK in tests/see_through_prio_test.gd with the reason" % [path, start + 1, sec, prio, UiKit.VR_PRIO_UNDER_UI])
			sec = l
			is_mat = l.contains("type=\"StandardMaterial3D\"") or l.contains("type=\"ORMMaterial3D\"") or (l.begins_with("[resource]") and text.contains("type=\"StandardMaterial3D\" format"))
			alpha = false
			prio = 0
			start = i
			continue
		var kv := l.split(" = ", true, 1)
		if kv.size() == 2:
			if kv[0] == "transparency" and (kv[1].strip_edges() == "1" or kv[1].strip_edges() == "4"):
				alpha = true
			elif kv[0] == "render_priority":
				prio = int(kv[1])


## The helper itself, and that VrViewCheck (the runtime check) agrees what it makes is under the cards.
func _runtime() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.5)
	UiKit.see_through(m)
	if m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or m.render_priority >= UiKit.VR_PRIO_PANEL:
		fails.append("UiKit.see_through(mat) must make it TRANSPARENCY_ALPHA with a priority under UiKit.VR_PRIO_PANEL (got %d / %d)" % [m.transparency, m.render_priority])
	if not VrViewCheck._blended(m):
		fails.append("core/vr_view_check.gd _blended() no longer counts an alpha StandardMaterial3D as see-through: keep this test and the check in step")
	var g := StandardMaterial3D.new()
	UiKit.see_through(g, true)
	if g.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS or g.render_priority != UiKit.VR_PRIO_UNDER_UI:
		fails.append("UiKit.see_through(mat, true) must use TRANSPARENCY_ALPHA_DEPTH_PRE_PASS + VR_PRIO_UNDER_UI")
	var s := ShaderMaterial.new()
	UiKit.see_through(s)
	if s.render_priority != UiKit.VR_PRIO_UNDER_UI:
		fails.append("UiKit.see_through(shader_material) must set VR_PRIO_UNDER_UI")
	var fm := StandardMaterial3D.new()  # opaque, priority 0
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = fm
	UiKit.fade3d(mi, 0.4)
	if not is_equal_approx(mi.transparency, 0.4) or fm.render_priority > UiKit.VR_PRIO_UNDER_UI:
		fails.append("UiKit.fade3d(node, 0.4) must set the node's transparency AND drop its materials to VR_PRIO_UNDER_UI (got %.2f / %d)" % [mi.transparency, fm.render_priority])
	mi.free()
	if UiKit.VR_PRIO_UNDER_UI >= UiKit.VR_PRIO_PANEL:
		fails.append("UiKit.VR_PRIO_UNDER_UI (%d) must be under UiKit.VR_PRIO_PANEL (%d)" % [UiKit.VR_PRIO_UNDER_UI, UiKit.VR_PRIO_PANEL])


## The scanner itself: what must fail and what must pass.
func _self_test() -> void:
	var cases := [
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA\n", 1],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS  # glass\n", 1],
		["\tm.transparency = 1\n", 1],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR\n", 0],
		["\treturn b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA\n", 0],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH\n", 0],
		["\tUiKit.see_through(m)\n", 0],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # see-through-ok: fade sphere round the head\n", 0],
		["\t# see-through-ok: fade sphere round the head\n\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA\n", 0],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # see-through-ok\n", 2],
		["const S := \"\"\"\nshader_type spatial;\nrender_mode blend_mix;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nfunc f():\n\tvar sm := ShaderMaterial.new()\n\tsm.shader = Shader.new()\n\tsm.shader.code = S\n", 1],
		["const S := \"\"\"\nshader_type spatial;\nrender_mode blend_mix;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nfunc f():\n\tvar sm := ShaderMaterial.new()\n\tsm.shader = Shader.new()\n\tsm.shader.code = S\n\tUiKit.see_through(sm)\n", 0],
		["const S := \"\"\"\nshader_type spatial;\nrender_mode blend_add;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nfunc f():\n\tmk(S)\n", 0],
		["const S := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nfunc f():\n\tmk(S)\nfunc mk(c):\n\tvar sm := ShaderMaterial.new()\n\tUiKit.see_through(sm)\n", 0],
		["\tmi.transparency = 0.45\n", 1],
		["\tmi.transparency = 0.0 if on else 0.45\n", 1],
		["\ttransparency = 0.5\n", 1],
		["\ttw.tween_property(g, \"transparency\", 1.0, 0.2)\n", 1],
		["\tg.set_transparency(0.3)\n", 1],
		["\ttw.tween_property(g, \"transparency\", 1.0, 0.2)  # see-through-ok: a VR card fading itself\n", 0],
		["\tUiKit.fade3d(mi, 0.45)\n", 0],
		["\tif mi.transparency == 0.0:\n", 0],
		["\tvar transparency := 0.5\n", 0],
		["\tm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED\n", 0],
		# per material: two blended shaders and one see_through call in the function using both -> one slips through
		["const A := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nconst B := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.3; }\n\"\"\"\nfunc f():\n\tvar a := ShaderMaterial.new()\n\ta.shader = Shader.new()\n\ta.shader.code = A\n\tvar b := ShaderMaterial.new()\n\tb.shader = Shader.new()\n\tb.shader.code = B\n\tUiKit.see_through(a)\n", 2],
		["const A := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nconst B := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.3; }\n\"\"\"\nfunc f():\n\tvar a := ShaderMaterial.new()\n\ta.shader = Shader.new()\n\ta.shader.code = A\n\tvar b := ShaderMaterial.new()\n\tb.shader = Shader.new()\n\tb.shader.code = B\n\tUiKit.see_through(a)\n\tUiKit.see_through(b)\n", 0],
		["const A := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\nconst B := \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.3; }\n\"\"\"\nfunc f():\n\tvar a := mk(A)\n\tvar b := mk(B)\nfunc mk(c):\n\tvar sm := ShaderMaterial.new()\n\tUiKit.see_through(sm)\n\treturn sm\n", 0],
		["func f():\n\tvar a := ShaderMaterial.new()\n\ta.shader = Shader.new()\n\ta.shader.code = \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.5; }\n\"\"\"\n\tvar b := ShaderMaterial.new()\n\tb.shader = Shader.new()\n\tb.shader.code = \"\"\"\nshader_type spatial;\nvoid fragment() { ALPHA = 0.3; }\n\"\"\"\n\tUiKit.see_through(b)\n", 2],
		["const S := \"\"\"\nshader_type canvas_item;\nvoid fragment() { COLOR.a = 0.5; }\n\"\"\"\n", 0],
	]
	for c in cases:
		var got := _check_script("res://self_test.gd", c[0]).size()
		if got != c[1]:
			fails.append("scanner self-test: expected %d failure(s), got %d for:\n%s" % [c[1], got, c[0]])