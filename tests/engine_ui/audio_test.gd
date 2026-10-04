extends "res://tests/engine_ui/part_base.gd"
## Audio part of the engine test: every core/sfx.gd sound and loop synthesises (not empty, not silent,
## not clipped); one-shot / 3D / loop playback; the classic API (DEFS, add_sound, streams, _make) still
## works; every core/music.gd mood synthesises at a sane level; crossfades, the victory jingle (with
## resume) and the classic play_track(0..2) all work.

const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")


func run() -> void:
	tag = "audio"
	var sfx: Node = SfxScript.new()
	add_child(sfx)
	await frames(1)
	for b in ["Music", "SFX", "UI"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	await _test_sounds(sfx)
	await _test_playback(sfx)
	_test_classic_sfx(sfx)
	await _test_music()


func _test_sounds(sfx: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var bad: Array[String] = []
	var names := SfxScript.list_sounds()
	for n in names:
		var st: AudioStream = sfx.get_stream(n)
		if not _sane(st as AudioStreamWAV, false):
			bad.append(n)
	check(bad.is_empty(), "all %d one-shot sounds synthesise, audible and unclipped %s" % [names.size(), bad])
	print("[audio] synthesised %d sounds in %d ms" % [names.size(), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	bad.clear()
	var loops := SfxScript.list_loops()
	for n in loops:
		var ls := sfx.get_loop_stream(n) as AudioStreamWAV
		if not _sane(ls, true):
			bad.append(n)
	check(bad.is_empty(), "all %d loops synthesise as seamless loops %s" % [loops.size(), bad])
	print("[audio] synthesised %d loops in %d ms" % [loops.size(), Time.get_ticks_msec() - t0])
	check(sfx.get_stream("no_such_sound") == null, "unknown sound -> null")
	check(SfxScript.bus_for("ui_move") == "UI" and SfxScript.bus_for("coin") == "SFX", "UI sounds route to the UI bus")
	# A second sfx node reuses the shared cache (same stream object).
	var other: Node = SfxScript.new()
	add_child(other)
	await frames(1)
	check(other.get_stream("coin") == sfx.get_stream("coin"), "synthesised sounds are shared across sfx nodes")
	other.queue_free()


func _test_playback(sfx: Node) -> void:
	for n in ["coin", "ui_move", "ui_select", "level_up", "shoot", "type"]:
		sfx.play(n, -6.0, 1.0)
	sfx.play("no_such_sound")
	# No current 3D camera here: play_at falls back to a flat voice faded by distance from `listener`.
	var lis := Node3D.new()
	add_child(lis)
	sfx.set("listener", lis)
	sfx.play_at("sword_hit", Vector3(3.0, 0.0, -4.0))
	var voices_3d: Array = sfx.get("voices_3d")
	check(voices_3d.is_empty(), "play_at without a 3D camera uses the flat fallback")
	var cam := Camera3D.new()
	lis.add_child(cam)
	cam.make_current()
	await frames(1)
	sfx.play_at("explosion", Vector3(5.0, 0.0, -10.0), -3.0, 0.9)
	voices_3d = sfx.get("voices_3d")
	check(voices_3d.size() == SfxScript.VOICES_3D, "play_at with a camera uses the 3D voice pool")
	var p3: AudioStreamPlayer3D = voices_3d[0]
	check(p3.global_position.distance_to(Vector3(5.0, 0.0, -10.0)) < 0.01, "3D voice placed at the sound position")
	# Loops: start, retarget, pitch, stop (fades then frees the player).
	sfx.play_loop("rain", -6.0, 0.2)
	sfx.play_loop("engine", -8.0, 0.0)
	check(sfx.is_looping("rain") and sfx.is_looping("engine"), "loops start")
	await wait(0.3)
	var rain: AudioStreamPlayer = sfx.loops["rain"]
	check(absf(rain.volume_db - -6.0) < 0.5, "loop faded in to its volume (%.1f dB)" % rain.volume_db)
	sfx.set_loop_pitch("engine", 1.4)
	check(absf((sfx.loops["engine"] as AudioStreamPlayer).pitch_scale - 1.4) < 0.001, "loop pitch follows set_loop_pitch")
	sfx.play_loop("rain", -12.0, 0.1)
	check(sfx.get_children().filter(func(c: Node) -> bool: return c.name == "Loop_rain").size() == 1, "replaying a loop reuses its player")
	sfx.stop_loop("rain", 0.2)
	check(not sfx.is_looping("rain"), "stop_loop ends the loop")
	await wait(0.4)
	check(not is_instance_valid(rain) or rain.is_queued_for_deletion(), "stopped loop player is freed after the fade")
	sfx.stop_all_loops(0.0)
	check(not sfx.is_looping("engine"), "stop_all_loops")
	var holder := Node3D.new()
	add_child(holder)
	var pl: AudioStreamPlayer3D = sfx.play_loop_at("fire", holder, -4.0)
	check(pl != null and pl.playing, "play_loop_at attaches a positional loop")
	sfx.stop_loop_at(holder, "fire")
	holder.queue_free()
	# Custom recipe and loop.
	sfx.add_recipe("zing", {"len": 0.3, "peak": 0.4, "layers": [{"w": "tri", "f": 880.0, "f1": 1760.0, "len": 0.25, "dec": 8.0}]})
	check(_sane(sfx.get_stream("zing") as AudioStreamWAV, false), "add_recipe makes a playable sound")
	sfx.add_loop("drone", {"len": 2.0, "loop": 0.0, "layers": [{"w": "sine", "f": 110.0, "vol": 0.5}]})
	sfx.play_loop("drone", -10.0)
	check(sfx.is_looping("drone"), "add_loop makes a playable loop")
	sfx.stop_loop("drone", 0.0)
	# Background warm-up.
	sfx.warm(["ui_open", "ui_close"], true)
	var deadline := Time.get_ticks_msec() + 10000
	while sfx.get("_bg_task") as int >= 0 and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(int(sfx.get("_bg_task")) < 0, "background warm() finishes")
	# Bus volume helpers.
	SfxScript.set_bus_volume("SFX", 0.5)
	check(absf(SfxScript.get_bus_volume("SFX") - 0.5) < 0.01, "set_bus_volume / get_bus_volume")
	SfxScript.set_bus_volume("SFX", 0.0)
	check(SfxScript.get_bus_volume("SFX") == 0.0, "bus volume 0 mutes")
	SfxScript.set_bus_volume("SFX", 1.0)
	check(absf(SfxScript.get_bus_volume("SFX") - 1.0) < 0.01, "bus volume restored")
	cam.queue_free()
	lis.queue_free()


func _test_classic_sfx(sfx: Node) -> void:
	var shoot := sfx.get_stream("shoot") as AudioStreamWAV
	check(shoot != null and shoot.mix_rate == 22050 and shoot.data.size() == int(0.07 * 22050) * 2, "DEFS sound 'shoot' unchanged (22050 Hz, 0.07 s)")
	sfx.add_sound("boop", [0.09, 620.0, 900.0, 0.3, "sine", 0.0])
	var streams: Dictionary = sfx.streams
	check(streams.has("boop"), "add_sound registers into streams")
	var w: AudioStreamWAV = sfx._make(0.1, 300.0, 600.0, 0.3, "square", 0.2)
	check(w.data.size() == int(0.1 * 22050) * 2, "_make still builds 6-value sweeps")
	streams["custom_raw"] = w
	sfx.play("custom_raw")
	sfx.play("pop")
	sfx.add_sound("pop", [0.15, 400.0, 1400.0, 0.3, "sine", 0.1])
	var pop := sfx.get_stream("pop") as AudioStreamWAV
	check(pop != null and pop.mix_rate == 22050, "a game's add_sound replaces a built-in of the same name")
	var before: AudioStream = sfx.get_stream("boop")
	sfx.add_sound("boop", [0.5, 100.0, 200.0, 0.3, "saw", 0.0])
	check(sfx.get_stream("boop") == before, "add_sound twice keeps the first definition (as before)")


func _test_music() -> void:
	var music: AudioStreamPlayer = MusicScript.new()
	add_child(music)
	check(music.has_method("play_track"), "music keeps play_track")
	music.play_mood("town")
	await frames(3)
	check(int(music.get("task")) < 0, "autoplay of track 0 is skipped when a mood was requested first")
	check(music.bus == "Music", "music plays on the Music bus")
	var moods := MusicScript.builtin_moods()
	var total_ms := 0
	for m in moods:
		music.prepare([m])
		var ok := await _wait_ready(music, m, 90.0)
		var st: AudioStreamWAV = music.get_mood_stream(m)
		var stats := _stats(st, 5)
		var ms := int((music.synth_ms as Dictionary).get(m, -1))
		total_ms += maxi(ms, 0)
		var def: Dictionary = music.get_def(m)
		var looped := bool(def.get("loop", true))
		check(ok and st != null and st.get_length() > 2.0, "mood '%s' synthesised (%.1f s, %d ms)" % [m, st.get_length() if st != null else 0.0, ms])
		check(stats.x <= 1.0 and stats.x > 0.3 and stats.y > 0.05 and stats.y < 0.3,
			"mood '%s' level sane (peak %.2f, rms %.3f)" % [m, stats.x, stats.y])
		check(looped == (st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD), "mood '%s' loop mode matches its definition" % m)
	print("[audio] all %d moods synthesised in %d ms total" % [moods.size(), total_ms])
	check(MusicScript.resolve("sleepy") == "cosy" and music.is_mood_ready("sleepy"), "mood aliases resolve")
	# Crossfade town -> battle.
	music.play_mood("town", 0.0)
	await frames(2)
	check(music.current_mood == "town", "town plays")
	music.play_mood("battle", 1.0)
	await frames(3)
	var decks := music.get_children().filter(func(c: Node) -> bool: return c is AudioStreamPlayer)
	var playing_n := decks.filter(func(c: AudioStreamPlayer) -> bool: return c.playing).size()
	check(music.current_mood == "battle" and playing_n == 2, "crossfade: both decks play during the fade")
	await wait(1.4)
	playing_n = decks.filter(func(c: AudioStreamPlayer) -> bool: return c.playing).size()
	check(playing_n == 1, "crossfade: old deck stops after the fade")
	music.volume_db = -20.0
	music.pitch_scale = 1.1
	await frames(2)
	var active: AudioStreamPlayer = decks.filter(func(c: AudioStreamPlayer) -> bool: return c.playing)[0]
	check(absf(active.volume_db - -20.0) < 0.5 and absf(active.pitch_scale - 1.1) < 0.001, "decks follow volume_db / pitch_scale")
	# Victory jingle, then back to battle (pitch 4 to run it faster).
	var finished: Array[String] = []
	music.jingle_finished.connect(func(m: String) -> void: finished.append(m))
	music.pitch_scale = 4.0
	music.play_mood("victory")
	await frames(2)
	check(music.current_mood == "victory", "victory jingle starts")
	var deadline := Time.get_ticks_msec() + 15000
	while finished.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	await frames(2)
	check(finished == ["victory"], "jingle_finished emitted")
	check(music.current_mood == "battle", "previous mood resumes after the jingle")
	music.pitch_scale = 1.0
	# Custom track.
	music.add_track({"name": "tiny", "bpm": 120.0, "key": 62, "chords": ["I", "IV", "V", "I"],
		"lead": {"inst": "square", "vol": 0.25, "style": "bouncy"}, "bass": {"inst": "sub", "vol": 0.4, "pattern": "octave"},
		"drums": {"style": "four", "vol": 0.5}})
	music.play_mood("tiny", 0.5)
	var ok_tiny := await _wait_ready(music, "tiny", 60.0)
	await frames(2)
	check(ok_tiny and music.current_mood == "tiny", "add_track + play_mood plays a custom track")
	check(music.list_moods().has("tiny"), "list_moods includes custom tracks")
	# Classic tracks still work (and fade the mood out).
	for i in 3:
		music.play_track(i)
		var dl := Time.get_ticks_msec() + 30000
		while int(music.get("current")) != i and Time.get_ticks_msec() < dl:
			await frames(1)
		check(int(music.get("current")) == i and music.playing, "play_track(%d) plays the classic track" % i)
		if i == 0:
			check(music.current_mood == "", "play_track fades moods out")
			var st0 := music.stream as AudioStreamWAV
			var s0 := _stats(st0, 5)
			print("[audio] classic track 0 level: peak %.2f rms %.3f" % [s0.x, s0.y])
	music.play_mood("cosy", 0.5)
	await frames(2)
	check(not music.playing and music.current_mood == "cosy", "a mood takes over from a classic track")
	music.fade_out(0.2)
	await wait(0.4)
	check(not music.is_music_playing(), "fade_out silences everything")
	music.queue_free()
	await frames(1)


func _wait_ready(music: Node, mood: String, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not music.is_mood_ready(mood) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return music.is_mood_ready(mood)


## A sound is sane when it has samples, is audible and stays below full scale (and loops if `looped`).
func _sane(st: AudioStreamWAV, looped: bool) -> bool:
	if st == null or st.data.size() < 64:
		return false
	var s := _stats(st, 1)
	if s.x < 0.05 or s.x > 1.0:
		return false
	if looped and st.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		return false
	return true


## Peak (x) and RMS (y) of a 16-bit stream, reading every `stride`-th sample.
func _stats(st: AudioStreamWAV, stride: int) -> Vector2:
	if st == null:
		return Vector2.ZERO
	var data := st.data
	var count := data.size() / 2
	var peak := 0.0
	var sum := 0.0
	var k := 0
	var i := 0
	while i < count:
		var v := data.decode_s16(i * 2) / 32767.0
		peak = maxf(peak, absf(v))
		sum += v * v
		k += 1
		i += stride
	return Vector2(peak, sqrt(sum / maxf(1.0, float(k))))
