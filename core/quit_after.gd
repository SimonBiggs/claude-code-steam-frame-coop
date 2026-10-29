extends Node
## Service: local test runs end at Godot's --quit-after N (frames). The engine's own stop there quits with sounds still
## playing, which leaks their AudioStreamWAV + playback ("WARNING: N ObjectDB instances were leaked at exit", every
## local bot run). So a little before frame N this quits through the quiet path instead (tests/bot_end.gd
## quit_quietly: stop every sound, let the audio thread drop them, quit with 0). Does nothing without --quit-after
## (the TV, Decks, VR never pass it). core/services.gd starts it only where tests/ exist.

## Frames before --quit-after's N to start quitting (quit_quietly itself waits 0.2 s, 12 frames at --fixed-fps 60).
const MARGIN := 30

var at := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	at = limit()
	set_process(at > 0)


## The --quit-after frame count, or -1 when not passed. Godot keeps engine options like --quit-after out of
## OS.get_cmdline_args(), so read the process's own command line (Linux; tests only run here).
static func limit() -> int:
	var args := PackedStringArray()
	var f := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	if f != null:
		var cur := PackedByteArray()
		for byte in f.get_buffer(65536):
			if byte == 0:
				args.append(cur.get_string_from_utf8())
				cur.clear()
			else:
				cur.append(byte)
	for i in args.size():
		var a := str(args[i])
		if a == "--quit-after" and i + 1 < args.size():
			return int(args[i + 1])
		if a.begins_with("--quit-after="):
			return int(a.get_slice("=", 1))
	return -1


func _process(_delta: float) -> void:
	if Engine.get_process_frames() < at - MARGIN:
		return
	set_process(false)
	print("QUIT AFTER: frame %d of --quit-after %d, quitting quietly (core/quit_after.gd)" % [Engine.get_process_frames(), at])
	load("res://tests/bot_end.gd").quit_quietly(get_tree(), 0)
