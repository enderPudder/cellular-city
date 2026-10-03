class_name TileBase extends TileMapLayer
@export var energy_consumption: int
@export var water_consumption: int
@export var waste_production: int
@export var top_middle_tile: Vector2

var connected_to: Array = []

func _process(_delta: float) -> void:
	if Input.is_action_pressed("click"):
		var mouse_position = get_global_mouse_position()
		var tile_pos = local_to_map(mouse_position)
		print("mouse position is: " , mouse_position)
		print("tile pos is: " , tile_pos)
		
		# Only place a tile if the cell at tile_pos is currently empty (-1)
		if get_cell_source_id(tile_pos) == -1:
			if top_middle_tile != Vector2(0,0):
				set_cell(tile_pos, 0, top_middle_tile)
				set_cells_terrain_connect([tile_pos], 0, 0)
