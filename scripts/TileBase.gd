class_name TileBase extends TileMapLayer
## Draws the tiles of one organelle type. Game rules live in CellSim; CellGame
## tells this layer what to show.

@export var organelle_id: String = ""
@export var terrain_id: int = -1  # >= 0 uses terrain autotiling (membrane, cell wall)

var atlas_tile: Vector2i = Vector2i.ZERO


func show_tile(cell: Vector2i) -> void:
	set_cell(cell, 0, atlas_tile)
	if terrain_id >= 0:
		set_cells_terrain_connect([cell], 0, terrain_id)


func hide_tile(cell: Vector2i) -> void:
	erase_cell(cell)
	if terrain_id >= 0:
		set_cells_terrain_connect(get_used_cells(), 0, terrain_id)
