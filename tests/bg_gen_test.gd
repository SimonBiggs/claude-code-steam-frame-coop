extends SceneTree
## core/bg_gen.gd: prefetched results come back the same as running the job now, once each; take() without a
## prefetch runs the job; kart_race cup tracks prefetched off the main thread match ones made on it.
const BgGen := preload("res://core/bg_gen.gd")
const Story := preload("res://games/kart_race/story.gd")
const Cups := preload("res://games/kart_race/cups.gd")


func _initialize() -> void:
	var fails: Array[String] = []
	BgGen.prefetch("sq", func() -> Variant: return 7 * 7)
	if BgGen.take("sq", func() -> Variant: return -1) != 49:
		fails.append("prefetched result lost")
	if BgGen.take("sq", func() -> Variant: return -1) != -1:
		fails.append("a result was handed out twice")
	if BgGen.take("none", func() -> Variant: return 3) != 3:
		fails.append("take() without prefetch did not run the job")
	var descs: Array = []
	for c in Cups.CUPS.size():
		descs.append(Cups.desc(5, c, 2, "zoom"))
	for d in descs:
		BgGen.prefetch(var_to_str(d), func() -> Variant: return Story.track_for(d))
	var t0 := Time.get_ticks_usec()
	for d in descs:
		var a: Array = BgGen.take(var_to_str(d), func() -> Variant: return [])
		var b: Array = Story.track_for(d)
		if a.is_empty() or var_to_str(a[0]) != var_to_str(b[0]) or a[1] != b[1]:
			fails.append("threaded track differs for %s" % str(d))
	BgGen.wait_all()
	if BgGen.pending() != 0:
		fails.append("jobs left after wait_all")
	print("BG GEN: %s (%d ms)%s" % ["PASS" if fails.is_empty() else "FAIL", (Time.get_ticks_usec() - t0) / 1000,
		"" if fails.is_empty() else "\n  " + "\n  ".join(fails)])
	quit(0 if fails.is_empty() else 1)
