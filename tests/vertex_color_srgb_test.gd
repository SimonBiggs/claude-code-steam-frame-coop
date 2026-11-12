extends SceneTree
## Vertex colours are sRGB: every material that sets `vertex_color_use_as_albedo` must also set
## `vertex_color_is_srgb = true` (same material, within a few lines), or carry a "linear on purpose" comment next to it
## when the game really builds its vertex colours in linear space. Without it Godot treats hand-picked palette colours
## (Color("#5a8f3c"), Color(0.35, 0.56, 0.24)) as linear: on the real graphics card the land came out washed out almost
## to white (Portal Explorer terrain, 2026-11-12; then the same pattern in 89 places across 47 arcade scripts).
## Static scan of every .gd / .tscn / .tres under res:// (not addons, not .godot).
##   godot-test --headless --path . -s res://tests/vertex_color_srgb_test.gd   -> VERTEX COLOR SRGB: PASS / FAIL

const WINDOW := 15
var assign_re := RegEx.create_from_string("^\\s*([\\w\\.]+)\\.vertex_color_use_as_albedo\\s*=\\s*(.+)$")
var fails: Array[String] = []


## Problems in one GDScript source: "line N: ..." for each vertex-colour material without sRGB.
func problems_gd(src: String) -> Array[String]:
	var out: Array[String] = []
	var lines := src.split("\n")
	for i in lines.size():
		var m := assign_re.search(lines[i])
		if m == null or m.get_string(2).strip_edges().begins_with("false"):
			continue
		var v := m.get_string(1)
		var srgb := RegEx.create_from_string("\\b%s\\.vertex_color_is_srgb\\s*=\\s*true" % v.replace(".", "\\."))
		var ok := false
		for j in range(maxi(0, i - WINDOW), mini(lines.size(), i + WINDOW + 1)):
			if srgb.search(lines[j]) != null or "linear on purpose" in lines[j].to_lower():
				ok = true
				break
		if not ok:
			out.append("line %d: %s.vertex_color_use_as_albedo without %s.vertex_color_is_srgb = true" % [i + 1, v, v])
	return out


## Problems in a .tscn / .tres: each [sub_resource] / [resource] section using vertex colours needs sRGB too.
func problems_res(src: String) -> Array[String]:
	var out: Array[String] = []
	var sections := ("\n" + src).split("\n[")
	for s in sections:
		if "vertex_color_use_as_albedo = true" in s and not "vertex_color_is_srgb = true" in s and not "linear on purpose" in s.to_lower():
			out.append("[%s: vertex_color_use_as_albedo without vertex_color_is_srgb = true" % s.get_slice("\n", 0))
	return out


func _scan(dir: String, n: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == "res://" and d == "addons"):
			continue
		_scan(dir.path_join(d), n)
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		var bad: Array[String] = []
		if f.ends_with(".gd"):
			bad = problems_gd(FileAccess.get_file_as_string(path))
		elif f.ends_with(".tscn") or f.ends_with(".tres"):
			bad = problems_res(FileAccess.get_file_as_string(path))
		else:
			continue
		n[0] += 1
		for b in bad:
			_check(false, "%s %s" % [path, b])


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("VERTEX COLOR SRGB: FAIL ", what)


func _initialize() -> void:
	# the scanner itself
	var vc := "vertex_color_use_as_albedo"
	_check(not problems_gd("\tvar m := StandardMaterial3D.new()\n\tm.%s = true\n\tm.roughness = 1.0" % vc).is_empty(), "self-test: missing sRGB")
	_check(problems_gd("\tm.%s = true\n\tm.vertex_color_is_srgb = true" % vc).is_empty(), "self-test: sRGB set")
	_check(problems_gd("\t# vertex colours are built with srgb_to_linear(): linear on purpose\n\tm.%s = true" % vc).is_empty(), "self-test: linear on purpose")
	_check(not problems_gd("\ta.%s = true\n\tb.vertex_color_is_srgb = true" % vc).is_empty(), "self-test: sRGB on another material")
	_check(problems_gd("\tm.%s = false" % vc).is_empty(), "self-test: off")
	_check(problems_gd("\tif mat.%s:\n\t\tpass" % vc).is_empty(), "self-test: a read")
	_check(not problems_res("[sub_resource type=\"StandardMaterial3D\" id=\"1\"]\n%s = true\n" % vc).is_empty(), "self-test: .tscn missing sRGB")
	_check(problems_res("[sub_resource type=\"StandardMaterial3D\" id=\"1\"]\n%s = true\nvertex_color_is_srgb = true\n" % vc).is_empty(), "self-test: .tscn sRGB")
	var n := [0]
	_scan("res://", n)
	print("VERTEX COLOR SRGB: scanned %d files" % n[0])
	print("VERTEX COLOR SRGB: " + ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
