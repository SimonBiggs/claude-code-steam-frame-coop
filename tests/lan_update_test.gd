extends SceneTree
## LAN update unit checks (core/lan_update.gd): home-network addresses, which paths an update may touch, version
## order, and that the post-apply script check has no false alarms on the real game (every script compiles).
##   godot-test --headless --path . -s res://tests/lan_update_test.gd
## (Two "Parse Error" lines are expected: the deliberately broken script.)
## The multi-machine tests (signatures, refusals, relays, rollback) are tools/lan-update-test.

const U := preload("res://core/lan_update.gd")
var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("BOT ASSERT FAILED: " + what)


func _init() -> void:
	for ip in ["10.0.0.5", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.3.4", "127.0.0.1", "::1",
			"fe80::1", "fd12::3", "::ffff:192.168.0.9"]:
		check(U.is_private_ip(ip), "private: " + ip)
	for ip in ["8.8.8.8", "172.32.0.1", "172.15.9.9", "192.169.0.1", "1.1.1.1", "2001:db8::1", "", "localhost",
			"192.168.1", "300.1.1.1", "::ffff:8.8.8.8", "fc.example.com"]:
		check(not U.is_private_ip(ip), "public: " + ip)
	for p in ["core/net.gd", "games/x/main.tscn", "arcade/thumbs/a.jpg", "arcade.tscn", "tests/a_bot.gd"]:
		check(U.path_ok(p), "allowed path: " + p)
	for p in ["addons/gdev/bridge.gd", "addons/lan_update/root.pub.pem", "project.godot", "core/lan_update/signers.json",
			"core/lan_update/signers.sig", "../x.gd", "core/../project.godot", "/etc/passwd", "core/.hidden/x.gd",
			"core/a.gd.uid", ".update/manifest.json", "core\\x.gd", "launch.sh", "res://core/x.gd", ""]:
		check(not U.path_ok(p), "refused path: " + p)
	check(U.newer([2, "a", "x"], [1, "z", "z"]), "newer timestamp wins")
	check(not U.newer([1, "z", "z"], [2, "a", "a"]), "older loses")
	check(U.newer([2, "simon-deck", "a"], [2, "simon-a", "z"]) != U.newer([2, "simon-a", "z"], [2, "simon-deck", "a"]), "ties are decided one way")
	check(not U.newer([2, "a", "x"], [2, "a", "x"]), "equal is not newer")
	# The script check after applying (GDScript.new().reload()) must pass for every script that's in the game now.
	var n := 0
	var stack: Array[String] = ["res://core", "res://games", "res://arcade", "res://tests"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				check(U.compiles(d + "/" + f), "compiles: %s/%s" % [d, f])
				n += 1
	check(n > 300, "found the game's scripts (%d)" % n)
	FileAccess.open("user://lanupd_broken.gd", FileAccess.WRITE).store_string("extends Node\nfunc broken(:\n")
	check(not U.compiles("user://lanupd_broken.gd"), "a broken script is caught")
	print("BOT RESULT: %s (%d scripts compile-checked)" % ["PASS" if fails == 0 else "FAIL", n])
	quit(1 if fails else 0)
