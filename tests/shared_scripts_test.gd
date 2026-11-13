extends SceneTree
## Shared scripts stay shared. Games once had 17 drifted copies of the see-through teaching hand
## (games/*/ghost_hand.gd, each ~120 lines, every one different) until they were merged into
## core/ghost_hand.gd (2026-11-13). This landing guard fails:
##   - any games/*/ghost_hand*.gd again (use core/ghost_hand.gd: `const GhostHand := preload("res://core/ghost_hand.gd")`,
##     options before add_child, the game's own choreography in its own code with gate / play / track / pose);
##   - any script under games/ or arcade/ that is a near copy of a core/ script: it holds most of that core
##     script's distinctive lines (preload / extend the core script instead, with an option for what really differs).
##   godot-test --headless --path . -s res://tests/shared_scripts_test.gd   -> SHARED SCRIPTS: PASS / FAIL

## Script names that must only live in core/ (name -> the core script to use).
const CORE_ONLY := {
	"ghost_hand": "res://core/ghost_hand.gd",
	"ghost_hands": "res://core/ghost_hand.gd",
}
const MIN_LINE := 28  ## a "distinctive" line: at least this long once stripped, not a comment
const MIN_LINES := 12  ## core scripts with fewer distinctive lines aren't checked for copies
const COPY_SHARE := 0.6  ## a game script holding this share of a core script's distinctive lines is a copy
## Known near copies still to merge (path -> why it may stay for now). Keep empty: merge, don't list.
const KNOWN := {}

var fails: Array[String] = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	# Distinctive line -> the core scripts that have it.
	var core_files: Array[String] = []
	_collect("res://core", core_files)
	var owner := {}
	var core_count := {}
	for path in core_files:
		var n := 0
		for line in _lines(path):
			if not owner.has(line):
				owner[line] = []
			if not (owner[line] as Array).has(path):
				(owner[line] as Array).append(path)
				n += 1
		core_count[path] = n
	var files: Array[String] = []
	for d in ["res://games", "res://arcade"]:
		_collect(d, files)
	for path in files:
		var base := path.get_file().get_basename()
		if CORE_ONLY.has(base):
			fails.append("%s: a per-game %s.gd is back; use the shared %s (options for real differences, choreography in the game's own code)" % [path, base, CORE_ONLY[base]])
		var hits := {}
		for line in _lines(path):
			if owner.has(line):
				for c in owner[line]:
					hits[c] = int(hits.get(c, 0)) + 1
		for c in hits:
			var n: int = core_count[c]
			if n >= MIN_LINES and float(hits[c]) >= COPY_SHARE * n and not KNOWN.has(path):
				fails.append("%s is a near copy of %s (%d of its %d distinctive lines): preload / extend %s instead and make what differs an option" % [path, c, hits[c], n, c])
	for f in fails:
		print("  FAIL ", f)
	print("SHARED SCRIPTS: %s (%d game scripts vs %d core scripts, %d ms)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(),
		files.size(), core_files.size(), Time.get_ticks_msec() - t0])
	quit(0 if fails.is_empty() else 1)


## The script's distinctive lines (stripped, long, no comments), each once.
func _lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for raw in FileAccess.get_file_as_string(path).split("\n", false):
		var line := raw.strip_edges()
		if line.length() < MIN_LINE or line.begins_with("#") or seen.has(line):
			continue
		seen[line] = true
		out.append(line)
	return out


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)