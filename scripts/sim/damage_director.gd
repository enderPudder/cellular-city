class_name DamageDirector extends RefCounted
## Fires bacteria and cut events and tracks their repair timers.

signal event_fired(label: String)

var bacteria_chance: float = 0.6
var timers: Array[Dictionary] = []

var _sim: CellSim
var _curve: DifficultyCurve
var _rng: RandomNumberGenerator
var _time_to_event: float


func _init(sim: CellSim, curve: DifficultyCurve, rng: RandomNumberGenerator) -> void:
	_sim = sim
	_curve = curve
	_rng = rng
	_time_to_event = curve.first_event_delay


func tick(dt: float) -> void:
	if _sim.is_lost:
		return
	_update_timers(dt)
	if _sim.is_lost:
		return
	_time_to_event -= dt
	if _time_to_event <= 0.0:
		_fire_event()
		_time_to_event = _curve.event_interval(_sim.elapsed)


func _update_timers(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for t in timers:
		if _is_resolved(t):
			continue
		t["remaining"] = float(t["remaining"]) - dt
		if float(t["remaining"]) <= 0.0:
			_sim.force_lose("repair_timeout")
			return
		kept.append(t)
	timers = kept


func _is_resolved(t: Dictionary) -> bool:
	if t["kind"] == "organelle":
		var o: PlacedOrganelle = _sim.organelles.get(t["uid"])
		return o == null or not o.disabled
	if not _sim.organelles.has(t["from_uid"]) or not _sim.organelles.has(t["to_uid"]):
		return true
	return _sim.has_link(t["from_uid"], t["to_uid"], t["type"])


func _fire_event() -> void:
	var count := _curve.event_size(_sim.elapsed)
	var window := _curve.repair_window(_sim.elapsed)
	if _rng.randf() < bacteria_chance:
		_bacteria(count, window)
	else:
		_cut(count, window)


func _bacteria(count: int, window: float) -> void:
	var pool: Array[PlacedOrganelle] = []
	for o: PlacedOrganelle in _sim.organelles.values():
		if o.alive():
			pool.append(o)
	for i in mini(count, pool.size()):
		var victim: PlacedOrganelle = pool.pop_at(_rng.randi() % pool.size())
		victim.disabled = true
		var label := "Bacteria in %s" % victim.def.display_name
		timers.append({"kind": "organelle", "uid": victim.uid, "label": label, "remaining": window})
		event_fired.emit(label)


func _cut(count: int, window: float) -> void:
	var pool: Array[SimLink] = _sim.links.duplicate()
	for i in mini(count, pool.size()):
		var victim: SimLink = pool.pop_at(_rng.randi() % pool.size())
		_sim.remove_link(victim.from_uid, victim.to_uid, victim.type)
		var from_o: PlacedOrganelle = _sim.organelles[victim.from_uid]
		var label := "Cut link at %s" % from_o.def.display_name
		timers.append({
			"kind": "link", "from_uid": victim.from_uid, "to_uid": victim.to_uid,
			"type": victim.type, "label": label, "remaining": window,
		})
		event_fired.emit(label)
