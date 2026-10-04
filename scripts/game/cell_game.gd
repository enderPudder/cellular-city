class_name CellGame extends Node2D
## Owns the CellSim, ticks it every second, mirrors it onto the TileMapLayers
## and exposes the player's actions. UI and input scripts talk to this node.

signal run_started
signal ticked
signal run_lost(reason: String)
signal sim_unlocked(def_id: String)
signal event_fired(label: String)
signal speed_changed(speed: int)
signal intro_finished
signal guide_changed
signal setup_done
signal panels_toggled(shown: bool)

const TICK_SECONDS := 1.0
## Radius in pixels of the repair brush (tiles are 16 px, so 3 tiles).
const REPAIR_RADIUS := 48.0
## Seconds a freshly revealed membrane/wall tile flashes while it pops in.
const POP_SECONDS := 0.2

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
## The basic-setup checklist for this run; the tick timer starts when it first completes.
var guide: SetupGuide
## True while the membrane and wall tiles are popping in; building is blocked.
var intro_playing: bool = false

var _layers: Dictionary = {}  # organelle id -> TileBase
var _grid: TileBase
var _timer := Timer.new()
var _reveal: IntroReveal


func _ready() -> void:
	for child in get_children():
		if child is TileBase and (child as TileBase).organelle_id != "":
			_layers[(child as TileBase).organelle_id] = child
	_grid = _layers["membrane"]
	_timer.wait_time = TICK_SECONDS
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_build_children()


func _process(delta: float) -> void:
	if intro_playing and _reveal != null:
		_reveal.advance(delta)


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
	for ui in [SpeedControls.new(), Hud.new(), GuideHud.new(), BuildMenu.new(), InfoCard.new(), Encyclopedia.new(), GameOver.new(), StartScreen.new()]:
		add_child(ui)
		ui.setup(self)


func start_run(is_animal: bool) -> void:
	Globals.player_plant_or_animal = is_animal
	($backround as AnimatedSprite2D).call("refresh")
	_timer.stop()
	for layer: TileBase in _layers.values():
		layer.clear()
	var cell_type := OrganelleDef.CellType.ANIMAL if is_animal else OrganelleDef.CellType.PLANT
	sim = CellSim.new(OrganelleCatalog.load_all(), cell_type)
	sim.organelle_removed.connect(_on_removed)
	sim.unlocked.connect(func(id: String) -> void: sim_unlocked.emit(id))
	sim.lost.connect(_on_lost)
	sim.links_changed.connect(_check_guide)
	director = DamageDirector.new(sim, curve, RandomNumberGenerator.new())
	director.event_fired.connect(func(l: String) -> void: event_fired.emit(l))
	# The shell goes into the sim now but is drawn by the reveal, so connect
	# organelle_added only afterwards.
	StarterLayout.build_shell(sim, RandomNumberGenerator.new())
	sim.organelle_added.connect(_on_added)
	guide = SetupGuide.new(sim)
	guide.begin()
	intro_playing = true
	_reveal = IntroReveal.new(StarterLayout.shell_tiles(cell_type), _reveal_tile)
	_reveal.finished.connect(_on_intro_finished)
	tool = ""
	paused = false
	speed = GameSpeed.NORMAL
	_apply_speed()
	speed_changed.emit(speed)
	running = true
	run_started.emit()


## Finishes the intro at once. Tests and tools only; the player cannot skip it.
func skip_intro() -> void:
	if _reveal != null:
		_reveal.skip()


func _reveal_tile(id: String, cell: Vector2i) -> void:
	if not _layers.has(id):
		return
	(_layers[id] as TileBase).show_tile(cell)
	_spawn_pop(cell)


## A short white flash over a tile as it appears. Visual only.
func _spawn_pop(cell: Vector2i) -> void:
	var half := Vector2(_grid.tile_set.tile_size) / 2.0
	var pop := Polygon2D.new()
	pop.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	pop.color = Color(1, 1, 1, 0.8)
	pop.position = _grid.map_to_local(cell)
	pop.scale = Vector2.ONE * 1.8
	_grid.add_child(pop)
	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "scale", Vector2.ONE, POP_SECONDS)
	tween.tween_property(pop, "color:a", 0.0, POP_SECONDS)
	tween.chain().tween_callback(pop.queue_free)


func _on_intro_finished() -> void:
	intro_playing = false
	intro_finished.emit()
	guide_changed.emit()


## Re-checks the checklist after any build or link change. The first time every
## step is done the clock starts.
func _check_guide() -> void:
	if guide == null:
		return
	guide_changed.emit()
	if guide.refresh():
		_timer.start()
		setup_done.emit()


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
	_check_guide()


func _on_removed(_uid: int, cell: Vector2i, def_id: String) -> void:
	if _layers.has(def_id):
		(_layers[def_id] as TileBase).hide_tile(cell)
	_check_guide()


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
	if intro_playing:
		return "intro"
	if sim == null or not StarterLayout.in_bounds(cell, sim.cell_type):
		return "outside_cell"
	var reason := sim.can_place(def_id, cell)
	if reason == "":
		sim.add_organelle(def_id, cell)
	return reason


func try_erase(cell: Vector2i) -> void:
	if intro_playing:
		return
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
