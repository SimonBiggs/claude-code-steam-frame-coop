extends SceneTree
## core/bg_gen.gd: prefetched results come back the same as running the job now, once each; take() without a
## prefetch runs the job; kart_race cup tracks prefetched off the main thread match ones made on it, and so do
## balloon_pop rounds, marble_maze mazes, sheep_round_up fields and hide_and_seek houses (several jobs at once,
## through each game's own _gen_job / _house_job, so the threaded path is the one the game really uses).
const BgGen := preload("res://core/bg_gen.gd")
const Story := preload("res://games/kart_race/story.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const BalloonMain := preload("res://games/balloon_pop/main.gd")
const BalloonWaves := preload("res://games/balloon_pop/wavegen.gd")
const BalloonStory := preload("res://games/balloon_pop/story.gd")
const MarbleMain := preload("res://games/marble_maze/main.gd")
const MarbleStory := preload("res://games/marble_maze/story.gd")
const SheepMain := preload("res://games/sheep_round_up/main.gd")
const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const HideMain := preload("res://games/hide_and_seek/main.gd")
const HouseGen := preload("res://games/hide_and_seek/housegen.gd")


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
	fails.append_array(_games())
	BgGen.wait_all()
	if BgGen.pending() != 0:
		fails.append("jobs left after wait_all")
	print("BG GEN: %s (%d ms)%s" % ["PASS" if fails.is_empty() else "FAIL", (Time.get_ticks_usec() - t0) / 1000,
		"" if fails.is_empty() else "\n  " + "\n  ".join(fails)])
	quit(0 if fails.is_empty() else 1)


## Each game's threaded generator gives exactly what the main thread makes (all jobs queued at once).
func _games() -> Array[String]:
	var out: Array[String] = []
	var jobs: Array = []  # [key, threaded job, direct func]
	var met := {BalloonWaves.GRUMPY: true, BalloonWaves.ICE: true, BalloonWaves.GIANT: true}
	for k in 4:
		var plan := [BalloonStory.spec(String(BalloonStory.RIDES[k * 2].id), 15, met, 6, 120.0), {"k": "story", "ride": "", "seed": 70 + k}]
		jobs.append([BalloonMain._gen_key(plan), BalloonMain._gen_job(plan),
			func() -> Variant: return BalloonWaves.generate(70 + k, plan[0])])
	for i in [40, 61, 82]:
		var desc := {"k": "story", "i": i, "w": 4242}
		jobs.append(["mm" + var_to_str(desc), MarbleMain._gen_job(desc),
			func() -> Variant:
				var d := MarbleStory.maze(4242, i)
				d["shiny_color"] = MarbleStory.shiny_of(i)[1]
				return d])
	var dd := {"k": "daily", "d": "2026-10-31"}
	jobs.append(["mm" + var_to_str(dd), MarbleMain._gen_job(dd),
		func() -> Variant:
			var d := MarbleStory.daily("2026-10-31")
			d["shiny_color"] = MarbleStory.GOLDEN[1]
			return d])
	for lv in [6, 9, 12]:
		var desc := {"seed": 900 + lv, "spec": FieldGen.spec(lv, 6, 120.0)}
		jobs.append([SheepMain._gen_key(desc), SheepMain._gen_job(desc),
			func() -> Variant: return FieldGen.generate(900 + lv, desc.spec)])
	HouseGen.clear_cache()
	var houses: Array = []
	for lv in [5, 9, 13]:
		var sp := {"seed": 300 + lv, "level": lv, "theme": lv % 3, "daily": false}
		houses.append(sp)
		jobs.append([HideMain._house_key(sp), HideMain._house_job(sp), Callable()])
	for at in range(0, jobs.size(), BgGen.KEEP):  # (BgGen keeps KEEP finished results)
		var batch := jobs.slice(at, at + BgGen.KEEP)
		for j in batch:
			BgGen.prefetch(String(j[0]), j[1])
		for j in batch:
			var a: Variant = BgGen.take(String(j[0]), func() -> Variant: return null)
			if a == null:
				out.append("%s: prefetched result lost" % String(j[0]))
			elif (j[2] as Callable).is_valid() and var_to_str(a) != var_to_str((j[2] as Callable).call()):
				out.append("threaded result differs for %s" % String(j[0]))
	# hide_and_seek: the threaded house is remembered (build() then finds it) and matches a fresh main-thread one.
	var hits: Array = []
	for sp in houses:
		var t0 := Time.get_ticks_usec()
		var g := HouseGen.generate(int(sp.seed), sp)
		if Time.get_ticks_usec() - t0 > 1000:
			out.append("house %s was not remembered after its prefetch" % str(sp))
		hits.append(var_to_str(g))
	for k in houses.size():
		HouseGen.clear_cache()
		if hits[k] != var_to_str(HouseGen.generate(int(houses[k].seed), houses[k])):
			out.append("threaded house differs for %s" % str(houses[k]))
	return out
