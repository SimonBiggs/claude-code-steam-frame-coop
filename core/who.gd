extends RefCounted
## WHO joined / left: the ONE home for join / leave messages and seat labels across the arcade and every game
## (Simon, 2026-10-24: "x TV players joined" -> say who). Never write "TV player(s) joined" / "PLAYER 3 LEFT" by
## hand: tests/who_test.gd fails on new generic join / leave strings.
##
##   const Who := preload("res://core/who.gd")
##   _show_center(Who.joined(Who.seat(self, index)), 1.5)       # "David joined!"  /  "TV (P3) joined!"
##   _show_center(Who.left(Who.seat(self, index), "the crew"))  # "David left the crew"
##   _show_center(Who.left(net.last_left_name) + " - see you soon!")
##   Who.names_line(["TV", "David", "Simon"])                   # "TV, David and Simon"
##
## Names come from each machine (core/machine.gd display_name: "TV", "VR", the person on a Deck's hostname), sent
## with its hello (core/net.gd machine_name_of). A Deck is one person, so its seat is just "David"; the TV seats
## several pads, so its seats say "TV (P3)". In local play (nobody else networked) a seat is plain "P3".

## The person / machine on a seat: "David", "TV (P3)", "P3" (local play). main: the game (main.net, and main.seats
## for classic games or main.party for core/party.gd games say which machine owns the seat).
static func seat(main: Object, index: int) -> String:
	var net: Object = main.get("net") if main != null else null
	if net == null or str(net.get("mode")) == "local" or not net.has_method("machine_name_of"):
		return "P%d" % (index + 1)
	var owners := seat_owners(main)
	var peer := int(owners.get(index, owners.get(str(index), 1)))
	var mine := 0
	for k in owners:
		if int(owners[k]) == peer:
			mine += 1
	return seat_label(net.machine_name_of(peer), index, mine)


## "David" for a one-person machine (a Deck), "TV (P3)" for one that seats several pads (or has several seats now).
static func seat_label(machine: String, index: int, seats_on_machine: int = 1) -> String:
	if machine == "":
		return "P%d" % (index + 1)
	if seats_on_machine > 1 or machine.begins_with("TV"):
		return "%s (P%d)" % [machine, index + 1]
	return machine


## {seat index: owner peer id} on any machine. Classic games: main.seats.owners(); core/party.gd games: the
## party's "_seat_owners" store key. Seats missing here are the host's own (peer 1).
static func seat_owners(main: Object) -> Dictionary:
	var seats: Object = main.get("seats") if main != null else null
	if seats != null and seats.has_method("owners"):
		return seats.owners()
	var net: Object = main.get("net") if main != null else null
	return net.state_get("_seat_owners", {}) if net != null and net.has_method("state_get") else {}


## "David joined!"  /  "David joined the crew!"
static func joined(who: String, what: String = "") -> String:
	return "%s joined%s!" % [who, (" " + what) if what != "" else ""]


## "David left"  /  "David left the crew"
static func left(who: String, what: String = "") -> String:
	return "%s left%s" % [who, (" " + what) if what != "" else ""]


## "David", "David and TV", "TV, David and Simon".
static func names_line(names: Array) -> String:
	var n: Array[String] = []
	for x in names:
		if str(x) != "":
			n.append(str(x))
	if n.size() <= 1:
		return n[0] if n.size() == 1 else ""
	return ", ".join(n.slice(0, n.size() - 1)) + " and " + n[n.size() - 1]


## A machine that opened the pause menu: "PAUSED\nDavid opened the menu".
static func paused_by(who: String) -> String:
	return "%s opened the menu" % who
