extends RefCounted
## Room sound while the Steam Frame streams: SteamVR makes its own "vrlink-sink" the DEFAULT PipeWire output, so every
## program on the Steam Machine that plays to "Default" ends up in the headset. A program that is for the people in the
## room (the TV screen core/tv_seat.gd starts, or a flat run while SteamVR still holds the sink) picks the room's
## output (HDMI = the TV) itself. ONE place for that choice (core/vr_watch.gd calls it too).
##   RoomAudio.use_room_output("TV seat") -> the device now in use ("" = none found: said in the log)
##   RoomAudio.choose(devices, current, default_sink) -> {"need": bool, "pick": String}  (pure, tests/tv_seat_test.gd)
## Godot's PulseAudio driver lists sinks by name ("alsa_output.pci-0000_04_00.1.hdmi-stereo", "vrlink-sink") plus
## "Default". Never a silent fallback: when sound is on the headset and nothing else exists, it says so.

const HEADSET_WORDS := ["vrlink", "steamvr", "steam frame", "steam_frame"]
const LAST_META := "room_audio_last"  # the last line said (each change is logged once, not every check)


## A sink that plays in the headset.
static func headset_output(device: String) -> bool:
	var d := device.to_lower()
	for w in HEADSET_WORDS:
		if d.contains(w):
			return true
	return false


## Whether `current` plays in the headset (directly, or "Default" while the default sink is the headset's), and the
## best room output among `devices`: an HDMI one (the TV) first, else any other that isn't the headset's.
static func choose(devices: Array, current: String, default_sink: String) -> Dictionary:
	var need := headset_output(current) or (current == "Default" and headset_output(default_sink))
	if not need:
		return {"need": false, "pick": current}
	var others: Array = []
	for d in devices:
		var s := str(d)
		if s != "Default" and not headset_output(s):
			others.append(s)
	for s in others:
		if s.to_lower().contains("hdmi"):
			return {"need": true, "pick": s}
	return {"need": true, "pick": str(others[0]) if not others.is_empty() else ""}


## The system's default output sink name ("" when PipeWire/PulseAudio can't be asked). Blocks a few ms.
static func default_sink() -> String:
	if OS.has_environment("ROOM_AUDIO_FAKE_DEFAULT"):
		return OS.get_environment("ROOM_AUDIO_FAKE_DEFAULT")
	var out := []
	if OS.execute("pactl", ["get-default-sink"], out, true) != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()


## Moves this program's sound to the room's output when it would play in the headset. Returns the device in use.
static func use_room_output(why: String) -> String:
	var cur := AudioServer.output_device
	var dflt := default_sink() if cur == "Default" else ""
	var r := choose(Array(AudioServer.get_output_device_list()), cur, dflt)
	var line := ""
	var result := cur
	if not bool(r.need):
		line = "RoomAudio (%s): sound plays on %s (not the headset)" % [why, cur if dflt == "" else "%s = %s" % [cur, dflt]]
	elif str(r.pick) == "":
		line = "RoomAudio (%s): sound would play in the HEADSET (%s) and there is no other output: it stays there" % [
			why, cur if dflt == "" else dflt]
		result = ""
	else:
		AudioServer.output_device = str(r.pick)
		line = "RoomAudio (%s): sound moved off the headset (%s) to %s" % [why, cur if dflt == "" else dflt, r.pick]
		result = str(r.pick)
	if str(Engine.get_meta(LAST_META, "")) != line:
		Engine.set_meta(LAST_META, line)
		print(line)
	return result
