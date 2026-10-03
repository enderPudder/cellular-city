extends SceneTree
## Plays the real main scene headless: start a run, place and link organelles,
## tick the sim by hand and check the tilemap layers mirror it.
## Run: godot --headless --path . --script res://tools/smoke_game.gd
## Prints OK or FAIL lines; exits non-zero on failure.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL  " + msg)


func _initialize() -> void:
	var scene: PackedScene = load("res://scene/cell Node2D.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _run_cell(game, true)
	await _run_cell(game, false)
	print("SMOKE %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _tiles(game, layer_name: String) -> int:
	return (game.get_node(layer_name) as TileMapLayer).get_used_cells().size()


func _run_cell(game, animal: bool) -> void:
	var tag := "animal" if animal else "plant"
	game.start_run(animal)
	await process_frame
	_check(game.running, tag + ": running after start_run")
	_check(_tiles(game, "membrane") == 120, tag + ": membrane tiles mirrored, got %d" % _tiles(game, "membrane"))
	_check(_tiles(game, "nucleus") == 1, tag + ": nucleus tile")
	_check(_tiles(game, "cell wall") == (128 if not animal else 0), tag + ": cell wall tiles, got %d" % _tiles(game, "cell wall"))
	for i in 5:
		game._on_tick()
	_check(not game.sim.is_lost, tag + ": alive after 5 ticks")
	# vacuole unlocks once water >= 80
	game.sim.meters["water"] = 100.0
	game.sim.refresh_unlocks()
	_check(game.sim.unlocked_ids.has("vacuole"), tag + ": vacuole unlocked")
	_check(game.try_place("vacuole", Vector2i(-5, 2)) == "", tag + ": vacuole placed")
	_check(_tiles(game, "vacuole") == 1, tag + ": vacuole tile drawn")
	_check(game.try_place("vacuole", Vector2i(-5, 2)) == "occupied", tag + ": occupied refused")
	_check(game.try_place("vacuole", Vector2i(60, 2)) == "outside_cell", tag + ": outside refused")
	var vac = game.uid_at(Vector2i(-5, 2))
	var mito = game.uid_at(Vector2i(-3, 0))
	var anchor = game.uid_at(Vector2i(0, -10))
	_check(game.sim.add_link(vac, mito), tag + ": energy link")
	_check(game.sim.add_link(vac, anchor), tag + ": water link")
	game._on_tick()
	_check(game.sim.organelles[vac].running, tag + ": vacuole running")
	_check(not game.describe(vac).is_empty(), tag + ": describe text")
	game.tool = ""
	game.try_erase(Vector2i(-5, 2))
	_check(_tiles(game, "vacuole") == 0, tag + ": erase clears the tile")
	# dismiss the unlock card and start screen like a player would
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() in [&"InfoCard", &"StartScreen"]:
			c.visible = false
	game.set_paused(false)
	# mouse handling through BuildInput: paint-place, link drag, erase
	var bi = null
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"BuildInput":
			bi = c
	var pointer := [Vector2i.ZERO]
	bi.mouse_cell = func(): return pointer[0]
	game.sim.meters["energy"] = 200.0
	game.tool = "vacuole"
	var target = Vector2i(-8, 5)
	pointer[0] = target
	Input.action_press("click")
	for i in 3:
		await process_frame
	Input.action_release("click")
	_check(game.uid_at(target) != -1, tag + ": click places the selected organelle")
	game.tool = "link"
	var src = game.uid_at(target)
	pointer[0] = target
	bi._unhandled_input(_button(true))
	pointer[0] = Vector2i(-3, 0)
	bi._unhandled_input(_button(false))
	_check(game.sim.has_link(src, game.uid_at(Vector2i(-3, 0)), SimLink.Type.ENERGY), tag + ": link drag creates an energy link")
	pointer[0] = target
	Input.action_press("erase")
	for i in 3:
		await process_frame
	Input.action_release("erase")
	_check(game.uid_at(target) != -1 and game.sim.links.size() > 0 and not game.sim.has_link(src, game.uid_at(Vector2i(-3, 0)), SimLink.Type.ENERGY), tag + ": link-mode erase cuts links but keeps the organelle")
	game.tool = ""
	Input.action_press("erase")
	for i in 3:
		await process_frame
	Input.action_release("erase")
	_check(game.uid_at(target) == -1, tag + ": erase removes the organelle")
	game.tool = "repair"
	game.sim.organelles[game.uid_at(Vector2i(0, 0))].health = 40.0
	pointer[0] = Vector2i(0, 0)
	Input.action_press("click")
	for i in 3:
		await process_frame
	Input.action_release("click")
	_check(game.sim.organelles[game.uid_at(Vector2i(0, 0))].health == 100.0, tag + ": repair tool restores health")
	game.tool = ""
	# plant-only organelles are refused for animals
	if animal:
		_check(game.try_place("chloroplast", Vector2i(5, 2)) in ["wrong_cell_type", "locked"], tag + ": chloroplast refused")
	else:
		_check(game.try_place("chloroplast", Vector2i(5, 2)) == "", tag + ": chloroplast placed")
	# the run is lost cleanly when the nucleus is removed
	game.sim.remove_organelle(game.uid_at(Vector2i(0, 0)))
	for i in 4:
		game._on_tick()
	_check(game.sim.is_lost and not game.running, tag + ": lost after nucleus removal")


func _button(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	return ev
