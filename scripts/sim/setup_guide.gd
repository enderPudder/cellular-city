class_name SetupGuide extends RefCounted
## The basic-setup checklist: which steps a new player must finish before the
## clock starts. Reads the sim live and knows nothing about scenes.

const STEP_NUCLEUS := "nucleus"
const STEP_POWER := "power"
const STEP_WIRE := "wire"
const STEP_CHLOROPLAST := "chloroplast"

## True once every step has been done at least once; erasing later does not clear it.
var core_done := false

var _sim: CellSim


func _init(sim: CellSim) -> void:
	_sim = sim


func core_ids() -> Array[String]:
	var ids: Array[String] = ["nucleus", "chromosomes", "mitochondria"]
	if _sim.cell_type == OrganelleDef.CellType.PLANT:
		ids.append("chloroplast")
	return ids


## Unlocks the core organelles (chromosomes normally need a water threshold) so
## their palette buttons work from the start. They already cost no energy.
func begin() -> void:
	for id in core_ids():
		_sim.unlocked_ids[id] = true


func steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": STEP_NUCLEUS, "label": "Place a nucleus with chromosomes touching it",
			"hint": "Pick Nucleus in the palette and place it, then place Chromosomes right beside it."},
		{"id": STEP_POWER, "label": "Place mitochondria and link it to the membrane",
			"hint": "Place Mitochondria. Pick Link, then drag from the mitochondria to a membrane tile for water."},
		{"id": STEP_WIRE, "label": "Wire the nucleus and chromosomes",
			"hint": "With Link, drag from the nucleus to the mitochondria (energy) and to a membrane tile (water). Drag from the chromosomes to a membrane tile too."},
	]
	if _sim.cell_type == OrganelleDef.CellType.PLANT:
		out.append({"id": STEP_CHLOROPLAST, "label": "Place a chloroplast and link it",
			"hint": "Place a Chloroplast, then link it to the mitochondria (energy) and to a membrane or cell wall tile (water)."})
	return out


func step_done(id: String) -> bool:
	match id:
		STEP_NUCLEUS:
			return not _nucleus_pairs().is_empty()
		STEP_POWER:
			return _uids("mitochondria").any(func(m: int) -> bool: return _has_supply(m, SimLink.Type.WATER))
		STEP_WIRE:
			return _nucleus_pairs().any(func(p: Array) -> bool:
				return _has_supply(p[0], SimLink.Type.ENERGY) and _has_supply(p[0], SimLink.Type.WATER) \
						and _has_supply(p[1], SimLink.Type.WATER))
		STEP_CHLOROPLAST:
			return _uids("chloroplast").any(func(c: int) -> bool:
				return _has_supply(c, SimLink.Type.ENERGY) and _has_supply(c, SimLink.Type.WATER))
	return false


func all_done() -> bool:
	for step in steps():
		if not step_done(step["id"]):
			return false
	return true


## The first step still to do, or `{}` when everything is done.
func current_step() -> Dictionary:
	for step in steps():
		if not step_done(step["id"]):
			return step
	return {}


## True exactly once: the first time every step is done.
func refresh() -> bool:
	if core_done or not all_done():
		return false
	core_done = true
	return true


func _uids(def_id: String) -> Array[int]:
	var out: Array[int] = []
	for uid in _sim.organelles:
		if (_sim.organelles[uid] as PlacedOrganelle).def.id == def_id:
			out.append(uid)
	return out


## [nucleus uid, chromosomes uid] for every nucleus with a chromosomes touching it.
func _nucleus_pairs() -> Array:
	var pairs := []
	for n in _uids("nucleus"):
		for c in _uids("chromosomes"):
			if _sim.are_adjacent(n, c):
				pairs.append([n, c])
	return pairs


## Does `uid` have a link of `type` to something that can supply it (a water
## source for WATER, an energy source that has water itself for ENERGY)?
func _has_supply(uid: int, type: int) -> bool:
	for l: SimLink in _sim.links:
		if l.from_uid != uid or l.type != type:
			continue
		var src: PlacedOrganelle = _sim.organelles.get(l.to_uid)
		if src == null:
			continue
		if type == SimLink.Type.WATER and src.def.water_output > 0.0:
			return true
		# An energy source only supplies while it has water itself (see CellSim._resolve_supply).
		if type == SimLink.Type.ENERGY and src.def.max_load > 0.0 and _has_supply(src.uid, SimLink.Type.WATER):
			return true
	return false
