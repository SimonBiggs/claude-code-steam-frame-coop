extends SceneTree
## Story cards take turns in ONE place: core/story_card.gd (a newer card waits until the one showing has been read
## MIN_READ s; opts.urgent replaces at once; opts.hold waits while a game says so; StoryCard.later defers a beat to
## the next frame or until after a title). 15 games once kept their own queue + timer (story_queue / story_t, popped
## every 2.6-3.6 s), each slightly different, and their cards still raced the shared turn-taking (2026-11-14). Static
## scan of games/ and arcade/: no script counts down its own story timer or pops its own story queue.
##   godot-test --headless --path . -s res://tests/story_queue_test.gd   -> STORY QUEUE: PASS / FAIL

var fails: Array[String] = []


func _initialize() -> void:
	var files: Array[String] = []
	for d in ["res://games", "res://arcade"]:
		_collect(d, files)
	var timer_re := RegEx.create_from_string("(?m)^\\s*(story|card|beat)_(t|cd|timer|wait)\\s*-=\\s*delta")
	var pop_re := RegEx.create_from_string("(story|card|beat)_?(queue|q)\\w*\\.pop_front\\(")
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var m := timer_re.search(src)
		if m != null:
			fails.append("%s counts down its own story timer (%s): call StoryCard.show / show_vr (or StoryCard.later) and let core/story_card.gd pace the cards" % [path, m.get_string().strip_edges()])
		m = pop_re.search(src)
		if m != null:
			fails.append("%s pops its own story queue (%s): StoryCard's shared queue takes turns (opts.urgent / opts.hold / StoryCard.later)" % [path, m.get_string()])
	for f in fails:
		print("  FAIL ", f)
	print("STORY QUEUE: %s (%d scripts)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), files.size()])
	quit(0 if fails.is_empty() else 1)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)