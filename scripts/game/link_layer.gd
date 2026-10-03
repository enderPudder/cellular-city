class_name LinkLayer extends Node2D
## Draws connection dots, links with animated flow dots, the link being
## dragged, and markers on damaged or worn organelles.

const COLORS := {
	SimLink.Type.ENERGY: Color("f2d64b"),
	SimLink.Type.WATER: Color("4aa3e0"),
	SimLink.Type.FAT: Color("d9c7a0"),
	SimLink.Type.PROTEIN: Color("c277e8"),
}
const FLOW_SPEED := 0.6

var _game: CellGame


func setup(game: CellGame) -> void:
	_game = game
	z_index = 10


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _game == null or _game.sim == null:
		return
	var sim := _game.sim
	var phase := Time.get_ticks_msec() / 1000.0 * FLOW_SPEED
	for i in sim.links.size():
		var l := sim.links[i]
		var consumer: PlacedOrganelle = sim.organelles.get(l.from_uid)
		var supplier: PlacedOrganelle = sim.organelles.get(l.to_uid)
		if consumer == null or supplier == null:
			continue
		var a := _game.cell_center(consumer.cell)
		var b := _game.cell_center(supplier.cell)
		var color: Color = COLORS[l.type]
		var live := supplier.alive()
		draw_line(a, b, color if live else color.darkened(0.6), 1.0)
		if live:
			var t := fmod(phase + i * 0.13, 1.0)
			draw_circle(b.lerp(a, t), 1.5, color)
	for o: PlacedOrganelle in sim.organelles.values():
		if o.def.needs_energy_link or o.def.needs_water_link or o.def.energy_output > 0.0:
			draw_circle(_game.cell_center(o.cell), 2.0, Color.WHITE)
		if o.disabled or o.health <= 0.0:
			draw_arc(_game.cell_center(o.cell), 6.0, 0.0, TAU, 16, Color("e03c3c"), 1.5)
		elif o.health < 50.0:
			draw_arc(_game.cell_center(o.cell), 6.0, 0.0, TAU, 16, Color("e0a43c"), 1.0)
	if _game.tool == "repair" and _game.running and not _game.paused \
			and get_viewport().gui_get_hovered_control() == null:
		var mouse := get_global_mouse_position()
		draw_circle(mouse, CellGame.REPAIR_RADIUS, Color(0.3, 1.0, 0.5, 0.12))
		draw_arc(mouse, CellGame.REPAIR_RADIUS, 0.0, TAU, 48, Color(0.3, 1.0, 0.5, 0.9), 1.5)
	if _game.link_drag_from != -1 and sim.organelles.has(_game.link_drag_from):
		var start := _game.cell_center((sim.organelles[_game.link_drag_from] as PlacedOrganelle).cell)
		draw_line(start, get_global_mouse_position(), Color.WHITE, 1.0)
