class_name CellSim extends RefCounted
## All game rules. No scene dependencies, so it is unit-testable.

signal unlocked(def_id: String)
signal lost(reason: String)
signal organelle_added(uid: int)
signal organelle_removed(uid: int, cell: Vector2i, def_id: String)

const METERS: Array[String] = ["food", "energy", "water", "waste", "fat"]
const BASE_CAPS := {"food": 200.0, "energy": 500.0, "water": 200.0, "waste": 200.0, "fat": 100.0}
const STARTING := {"food": 50.0, "energy": 100.0, "water": 60.0, "waste": 0.0, "fat": 30.0}
const FAT_FROM_SURPLUS := 0.5
const NUCLEUS_GRACE := 3.0
const TOXIC_DAMAGE := 2.0

var cell_type: int
var defs: Dictionary = {}
var meters: Dictionary = {}
var organelles: Dictionary = {}
var links: Array[SimLink] = []
var unlocked_ids: Dictionary = {}
var elapsed: float = 0.0
var is_lost: bool = false
var lost_reason: String = ""
var nucleus_required: bool = true
var decay_multiplier: float = 1.0

var _cell_index: Dictionary = {}
var _next_uid: int = 1
var _no_nucleus_time: float = 0.0
var _fat_paired: Dictionary = {}  # mitochondria uid -> ER uid


func _init(p_defs: Array, p_cell_type: int) -> void:
	cell_type = p_cell_type
	for d: OrganelleDef in p_defs:
		defs[d.id] = d
	meters = STARTING.duplicate()
	refresh_unlocks(false)


# ----- capacities and unlocks -----

func capacities() -> Dictionary:
	var caps := BASE_CAPS.duplicate()
	for o: PlacedOrganelle in organelles.values():
		if o.alive():
			caps["water"] += o.def.water_capacity_bonus
	return caps


static func thresholds_met(current: Dictionary, thresholds: Dictionary) -> bool:
	for key in thresholds:
		if float(current.get(key, 0.0)) < float(thresholds[key]):
			return false
	return true


func unlock_progress(def_id: String) -> Dictionary:
	var out := {}
	var d: OrganelleDef = defs[def_id]
	for key in d.unlock_thresholds:
		out[key] = [float(meters.get(key, 0.0)), float(d.unlock_thresholds[key])]
	return out


func refresh_unlocks(emit_signals: bool = true) -> void:
	for id in defs:
		if unlocked_ids.has(id):
			continue
		var d: OrganelleDef = defs[id]
		if not d.allowed_cell_types.has(cell_type):
			continue
		if thresholds_met(meters, d.unlock_thresholds):
			unlocked_ids[id] = true
			if emit_signals:
				unlocked.emit(id)


# ----- placement -----

func can_place(def_id: String, cell: Vector2i, free: bool = false) -> String:
	var d: OrganelleDef = defs.get(def_id)
	if d == null:
		return "unknown"
	if not d.allowed_cell_types.has(cell_type):
		return "wrong_cell_type"
	if not free and not unlocked_ids.has(def_id):
		return "locked"
	if _cell_index.has(cell):
		return "occupied"
	if not free and float(meters["energy"]) < d.placement_energy_cost:
		return "no_energy"
	var limit := d.max_group_size_plant if cell_type == OrganelleDef.CellType.PLANT else d.max_group_size_animal
	if limit > 0 and _group_size_with(def_id, cell) > limit:
		return "group_full"
	return ""


func add_organelle(def_id: String, cell: Vector2i, free: bool = false) -> int:
	if can_place(def_id, cell, free) != "":
		return -1
	var d: OrganelleDef = defs[def_id]
	if free:
		unlocked_ids[def_id] = true
	else:
		meters["energy"] = float(meters["energy"]) - d.placement_energy_cost
	var o := PlacedOrganelle.new()
	o.uid = _next_uid
	_next_uid += 1
	o.def = d
	o.cell = cell
	organelles[o.uid] = o
	_cell_index[cell] = o.uid
	organelle_added.emit(o.uid)
	return o.uid


func remove_organelle(uid: int) -> void:
	var o: PlacedOrganelle = organelles.get(uid)
	if o == null:
		return
	organelles.erase(uid)
	_cell_index.erase(o.cell)
	remove_links_of(uid)
	organelle_removed.emit(uid, o.cell, o.def.id)


func organelle_at(cell: Vector2i) -> int:
	return _cell_index.get(cell, -1)


func are_adjacent(a_uid: int, b_uid: int) -> bool:
	var a: PlacedOrganelle = organelles.get(a_uid)
	var b: PlacedOrganelle = organelles.get(b_uid)
	if a == null or b == null:
		return false
	return absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y) == 1


func is_fat_paired(mito_uid: int) -> bool:
	return _fat_paired.has(mito_uid)


func _neighbors(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN]


func _group_size_with(def_id: String, cell: Vector2i) -> int:
	var seen := {cell: true}
	var stack: Array[Vector2i] = [cell]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for n in _neighbors(c):
			if seen.has(n):
				continue
			var uid: int = _cell_index.get(n, -1)
			if uid != -1 and (organelles[uid] as PlacedOrganelle).def.id == def_id:
				seen[n] = true
				stack.append(n)
	return seen.size()


# ----- links -----

func infer_link_type(from_uid: int, to_uid: int) -> int:
	var a: PlacedOrganelle = organelles.get(from_uid)
	var b: PlacedOrganelle = organelles.get(to_uid)
	if a == null or b == null or from_uid == to_uid:
		return -1
	if b.def.max_load > 0.0 and a.def.needs_energy_link:
		return SimLink.Type.ENERGY
	if b.def.water_output > 0.0 and a.def.needs_water_link:
		return SimLink.Type.WATER
	if a.def.energy_output > 0.0 and b.def.fat_access:
		return SimLink.Type.FAT
	return -1


func add_link(from_uid: int, to_uid: int) -> bool:
	var t := infer_link_type(from_uid, to_uid)
	if t == -1 or has_link(from_uid, to_uid, t):
		return false
	links.append(SimLink.make(from_uid, to_uid, t))
	return true


func has_link(from_uid: int, to_uid: int, type: int) -> bool:
	for l in links:
		if l.from_uid == from_uid and l.to_uid == to_uid and l.type == type:
			return true
	return false


func remove_link(from_uid: int, to_uid: int, type: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return not (l.from_uid == from_uid and l.to_uid == to_uid and l.type == type)))


func remove_links_of(uid: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return l.from_uid != uid and l.to_uid != uid))


# ----- tick -----

func tick(dt: float) -> void:
	if is_lost:
		return
	elapsed += dt
	_apply_decay(dt)
	_resolve_supply()
	_update_running()
	_run_economy(dt)
	refresh_unlocks()
	_check_nucleus(dt)


func _resolve_supply() -> void:
	for o: PlacedOrganelle in organelles.values():
		o.water_ok = not o.def.needs_water_link
		o.energy_ok = not o.def.needs_energy_link
	for l in links:
		if l.type != SimLink.Type.WATER:
			continue
		var consumer: PlacedOrganelle = organelles.get(l.from_uid)
		var source: PlacedOrganelle = organelles.get(l.to_uid)
		if consumer != null and source != null and source.def.water_output > 0.0 and source.alive():
			consumer.water_ok = true
	var used := {}
	for l in links:
		if l.type != SimLink.Type.ENERGY:
			continue
		var consumer: PlacedOrganelle = organelles.get(l.from_uid)
		var source: PlacedOrganelle = organelles.get(l.to_uid)
		if consumer == null or source == null:
			continue
		if source.def.max_load <= 0.0 or not source.alive() or not source.water_ok:
			continue
		var load_now: float = used.get(source.uid, 0.0)
		if load_now + consumer.def.energy_use <= source.def.max_load:
			used[source.uid] = load_now + consumer.def.energy_use
			consumer.energy_ok = true
	_fat_paired.clear()
	var er_taken := {}
	for l in links:
		if l.type != SimLink.Type.FAT or _fat_paired.has(l.from_uid):
			continue
		var m: PlacedOrganelle = organelles.get(l.from_uid)
		var er: PlacedOrganelle = organelles.get(l.to_uid)
		if m == null or er == null:
			continue
		if m.def.energy_output <= 0.0 or not er.def.fat_access or not er.alive():
			continue
		if not are_adjacent(m.uid, er.uid):
			continue
		var taken: int = er_taken.get(er.uid, 0)
		if taken >= er.def.max_paired_mitochondria:
			continue
		er_taken[er.uid] = taken + 1
		_fat_paired[m.uid] = er.uid


func _update_running() -> void:
	for o: PlacedOrganelle in organelles.values():
		o.running = o.alive() and o.energy_ok and o.water_ok and _adjacency_ok(o)


func _adjacency_ok(o: PlacedOrganelle) -> bool:
	if o.def.requires_adjacent == "":
		return true
	for n in _neighbors(o.cell):
		var uid: int = _cell_index.get(n, -1)
		if uid == -1:
			continue
		var other: PlacedOrganelle = organelles[uid]
		if other.def.id == o.def.requires_adjacent and other.alive():
			return true
	return false


func _run_economy(dt: float) -> void:
	var active: Array[PlacedOrganelle] = []
	for o: PlacedOrganelle in organelles.values():
		if o.running:
			active.append(o)
	# 1. mitochondria turn fuel into energy
	for o in active:
		if o.def.energy_output > 0.0:
			meters["energy"] += o.def.energy_output * dt * _fuel_fraction(o, dt)
	# 2. energy is spent; a shortage scales everyone's output down
	var energy_demand := 0.0
	var water_demand := 0.0
	for o in active:
		energy_demand += o.def.energy_use * dt
		water_demand += o.def.water_use * dt
	var energy_factor := 1.0 if energy_demand <= 0.0 else minf(1.0, float(meters["energy"]) / energy_demand)
	meters["energy"] -= energy_demand * energy_factor
	# 3. water is collected, then spent
	for o in active:
		if o.def.water_output > 0.0:
			var yield_fraction := 1.0 if o.health >= 90.0 else 1.0 / 16.0
			meters["water"] += o.def.water_output * dt * energy_factor * yield_fraction
	var water_factor := 1.0 if water_demand <= 0.0 else minf(1.0, float(meters["water"]) / water_demand)
	meters["water"] -= water_demand * water_factor
	# 4. food and waste follow the slower of the two
	var rate := minf(energy_factor, water_factor)
	for o in active:
		var d := o.def
		meters["food"] += d.food_output_for(cell_type) * dt * rate
		meters["waste"] += d.waste_production * dt * rate
		var removal := minf(float(meters["waste"]), d.waste_removal_for(cell_type) * dt * rate)
		meters["waste"] -= removal
		meters["food"] += removal * d.waste_to_food
	_clamp_meters()


## Fraction (0..1) of a mitochondria's fuel need that was satisfied this tick.
func _fuel_fraction(o: PlacedOrganelle, dt: float) -> float:
	var need := o.def.food_use * dt
	if need <= 0.0:
		return 1.0
	var from_food := minf(float(meters["food"]), need)
	var from_fat := 0.0
	if from_food < need and _fat_paired.has(o.uid):
		from_fat = minf(float(meters["fat"]), need - from_food)
	meters["food"] -= from_food
	meters["fat"] -= from_fat
	return (from_food + from_fat) / need


func _clamp_meters() -> void:
	var caps := capacities()
	var surplus := maxf(0.0, float(meters["food"]) - float(caps["food"]))
	meters["fat"] += surplus * FAT_FROM_SURPLUS
	for m in METERS:
		meters[m] = clampf(float(meters[m]), 0.0, float(caps[m]))


func _apply_decay(dt: float) -> void:
	var toxic := float(meters["waste"]) >= float(capacities()["waste"])
	for o: PlacedOrganelle in organelles.values():
		var loss := o.def.decay_per_second * decay_multiplier
		if toxic:
			loss += TOXIC_DAMAGE
		if loss > 0.0:
			o.health = maxf(0.0, o.health - loss * dt)


func needs_repair(uid: int) -> bool:
	var o: PlacedOrganelle = organelles.get(uid)
	return o != null and (o.disabled or o.health < 100.0)


func repair(uid: int) -> bool:
	var o: PlacedOrganelle = organelles.get(uid)
	if o == null or not needs_repair(uid):
		return false
	if float(meters["energy"]) < o.def.repair_energy_cost:
		return false
	meters["energy"] -= o.def.repair_energy_cost
	o.health = 100.0
	o.disabled = false
	return true


func _check_nucleus(dt: float) -> void:
	if not nucleus_required:
		return
	var has_nucleus := false
	for o: PlacedOrganelle in organelles.values():
		if o.def.id == "nucleus" and o.running:
			has_nucleus = true
			break
	_no_nucleus_time = 0.0 if has_nucleus else _no_nucleus_time + dt
	if _no_nucleus_time >= NUCLEUS_GRACE:
		force_lose("nucleus")


func force_lose(reason: String) -> void:
	if is_lost:
		return
	is_lost = true
	lost_reason = reason
	lost.emit(reason)
