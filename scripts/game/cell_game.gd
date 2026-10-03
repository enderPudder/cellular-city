class_name CellGame extends Node2D
## Owns the CellSim, ticks it every second, mirrors it onto the TileMapLayers
## and exposes the player's actions. UI and input scripts talk to this node.

signal run_started
signal ticked
signal run_lost(reason: String)
signal sim_unlocked(def_id: String)
signal event_fired(label: String)
signal speed_changed(speed: int)

const TICK_SECONDS := 1.0
## Radius in pixels of the repair brush (tiles are 16 px, so 3 tiles).
const REPAIR_RADIUS := 48.0

var sim: CellSim
var director: DamageDirector
var curve := DifficultyCurve.new()
var tool: String = ""
var running: bool = false
var paused: bool = false
var link_drag_from: int = -1
## GameSpeed.PAUSED / NORMAL / DOUBLE, chosen with the speed buttons. `paused` below is
## separate: it is set while an unlock card is open and also blocks building.
var speed: int = GameSpeed.NORMAL

var _layers: Dictionary = {}  # organelle id -> TileBase
var _grid: TileBase
var _timer := Timer.new()


func _ready() -> void:
	for child in get_children():
		if child is TileBase and (child as TileBase).organelle_id != "":
			_layers[(child as TileBase).organelle_id] = child
	_grid = _layers["membrane"]
	_timer.wait_time = TICK_SECONDS
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_build_children()


func _build_children() -> void:
	var link_layer := LinkLayer.new()
	link_layer.setup(self)
	add_child(link_layer)
	var build_input := BuildInput.new()
	build_input.setup(self)
	add_child(build_input)
	var fleet := VesicleFleet.new()
	fleet.setup(self)
	add_child(fleet)
	for ui in [SpeedControls.new(), Hud.new(), BuildMenu.new(), InfoCard.new(), Encyclopedia.new(), GameOver.new(), StartScreen.new()]:
		add_child(ui)
		ui.setup(self)


func start_run(is_animal: bool) -> void:
	Globals.player_plant_or_animal = is_animal
	($backround as AnimatedSprite2D).call("refresh")
	for layer: TileBase in _layers.values():
		layer.clear()
	var cell_type := OrganelleDef.CellType.ANIMAL if is_animal else OrganelleDef.CellType.PLANT
	sim = CellSim.new(OrganelleCatalog.load_all(), cell_type)
	sim.organelle_added.connect(_on_added)
	sim.organelle_removed.connect(_on_removed)
	sim.unlocked.connect(func(id: String) -> void: sim_unlocked.emit(id))
	sim.lost.connect(_on_lost)
	director = DamageDirector.new(sim, curve, RandomNumberGenerator.new())
	director.event_fired.connect(func(l: String) -> void: event_fired.emit(l))
	StarterLayout.build(sim, RandomNumberGenerator.new())
	tool = ""
	paused = false
	speed = GameSpeed.NORMAL
	_apply_speed()
	speed_changed.emit(speed)
	running = true
	_timer.start()
	run_started.emit()


func set_paused(p: bool) -> void:
	paused = p
	_apply_speed()


func set_speed(new_speed: int) -> void:
	speed = new_speed
	_apply_speed()
	speed_changed.emit(speed)


## `delta` scaled by the current speed; 0 while paused by the player or a card.
func scaled_delta(delta: float) -> float:
	return 0.0 if paused else delta * GameSpeed.multiplier(speed)


func _apply_speed() -> void:
	_timer.wait_time = GameSpeed.tick_interval(speed, TICK_SECONDS)
	_timer.paused = paused or speed == GameSpeed.PAUSED


func _on_tick() -> void:
	sim.decay_multiplier = curve.decay_multiplier(sim.elapsed)
	sim.tick(TICK_SECONDS)
	director.tick(TICK_SECONDS)
	ticked.emit()


func _on_lost(reason: String) -> void:
	running = false
	_timer.stop()
	run_lost.emit(reason)


func _on_added(uid: int) -> void:
	var o: PlacedOrganelle = sim.organelles[uid]
	if _layers.has(o.def.id):
		(_layers[o.def.id] as TileBase).show_tile(o.cell)


func _on_removed(_uid: int, cell: Vector2i, def_id: String) -> void:
	if _layers.has(def_id):
		(_layers[def_id] as TileBase).hide_tile(cell)


# ----- queries -----

## The TileBase layer with this `organelle_id` (e.g. "vesicles"), or null.
func layer_for(id: String) -> TileBase:
	return _layers.get(id)


func cell_at_mouse() -> Vector2i:
	return _grid.local_to_map(_grid.to_local(get_global_mouse_position()))


func uid_at(cell: Vector2i) -> int:
	return sim.organelle_at(cell) if sim != null else -1


func cell_center(cell: Vector2i) -> Vector2:
	return _grid.to_global(_grid.map_to_local(cell))


func describe(uid: int) -> String:
	var o: PlacedOrganelle = sim.organelles.get(uid)
	if o == null:
		return ""
	var status := "running"
	if o.disabled:
		status = "DAMAGED - repair it"
	elif o.health <= 0.0:
		status = "worn out - repair it"
	elif not o.energy_ok:
		status = "no energy link (or supplier full)"
	elif not o.water_ok:
		status = "no water link"
	elif not o.running:
		status = "waiting for its neighbour"
	if o.def.energy_output > 0.0 and sim.is_fat_paired(uid):
		status += ", burning fat via ER"
	if o.def.protein_capacity > 0.0:
		status += ", proteins %d/%d" % [int(o.proteins), int(o.def.protein_capacity)]
	return "%s (%s)\n%s\nhealth %d%%" % [o.def.display_name, o.def.city_name, status, int(o.health)]


# ----- player actions -----

## Returns "" on success, otherwise the refusal reason.
func try_place(def_id: String, cell: Vector2i) -> String:
	if sim == null or not StarterLayout.in_bounds(cell, sim.cell_type):
		return "outside_cell"
	var reason := sim.can_place(def_id, cell)
	if reason == "":
		sim.add_organelle(def_id, cell)
	return reason


func try_erase(cell: Vector2i) -> void:
	var uid := uid_at(cell)
	if uid == -1:
		return
	if tool == "link":
		sim.remove_links_of(uid)
	else:
		sim.remove_organelle(uid)


## Repairs every damaged organelle whose tile centre is inside the repair
## circle around `center` (world position). Returns how many were repaired.
func repair_area(center: Vector2) -> int:
	var fixed := 0
	for uid in sim.organelles.keys():
		var o: PlacedOrganelle = sim.organelles[uid]
		if sim.needs_repair(uid) and cell_center(o.cell).distance_to(center) <= REPAIR_RADIUS:
			if sim.repair(uid):
				fixed += 1
	return fixed
