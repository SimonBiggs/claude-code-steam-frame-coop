extends SceneTree
## The arcade lobby sends RPCs only to machines still connected (core/lobby_send.gd): a broadcast `.rpc(...)` or an
## `.rpc_id(id, ...)` to a joiner reached machines that were leaving too, and ENet printed "ERROR: Unable to send
## packet on channel 0, max channels: 0" (the lobby host's who-left line, a start, a selection relay; 2026-11-26:
## safe_apply_bot and arcade_lobby_bot failed on it).
## Fails:
##   - a `.rpc(` in arcade/*.gd or core/safe_apply.gd (use LobbySend.all(self, &"method", [args]));
##   - an `.rpc_id(` there to anyone but the lobby host (1) (use LobbySend.one(self, id, &"method", [args]));
##   - LobbySend calling an offline / missing peer live, or sending without a connection.
##   godot-test --headless --path . -s res://tests/lobby_send_test.gd   -> LOBBY SEND: PASS / FAIL

const LobbySend := preload("res://core/lobby_send.gd")

var fails: Array[String] = []


func _initialize() -> void:
	var files: Array[String] = ["res://core/safe_apply.gd"]
	for f in DirAccess.get_files_at("res://arcade"):
		if f.ends_with(".gd"):
			files.append("res://arcade/" + f)
	var bcast := RegEx.create_from_string("\\.rpc\\(")
	var one := RegEx.create_from_string("\\.rpc_id\\(\\s*([^,)]+)")
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i].split("#")[0]
			if bcast.search(code) != null:
				fails.append("%s:%d broadcasts with .rpc(): use LobbySend.all(self, &\"method\", [args]) (never to a machine that is leaving)" % [path, i + 1])
			for m in one.search_all(code):
				if m.get_string(1).strip_edges() != "1":
					fails.append("%s:%d sends .rpc_id(%s, ...) to a lobby machine: use LobbySend.one(self, id, &\"method\", [args])" % [path, i + 1, m.get_string(1)])
	_runtime()
	for f in fails:
		print("  FAIL ", f)
	print("LOBBY SEND: %s (%d files scanned)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), files.size()])
	quit(0 if fails.is_empty() else 1)


func _runtime() -> void:
	var n := Node.new()
	root.add_child(n)
	if LobbySend.live(n.multiplayer, 2):
		fails.append("LobbySend.live says yes with no connection (offline peer)")
	if LobbySend.all(n, &"queue_free", []) != 0 or LobbySend.one(n, 2, &"queue_free", []):
		fails.append("LobbySend sent something with no connection")
	if not LobbySend.live_peers(n.multiplayer).is_empty():
		fails.append("LobbySend.live_peers isn't empty with no connection")
	n.free()