extends Node
## In-game achievements (Steam achievements need a published Steam app). Decided on the host,
## saved in user://achievements.cfg, announced with a toast on every screen.

const LIST := [
	["first_blood", "FIRST BLOOD", "Defeat your first enemy"],
	["wave_5", "GETTING WARM", "Reach wave 5"],
	["wave_10", "DOUBLE DIGITS", "Reach wave 10"],
	["wave_15", "UNSTOPPABLE", "Reach wave 15"],
	["boss", "BOSS SLAYER", "Defeat a boss"],
	["fish_fry", "FISH FRY", "Shoot a fireball out of the sky"],
	["parry", "PARRY!", "Reflect an orb with the VR shield"],
	["reflect_kill", "RETURN TO SENDER", "Destroy an enemy with a reflected orb"],
	["teamwork", "TEAMWORK", "Revive your partner"],
	["beam_team", "BEAM TEAM", "Zap an enemy to death with the co-op beam"],
	["close_call", "CLOSE CALL", "Clear a wave with under 10 health"],
	["untouchable", "UNTOUCHABLE", "Clear a wave without anyone getting hurt"],
	["hoarder", "HOARDER", "Collect 10 pickups in one game"],
	["bomb_squad", "BOMB SQUAD", "Destroy 5 enemies within 2 seconds"],
	["high_score", "HIGH SCORER", "Score 25,000 points in one game"],
]
const SAVE := "user://achievements.cfg"

var main
var unlocked := {}
var kill_times: Array[float] = []
var pickups := 0
var wave_damage := 0.0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK:
		for key in cfg.get_section_keys("unlocked"):
			unlocked[key] = true


func unlock(key: String) -> void:
	if main.net.mode == "client" or unlocked.has(key):
		return
	for a in LIST:
		if a[0] == key:
			unlocked[key] = true
			var cfg := ConfigFile.new()
			for k in unlocked:
				cfg.set_value("unlocked", k, true)
			cfg.save(SAVE)
			print("Achievement: %s" % a[1])
			main.achievement_toast(a[1], a[2], unlocked.size(), LIST.size())
			return


func summary() -> String:
	return "Achievements: %d / %d" % [unlocked.size(), LIST.size()]


# --- Hooks called by the game ------------------------------------------------

func on_kill(points: int, radius: float) -> void:
	unlock("first_blood")
	if radius >= 1.5:
		unlock("boss")
	var now := Time.get_ticks_msec() / 1000.0
	kill_times.append(now)
	kill_times = kill_times.filter(func(t: float) -> bool: return now - t <= 2.0)
	if kill_times.size() >= 5:
		unlock("bomb_squad")
	if main.score >= 25000:
		unlock("high_score")


func on_wave_started(wave: int) -> void:
	wave_damage = 0.0
	if wave >= 5:
		unlock("wave_5")
	if wave >= 10:
		unlock("wave_10")
	if wave >= 15:
		unlock("wave_15")


func on_wave_cleared() -> void:
	if wave_damage <= 0.0:
		unlock("untouchable")
	for p in main.players:
		if not p.is_down and p.hp < 10.0:
			unlock("close_call")


func on_damage(amount: float) -> void:
	wave_damage += amount


func on_pickup() -> void:
	pickups += 1
	if pickups >= 10:
		unlock("hoarder")
