extends SceneTree
## core/telemetry_push.gd outbox: test runs never queue, ids are stable, acks remove exactly the sent lines,
## a full outbox drops the OLDEST lines and counts them (no silent loss). The networked part (finding the Steam
## Machine, sending, duplicates ignored on the receiver) is tools/telemetry-push-test.
##   godot-test --headless --path . -s res://tests/telemetry_push_test.gd

const Push := preload("res://core/telemetry_push.gd")
const Telemetry := preload("res://core/telemetry.gd")

var fails: Array = []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL: " + what)


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)
	OS.set_environment("DUO_TELEMETRY_PORT", "1")  # nothing listens there: no test line can reach a real receiver
	# 1. A test run never queues anything (SAVE_TEST).
	OS.set_environment("DUO_TELEMETRY_PUSH_TEST", "0")
	check(not Push.enabled(), "push is on in a test run")
	var before := Push.pending().size()
	Push.enqueue('{"game":"x","t":1}')
	check(Push.pending().size() == before, "a test run queued a line")
	check(Push.outbox_path() == Push.OUTBOX, "outbox path")
	# 2. The push test's own outbox.
	OS.set_environment("DUO_TELEMETRY_PUSH_TEST", "1")
	check(Push.enabled() and Push.outbox_path() == Push.OUTBOX_TEST, "push test mode uses its own outbox")
	DirAccess.remove_absolute(Push.OUTBOX_TEST)
	DirAccess.remove_absolute(Push.META_TEST)
	var lines := []
	for i in 5:
		var l := JSON.stringify({"game": "push_test", "t": 1000 + i, "i": i})
		lines.append(l)
		Push.enqueue(l)
	check(Push.pending().size() == 5, "5 queued (got %d)" % Push.pending().size())
	check(Push.id_of(lines[0]) == Push.id_of(str(lines[0])) and Push.id_of(lines[0]).length() == 16, "id is 16 hex, stable")
	check(Push.id_of(lines[0]) != Push.id_of(lines[1]), "ids differ")
	# 3. Acks remove exactly those lines (also when an unknown id comes back).
	check(Push.ack([Push.id_of(lines[1]), Push.id_of(lines[3]), "ffffffffffffffff"]) == 2, "ack removed 2")
	var left := Push.pending()
	check(left.size() == 3 and left[0] == lines[0] and left[1] == lines[2] and left[2] == lines[4], "the other 3 stay in order")
	# 4. Full outbox: the oldest go, counted in the meta (sent with the next batch) and logged.
	for i in 40:
		Push.enqueue(JSON.stringify({"game": "push_test", "t": 2000 + i, "pad": "x".repeat(40)}))
	var n := Push.pending().size()
	var dropped := Push.trim(2000)
	var after := Push.pending()
	check(dropped > 0 and after.size() == n - dropped, "trim dropped %d of %d" % [dropped, n])
	check(not after.has(lines[0]) and after[after.size() - 1].contains("\"t\":2039"), "the oldest went, the newest stayed")
	var m := Push.read_meta()
	check(int(m.get("dropped", 0)) == dropped and int(m.get("dropped_unreported", 0)) == dropped, "drops counted: %s" % m)
	check(Push.trim(2000) == 0, "a second trim drops nothing")
	# 5. Device names are plain.
	OS.set_environment("DUO_TELEMETRY_DEVICE", "Samuel-Deck!")
	check(Push.device() == "samuel-deck", "device name cleaned (%s)" % Push.device())
	OS.unset_environment("DUO_TELEMETRY_DEVICE")
	check(Push._private("192.168.0.20") and Push._private("10.1.2.3") and not Push._private("8.8.8.8") and not Push._private("172.32.0.1"), "private addresses")
	DirAccess.remove_absolute(Push.OUTBOX_TEST)
	DirAccess.remove_absolute(Push.META_TEST)
	OS.set_environment("DUO_TELEMETRY_PUSH_TEST", "0")
	print("PASS telemetry_push_test" if fails.is_empty() else "FAIL telemetry_push_test: %d" % fails.size())
	quit(0 if fails.is_empty() else 1)