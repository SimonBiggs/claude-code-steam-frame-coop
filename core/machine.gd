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


## This machine's short name for join / leave messages and seat labels (core/who.gd): "TV" (the Steam Machine
## and any other big-screen machine), "VR" (the Frame), and for a Steam Deck the person in its hostname
## ("david-steamdeck" -> "David", "nathanael-deck" -> "Nathanael"; a plain "steamdeck" -> "Deck"), so any new
## Deck is named without a list to update. DUO_MACHINE_NAME overrides it (tests, or a nickname); a comma list
## ("TV,David,Simon") gives each test machine its own, picked by BOT_MACHINE (tools/multibot.ts).
static func display_name(k: String = "") -> String:
	if OS.has_environment("DUO_MACHINE_NAME"):
		var names := OS.get_environment("DUO_MACHINE_NAME").split(",")
		var i := clampi(int(OS.get_environment("BOT_MACHINE")), 0, names.size() - 1)
		if names[i].strip_edges() != "":
			return names[i].strip_edges()
	if k == "":
		k = kind()
	if k == "frame":
		return "VR"
	if k != "deck":
		return "TV"
	var host := OS.get_environment("DUO_HOSTNAME") if OS.has_environment("DUO_HOSTNAME") \
		else FileAccess.get_file_as_string("/etc/hostname")
	return name_from_hostname(host, k)


## "david-steamdeck" -> "David", "Simon-SteamDeck" -> "Simon", "steamdeck" -> "Deck" (k: the machine's kind).
static func name_from_hostname(host: String, k: String = "deck") -> String:
	var h := host.strip_edges().to_lower().split(".")[0] if host.strip_edges() != "" else ""
	for word in ["steam-deck", "steamdeck", "steam-machine", "steammachine", "deck", "frame", "oled", "lcd"]:
		h = h.replace(word, " ")
	var person := ""
	for part in h.replace("-", " ").replace("_", " ").split(" ", false):
		if part.length() >= 2 and not part.is_valid_int() and part not in ["s", "the", "my"]:
			person = part
			break
	if person == "":
		return {"deck": "Deck", "frame": "VR"}.get(k, "TV")
	return person.capitalize()
