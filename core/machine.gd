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
	var product := FileAccess.get_file_as_string("/sys/devices/virtual/dmi/id/product_name").strip_edges()
	if product in ["Jupiter", "Galileo"]:
		return "deck"
	return "tv"


static func join_target() -> String:
	if OS.has_environment("DUO_SOLO"):
		return ""
	if OS.has_environment("DUO_JOIN"):
		return OS.get_environment("DUO_JOIN")
	return "auto"
