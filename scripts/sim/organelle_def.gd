class_name OrganelleDef extends Resource
## Static data for one organelle type. Stats are per placed tile, per second.

enum CellType { ANIMAL, PLANT }

@export var id: String = ""
@export var display_name: String = ""
@export var city_name: String = ""
@export_multiline var function_text: String = ""
@export_multiline var city_text: String = ""

@export_group("Consumption")
@export var energy_use: float = 0.0
@export var water_use: float = 0.0
@export var food_use: float = 0.0
@export var waste_production: float = 0.0

@export_group("Production")
@export var energy_output: float = 0.0
@export var water_output: float = 0.0
@export var food_output_animal: float = 0.0
@export var food_output_plant: float = 0.0
@export var waste_removal_animal: float = 0.0
@export var waste_removal_plant: float = 0.0
@export var waste_to_food: float = 0.0
@export var water_capacity_bonus: float = 0.0

@export_group("Supply rules")
@export var needs_energy_link: bool = true
@export var needs_water_link: bool = true
@export var max_load: float = 0.0
@export var fat_access: bool = false
@export var max_paired_mitochondria: int = 0
@export var requires_adjacent: String = ""

@export_group("Progression and upkeep")
@export var unlock_thresholds: Dictionary = {}
@export var allowed_cell_types: PackedInt32Array = PackedInt32Array([0, 1])
@export var placement_energy_cost: float = 0.0
@export var repair_energy_cost: float = 0.0
@export var decay_per_second: float = 0.0
@export var max_group_size_animal: int = 0
@export var max_group_size_plant: int = 0

@export_group("Art")
@export var atlas_tile: Vector2i = Vector2i.ZERO


func food_output_for(cell_type: int) -> float:
	return food_output_plant if cell_type == CellType.PLANT else food_output_animal


func waste_removal_for(cell_type: int) -> float:
	return waste_removal_plant if cell_type == CellType.PLANT else waste_removal_animal
