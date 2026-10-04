extends SceneTree
## Renders the main scene after a scripted run and saves a PNG (needs a window,
## so do NOT run with --headless).
## Run: godot --path . --script res://tools/screenshot.gd -- animal|plant out.png

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var animal := args.size() < 1 or args[0] != "plant"
	var out := args[1] if args.size() > 1 else "/tmp/cell.png"
	var game = (load("res://scene/cell Node2D.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.start_run(animal)
	var mode := OS.get_cmdline_user_args()
	if mode.has("reveal"):
		for i in 40:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
		return
	game.skip_intro()
	if mode.has("guide"):
		for i in 20:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
		return
	StarterLayout.build_core(game.sim)
	for i in 12:
		game._on_tick()
	game.sim.meters["water"] = 200.0
	game.sim.meters["waste"] = 30.0
	game.sim.refresh_unlocks()
	game.try_place("vacuole", Vector2i(-6, 3))
	var vac = game.uid_at(Vector2i(-6, 3))
	game.sim.add_link(vac, game.uid_at(Vector2i(-3, 0)))
	game.sim.add_link(vac, game.uid_at(Vector2i(0, -7)))
	game._on_tick()
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() in ([&"StartScreen"] if OS.get_cmdline_user_args().has("dialogs") else [&"InfoCard", &"StartScreen"]):
			c.visible = false
	var extra := OS.get_cmdline_user_args()
	if extra.has("golgi"):
		var mito = game.uid_at(Vector2i(-3, 0))
		var anchor = game.uid_at(Vector2i(0, -7))
		var er = game.sim.add_organelle("endoplasmic_reticulum", Vector2i(-4, -3), true)
		var gol = game.sim.add_organelle("golgi_apparatus", Vector2i(4, 3), true)
		for pair in [[er, mito], [er, anchor], [gol, mito], [gol, anchor], [er, gol]]:
			game.sim.add_link(pair[0], pair[1])
		game.sim.organelles[game.uid_at(Vector2i(-10, 7))].health = 10.0
		game.sim.organelles[gol].proteins = 30.0
		game.sim.organelles[gol].dispatch_timer = 5.9
		game.sim.meters["energy"] = 400.0
		game._on_tick()
		for fleet in game.get_children():
			if fleet.get_script() != null and fleet.get_script().get_global_name() == &"VesicleFleet":
				for i in 22:
					fleet.step(0.1)
	for c in game.get_children():
		var name = c.get_script().get_global_name() if c.get_script() != null else &""
		if name == &"BuildMenu" and extra.has("tip"):
			c.show_tip_for("nucleus", game.get_node("organell buttons and stuff/MarginContainer/Panel/MarginContainer/VBoxContainer/nucleus button"))
		if name == &"Encyclopedia" and extra.has("enc"):
			c.toggle()
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
