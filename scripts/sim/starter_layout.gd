class_name StarterLayout extends RefCounted
## The pre-built cell a run starts with: a membrane ring (plus a wall ring for
## plants) and a pre-wired nucleus, chromosomes and mitochondria.

const HALF := Vector2i(20, 10)


static func ring(half: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-half.x, half.x + 1):
		cells.append(Vector2i(x, -half.y))
		cells.append(Vector2i(x, half.y))
	for y in range(-half.y + 1, half.y):
		cells.append(Vector2i(-half.x, y))
		cells.append(Vector2i(half.x, y))
	return cells


## Cells the player may build on: inside the outer ring (the wall ring for plants).
static func in_bounds(cell: Vector2i, cell_type: int) -> bool:
	var pad := 1 if cell_type == OrganelleDef.CellType.PLANT else 0
	return absi(cell.x) <= HALF.x + pad and absi(cell.y) <= HALF.y + pad


static func build(sim: CellSim, rng: RandomNumberGenerator) -> void:
	for c in ring(HALF):
		_place(sim, "membrane", c, rng.randf_range(90.0, 100.0))
	var plant := sim.cell_type == OrganelleDef.CellType.PLANT
	if plant:
		for c in ring(HALF + Vector2i(1, 1)):
			_place(sim, "cell_wall", c, rng.randf_range(90.0, 100.0))
	var nucleus := _place(sim, "nucleus", Vector2i(0, 0))
	var chromosomes := _place(sim, "chromosomes", Vector2i(1, 0))
	var mito := _place(sim, "mitochondria", Vector2i(-3, 0))
	var anchor := sim.organelle_at(Vector2i(0, -HALF.y))
	sim.add_link(nucleus, mito)
	sim.add_link(nucleus, anchor)
	sim.add_link(chromosomes, anchor)
	sim.add_link(mito, anchor)
	if plant:
		var chloroplast := _place(sim, "chloroplast", Vector2i(3, 0))
		sim.add_link(chloroplast, mito)
		sim.add_link(chloroplast, anchor)


static func _place(sim: CellSim, id: String, cell: Vector2i, health: float = 100.0) -> int:
	var uid := sim.add_organelle(id, cell, true)
	if uid != -1:
		(sim.organelles[uid] as PlacedOrganelle).health = health
	return uid
