class_name StarterLayout extends RefCounted
## The cell a run starts from. `build_shell` places the membrane ring (plus a
## wall ring for plants), which the game reveals tile by tile. `build_core` is
## the nucleus, chromosomes and mitochondria pre-wired: the player now builds
## those themselves, so only tests and tools use it as the reference wiring.

## Half-size of the membrane ring in tiles (the cell is 2*HALF+1 tiles across).
const HALF := Vector2i(12, 7)


static func ring(half: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-half.x, half.x + 1):
		cells.append(Vector2i(x, -half.y))
		cells.append(Vector2i(x, half.y))
	for y in range(-half.y + 1, half.y):
		cells.append(Vector2i(-half.x, y))
		cells.append(Vector2i(half.x, y))
	return cells


## The same cells as `ring`, walked clockwise from the top-left corner so list
## neighbours are neighbours on screen (the intro reveal grows around the ring).
static func ring_ordered(half: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-half.x, half.x + 1):
		cells.append(Vector2i(x, -half.y))
	for y in range(-half.y + 1, half.y + 1):
		cells.append(Vector2i(half.x, y))
	for x in range(half.x - 1, -half.x - 1, -1):
		cells.append(Vector2i(x, half.y))
	for y in range(half.y - 1, -half.y, -1):
		cells.append(Vector2i(-half.x, y))
	return cells


## What the intro reveals, in order: `{"id", "cell"}` for the membrane ring, then
## the wall ring for plants.
static func shell_tiles(cell_type: int) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	for c in ring_ordered(HALF):
		tiles.append({"id": "membrane", "cell": c})
	if cell_type == OrganelleDef.CellType.PLANT:
		for c in ring_ordered(HALF + Vector2i(1, 1)):
			tiles.append({"id": "cell_wall", "cell": c})
	return tiles


## Cells the player may build on: inside the outer ring (the wall ring for plants).
static func in_bounds(cell: Vector2i, cell_type: int) -> bool:
	var pad := 1 if cell_type == OrganelleDef.CellType.PLANT else 0
	return absi(cell.x) <= HALF.x + pad and absi(cell.y) <= HALF.y + pad


static func build(sim: CellSim, rng: RandomNumberGenerator) -> void:
	build_shell(sim, rng)
	build_core(sim)


static func build_shell(sim: CellSim, rng: RandomNumberGenerator) -> void:
	for c in ring(HALF):
		_place(sim, "membrane", c, rng.randf_range(90.0, 100.0))
	if sim.cell_type == OrganelleDef.CellType.PLANT:
		for c in ring(HALF + Vector2i(1, 1)):
			_place(sim, "cell_wall", c, rng.randf_range(90.0, 100.0))


## Needs the shell: links go to the membrane tile at the top centre.
static func build_core(sim: CellSim) -> void:
	var nucleus := _place(sim, "nucleus", Vector2i(0, 0))
	var chromosomes := _place(sim, "chromosomes", Vector2i(1, 0))
	var mito := _place(sim, "mitochondria", Vector2i(-3, 0))
	var anchor := sim.organelle_at(Vector2i(0, -HALF.y))
	sim.add_link(nucleus, mito)
	sim.add_link(nucleus, anchor)
	sim.add_link(chromosomes, anchor)
	sim.add_link(mito, anchor)
	if sim.cell_type == OrganelleDef.CellType.PLANT:
		var chloroplast := _place(sim, "chloroplast", Vector2i(3, 0))
		sim.add_link(chloroplast, mito)
		sim.add_link(chloroplast, anchor)


static func _place(sim: CellSim, id: String, cell: Vector2i, health: float = 100.0) -> int:
	var uid := sim.add_organelle(id, cell, true)
	if uid != -1:
		(sim.organelles[uid] as PlacedOrganelle).health = health
	return uid
