class_name CellSim extends RefCounted
## All game rules. No scene dependencies, so it is unit-testable.

signal unlocked(def_id: String)
signal lost(reason: String)
signal organelle_added(uid: int)
signal organelle_removed(uid: int, cell: Vector2i, def_id: String)

const METERS: Array[String] = ["food", "energy", "water", "waste", "fat"]
const BASE_CAPS := {"food": 200.0, "energy": 500.0, "water": 200.0, "waste": 200.0, "fat": 100.0}
const STARTING := {"food": 50.0, "energy": 100.0, "water": 60.0, "waste": 0.0, "fat": 30.0}

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
