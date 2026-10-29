extends RefCounted
## The arcade's services: nodes that live for the whole run, under the root with FIXED names (other code finds them
## by path, e.g. /root/SafeApply, so references survive a replace). Run by the frozen Boot autoload
## (addons/boot/boot.gd), which compiles THIS file whenever it changes (at a safe point: core/safe_apply.gd).
## Add a service = add a line here (and its script). No restart, no project.godot change.
## A service script may define:
##   _handoff() -> Dictionary  (it is being replaced: return what the new one needs)
##   _adopt(state: Dictionary)  (called on the new node before it enters the tree)
## Edits to a service's script reload in place (gdev bridge, gated by safe apply; a copy that doesn't compile is
## refused and the old one keeps running). A service whose script doesn't load is skipped and retried when its file
## changes. docs/MULTI_MACHINE.md "Everything hot-reloads".
##   name: node name under /root  path: script  meta: root meta older code uses to find it (kept pointing at it)
##   needs: only when this file exists

const SERVICES := [
	{"name": "RuntimeSettings", "path": "res://core/runtime_settings.gd"},
	{"name": "SafeApply", "path": "res://core/safe_apply.gd", "meta": "safe_apply"},
	{"name": "LanUpdate", "path": "res://core/lan_update.gd", "meta": "lan_update", "needs": "res://addons/lan_update/root.pub.pem"},
	{"name": "VrTextGuard", "path": "res://core/vr_text_guard.gd", "meta": "vr_text_guard"},
	{"name": "QuitAfter", "path": "res://core/quit_after.gd", "needs": "res://tests/bot_end.gd"},
]


static func sync(root: Node, boot: Node) -> void:
	var made: Dictionary = boot.get_meta("services", {})  # name -> path (the ones Boot made)
	var failed: Dictionary = boot.get_meta("services_failed", {})  # path -> mtime of the copy that didn't load
	var names := {}
	for e in SERVICES:
		var name := str(e.name)
		var path := str(e.path)
		names[name] = true
		if e.has("needs") and not FileAccess.file_exists(str(e.needs)):
			continue
		var n := root.get_node_or_null(name)
		if n == null and e.has("meta") and root.has_meta(e.meta):
			var m = root.get_meta(e.meta)
			if m is Node and is_instance_valid(m) and not m.is_queued_for_deletion():
				n = m  # made by older code under another name: keep it, don't make a second one
		if n != null and n.is_queued_for_deletion():
			continue
		var cur := ""
		if n != null and n.get_script() != null:
			cur = str((n.get_script() as Script).resource_path)
		if n != null and cur == path:
			made[name] = path
			continue
		var mt := FileAccess.get_modified_time(path)
		if int(failed.get(path, -1)) == mt or not ResourceLoader.exists(path):
			continue
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			failed[path] = mt
			print("Boot: service %s (%s) doesn't load (error above): skipped until the file changes" % [name, path])
			continue
		failed.erase(path)
		var nn: Node = s.new()
		if n != null:  # its script moved: replace it, handing over its state
			var state: Dictionary = n.call("_handoff") if n.has_method("_handoff") else {}
			if nn.has_method("_adopt"):
				nn.call("_adopt", state)
			n.name = name + "Old"
			n.queue_free()
			print("Boot: service %s replaced (%s -> %s)" % [name, cur, path])
		else:
			print("Boot: service %s started (%s)" % [name, path])
		nn.name = name
		root.add_child(nn)
		if e.has("meta"):
			root.set_meta(e.meta, nn)
		made[name] = path
	for name in made.keys():
		if names.has(name):
			continue
		var old := root.get_node_or_null(str(name))
		if old != null:
			print("Boot: service %s stopped (no longer in core/services.gd)" % name)
			old.queue_free()
		made.erase(name)
	boot.set_meta("services", made)
	boot.set_meta("services_failed", failed)
