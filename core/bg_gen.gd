extends RefCounted
## Procedural generation OFF the main thread, so a slow generator never hitches a frame on a Deck.
## A game knows the next round before it starts (results screen, pit stop, countdown): it calls prefetch() then, and
## take() at round start gets the finished result at once (or waits for the job still running, or, when nothing was
## prefetched, just runs it now: never worse than before). The job must be PURE (numbers in, data out; nodes it
## makes for itself, off the tree, are fine, like kart_race/trackgen.gd's in-memory Track) and give the same result
## on every machine, so a client can prefetch from the same description the host will send.
##   const BgGen := preload("res://core/bg_gen.gd")
##   BgGen.prefetch(key, func() -> Variant: return Gen.generate(seed, spec))   # when the next round is known
##   var info: Dictionary = BgGen.take(key, func() -> Variant: return Gen.generate(seed, spec))   # at round start
## take() hands each result out once (the caller owns it and may change it). tests/bg_gen_test.gd checks it.

const KEEP := 8  # finished results kept (oldest dropped first)

static var _mutex := Mutex.new()
static var _tasks := {}  # key -> WorkerThreadPool task id
static var _done := {}  # key -> result (insertion order = age)


static func prefetch(key: String, job: Callable) -> void:
	_reap()
	_mutex.lock()
	var busy := _tasks.has(key) or _done.has(key)
	_mutex.unlock()
	if busy:
		return
	var id := WorkerThreadPool.add_task(func() -> void: _finish(key, job.call()), false, "BgGen " + key)
	_mutex.lock()
	_tasks[key] = id
	_mutex.unlock()


## The result for key: prefetched (instant), still running (waits for it) or not asked for (runs `job` now).
static func take(key: String, job: Callable) -> Variant:
	_mutex.lock()
	var id: int = _tasks.get(key, -1)
	_mutex.unlock()
	if id >= 0:
		WorkerThreadPool.wait_for_task_completion(id)
		_mutex.lock()
		_tasks.erase(key)
		_mutex.unlock()
	_mutex.lock()
	var have := _done.has(key)
	var r: Variant = _done.get(key)
	_done.erase(key)
	_mutex.unlock()
	return r if have else job.call()


## Is key's result ready (prefetched and finished)? For tests and "still thinking" spinners.
static func ready(key: String) -> bool:
	_mutex.lock()
	var r := _done.has(key)
	_mutex.unlock()
	return r


static func pending() -> int:
	_mutex.lock()
	var r := _tasks.size()
	_mutex.unlock()
	return r


## Wait for every job (tests, and before quitting so no thread outlives the scripts).
static func wait_all() -> void:
	_mutex.lock()
	var ids: Array = _tasks.values()
	_tasks.clear()
	_mutex.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))


static func _finish(key: String, r: Variant) -> void:
	_mutex.lock()
	_done[key] = r
	while _done.size() > KEEP:
		_done.erase(_done.keys()[0])
	_mutex.unlock()


## Every finished task must be waited on once (WorkerThreadPool frees it then).
static func _reap() -> void:
	_mutex.lock()
	var finished: Array = []
	for k in _tasks:
		if WorkerThreadPool.is_task_completed(int(_tasks[k])):
			finished.append(k)
	var ids: Array = []
	for k in finished:
		ids.append(_tasks[k])
		_tasks.erase(k)
	_mutex.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))
