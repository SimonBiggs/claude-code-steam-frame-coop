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
## Party games: core/party.gd (no keyboard player). Classic games: core/classic_seats.gd deck_solo().
static func one_player_screen() -> bool:
	return kind() == "deck"


static func join_target() -> String:
	if OS.has_environment("DUO_SOLO"):
		return ""
	if OS.has_environment("DUO_JOIN"):
		return OS.get_environment("DUO_JOIN")
	return "auto"
