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
	return arg_int("--quit-after")


## An engine option's int value from this process's command line ("--x N" or "--x=N"), or -1 when not passed.
## (Also --fixed-fps for tests/bot_end.gd run_length.)
static func arg_int(flag: String) -> int:
	var v := engine_arg(flag)
	return int(v) if v != "" else -1


## An engine option's value from this process's own command line ("--x V" or "--x=V"), "" when not passed. The one
## place that reads engine options (--quit-after, --fixed-fps, --xr-mode: core/vr_watch.gd): OS.get_cmdline_args()
## leaves them out (2026-11-20: VrWatch looked for --xr-mode there, never found it and restarted in a loop).
static func engine_arg(flag: String) -> String:
	var args := PackedStringArray()
	var f := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	if f != null:
		var cur := PackedByteArray()
		for byte in f.get_buffer(65536):  # (/proc files read as length 0: ask for a block)
			if byte == 0:
				args.append(cur.get_string_from_utf8())
				cur.clear()
			else:
				cur.append(byte)
	for i in args.size():
		var a := str(args[i])
		if a == flag and i + 1 < args.size():
			return str(args[i + 1])
		if a.begins_with(flag + "="):
			return a.get_slice("=", 1)
	return ""


func _process(_delta: float) -> void:
	if Engine.get_process_frames() < at - MARGIN:
		return
	set_process(false)
	print("QUIT AFTER: frame %d of --quit-after %d, quitting quietly (core/quit_after.gd)" % [Engine.get_process_frames(), at])
	# quit_quietly has every bot say its BOT RESULT so far (tests/bot_kit.gd on_frame_limit, or the shared tally of
	# tests/bot_end.gd check() for bots without bot_kit), noting the cut-off, so it's never mistaken for a full run.
	load("res://tests/bot_end.gd").quit_quietly(get_tree(), 0, ", stopped at the --quit-after frame limit")
