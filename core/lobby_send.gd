extends RefCounted
## Sending RPCs only to machines whose connection is still up. A machine that is leaving (for a game, or quitting)
## stays in multiplayer.get_peers() for a moment while ENet disconnects it, and an RPC to it then prints an engine
## "ERROR: Unable to send packet on channel 0, max channels: 0" (the arcade lobby host telling the others who left,
## while they were leaving too: 2026-10-25 half-fixed by turning off server relay, 2026-11-26 seen again from
## _lobby_status). Use these instead of `.rpc(...)` / `.rpc_id(id, ...)` towards lobby machines;
## tests/lobby_send_test.gd fails a plain `.rpc(` in the arcade or core/safe_apply.gd.

## Is peer `id` connected right now (not connecting, not already disconnecting)?
static func live(mp: MultiplayerAPI, id: int) -> bool:
	var p := mp.multiplayer_peer if mp != null else null
	if p == null or p is OfflineMultiplayerPeer or p.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	if not id in mp.get_peers():
		return false
	if p is ENetMultiplayerPeer:
		var ep := (p as ENetMultiplayerPeer).get_peer(id)
		return ep != null and ep.get_state() == ENetPacketPeer.STATE_CONNECTED
	return true


## Every peer connected right now.
static func live_peers(mp: MultiplayerAPI) -> Array[int]:
	var out: Array[int] = []
	if mp == null:
		return out
	for id in mp.get_peers():
		if live(mp, id):
			out.append(id)
	return out


## node.method.rpc_id(id, args...) if `id` is still connected; false (nothing sent) if it isn't.
static func one(node: Node, id: int, method: StringName, args: Array = []) -> bool:
	if not live(node.multiplayer, id):
		return false
	node.callv("rpc_id", [id, method] + args)
	return true


## node.method.rpc(args...), but only to the peers still connected. Returns how many it went to.
static func all(node: Node, method: StringName, args: Array = []) -> int:
	var n := 0
	for id in live_peers(node.multiplayer):
		node.callv("rpc_id", [id, method] + args)
		n += 1
	return n