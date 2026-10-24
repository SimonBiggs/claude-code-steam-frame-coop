extends Node
## LAN updates (Simon, 2026-10-24: "it updates via the host and only over the local network"). Every machine in an
## arcade lobby ends up running the same game code, with no SSH or devkit pairing: game code travels inside the arcade,
## from machine to machine, over the lobby's own ENet connection. docs/MULTI_MACHINE.md "Updates over the home network".
##
## - TRUST: an update is a signed manifest (res://.update/manifest.json + .sig: timestamp, signer, content hash, every
##   file's SHA-256), made by tools/duo-update-bundle on a SIGNER machine (the Steam Machine = the ROOT, whose public
##   key is pinned in addons/lan_update/root.pub.pem; Simon's Deck = a code signer listed in core/lan_update/signers.json,
##   which only the root can sign). Every machine checks the signature and every file's hash before writing anything.
##   Any machine can RELAY an update it has (it serves its own signed manifest), but only signers can make one.
## - LOCAL ONLY, HOST ONLY: transfers happen only in the arcade lobby, only with a peer on a private address
##   (10/8, 172.16/12, 192.168/16, link-local, loopback), and a joiner only takes updates from its lobby host. The host
##   takes them from a lobby member that has a NEWER version (newest wins, so a fresh deploy spreads to everyone).
## - SAFE: files are fetched to res://.update/staging, verified, then swapped in with atomic renames while the arcade
##   menu is showing (never during a game); the old files go to res://.update/backup first. Changed scripts are compiled
##   right away and any error rolls everything back (addons/lan_update/guard.gd also rolls back if the arcade isn't
##   running 15 s later or after a crash loop). The gdev bridge then hot-reloads the new files.
## - Never touched: addons/ (gdev can't hot-reload itself; the guard and the root key must survive a bad update),
##   project.godot, the trusted signer list except through its own root signature.
## - Machines running from a git checkout (the TV's live copy, worktrees) are where code is made: they serve but never
##   take updates (env DUO_UPDATE_RECEIVE=1/0 overrides).
## Env: DUO_UPDATE_RATE (bytes/s served, default 1 MB/s), DUO_UPDATE_RECEIVE; tests: DUO_UPDATE_TEST_PEER_IP (pretend
## every peer has this address, to prove public addresses are refused).

signal verified(version: String)  # an update is downloaded and checked (applied once the arcade menu shows)
signal applied(version: String)
signal refused(what: String, reason: String)

const ROOT_KEY_PATH := "res://addons/lan_update/root.pub.pem"
const GUARD_PATH := "res://addons/lan_update/guard.gd"
const SIGNERS_PATH := "res://core/lan_update/signers.json"
const SIGNERS_SIG_PATH := "res://core/lan_update/signers.sig"
const ROOT_NAME := "steam-machine"
const META := "res://.update"
const ARCADE_SCENE := "res://arcade.tscn"
const ROOTS := ["core/", "games/", "arcade/", "tests/"]
const ROOT_FILES := ["arcade.tscn"]
const PROTECTED := ["core/lan_update/signers.json", "core/lan_update/signers.sig"]
const MAX_FILES := 4000
const MAX_FILE := 8 << 20
const MAX_TOTAL := 64 << 20
const MAX_TEXT := 1 << 20  # manifest / signer list size
const CHUNK := 32768
const FUTURE_SLACK := 300  # seconds: a bundle stamped further in the future than this is refused (clock games)
const STALL_MS := 12000
const APPLY_DELAY := 1.0  # seconds after verifying, so the "Updating" toast shows and a game start can win

var rate: float = float(OS.get_environment("DUO_UPDATE_RATE")) if OS.has_environment("DUO_UPDATE_RATE") else 1048576.0
var mine := {}  # my verified manifest: {text, sig, m (parsed), ver}
var trust := {}  # signer name -> CryptoKey (root + the newest root-signed signer list)
var trust_issued := 0
var job := {}  # the update being fetched
var waiting := {}  # verified, waiting for the arcade menu
var queue: Array = []  # [peer, path, offset] chunk requests to serve
var budget := 0.0
var cooldown := {}  # version string -> msec until we try it again (after a refusal)
var served_ok := {}  # path -> mtime when its hash last matched my manifest
var toast_layer: CanvasLayer
var toast: Label
var toast_until := 0
var _said_dev := false


func _ready() -> void:
	name = "LanUpdate"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_trust()
	_load_mine()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected)
	log_line("ready: version %s, trusted signers %s, %s" % [ver_text(my_ver()), ", ".join(trust.keys()),
		"takes updates" if can_receive() else "serves only (a dev checkout)"])


# --- Versions and trust ---------------------------------------------------------

func my_ver() -> Array:
	return mine.get("ver", [0, "", ""])


static func ver_of(m: Dictionary) -> Array:
	return [int(m.get("timestamp", 0)), str(m.get("signer", "")), str(m.get("content", ""))]


## Newest timestamp wins; ties go by signer then content so every machine agrees.
static func newer(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) > int(b[0])
	if str(a[1]) != str(b[1]):
		return str(a[1]) > str(b[1])
	return str(a[2]) > str(b[2])


static func ver_text(v: Array) -> String:
	if int(v[0]) == 0:
		return "none"
	return "%d-%s-%s" % [int(v[0]), v[1], str(v[2]).left(8)]


static func _key_from(pem: String) -> CryptoKey:
	var k := CryptoKey.new()
	if pem.strip_edges() == "" or k.load_from_string(pem, true) != OK:
		return null
	return k


static func _sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()


static func verify_sig(text: String, sig_b64: String, key: CryptoKey) -> bool:
	if key == null or text == "" or sig_b64 == "":
		return false
	var sig := Marshalls.base64_to_raw(sig_b64.strip_edges())
	if sig.is_empty():
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, _sha256_bytes(text.to_utf8_buffer()), sig, key)


func root_key() -> CryptoKey:
	return _key_from(_read(ROOT_KEY_PATH))


## A signer list (core/lan_update/signers.json) is only ever believed with the ROOT's signature, so a code signer
## (a Deck) can neither add itself nor undo its own revocation. Returns {issued, keys} or {} if it isn't valid.
func parse_signers(text: String, sig: String) -> Dictionary:
	var root := root_key()
	if root == null:
		return {}
	var keys := {ROOT_NAME: root}
	if text == "":
		return {"issued": 0, "keys": keys}
	if not verify_sig(text, sig, root):
		return {}
	var d = JSON.parse_string(text)
	if not d is Dictionary or not d.get("signers") is Dictionary:
		return {}
	for n in d.signers:
		if str(n) == ROOT_NAME:
			continue
		var k := _key_from(str(d.signers[n]))
		if k != null:
			keys[str(n)] = k
	return {"issued": int(d.get("issued", 0)), "keys": keys}


func _load_trust() -> void:
	var t := parse_signers(_read(SIGNERS_PATH), _read(SIGNERS_SIG_PATH))
	if t.is_empty():
		var root := root_key()
		t = {"issued": 0, "keys": {ROOT_NAME: root} if root != null else {}}
		if FileAccess.file_exists(SIGNERS_PATH):
			log_line("signer list is not signed by the root: trusting only the root")
	trust = t.keys
	trust_issued = t.issued


func _load_mine() -> void:
	mine = {}
	var text := _read(META + "/manifest.json")
	if text == "":
		return
	var r := check_manifest(text, _read(META + "/manifest.sig"), trust)
	if r.has("error"):
		log_line("my own manifest doesn't verify (%s): treating this copy as unversioned" % r.error)
		return
	mine = {"text": text, "sig": _read(META + "/manifest.sig"), "m": r.m, "ver": ver_of(r.m)}


## Everything about a manifest that can be checked without the files. Returns {m} or {error}.
func check_manifest(text: String, sig: String, keys: Dictionary) -> Dictionary:
	if text.length() > MAX_TEXT * 8:
		return {"error": "manifest too big"}
	var m = JSON.parse_string(text)
	if not m is Dictionary or not m.get("files") is Dictionary:
		return {"error": "not a manifest"}
	var signer := str(m.get("signer", ""))
	if not keys.has(signer):
		return {"error": "unknown or revoked signer '%s'" % signer}
	if not verify_sig(text, sig, keys[signer]):
		return {"error": "bad signature (claims signer '%s')" % signer}
	if str(m.get("app", "")) != "duo-arena" or int(m.get("format", 0)) != 1:
		return {"error": "not a Duo Arena manifest"}
	var files: Dictionary = m.files
	if files.size() > MAX_FILES:
		return {"error": "too many files"}
	var total := 0
	var lines: Array[String] = []
	for p in files:
		var rel := str(p)
		if not path_ok(rel):
			return {"error": "file outside the game code: %s" % rel}
		var e = files[p]
		if not e is Dictionary or str(e.get("sha256", "")).length() != 64 or not str(e.sha256).is_valid_hex_number():
			return {"error": "bad entry for %s" % rel}
		var size := int(e.get("size", -1))
		if size < 0 or size > MAX_FILE:
			return {"error": "%s too big" % rel}
		total += size
		lines.append("%s %s\n" % [rel, str(e.sha256).to_lower()])
	if total > MAX_TOTAL:
		return {"error": "bundle too big"}
	lines.sort()
	if "".join(lines).sha256_text() != str(m.get("content", "")):
		return {"error": "content hash doesn't match the file list"}
	return {"m": m}


## Only game code: core/ games/ arcade/ tests/ and arcade.tscn. Never addons/ (gdev, the guard, the root key),
## project.godot, the signer list, hidden or parent paths.
static func path_ok(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.contains("\\") or rel.contains("..") or rel.contains("//") or rel.contains(":"):
		return false
	if rel in PROTECTED or rel.ends_with(".uid") or rel.ends_with(".import") or rel.ends_with(".tmp"):
		return false
	for part in rel.split("/"):
		if part.begins_with("."):
			return false
	if rel in ROOT_FILES:
		return true
	for r in ROOTS:
		if rel.begins_with(r):
			return true
	return false


## Home network only: 10/8, 172.16/12, 192.168/16, 169.254/16 (link-local), 127/8 (loopback, tests), and IPv6 ::1,
## fe80::/10, fc00::/7.
static func is_private_ip(ip: String) -> bool:
	var a := ip.strip_edges().to_lower()
	if a.begins_with("::ffff:"):
		a = a.substr(7)
	if a.contains(":"):
		return a == "::1" or a.begins_with("fe8") or a.begins_with("fe9") or a.begins_with("fea") or a.begins_with("feb") \
			or a.begins_with("fc") or a.begins_with("fd")
	var p := a.split(".")
	if p.size() != 4:
		return false
	for x in p:
		if not x.is_valid_int() or int(x) < 0 or int(x) > 255:
			return false
	var o0 := int(p[0])
	var o1 := int(p[1])
	return o0 == 10 or o0 == 127 or (o0 == 172 and o1 >= 16 and o1 <= 31) or (o0 == 192 and o1 == 168) or (o0 == 169 and o1 == 254)


func can_receive() -> bool:
	if OS.has_environment("DUO_UPDATE_RECEIVE"):
		return OS.get_environment("DUO_UPDATE_RECEIVE") == "1"
	var git := ProjectSettings.globalize_path("res://.git")
	return not (DirAccess.dir_exists_absolute(git) or FileAccess.file_exists(git))


# --- Who we talk to ------------------------------------------------------------

## The arcade lobby scene, or null (updates only move in the lobby, never during a game).
func _lobby() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.scene_file_path == ARCADE_SCENE else null


func _enet() -> ENetMultiplayerPeer:
	var p := multiplayer.multiplayer_peer
	if p is ENetMultiplayerPeer and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return p
	return null


func peer_ip(peer: int) -> String:
	if OS.has_environment("DUO_UPDATE_TEST_PEER_IP"):
		return OS.get_environment("DUO_UPDATE_TEST_PEER_IP")
	var e := _enet()
	# (only machines we have a direct ENet link to: a client links only to the host; others' messages are relayed)
	if e == null or not (peer in multiplayer.get_peers() if multiplayer.is_server() else peer == 1):
		return ""
	var pp := e.get_peer(peer)
	return pp.get_remote_address() if pp != null else ""


## "" if this peer may give us an update now, else why not. A joiner takes updates only from its lobby host (peer 1);
## the lobby host only from a machine in its lobby. Always a private address, always in the arcade lobby.
func source_problem(peer: int, ip: String) -> String:
	if _lobby() == null or _enet() == null:
		return "not in an arcade lobby"
	if multiplayer.is_server():
		if not peer in multiplayer.get_peers():
			return "not a machine in this lobby"
	elif peer != 1:
		return "not the lobby host"
	if not is_private_ip(ip):
		return "not a home-network address"
	return ""


func _refuse(what: String, peer: int, reason: String) -> void:
	var ip := peer_ip(peer)
	log_line("REFUSED %s from %s (peer %d): %s" % [what, ip if ip != "" else "another machine, relayed", peer, reason])
	refused.emit(what, reason)


# --- Version exchange ----------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server() and _lobby() != null:
		_send_ver(peer)


func _on_connected() -> void:
	if _lobby() != null:
		_send_ver(1)


func _send_ver(peer: int) -> void:
	var v := my_ver()
	_u_ver.rpc_id(peer, int(v[0]), str(v[1]), str(v[2]))


func announce() -> void:
	if _enet() == null or _lobby() == null:
		return
	if multiplayer.is_server():
		for p in multiplayer.get_peers():
			_send_ver(p)
	else:
		_send_ver(1)


@rpc("any_peer", "call_remote", "reliable")
func _u_ver(ts, signer, content) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not (ts is int and signer is String and content is String):
		return
	var v := [ts, signer, content]
	if multiplayer.is_server() and peer in multiplayer.get_peers() and _lobby() != null:
		_send_ver(peer)  # the host always answers with its own version
	if not job.is_empty() and job.peer == peer and v != job.ver:
		log_line("source moved on to %s: starting again" % ver_text(v))
		_abort("source changed")
	if not newer(v, my_ver()):
		return
	if not waiting.is_empty() and not newer(v, waiting.ver):
		return
	consider(peer, v)


## Peer `peer` says it has version v (newer than ours): fetch it if it's allowed to give it to us.
func consider(peer: int, v: Array) -> void:
	if not can_receive():
		if not _said_dev:
			_said_dev = true
			log_line("peer %d has %s, but this is a dev checkout: not taking updates" % [peer, ver_text(v)])
		return
	if not job.is_empty():
		return
	var vt := ver_text(v)
	if vt in GUARD().read_json(META + "/state.json").get("bad", []):
		if not cooldown.has("bad " + vt):
			cooldown["bad " + vt] = 0
			log_line("not fetching %s again: it was rolled back here" % vt)
		return
	if Time.get_ticks_msec() < int(cooldown.get(vt, 0)):
		return
	var why := source_problem(peer, peer_ip(peer))
	if why != "":
		_refuse("update offer %s" % vt, peer, why)
		return
	if int(v[0]) > int(Time.get_unix_time_from_system()) + FUTURE_SLACK:
		_refuse("update offer %s" % vt, peer, "stamped in the future")
		return
	job = {"peer": peer, "ip": peer_ip(peer), "ver": v, "stage": "manifest", "t": Time.get_ticks_msec()}
	log_line("fetching update %s from %s (have %s)" % [vt, job.ip, ver_text(my_ver())])
	_show_toast("Updating...", 600000)
	_u_get_manifest.rpc_id(peer)


# --- Serving -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _u_get_manifest() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not _may_serve(peer) or mine.is_empty():
		return
	_u_manifest.rpc_id(peer, mine.text, mine.sig, _read(SIGNERS_PATH), _read(SIGNERS_SIG_PATH))


## Serve only machines in the same lobby on the home network (a joiner serves only its host).
func _may_serve(peer: int) -> bool:
	if _lobby() == null or _enet() == null or not is_private_ip(peer_ip(peer)):
		return false
	return peer in multiplayer.get_peers() if multiplayer.is_server() else peer == 1


@rpc("any_peer", "call_remote", "reliable")
func _u_get(path, offset) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not (path is String and offset is int) or not _may_serve(peer) or mine.is_empty():
		return
	if not mine.m.files.has(path) or queue.size() > 64:
		return
	queue.append([peer, path, offset])


func _serve(delta: float) -> void:
	budget = minf(budget + rate * delta, maxf(rate * 0.25, CHUNK))
	while not queue.is_empty() and budget >= CHUNK:
		var r: Array = queue.pop_front()
		var peer: int = r[0]
		var rel: String = r[1]
		var off: int = r[2]
		if not _may_serve(peer):
			continue
		var path := "res://" + rel
		var mt := FileAccess.get_modified_time(path)
		if served_ok.get(rel, -1) != mt:
			if FileAccess.get_sha256(path) != str(mine.m.files[rel].sha256):
				log_line("not serving %s: it doesn't match my manifest" % rel)
				continue
			served_ok[rel] = mt
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var size := f.get_length()
		if off < 0 or off > size:
			continue
		f.seek(off)
		var data := f.get_buffer(mini(CHUNK, size - off))
		budget -= data.size()
		_u_chunk.rpc_id(peer, rel, off, size, data)


# --- Fetching ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _u_manifest(text, sig, signers_text, signers_sig) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if job.is_empty() or job.peer != peer or job.stage != "manifest":
		_refuse("unasked-for manifest", peer, "no fetch from this peer in progress")
		return
	if not (text is String and sig is String and signers_text is String and signers_sig is String) \
			or text.length() > MAX_TEXT * 8 or signers_text.length() > MAX_TEXT:
		_fail("malformed manifest")
		return
	# The signer list it carries: believed only with the root's signature; adopted only if newer than ours (so a
	# revocation sticks even if an old list is replayed).
	var keys := trust
	var issued := trust_issued
	if signers_text != "":
		var t := parse_signers(signers_text, signers_sig)
		if t.is_empty():
			_fail("its signer list is not signed by the root")
			return
		if int(t.issued) > trust_issued:
			keys = t.keys
			issued = int(t.issued)
	var r := check_manifest(text, sig, keys)
	if r.has("error"):
		_fail(r.error)
		return
	var m: Dictionary = r.m
	var v := ver_of(m)
	if not newer(v, my_ver()):
		_fail("not newer than mine (%s)" % ver_text(v))
		return
	if int(v[0]) > int(Time.get_unix_time_from_system()) + FUTURE_SLACK:
		_fail("stamped in the future")
		return
	var need: Array[String] = []
	var stage := _stage_dir(v)
	for rel in m.files:
		var want := str(m.files[rel].sha256).to_lower()
		if FileAccess.get_sha256("res://" + str(rel)) == want:
			continue
		if FileAccess.get_sha256(stage + "/" + str(rel)) == want:
			continue  # fetched last time (an interrupted update resumes)
		need.append(str(rel))
	need.sort()
	job.merge({"stage": "files", "m": m, "text": text, "sig": sig, "signers_text": signers_text if issued > trust_issued else "",
		"signers_sig": signers_sig if issued > trust_issued else "", "keys": keys, "issued": issued, "ver": v, "need": need,
		"i": -1, "t": Time.get_ticks_msec()}, true)
	log_line("update %s signed by %s verified: %d of %d files to fetch" % [ver_text(v), v[1], need.size(), m.files.size()])
	_next_file()


func _stage_dir(v: Array) -> String:
	return META + "/staging/" + str(v[2]).left(16)


func _next_file() -> void:
	if job.has("f") and job.f != null:
		(job.f as FileAccess).close()
		job.f = null
	job.i = int(job.i) + 1
	if job.i >= job.need.size():
		_fetched()
		return
	var rel: String = job.need[job.i]
	var p := ProjectSettings.globalize_path(_stage_dir(job.ver) + "/" + rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	job.f = FileAccess.open(p + ".part", FileAccess.WRITE)
	job.off = 0
	if job.f == null:
		_fail("can't write %s" % p)
		return
	_u_get.rpc_id(job.peer, rel, 0)


@rpc("any_peer", "call_remote", "reliable")
func _u_chunk(path, offset, total, data) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if job.is_empty() or job.peer != peer or job.stage != "files" or job.i < 0 or job.i >= job.need.size():
		_refuse("unasked-for file data", peer, "no fetch from this peer in progress")
		return
	if not (path is String and offset is int and total is int and data is PackedByteArray):
		_fail("malformed file data")
		return
	var rel: String = job.need[job.i]
	var e: Dictionary = job.m.files[rel]
	if path != rel or offset != int(job.off) or total != int(e.size) or data.size() > CHUNK or offset + data.size() > total:
		_fail("unexpected data for %s" % rel)
		return
	(job.f as FileAccess).store_buffer(data)
	job.off = offset + data.size()
	job.t = Time.get_ticks_msec()
	if job.off < total and data.size() > 0:
		_u_get.rpc_id(peer, rel, job.off)
		return
	(job.f as FileAccess).close()
	job.f = null
	var part := ProjectSettings.globalize_path(_stage_dir(job.ver) + "/" + rel + ".part")
	if FileAccess.get_sha256(part) != str(e.sha256).to_lower():
		DirAccess.remove_absolute(part)
		_fail("%s doesn't match its signed hash (tampered or corrupted)" % rel)
		return
	DirAccess.rename_absolute(part, part.trim_suffix(".part"))
	_next_file()


func _fetched() -> void:
	var m: Dictionary = job.m
	var dels: Array[String] = []
	for rel in managed_files():
		if not m.files.has(rel):
			dels.append(rel)
	waiting = {"ver": job.ver, "m": m, "text": job.text, "sig": job.sig, "signers_text": job.signers_text,
		"signers_sig": job.signers_sig, "keys": job.keys, "issued": job.issued, "from": job.ip, "deletes": dels,
		"at": Time.get_ticks_msec() + int(APPLY_DELAY * 1000)}
	log_line("update %s from %s downloaded and verified (applies in the arcade menu)" % [ver_text(job.ver), job.ip])
	job = {}
	verified.emit(ver_text(waiting.ver))


## A refusal while fetching: nothing is written to the game, the staged files of this version are dropped, and the
## version isn't tried again for a minute.
func _fail(reason: String) -> void:
	var vt := ver_text(job.ver)
	_refuse("update %s" % vt, int(job.peer), reason)
	_abort(reason)
	_remove_tree(ProjectSettings.globalize_path(META + "/staging"))
	cooldown[vt] = Time.get_ticks_msec() + 60000
	_show_toast("Update refused", 4000)


func _abort(_reason: String) -> void:
	if job.has("f") and job.f != null:
		(job.f as FileAccess).close()
	job = {}
	if toast != null and toast.text == "Updating...":
		toast_until = 0


## Files in the game directory that updates manage (what a bundle would contain).
func managed_files() -> Array[String]:
	var out: Array[String] = []
	for r in ROOTS:
		_walk(r.trim_suffix("/"), out)
	for f in ROOT_FILES:
		if FileAccess.file_exists("res://" + f):
			out.append(f)
	return out


func _walk(rel: String, out: Array[String]) -> void:
	var abs := "res://" + rel
	for d in DirAccess.get_directories_at(abs):
		if not d.begins_with("."):
			_walk(rel + "/" + d, out)
	for f in DirAccess.get_files_at(abs):
		var p := rel + "/" + f
		if path_ok(p):
			out.append(p)


# --- Applying ------------------------------------------------------------------

func _process(delta: float) -> void:
	_serve(delta)
	if not job.is_empty() and Time.get_ticks_msec() - int(job.t) > STALL_MS:
		log_line("update %s stalled (source gone?): will resume next time" % ver_text(job.ver))
		_abort("stalled")
	if not job.is_empty() and (_lobby() == null or _enet() == null):
		log_line("left the lobby during the update: will resume next time")
		_abort("left lobby")
	var lobby := _lobby()
	if not waiting.is_empty() and lobby != null and lobby.get("starting") != true and Time.get_ticks_msec() >= int(waiting.at):
		apply_ready()
	_update_toast(lobby != null)


## Swap the verified update in (only from the arcade menu). Old files go to res://.update/backup first; each file is
## written to a temp name and renamed over the old one; the manifest goes last. Then every changed script is compiled:
## any error rolls everything back.
func apply_ready() -> void:
	var r := waiting
	waiting = {}
	var m: Dictionary = r.m
	var stage := _stage_dir(r.ver)
	var changed: Array[String] = []
	for rel in m.files:
		if FileAccess.get_sha256("res://" + str(rel)) != str(m.files[rel].sha256).to_lower():
			changed.append(str(rel))
	# Re-check the staged copies right before writing (nothing unverified ever reaches the game directory).
	for rel in changed:
		if FileAccess.get_sha256(stage + "/" + rel) != str(m.files[rel].sha256).to_lower():
			log_line("staged %s changed since it was verified: not applying" % rel)
			_remove_tree(ProjectSettings.globalize_path(META + "/staging"))
			return
	var G := GUARD()
	var bk := ProjectSettings.globalize_path(META + "/backup")
	_remove_tree(bk)
	var replaced: Array[String] = []
	var added: Array[String] = []
	for rel in changed + r.deletes:
		if FileAccess.file_exists("res://" + rel):
			G.write_bytes(META + "/backup/files/" + rel, FileAccess.get_file_as_bytes("res://" + rel))
			replaced.append(rel)
		else:
			added.append(rel)
	for f in ["manifest.json", "manifest.sig"]:
		if FileAccess.file_exists(META + "/" + f):
			G.write_bytes(META + "/backup/meta/" + f, FileAccess.get_file_as_bytes(META + "/" + f))
	G.write_text(META + "/backup/restore.json", JSON.stringify({"from": ver_text(my_ver()), "to": ver_text(r.ver),
		"replaced": replaced, "added": added}))
	G.write_text(META + "/boot_pending.json", JSON.stringify({"to": ver_text(r.ver), "attempts": 0}))
	for rel in changed:
		G.write_bytes("res://" + rel, FileAccess.get_file_as_bytes(stage + "/" + rel))
	for rel in r.deletes:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + rel))
	G.write_text(META + "/manifest.sig", r.sig)
	G.write_text(META + "/manifest.json", r.text)
	var bad := ""
	for rel in changed:
		if rel.ends_with(".gd") and not compiles("res://" + rel):
			bad = rel
			break
	if bad != "":
		log_line("update %s: %s doesn't compile" % [ver_text(r.ver), bad])
		G.restore("script error in " + bad)
		_load_mine()
		_show_toast("Update failed: kept the old version", 5000)
		announce()  # the host answers with its version, which is now on the bad list: nothing is fetched again
		return
	if r.signers_text != "":
		G.write_text(SIGNERS_SIG_PATH, r.signers_sig)
		G.write_text(SIGNERS_PATH, r.signers_text)
		log_line("adopted the root's signer list issued %d" % int(r.issued))
	_load_trust()
	_load_mine()
	_remove_tree(ProjectSettings.globalize_path(META + "/staging"))
	var guard := get_node_or_null("/root/LanUpdateGuard")
	if guard != null and guard.has_method("watch"):
		guard.watch()
	log_line("UPDATED to %s (signed by %s) from %s: %d files changed, %d removed" % [ver_text(my_ver()), my_ver()[1],
		r.from, changed.size(), r.deletes.size()])
	_show_toast("Updated!", 4000)
	applied.emit(ver_text(my_ver()))
	announce()  # the lobby host passes it on to everyone else


## Does this script compile (as it is on disk now)? First a side-effect-free compile of a copy; a script that refers
## to its own type fails that way (the copy isn't "itself"), so then it's checked the way the gdev bridge will load
## it anyway: reloaded in place if the game has it loaded, else loaded. (A fresh CACHE_MODE_IGNORE load is NOT safe:
## loading a running script again that way wiped the running copy's constants.) guard.restore() reloads cached
## scripts with the old code, so a failed check leaves nothing broken. tests/lan_update_test.gd checks every script.
static func compiles(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if not text.contains('preload("%s")' % path):  # (self-referring scripts: straight to the real check, no false alarm)
		var copy := GDScript.new()
		copy.source_code = text
		if copy.reload() == OK:
			return true
	if path == "res://core/lan_update.gd":
		return false  # never reload the running updater under its own feet
	if ResourceLoader.has_cached(path):
		var s := load(path) as GDScript
		if s == null:
			return false
		s.source_code = text
		return s.reload(true) == OK and s.can_instantiate()
	var fresh := load(path) as GDScript
	return fresh != null and fresh.can_instantiate()


static func GUARD() -> GDScript:
	return load(GUARD_PATH) as GDScript


# --- Toast -----------------------------------------------------------------------

func _show_toast(text: String, ms: int) -> void:
	if DisplayServer.get_name() == "headless":
		toast_until = Time.get_ticks_msec() + ms
		return
	if toast == null or not is_instance_valid(toast):
		toast_layer = CanvasLayer.new()
		toast_layer.layer = 90
		add_child(toast_layer)
		toast = Label.new()
		toast.add_theme_font_size_override("font_size", 22)
		toast.add_theme_color_override("font_outline_color", Color.BLACK)
		toast.add_theme_constant_override("outline_size", 6)
		toast.modulate = Color(0.8, 0.95, 1.0, 0.85)
		toast_layer.add_child(toast)
		toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
		toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
		toast.position -= Vector2(24, 18)
	toast.text = text
	toast_until = Time.get_ticks_msec() + ms


func _update_toast(in_lobby: bool) -> void:
	if toast != null and is_instance_valid(toast):
		toast.visible = in_lobby and Time.get_ticks_msec() < toast_until


# --- Small helpers -----------------------------------------------------------------

static func log_line(msg: String) -> void:
	print("LanUpdate: " + msg)


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	for d in DirAccess.get_directories_at(abs_path):
		_remove_tree(abs_path.path_join(d))
	for f in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)
