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
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
