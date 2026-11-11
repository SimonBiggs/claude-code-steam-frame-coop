extends Node
## One arcade machine's half of tools/telemetry-push-test: records 3 RUN lines, waits until core/telemetry_push.gd
## has found the (test) receiver on DUO_TELEMETRY_PORT by its UDP hello and sent them, then queues the first line
## AGAIN (a resend after a lost reply) plus one new line and waits for those too. The runner checks the receiver
## kept exactly 4 lines for this device and counted 1 duplicate. Needs DUO_TELEMETRY_PUSH_TEST=1 (own outbox, the
## real receiver refuses test lines). Ends itself: BOT RESULT.

const Push := preload("res://core/telemetry_push.gd")
const Telemetry := preload("res://core/telemetry.gd")
const BotEnd := preload("res://tests/bot_end.gd")


func _ready() -> void:
	_run.call_deferred()


func _wait_empty(s: float) -> bool:
	var until := Time.get_ticks_msec() + int(s * 1000)
	while Time.get_ticks_msec() < until:
		if Push.pending().is_empty():
			return true
		await get_tree().create_timer(0.25).timeout
	return false


func _end(ok: bool, what: String) -> void:
	print("BOT RESULT: %s telemetry_push %s (%s)" % ["PASS" if ok else "FAIL", Push.device(), what])
	BotEnd.quit_quietly(get_tree(), 0 if ok else 1)


func _run() -> void:
	if not Push.push_test():
		_end(false, "needs DUO_TELEMETRY_PUSH_TEST=1")
		return
	DirAccess.remove_absolute(Push.OUTBOX_TEST)
	DirAccess.remove_absolute(Push.META_TEST)
	var svc := get_tree().root.get_node_or_null("TelemetryPush")
	if svc == null:
		svc = Push.new()
		get_tree().root.add_child(svc)
	for i in 3:
		Telemetry.run("push_test", {"n": i, "mode": "bot"})
	var first := Push.pending()[0] if Push.pending().size() > 0 else ""
	if first == "" or Push.pending().size() != 3:
		_end(false, "3 lines weren't queued (%d)" % Push.pending().size())
		return
	if not await _wait_empty(30.0):
		_end(false, "first 3 never sent (%d waiting)" % Push.pending().size())
		return
	Push.enqueue(first)  # the same line again: the receiver must not store it twice
	Telemetry.run("push_test", {"n": 3, "mode": "bot"})
	if not await _wait_empty(30.0):
		_end(false, "resend never acknowledged (%d waiting)" % Push.pending().size())
		return
	_end(true, "4 lines sent, 1 resent")