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
	_check(_tiles(game, "membrane") == 76, tag + ": membrane tiles mirrored, got %d" % _tiles(game, "membrane"))
	_check(_tiles(game, "nucleus") == 1, tag + ": nucleus tile")
	_check(_tiles(game, "cell wall") == (84 if not animal else 0), tag + ": cell wall tiles, got %d" % _tiles(game, "cell wall"))
	for i in 5:
		game._on_tick()
	_check(not game.sim.is_lost, tag + ": alive after 5 ticks")
	# vacuole unlocks once water >= 80
	game.sim.meters["water"] = 200.0
	game.sim.meters["waste"] = 30.0
	game.sim.refresh_unlocks()
	_check(game.sim.unlocked_ids.has("vacuole"), tag + ": vacuole unlocked")
	_check(game.try_place("vacuole", Vector2i(-5, 2)) == "", tag + ": vacuole placed")
	_check(_tiles(game, "vacuole") == 1, tag + ": vacuole tile drawn")
	_check(game.try_place("vacuole", Vector2i(-5, 2)) == "occupied", tag + ": occupied refused")
	_check(game.try_place("vacuole", Vector2i(60, 2)) == "outside_cell", tag + ": outside refused")
	var vac = game.uid_at(Vector2i(-5, 2))
	var mito = game.uid_at(Vector2i(-3, 0))
	var anchor = game.uid_at(Vector2i(0, -7))
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
	# repair brush: everything inside the circle is repaired, nothing outside
	var inside := [Vector2i(0, -7), Vector2i(1, -7), Vector2i(2, -7)]
	var outside := Vector2i(-12, 7)
	for c in inside + [outside]:
		game.sim.organelles[game.uid_at(c)].health = 10.0
	game.sim.meters["energy"] = 300.0
	var fixed = game.repair_area(game.cell_center(Vector2i(1, -7)))
	_check(fixed >= 3, tag + ": repair_area fixed the damaged tiles in the circle, got %d" % fixed)
	for c in inside:
		_check(game.sim.organelles[game.uid_at(c)].health == 100.0, tag + ": tile %s inside the circle repaired" % [c])
	_check(game.sim.organelles[game.uid_at(outside)].health == 10.0, tag + ": tile outside the circle untouched")
	# encyclopedia shows readable text
	var enc = null
	var bm = null
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"Encyclopedia":
			enc = c
		if c.get_script() != null and c.get_script().get_global_name() == &"BuildMenu":
			bm = c
	enc.toggle()
	for i in 3:
		await process_frame
	var labels = enc.find_children("*", "RichTextLabel", true, false)
	_check(labels.size() > 0, tag + ": encyclopedia has entries")
	if labels.size() > 0:
		_check(labels[0].size.x > 200 and labels[0].get_content_height() > 20, tag + ": encyclopedia text has size, w=%d h=%d" % [labels[0].size.x, labels[0].get_content_height()])
	enc.toggle()
	# hover tip fits on screen and says what to connect
	var palette_button = game.get_node("organell buttons and stuff/MarginContainer/Panel/MarginContainer/VBoxContainer/lysosome button")
	bm.show_tip_for("lysosome", palette_button)
	for i in 3:
		await process_frame
	var tip_rect: Rect2 = bm._tip_panel.get_global_rect()
	_check(bm._tip_panel.visible, tag + ": tip is shown")
	_check(root.get_visible_rect().encloses(tip_rect), tag + ": tip is fully on screen, rect %s" % [tip_rect])
	_check(bm._tip_label.text.contains("Connect it to:"), tag + ": tip says what to connect")
	bm.hide_tip()
	# open_buildings toggles the palette and stats; an attack pops the stats back up
	var hud = null
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"Hud":
			hud = c
	var palette = game.get_node("organell buttons and stuff")
	var stats = hud.get_child(0).get_child(0)  # CanvasLayer > UiRoot > stats panel
	_check(palette.visible and stats.visible, tag + ": panels visible at start")
	hud._input(_action("open_buildings"))
	_check(not palette.visible and not stats.visible, tag + ": open_buildings hides palette and stats")
	game.director.bacteria_chance = 1.0
	game.director._time_to_event = 0.0
	game._on_tick()
	_check(not game.director.timers.is_empty(), tag + ": a bacteria event started")
	_check(stats.visible and not palette.visible, tag + ": attack pops the stats tab up, palette stays hidden")
	for t in game.director.timers.duplicate():
		game.sim.repair(t["uid"])
	game._on_tick()
	_check(game.director.timers.is_empty() and not stats.visible, tag + ": stats tab hides again once resolved")
	hud._input(_action("open_buildings"))
	_check(palette.visible and stats.visible, tag + ": open_buildings shows both again")
	# speed buttons: pause / normal / double
	var speed_ui = null
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"SpeedControls":
			speed_ui = c
	_check(speed_ui != null, tag + ": speed controls exist")
	if speed_ui != null:
		var buttons = speed_ui.find_children("*", "Button", true, false)
		_check(buttons.size() == 3, tag + ": three speed buttons, got %d" % buttons.size())
		_check(game.speed == GameSpeed.NORMAL and not game._timer.paused, tag + ": starts at normal speed")
		buttons[2].set_pressed(true)
		_check(game.speed == GameSpeed.DOUBLE and absf(game._timer.wait_time - 0.5) < 0.001 and not game._timer.paused, tag + ": 2x halves the tick interval")
		_check(absf(game.scaled_delta(1.0) - 2.0) < 0.001, tag + ": 2x doubles train movement")
		buttons[0].set_pressed(true)
		_check(game.speed == GameSpeed.PAUSED and game._timer.paused, tag + ": pause stops the tick timer")
		_check(game.scaled_delta(1.0) == 0.0, tag + ": pause stops the trains")
		buttons[1].set_pressed(true)
		_check(game.speed == GameSpeed.NORMAL and absf(game._timer.wait_time - 1.0) < 0.001 and not game._timer.paused, tag + ": 1x resumes at normal speed")
		game.set_paused(true)
		_check(game._timer.paused and game.scaled_delta(1.0) == 0.0, tag + ": an unlock card still pauses at 1x")
		game.set_paused(false)
		game.set_speed(GameSpeed.PAUSED)
		game.set_paused(false)
		_check(game._timer.paused, tag + ": dismissing a card does not un-pause a player pause")
		game.set_speed(GameSpeed.NORMAL)
	# each layer's own Atlas Tile (set in the scene Inspector)
	var expected_tiles := {"membrane": Vector2i(2, 0), "nucleus": Vector2i(0, 0), "vacuole": Vector2i(0, 1),
		"cytoplasm": Vector2i(0, 8), "mitochondria": Vector2i(0, 2), "chromosomes": Vector2i(0, 3),
		"chloroplast": Vector2i(0, 4), "endoplasmic reculum": Vector2i(0, 5), "lysosomes": Vector2i(0, 6),
		"golgoi apparatus": Vector2i(0, 7)}
	for layer_name in expected_tiles:
		_check(game.get_node(layer_name).atlas_tile == expected_tiles[layer_name], tag + ": %s layer atlas tile is %s, got %s" % [layer_name, expected_tiles[layer_name], game.get_node(layer_name).atlas_tile])
	# unlocked palette buttons keep the font size the scene gave them
	var er_button = game.get_node("organell buttons and stuff/MarginContainer/Panel/MarginContainer/VBoxContainer/endoplasmic reculum")
	game.sim.meters["food"] = 200.0
	game.sim.meters["water"] = 200.0
	game.sim.meters["waste"] = 100.0
	game.sim.refresh_unlocks(false)
	bm._refresh()
	_check(not er_button.disabled and er_button.get_theme_font_size("font_size") == bm._base_font_size["endoplasmic_reticulum"] and bm._base_font_size["endoplasmic_reticulum"] == 14, tag + ": ER button keeps its own font size, got %d" % er_button.get_theme_font_size("font_size"))
	# golgi button is wired to the palette
	_check(bm._buttons.has("golgi_apparatus"), tag + ": golgi palette button is bound")
	# golgi + vesicle trains deliver proteins and lay track
	var fleet = null
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"VesicleFleet":
			fleet = c
	_check(fleet != null, tag + ": vesicle fleet exists")
	if fleet != null:
		var mito_uid = game.uid_at(Vector2i(-3, 0))
		var anchor_uid = game.uid_at(Vector2i(0, -7))
		var er = game.sim.add_organelle("endoplasmic_reticulum", Vector2i(-3, -3), true)
		var golgi = game.sim.add_organelle("golgi_apparatus", Vector2i(3, 3), true)
		for pair in [[er, mito_uid], [er, anchor_uid], [golgi, mito_uid], [golgi, anchor_uid], [er, golgi]]:
			_check(game.sim.add_link(pair[0], pair[1]), tag + ": link %s -> %s" % [pair[0], pair[1]])
		var weak = game.uid_at(Vector2i(-12, 7))  # the lowest-health tile, so it gets the shipment
		game.sim.organelles[weak].health = 5.0
		game.sim.organelles[golgi].proteins = 20.0
		game.sim.organelles[golgi].dispatch_timer = 5.9
		game.sim.meters["energy"] = 400.0
		game._on_tick()
		_check(fleet.trains.size() >= 1, tag + ": a vesicle train left the golgi, trains=%d" % fleet.trains.size())
		for i in 400:
			fleet.step(0.1)
		_check(fleet.trains.is_empty(), tag + ": trains arrived")
		_check(game.get_node("vesicles").get_used_cells().size() > 3, tag + ": track tiles were laid, got %d" % game.get_node("vesicles").get_used_cells().size())
		_check(game.sim.organelles[weak].health > 5.0, tag + ": delivered proteins repaired the weakest membrane tile")
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


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev
