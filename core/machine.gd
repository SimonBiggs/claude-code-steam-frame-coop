extends RefCounted
## What this machine is and how it networks, decided in code (not by the launcher), so it hot-reloads and every device
## uses one plain launcher (Simon, 2026-10-24: "just have one launcher", "start in local but always try and see if
## other devices are on the local network"). Env vars still override, for tests.
##   Machine.kind()        "frame" (headset on), "deck" (Steam Deck: DMI Jupiter / Galileo), else "tv"
##   Machine.join_target() "auto" = start playing locally at once and keep looking for other devices on the home
##                         network (join a lobby/game you find, or host so others find you); DUO_JOIN=<addr> forces
##                         one host; DUO_SOLO=1 never networks.

static func kind() -> String:
	if OS.has_environment("DUO_MACHINE_KIND"):
		return OS.get_environment("DUO_MACHINE_KIND")
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		return "frame"
	if not Engine.has_meta("machine_dmi_product"):  # read the hardware once (games ask every frame)
		Engine.set_meta("machine_dmi_product", FileAccess.get_file_as_string("/sys/devices/virtual/dmi/id/product_name").strip_edges())
	if str(Engine.get_meta("machine_dmi_product")) in ["Jupiter", "Galileo"]:
		return "deck"
	return "tv"


## One player per screen (Simon: "when I play on the deck I normally just have one player per deck"): a handheld
## starts local play with ONE player on its own controls, full screen; more pads drop in with A (split screen).
static func one_player_screen() -> bool:
	return kind() == "deck"


## Classic games (main.players, players[0] = the VR / keyboard seat, players[1] = the first pad): should player p get
## a split-screen view? On a handheld in local play the keyboard seat (players[0]) has no view unless a pad drives
## it, so the Deck's own controls (players[1]) play full screen. Use it wherever a view's visibility is decided.
## Decided every time it's asked (hot reload, pads coming and going).
static func view_on(main: Node, p: Object) -> bool:
	if main != null and not main.has_meta("view_watch") and one_player_screen():
		main.set_meta("view_watch", true)
		var w: Node = (load("res://core/view_watch.gd") as GDScript).new()
		w.set("main", main)
		w.name = "ViewWatch"
		main.add_child.call_deferred(w)
	if p == null or not is_instance_valid(p) or not _truthy(p.get("active")):
		return false
	if not one_player_screen() or p.get("index") == null or int(p.get("index")) != 0:
		return true
	var net: Variant = main.get("net") if main != null else null
	if not (net is Object) or str((net as Object).get("mode")) != "local":
		return true
	if _truthy(p.get("vr")) or _truthy(p.get("fake_vr")):
		return true
	return int(p.get("joy")) >= 0 if p.get("joy") is int else false


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is Object:
		return is_instance_valid(v)
	return v != null and v is int and v != 0


static func join_target() -> String:
	if OS.has_environment("DUO_SOLO"):
		return ""
	if OS.has_environment("DUO_JOIN"):
		return OS.get_environment("DUO_JOIN")
	return "auto"
