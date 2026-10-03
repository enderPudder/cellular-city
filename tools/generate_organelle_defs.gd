extends SceneTree
## Regenerates data/organelles/*.tres from the table below.
## Run: godot --headless --path . --script res://tools/generate_organelle_defs.gd
## Tune numbers HERE (or edit the .tres in the inspector), not in game code.

const OUT_DIR := "res://data/organelles/"
const PLANT := OrganelleDef.CellType.PLANT


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var failed := false
	for row in _rows():
		var d := OrganelleDef.new()
		for key in row:
			d.set(key, row[key])
		var err := ResourceSaver.save(d, OUT_DIR + String(row["id"]) + ".tres")
		if err != OK:
			push_error("save failed for %s: %s" % [row["id"], error_string(err)])
			failed = true
	quit(1 if failed else 0)


func _rows() -> Array[Dictionary]:
	return [
		{
			"id": "membrane", "display_name": "Membrane", "city_name": "City limits",
			"function_text": "A semi-permeable layer that controls what enters and exits the cell. It collects water, and in animal cells it absorbs food.",
			"city_text": "City limits control what enters and exits a city, just like a membrane controls what enters and exits a cell.",
			"energy_use": 0.2, "water_output": 0.6, "food_output_animal": 0.4,
			"needs_energy_link": false, "needs_water_link": false,
			"decay_per_second": 0.1, "repair_energy_cost": 0.5, "protein_effect": "repair"
		},
		{
			"id": "nucleus", "display_name": "Nucleus", "city_name": "Municipal government",
			"function_text": "Controls the cell's actions and holds the chromosomes. Every cell needs one, and it only works beside its chromosomes.",
			"city_text": "The government creates laws and makes sure everything is in order, just like a nucleus. The DNA inside holds the instructions that tell the cell what to do.",
			"energy_use": 5.0, "water_use": 10.0, "waste_production": 0.5,
			"requires_adjacent": "chromosomes", "repair_energy_cost": 3.0
		},
		{
			"id": "cytoplasm", "display_name": "Cytoplasm", "city_name": "Delivery systems",
			"function_text": "A jelly-like substance that constantly moves around the cell, carrying food and oxygen to organelles. In plant cells its movement also carries waste away.",
			"city_text": "People who deliver food to people are like cytoplasm, except they aren't jelly.",
			"energy_use": 1.0, "water_use": 2.0, "waste_production": 0.1, "waste_removal_plant": 0.5,
			"needs_energy_link": false, "needs_water_link": false
		},
		{
			"id": "mitochondria", "display_name": "Mitochondria", "city_name": "Coal and oil power plant",
			"function_text": "Takes in food and breaks it down into chemical energy for the whole cell. Beside an endoplasmic reticulum it can also burn stored fat.",
			"city_text": "Power plants take in resources that burn hot to turn turbines and create energy. Mitochondria take in food to make the cell's chemical energy.",
			"energy_use": 20.0, "water_use": 15.0, "food_use": 20.0, "waste_production": 2.0,
			"energy_output": 150.0, "max_load": 150.0, "needs_energy_link": false,
			"repair_energy_cost": 5.0
		},
		{
			"id": "vacuole", "display_name": "Vacuole", "city_name": "Water tower",
			"function_text": "Stores water and liquid waste so the cell can use or expel it later. Animal vacuoles stay small, plant vacuoles can grow large.",
			"city_text": "Water towers store water or liquids for later use. A vacuole does the same, and can also expel waste water.",
			"energy_use": 5.0, "water_use": 15.0,
			"waste_removal_animal": 3.33, "waste_removal_plant": 3.33, "water_capacity_bonus": 40.0,
			"max_group_size_animal": 4, "max_group_size_plant": 25,
			"unlock_thresholds": {"water": 150.0, "waste": 20.0}
		},
		{
			"id": "cell_wall", "display_name": "Cell wall", "city_name": "Flood gates",
			"function_text": "A thick, sturdy outer layer of plant cells that gives support and keeps the inside separate from the outside. It slowly wears down and must be replaced.",
			"city_text": "Flood gates protect a city from storms and tsunamis. A cell wall is sturdy and keeps the inside of the cell separated from the outside.",
			"energy_use": 0.1, "water_output": 0.4, "needs_energy_link": false, "needs_water_link": false,
			"allowed_cell_types": PackedInt32Array([PLANT]), "placement_energy_cost": 0.5,
			"decay_per_second": 0.05, "repair_energy_cost": 0.5, "protein_effect": "repair"
		},
		{
			"id": "chromosomes", "display_name": "Chromosomes", "city_name": "Library",
			"function_text": "Store, protect and spread your DNA around the cell. They wear down and need energy to repair, and must sit beside the nucleus.",
			"city_text": "A library holds information on how to do things, make things and where places are. Chromosomes store information on what the cell should do and look like.",
			"water_use": 3.0, "waste_production": 0.3, "needs_energy_link": false,
			"decay_per_second": 0.1, "repair_energy_cost": 3.0,
			"unlock_thresholds": {"water": 150.0}
		},
		{
			"id": "chloroplast", "display_name": "Chloroplast", "city_name": "Solar panels",
			"function_text": "Where photosynthesis happens. In plant cells this is where food comes from for the mitochondria to turn into energy.",
			"city_text": "Solar panels are chloroplasts of a city: they take sunlight and make it into usable energy.",
			"energy_use": 20.0, "water_use": 10.0, "waste_production": 1.0, "food_output_plant": 20.0,
			"allowed_cell_types": PackedInt32Array([PLANT]), "repair_energy_cost": 5.0
		},
		{
			"id": "endoplasmic_reticulum", "display_name": "Endoplasmic reticulum", "city_name": "Factory",
			"function_text": "Folded canals that make proteins and lipids. Here it stores fat: a mitochondria placed right beside it and linked to it can burn that fat when food runs short.",
			"city_text": "A factory quickly creates goods and sends them on their way. The ER makes proteins and lipids and holds the reserves that keep production going.",
			"energy_use": 10.0, "water_use": 10.0, "waste_production": 0.5,
			"fat_access": true, "max_paired_mitochondria": 1, "repair_energy_cost": 3.0, "protein_output": 2.0,
			"unlock_thresholds": {"food": 180.0, "water": 150.0, "waste": 40.0}
		},
		{
			"id": "lysosome", "display_name": "Lysosome", "city_name": "Waste processing facility",
			"function_text": "Takes in waste and turns it into usable nutrients or harmless particles. Its nutrients go back to the cell as food.",
			"city_text": "Waste processing facilities take in garbage and grind it up or burn it for energy. Lysosomes turn waste into usable nutrients.",
			"energy_use": 15.0, "water_use": 5.0,
			"waste_removal_animal": 3.0, "waste_removal_plant": 3.0, "waste_to_food": 0.5,
			"unlock_thresholds": {"waste": 80.0}, "repair_energy_cost": 5.0, "protein_effect": "enzymes"
		},
		{
			"id": "golgi_apparatus", "display_name": "Golgi apparatus", "city_name": "Post office",
			"function_text": "Receives proteins from the ER, packs them into vesicles and sends them where they are needed: half to the lysosomes to help break down waste, half to the membrane to repair it. It holds up to 50 proteins.",
			"city_text": "A post office takes mail and sends it to the right address. The Golgi takes proteins, packages them and labels them for the organelle that needs them.",
			"energy_use": 20.0, "water_use": 10.0,
			"protein_capacity": 50.0, "dispatch_interval": 6.0, "dispatch_amount": 10.0,
			"repair_energy_cost": 5.0,
			"unlock_thresholds": {"food": 190.0, "water": 170.0, "waste": 60.0}
		},
	]
