extends Node
## Sequencer: runs game-flow steps one after another in _process, so the flow pauses with the game
## (no awaits on timers that would resume on a freed scene). Steps added WHILE a step runs are
## inserted right after it, in order, so a step can expand into sub-steps like a coroutine:
##   seq.add(func() -> void: announce())
##   seq.wait(1.5)
##   seq.until(func() -> bool: return dice_done, 20.0, auto_roll)   # optional timeout + fallback
## Host / local only (the TV machine never runs game flow).

var _steps: Array = []  # [kind, Callable/float, float timeout, Callable on_timeout, float elapsed]
var _insert_at := -1  # >= 0 while a call step runs: where its sub-steps go
var _running := false


## Run fn once (it may add more steps: they run before the ones already queued).
func add(fn: Callable) -> void:
	_push(["call", fn, 0.0, Callable(), 0.0])


## Wait `seconds` of game time.
func wait(seconds: float) -> void:
	_push(["wait", Callable(), seconds, Callable(), 0.0])


## Wait until cond() is true. With timeout > 0, give up after that many seconds and call on_timeout.
func until(cond: Callable, timeout: float = -1.0, on_timeout: Callable = Callable()) -> void:
	_push(["until", cond, timeout, on_timeout, 0.0])


## Drop every queued step (a new phase starts).
func clear() -> void:
	_steps.clear()
	_insert_at = -1


## True while steps are queued.
func busy() -> bool:
	return not _steps.is_empty()


## How many steps are queued (debugging).
func size() -> int:
	return _steps.size()


func _push(step: Array) -> void:
	if _insert_at >= 0:
		_steps.insert(_insert_at, step)
		_insert_at += 1
	else:
		_steps.append(step)


func _process(delta: float) -> void:
	if _running:
		return
	_running = true
	var guard := 0
	while not _steps.is_empty() and guard < 64:
		guard += 1
		var s: Array = _steps[0]
		var kind: String = s[0]
		if kind == "call":
			_steps.pop_front()
			_insert_at = 0
			var fn: Callable = s[1]
			if fn.is_valid():
				fn.call()
			_insert_at = -1
			continue
		if kind == "wait":
			s[4] = float(s[4]) + delta
			if float(s[4]) >= float(s[2]):
				_steps.pop_front()
				delta = 0.0
				continue
			break
		if kind == "until":
			var cond: Callable = s[1]
			if not cond.is_valid() or bool(cond.call()):
				_steps.pop_front()
				continue
			s[4] = float(s[4]) + delta
			if float(s[2]) > 0.0 and float(s[4]) >= float(s[2]):
				_steps.pop_front()
				var to: Callable = s[3]
				if to.is_valid():
					_insert_at = 0
					to.call()
					_insert_at = -1
				continue
			break
	_running = false
