extends Node
## MECH TITANS mission flow (host / local): the steps of Data.MISSIONS (mini-kaiju waves, then the
## boss fight with extra minis now and then), the objective line, team score, the city-damage meter,
## the protected landmark, rescues, stars and the results (with parts to spend in the hangar).
## Everything the screens need goes into the net store, so the TV machine shows the same:
## "objective", "score", "cdmg" (city damage %), "landmark" (%), "rescued" / "rescue_total" (groups),
## "time" (s), "step", "results".

const Data := preload("res://games/mech_titans/data.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")

var main: Node
var index := 0
var info: Dictionary = {}
var step := -1
var step_t := 0.0
var extra_t := 0.0
var time := 0.0
var reboots := 0
var landmark_hp := 100.0
var score := 0
var active := false
var done_t := -1.0
var failed := false
var bosses_home := 0
var minis_home := 0
var _cdmg_t := 0.0
var _cdmg_dirty := false
var _rain_t := 0.0
var _warned_landmark := false
## PRACTICE warm-up before the first wave (teach by doing): 1 = punch the two bats in front of the
## canopy, 2 = beam the two far bats, 0 = off / done. Runs on mission 1 and on the first mission of a session.
var practice := 0
var practice_t := 0.0
var practice_ids: Array[int] = []


## Host: begin mission i (the city is already built for it).
func start(i: int) -> void:
	index = i
	info = Data.mission(i)
	step = -1
	step_t = 2.5
	extra_t = 0.0
	time = 0.0
	reboots = 0
	landmark_hp = 100.0
	score = 0
	active = true
	done_t = -1.0
	failed = false
	bosses_home = 0
	minis_home = 0
	_warned_landmark = false
	main.net.state_set("score", 0)
	main.net.state_set("landmark", 100 if String(info["protect"]) != "" else -1)
	main.net.state_set("cdmg", 0)
	main.net.state_set("time", 0)
	main.net.state_set("rescue_total", main.support.groups.size())
	main.net.state_set("rescued", 0)
	main.net.state_set("objective", "Get ready, Titans!")
	main.net.state_set("step", -1)
	practice_ids.clear()
	practice = 1 if (i == 0 or not main.has_meta("practiced")) else 0
	if bool(main.test_boss_only) and not bool(main.test_practice):
		practice = 0


func playing() -> bool:
	return active and step >= 0


func tick(delta: float) -> void:
	if not active:
		return
	time += delta
	if int(time) != int(main.net.state_get("time", 0)):
		main.net.state_set("time", int(time))
	if _cdmg_dirty:
		_cdmg_t -= delta
		if _cdmg_t <= 0.0:
			_cdmg_dirty = false
			_cdmg_t = 0.5
			main.net.state_set("cdmg", int(round(main.city.damage_percent())))
	if String(info.get("sky", "")) == "stormy":
		_rain_t += delta
		if _rain_t > 9.0:
			_rain_t = 0.0
			var fires: Array[int] = main.city.burning()
			if not fires.is_empty():
				main.combat.put_out(fires[0], -1)
	if done_t >= 0.0:
		done_t -= delta
		if done_t <= 0.0:
			finish(not failed)
		return
	step_t -= delta
	if step < 0:
		if step_t <= 0.0:
			if practice > 0:
				_practice_tick(delta)
			else:
				if bool(main.test_boss_only):
					step = maxi(step, (info["steps"] as Array).size() - 2)  # bots: straight to the boss fight
				_next_step()
		return
	var st: Dictionary = (info["steps"] as Array)[step]
	if st.has("extra"):
		var ex: Array = st["extra"]
		extra_t += delta
		if extra_t >= float(ex[2]) and main.combat.minis_alive() < 6:
			extra_t = 0.0
			main.combat.spawn_minis(String(ex[0]), int(ex[1]), false)
	_update_objective()
	if step_t <= 0.0 and main.combat.blocking_left() == 0:
		if step + 1 < (info["steps"] as Array).size():
			_next_step()
		else:
			done_t = 4.0
			main.net.state_set("objective", "ALL KAIJU SENT HOME!")


## The warm-up: glowing practice targets the pilot clears by doing (never blocks: 25 s per part).
func _practice_tick(delta: float) -> void:
	var vr: bool = main.vr_rig != null
	if practice_ids.is_empty():
		practice_t = 0.0
		var spots: Array[Vector3] = []
		if practice == 1:
			spots = [Vector3(-2.3, 6.0, -6.2), Vector3(2.3, 6.0, -6.2)]
			main.net.state_set("objective", "PRACTICE: punch the two glowing bats!")
			main.combat.announce("PRACTICE!", "PUNCH!", "info")
			main.hint_vr("practice_punch", "PUNCH! Throw a real punch" if vr else "X: PUNCH the bats")
			main.radio("Warm-up time, Titan! Punch those practice bats!")
			main.hint_tv("practice_tv", "The Titan is warming up: try your vehicle!")
		else:
			spots = [Vector3(-11.0, 10.0, -42.0), Vector3(11.0, 12.0, -46.0)]
			main.net.state_set("objective", "PRACTICE: beam the far bats!")
			main.combat.announce("BEAM!", "Point and pull the trigger" if vr else "RT: beam", "info")
			main.hint_vr("practice_beam", "TRIGGER: BEAM! Point your right hand" if vr else "RT: BEAM the far bats")
		for sp in spots:
			var k: Kaiju = main.combat.spawn_practice(sp)
			practice_ids.append(k.id)
		main.sfx.play("ui_notify", -2.0)
		return
	practice_t += delta
	var left := 0
	for id in practice_ids:
		var k: Kaiju = main.combat.kaiju.get(id, null)
		if k != null and k.state == "practice":
			left += 1
	if left > 0 and practice_t < 25.0:
		return
	for id in practice_ids:
		var k: Kaiju = main.combat.kaiju.get(id, null)
		if k != null and k.state == "practice":
			main.combat.send_home(k, false)
	practice_ids.clear()
	main.sfx.play("level_up" if left == 0 else "ui_notify", -2.0)
	main.cockpit_message("GREAT!" if left == 0 else "NICE TRY!", Color(0.5, 1.0, 0.6), 1.6)
	main.pulse(0, 0.6, 0.15)
	main.pulse(1, 0.6, 0.15)
	practice += 1
	if practice > 2:
		practice = 0
		main.set_meta("practiced", true)
		step_t = 2.0
		main.net.state_set("objective", "Warm-up done! Here they come!")
		main.radio("Great warm-up, Titans! Here they come!")
	else:
		step_t = 1.2


func _next_step() -> void:
	step += 1
	step_t = 3.0
	extra_t = 0.0
	main.net.state_set("step", step)
	var st: Dictionary = (info["steps"] as Array)[step]
	if st.has("say"):
		main.radio(String(st["say"]))
	if st.has("wave"):
		for w in st["wave"]:
			var arr: Array = w
			main.combat.spawn_minis(String(arr[0]), int(arr[1]), true)
		main.music.play_mood("battle")
		main.combat.announce("MINI KAIJU!", "Bonk them home!", "default")
	elif st.has("boss"):
		var list: Array = st["boss"]
		var names: Array[String] = []
		for i in list.size():
			var k: Kaiju = main.combat.spawn_boss(String(list[i]), i, list.size())
			names.append(String(k.info["name"]))
		main.net.state_set("boss_intro", [step, list])
		main.music.play_mood("boss")
	_update_objective()


func _update_objective() -> void:
	if step < 0:
		return
	var st: Dictionary = (info["steps"] as Array)[step]
	var text := ""
	if st.has("wave"):
		text = "Bonk the mini kaiju home: %d left" % main.combat.blocking_left()
	else:
		var names: Array[String] = []
		for k in main.combat.active_bosses():
			var kk: Kaiju = k
			if bool(kk.get_meta("blocking", true)) and not names.has(String(kk.info["name"])):
				names.append(String(kk.info["name"]))
		text = "Send %s home!" % " and ".join(names) if not names.is_empty() else "Nearly there!"
	if String(main.net.state_get("objective", "")) != text:
		main.net.state_set("objective", text)


## Extra mini kind for this mission (summons).
func extra_kind() -> String:
	for st in info.get("steps", []):
		var d: Dictionary = st
		if d.has("extra"):
			return String((d["extra"] as Array)[0])
	return "slimelet"


func add_score(by: int, pts: int, stat: String = "") -> void:
	if pts <= 0:
		return
	score += pts
	main.net.state_set("score", score)
	var who := by if by >= 0 else 0
	main.awards.add(who, "score", pts)
	if stat != "" and stat != "damage" and stat != "hits":
		main.awards.add(who, stat)


func on_kaiju_home(k: Kaiju) -> void:
	if k.is_mini:
		minis_home += 1
	else:
		bosses_home += 1


func on_city_changed() -> void:
	_cdmg_dirty = true


func damage_landmark(amount: float) -> void:
	if main.city.landmark == null or not active:
		return
	landmark_hp = maxf(0.0, landmark_hp - amount)
	main.city.landmark_hp = landmark_hp
	main.net.state_set("landmark", int(ceil(landmark_hp)))
	if landmark_hp < 40.0 and not _warned_landmark:
		_warned_landmark = true
		main.combat.announce("PROTECT THE %s!" % _landmark_name(), "Drones can repair it!", "defeat")
	if landmark_hp <= 0.0 and done_t < 0.0:
		failed = true
		done_t = 2.5
		main.net.state_set("objective", "Oh no! The %s is out of action!" % _landmark_name().to_lower())


func repair_landmark(amount: float) -> void:
	if main.city.landmark == null or landmark_hp <= 0.0:
		return
	landmark_hp = minf(100.0, landmark_hp + amount)
	main.city.landmark_hp = landmark_hp
	if int(ceil(landmark_hp)) != int(main.net.state_get("landmark", 0)):
		main.net.state_set("landmark", int(ceil(landmark_hp)))


func _landmark_name() -> String:
	return {"hospital": "HOSPITAL", "plant": "POWER PLANT", "dome": "MOON DOME"}.get(String(info.get("protect", "")), "CITY")


func on_reboot() -> void:
	reboots += 1


func on_citizens_changed() -> void:
	main.net.state_set("cit", main.support.citizen_states())
	main.net.state_set("rescued", main.support.rescued_groups())


# --- Results ------------------------------------------------------------------------------------------

## Is star rule [kind, value] met right now?
func rule_met(rule: Array) -> bool:
	var v := int(rule[1])
	match String(rule[0]):
		"damage":
			return main.city.damage_percent() < float(v)
		"rescue_all":
			return main.support.rescued_groups() >= main.support.groups.size()
		"no_reboot":
			return reboots == 0
		"protect":
			return landmark_hp >= float(v)
		"time":
			return time < float(v)
	return false


func finish(win: bool) -> void:
	active = false
	var stars := 0
	var lines: Array = []
	if win:
		stars = 1
		var s2: Array = info["star2"]
		var s3: Array = info["star3"]
		var ok2 := rule_met(s2)
		var ok3 := rule_met(s3)
		stars += (1 if ok2 else 0) + (1 if ok3 else 0)
		lines = [["MISSION DONE", "YES"], [Data.star_text(s2).to_upper(), "YES" if ok2 else "NO"], [Data.star_text(s3).to_upper(), "YES" if ok3 else "NO"]]
	var parts := (60 + stars * 40 + score / 25) if win else 30 + score / 50
	var title := "MISSION COMPLETE!" if win else "MISSION FAILED"
	var sub := "%d / 3 STARS" % stars if win else "Try again, Titans!"
	var stats: Array = [["STARS", "%d / 3" % stars], ["CITY DAMAGE", "%d%%" % int(round(main.city.damage_percent()))],
		["CITIZENS SAVED", str(main.support.rescued_groups() * 3)], ["TIME", Data.clock(time)], ["PARTS", "+%d" % parts]]
	var data: Dictionary = main.awards.results({"title": title, "subtitle": sub, "style": "victory" if win else "defeat",
		"stats": stats, "score_format": "%d PTS"})
	data["stars"] = stars
	data["mission"] = index
	data["win"] = win
	data["lines"] = lines
	data["parts"] = parts
	main.mission_finished(index, win, stars, parts, data)
