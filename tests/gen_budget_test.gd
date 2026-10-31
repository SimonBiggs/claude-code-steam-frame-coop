extends SceneTree
## Frame budget for round-start generators (🐜 guard, 2026-10-31). A game that builds its procedural round in
## ONE frame at round start hitches on a Steam Deck (2-3x slower than the Steam Machine). For every generator
## entry point a game's main.gd calls when a round starts, this times the worst of SEEDS seeds (default 20) at
## the hardest spec, and FAILS when that worst case is over BUDGET_MS here and the game's main.gd does not run
## it through core/bg_gen.gd (BgGen.prefetch / take: made on a worker thread before the round starts).
## It also FAILS when a games/*/*gen.gd file has no entry below (add one when you write a new generator).
##   godot-test --headless --path . -s res://tests/gen_budget_test.gd      (SEEDS=40 for a closer look)
## Each entry: [game, generator file, label, func(seed) -> Variant]. The worst seed is re-timed twice (the
## fastest of the three counts) so a busy machine doesn't fail it.

const BUDGET_MS := 40.0

const BalloonWaves := preload("res://games/balloon_pop/wavegen.gd")
const BalloonStory := preload("res://games/balloon_pop/story.gd")
const MazeGen := preload("res://games/marble_maze/mazegen.gd")
const MarbleStory := preload("res://games/marble_maze/story.gd")
const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const HouseGen := preload("res://games/hide_and_seek/housegen.gd")
const HideStory := preload("res://games/hide_and_seek/story.gd")
const KartStory := preload("res://games/kart_race/story.gd")
const BeeGardenGen := preload("res://games/bee_garden/gardengen.gd")
const BlockCourseGen := preload("res://games/block_builders/coursegen.gd")
const BathGen := preload("res://games/bubble_bath/bathgen.gd")
const VoyageGen := preload("res://games/cannon_cove/voyagegen.gd")
const SagaGen := preload("res://games/crystal_saga/sagagen.gd")
const CourtGen := preload("res://games/dodge_ball/courtgen.gd")
const RouteGen := preload("res://games/dragon_rider/routegen.gd")
const DragonMain := preload("res://games/dragon_rider/main.gd")
const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const TempleWaves := preload("res://games/elemental_bender/wavegen.gd")
const LakeGen := preload("res://games/fishing_lake/lakegen.gd")
const HarvestGen := preload("res://games/fruit_catch/harvestgen.gd")
const GhostHouseGen := preload("res://games/ghost_lantern/housegen.gd")
const RaidGen := preload("res://games/giants_table/raidgen.gd")
const MechRoundGen := preload("res://games/mech_titans/roundgen.gd")
const HoleGen := preload("res://games/mini_golf_party/holegen.gd")
const RushCourseGen := preload("res://games/obstacle_rush/coursegen.gd")
const PaintGen := preload("res://games/paint_and_guess/paintgen.gd")
const PlaneStory := preload("res://games/paper_planes/story.gd")
const SnowStory := preload("res://games/snowman_maker/story.gd")
const SkyGen := preload("res://games/paper_planes/skygen.gd")
const PartyGen := preload("res://games/party_board/partygen.gd")
const PartyBoardData := preload("res://games/party_board/board_data.gd")
const MatchGen := preload("res://games/penalty_shootout/matchgen.gd")
const SongGen := preload("res://games/rhythm_band/songgen.gd")
const RocketGen := preload("res://games/rocket_workshop/rocketgen.gd")
const CoasterGen := preload("res://games/roller_coaster/coastergen.gd")
const SiegeGen := preload("res://games/snowball_blitz/siegegen.gd")
const SnowGardenGen := preload("res://games/snowman_maker/gardengen.gd")
const MissionGen := preload("res://games/starship_crew/missiongen.gd")
const TownIslandGen := preload("res://games/tiny_town_tycoon/islandgen.gd")
const TowerGen := preload("res://games/tower_stack/towergen.gd")
const DigIslandGen := preload("res://games/treasure_dig/islandgen.gd")
const DigStory := preload("res://games/treasure_dig/story.gd")
const MoleGen := preload("res://games/whack_a_mole/roundgen.gd")
const MoleStory := preload("res://games/whack_a_mole/story.gd")


func _entries() -> Array:
	var out: Array = []
	# --- balloon_pop: WaveGen.generate(seed, Story.spec(ride, built, met, players, time)) in _start_play.
	var met := {BalloonWaves.GRUMPY: true, BalloonWaves.ICE: true, BalloonWaves.GIANT: true}
	out.append(["balloon_pop", "wavegen.gd", "WaveGen.generate (any ride, 15 built, 6 players, 120 s)",
		func(s: int) -> Variant:
			var r: Dictionary = BalloonStory.RIDES[s % BalloonStory.RIDES.size()]
			return BalloonWaves.generate(s, BalloonStory.spec(String(r.id), 15, met, 6, 120.0))])
	# --- marble_maze: Story.maze(world, i) / Story.daily() -> MazeGen.generate in def_from_desc.
	# The slowest story mazes (measured over 40 seeds, 2026-10-31): the third maze of places 4 and 6 on laps 1-3.
	out.append(["marble_maze", "mazegen.gd", "MazeGen.generate (slowest story mazes 39-41, 60-62, 81-83)",
		func(s: int) -> Variant:
			var hard: Array[int] = [39, 40, 41, 60, 61, 62, 81, 82, 83]
			return MazeGen.generate(s, MarbleStory.spec(hard[s % hard.size()]))])
	# --- sheep_round_up: FieldGen.generate(seed, spec) in _apply_field.
	out.append(["sheep_round_up", "fieldgen.gd", "FieldGen.generate (levels 6..12, 6 players)",
		func(s: int) -> Variant: return FieldGen.generate(s, FieldGen.spec(6 + s % 7, 6, 120.0))])
	# --- hide_and_seek: HouseGen.generate (map_house.gd) in _build_map, cold cache.
	out.append(["hide_and_seek", "housegen.gd", "HouseGen.generate (houses 5..14, cold cache)",
		func(s: int) -> Variant:
			HouseGen.clear_cache()
			return HouseGen.generate(s, {"seed": s, "level": 5 + s % 10, "theme": s % HideStory.THEMES.size()})])
	# --- kart_race: Story.track_for(desc) -> trackgen.gd in _build_desc.
	out.append(["kart_race", "trackgen.gd", "Story.track_for (story tracks, later worlds)",
		func(s: int) -> Variant: return KartStory.track_for(KartStory.story_desc(s, 6 + s % 18))])
	# --- bee_garden: GardenGen.generate(seed, Story.spec) in _new_garden, then GardenGen.day_plan each round.
	out.append(["bee_garden", "gardengen.gd", "GardenGen.generate (3 kinds, level 12+)",
		func(s: int) -> Variant: return BeeGardenGen.generate(s, {"kinds": 3, "level": 12 + s % 10, "bees": 6})])
	out.append(["bee_garden", "gardengen.gd", "GardenGen.day_plan (late rounds, 6 bees)",
		func(s: int) -> Variant:
			var sp := {"kinds": 3, "level": 12 + s % 10, "bees": 6}
			return BeeGardenGen.day_plan(BeeGardenGen.generate(s, sp), 8 + s % 8, sp)])
	# --- block_builders: Story.course(world, i) -> CourseGen.generate(seed, adv).
	out.append(["block_builders", "coursegen.gd", "CourseGen.generate (adventures 6..12)",
		func(s: int) -> Variant: return BlockCourseGen.generate(s, 6 + s % 7)])
	# --- bubble_bath: BathGen.plan(bath_seed, n) at each round.
	out.append(["bubble_bath", "bathgen.gd", "BathGen.plan (rounds 6..12)",
		func(s: int) -> Variant: return BathGen.plan(s, 6 + s % 7)])
	# --- cannon_cove: VoyageGen.wave_plan(seed, wave, simple, crew_extra) each wave.
	out.append(["cannon_cove", "voyagegen.gd", "VoyageGen.wave_plan (waves 8..16, full crew)",
		func(s: int) -> Variant: return VoyageGen.wave_plan(s, 8 + s % 9, s % 2 == 0, 4)])
	# --- crystal_saga: SagaGen.generate(seed, tier) at journey start.
	out.append(["crystal_saga", "sagagen.gd", "SagaGen.generate (tiers 3..5)",
		func(s: int) -> Variant: return SagaGen.generate(s, SagaGen.TIERS - 1 - s % 3)])
	# --- dodge_ball: CourtGen.build(code) each round.
	out.append(["dodge_ball", "courtgen.gd", "CourtGen.build (levels 4..6)",
		func(s: int) -> Variant: return CourtGen.build(CourtGen.code_of(s, CourtGen.MAX_LEVEL - s % 3, false))])
	# --- dragon_rider: course.gd RouteGen.route(seed, origin, yaw, lv, mission, simple) each stage.
	out.append(["dragon_rider", "routegen.gd", "RouteGen.route (stages 7..12)",
		func(s: int) -> Variant:
			var lv := RouteGen.MAX_STAGE - s % 6
			return RouteGen.route(s, Vector3(0, 45, 0), 0.3 * s, lv, DragonMain.mission_for(lv), s % 2 == 0)])
	# --- dungeon_delve: deep.gd load_floor -> FloorGen.generate(seed, zone, floor, heroic, kind).
	out.append(["dungeon_delve", "floorgen.gd", "FloorGen.generate (late zones + endless depths, heroic)",
		func(s: int) -> Variant:
			return FloorGen.generate(s, 2 + s % 4, s % FloorGen.FLOORS_PER_ZONE, true, "floor")])
	# --- elemental_bender: WaveGen.plan(temple_seed, wave, players, fast) each wave.
	out.append(["elemental_bender", "wavegen.gd", "WaveGen.plan (waves 9..15, 6 players)",
		func(s: int) -> Variant: return TempleWaves.plan(s, TempleWaves.MAX_WAVE - s % 7, 6, s % 2 == 0)])
	# --- fishing_lake: LakeGen.generate(seed, {level, wish}) each lake.
	out.append(["fishing_lake", "lakegen.gd", "LakeGen.generate (level 3, wishes)",
		func(s: int) -> Variant:
			var sp := LakeGen.species()
			return LakeGen.generate(s, {"level": 3, "wish": sp[s % sp.size()] if s % 3 else -1})])
	# --- fruit_catch: G.harvest(seed, lv, daily, round_time) each round.
	out.append(["fruit_catch", "harvestgen.gd", "Harvest.harvest (levels 4..6, 120 s)",
		func(s: int) -> Variant: return HarvestGen.harvest(s, HarvestGen.MAX_LEVEL - s % 3, false, HarvestGen.ROUND_SECS)])
	# --- ghost_lantern: HouseGen.generate(seed, {level}) per house, cold caches.
	out.append(["ghost_lantern", "housegen.gd", "HouseGen.generate (level 3+, cold cache)",
		func(s: int) -> Variant:
			GhostHouseGen._free_cache = PackedByteArray()
			GhostHouseGen._ring_cache = []
			return GhostHouseGen.generate(s, {"level": 3 + s % 4})])
	# --- giants_table: RaidGen.plan(raid_seed, wave, extra, solo) each wave.
	out.append(["giants_table", "raidgen.gd", "RaidGen.plan (waves 8..14, 4 extra knights)",
		func(s: int) -> Variant: return RaidGen.plan(s, RaidGen.MAX_WAVE - s % 7, 4, false)])
	# --- mech_titans: RoundGen.make(i, run_seed, friends, mode) each round.
	out.append(["mech_titans", "roundgen.gd", "RoundGen.make (rounds 10..39, mega, 20 friends)",
		func(s: int) -> Variant: return MechRoundGen.make(10 + s % 30, s, 20, "mega" if s % 2 else "brave")])
	# --- mini_golf_party: HoleGen.hole(course_seed, i, level) each hole.
	out.append(["mini_golf_party", "holegen.gd", "HoleGen.hole (level 4, any hole)",
		func(s: int) -> Variant: return HoleGen.hole(s, s % HoleGen.HOLES, HoleGen.MAX_LEVEL)])
	# --- obstacle_rush: CourseGen.make(story desc) == CourseGen.generate(seed, tier).
	out.append(["obstacle_rush", "coursegen.gd", "CourseGen.generate (top tiers)",
		func(s: int) -> Variant: return RushCourseGen.generate(s, RushCourseGen.tier_count() - 1 - s % 2)])
	# --- paint_and_guess: PaintGen.build(plan_code) per game.
	out.append(["paint_and_guess", "paintgen.gd", "PaintGen.build (all themes)",
		func(s: int) -> Variant: return PaintGen.build(PaintGen.code_of(s, PaintGen.BASE_THEMES + 2 + s % 2, false))])
	# --- paper_planes: SkyGen.flight(seed, chapter, {lucky}) each flight.
	out.append(["paper_planes", "skygen.gd", "SkyGen.flight (late chapters, lucky)",
		func(s: int) -> Variant: return SkyGen.flight(s, PlaneStory.CHAPTERS.size() - 1 - s % 2, {"lucky": s % 2 == 0})])
	# --- party_board: PartyGen.generate(data, seed, desc) per party.
	var board := PartyBoardData.new()
	out.append(["party_board", "partygen.gd", "PartyGen.generate (level 20, 8 rounds)",
		func(s: int) -> Variant: return PartyGen.generate(board, s, {"level": 8 + (s % 2) * 12, "rounds": 8})])
	# --- penalty_shootout: MatchGen.plan(cup_seed, n) each match.
	out.append(["penalty_shootout", "matchgen.gd", "MatchGen.plan (matches 4..8)",
		func(s: int) -> Variant: return MatchGen.plan(s, MatchGen.MAX_MATCH - s % 5)])
	# --- rhythm_band: SongGen.build(code, tour_pos, bars, simple) each song.
	out.append(["rhythm_band", "songgen.gd", "SongGen.build (tour 5..9)",
		func(s: int) -> Variant:
			var pos := 5 + s % 5
			return SongGen.build(SongGen.code_at(s, pos, false), pos, -1, s % 2 == 0)])
	# --- rocket_workshop: G.rocket(seed, n, crew, simple, launched, daily) each rocket.
	out.append(["rocket_workshop", "rocketgen.gd", "RocketGen.rocket (rockets 10..16, 6 crew)",
		func(s: int) -> Variant: return RocketGen.rocket(s, 10 + s % 7, 6, s % 2 == 0, 60)])
	# --- roller_coaster: CoasterGen.section(seed, base, k) each plan.
	out.append(["roller_coaster", "coastergen.gd", "CoasterGen.section (k 3..5 from practice base)",
		func(s: int) -> Variant: return CoasterGen.section(s, CoasterGen.practice_base(), 3 + s % 3)])
	# --- snowball_blitz: SiegeGen.siege(seed, lv, daily) per siege.
	out.append(["snowball_blitz", "siegegen.gd", "SiegeGen.siege (level 3..4)",
		func(s: int) -> Variant: return SiegeGen.siege(s, SiegeGen.MAX_LEVEL - s % 2)])
	# --- snowman_maker: GardenGen.garden(seed, chapter) per garden.
	out.append(["snowman_maker", "gardengen.gd", "GardenGen.garden (late chapters)",
		func(s: int) -> Variant: return SnowGardenGen.garden(s, SnowStory.CHAPTERS.size() - 1 - s % 2)])
	# --- starship_crew: MissionGen.generate(seed, kind, tier, lap) per mission.
	out.append(["starship_crew", "missiongen.gd", "MissionGen.generate (any kind, top tiers, lap 7)",
		func(s: int) -> Variant:
			return MissionGen.generate(s, MissionGen.KINDS[s % MissionGen.KINDS.size()], MissionGen.TIERS - 1 - s % 2, 7)])
	# --- tiny_town_tycoon: IslandGen.generate(seed) for a new town.
	out.append(["tiny_town_tycoon", "islandgen.gd", "IslandGen.generate",
		func(s: int) -> Variant: return TownIslandGen.generate(s)])
	# --- tower_stack: G.site(seed, lv, daily) per job.
	out.append(["tower_stack", "towergen.gd", "TowerGen.site (levels 4..6)",
		func(s: int) -> Variant: return TowerGen.site(s, TowerGen.MAX_LEVEL - s % 3)])
	# --- treasure_dig: IslandGen.generate(seed, desc) per island.
	out.append(["treasure_dig", "islandgen.gd", "IslandGen.generate (any island, level 8..30)",
		func(s: int) -> Variant:
			return DigIslandGen.generate(s, {"kind": DigStory.ISLANDS[s % DigStory.ISLANDS.size()].id, "level": [8, 30][s % 2]})])
	# --- whack_a_mole: RoundGen.generate(seed, Story.spec(crop, beds, met, players, time)) each round.
	var mole_met := {MoleGen.HELMET: true, MoleGen.SPEEDY: true}
	out.append(["whack_a_mole", "roundgen.gd", "RoundGen.generate (any crop, 15 beds, 6 players, 120 s)",
		func(s: int) -> Variant:
			var c: Dictionary = MoleStory.CROPS[s % MoleStory.CROPS.size()]
			return MoleGen.generate(s, MoleStory.spec(c.id, 15, mole_met, 6, 120.0))])
	return out


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 20
	var t_all := Time.get_ticks_msec()
	var fails: Array[String] = []
	var rows: Array = []
	var covered := {}
	for e in _entries():
		var game := String(e[0])
		var job: Callable = e[3]
		covered["res://games/%s/%s" % [game, String(e[1])]] = true
		var cold := _time(job, 1000003)  # the first call pays any one-time setup (data loads, static caches)
		var worst := 0.0
		var worst_s := 0
		var total := 0.0
		for s in seeds:
			var ms := _time(job, s)
			total += ms
			if ms > worst:
				worst = ms
				worst_s = s
		worst = minf(worst, minf(_time(job, worst_s), _time(job, worst_s)))
		var main_src := FileAccess.get_file_as_string("res://games/%s/main.gd" % game)
		var threaded := main_src.contains("BgGen.")
		rows.append([worst, "%-16s %7.1f ms max  %6.1f ms mean  %6.1f ms first call  %s  %s" % [game, worst, total / seeds,
			cold, "BgGen" if threaded else "MAIN THREAD", String(e[2])]])
		if cold > BUDGET_MS * 2.0 and cold > worst * 2.0 and not threaded:
			print("  (note) %s: the first call takes %.0f ms (one-time setup): that hitches the first round once" % [game, cold])
		if worst > BUDGET_MS and not threaded:
			fails.append("%s: %s takes up to %.0f ms (seed %d) in one frame at round start (budget %d ms here, Decks are 2-3x slower): run it through core/bg_gen.gd (BgGen.prefetch when the next round is known, BgGen.take at round start) or make it cheaper" % [
				game, String(e[2]), worst, worst_s, int(BUDGET_MS)])
	for dir in DirAccess.get_directories_at("res://games"):
		for f in DirAccess.get_files_at("res://games/" + dir):
			var path := "res://games/%s/%s" % [dir, f]
			if f.ends_with("gen.gd") and not covered.has(path):
				fails.append("%s has no entry in tests/gen_budget_test.gd (time its round-start entry point there)" % path)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for r in rows:
		print("  " + String(r[1]))
	for f in fails:
		print("SCRIPT ERROR: GEN BUDGET " + f)
	print("GEN BUDGET: %s (%d generators, %d seeds, %d ms)" % ["PASS" if fails.is_empty() else "FAIL", rows.size(), seeds,
		Time.get_ticks_msec() - t_all])
	quit(0 if fails.is_empty() else 1)


func _time(job: Callable, s: int) -> float:
	var t0 := Time.get_ticks_usec()
	job.call(s)
	return (Time.get_ticks_usec() - t0) / 1000.0
