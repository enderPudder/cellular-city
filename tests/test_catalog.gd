extends McpTestSuite

const EXPECTED_IDS := [
	"membrane", "nucleus", "cytoplasm", "mitochondria", "vacuole",
	"cell_wall", "chromosomes", "chloroplast", "endoplasmic_reticulum", "lysosome", "golgi_apparatus",
]


func suite_name() -> String:
	return "catalog"


func test_all_eleven_organelles_exist() -> void:
	var ids: Array[String] = []
	for d in OrganelleCatalog.load_all():
		ids.append(d.id)
	ids.sort()
	var expected := EXPECTED_IDS.duplicate()
	expected.sort()
	assert_eq(ids, expected)


func test_every_def_has_teaching_text() -> void:
	for d in OrganelleCatalog.load_all():
		assert_false(d.display_name.is_empty(), d.id + " display_name")
		assert_false(d.city_name.is_empty(), d.id + " city_name")
		assert_false(d.function_text.is_empty(), d.id + " function_text")
		assert_false(d.city_text.is_empty(), d.id + " city_text")


func test_thresholds_only_use_food_water_waste() -> void:
	for d in OrganelleCatalog.load_all():
		for key in d.unlock_thresholds:
			assert_contains(["food", "water", "waste"], key, d.id)


func test_plant_only_organelles() -> void:
	var by_id := {}
	for d in OrganelleCatalog.load_all():
		by_id[d.id] = d
	for id in ["cell_wall", "chloroplast"]:
		assert_eq(Array(by_id[id].allowed_cell_types), [OrganelleDef.CellType.PLANT], id)


func test_special_roles() -> void:
	var by_id := {}
	for d in OrganelleCatalog.load_all():
		by_id[d.id] = d
	assert_gt(by_id["mitochondria"].max_load, 0.0)
	assert_true(by_id["endoplasmic_reticulum"].fat_access)
	assert_eq(by_id["endoplasmic_reticulum"].max_paired_mitochondria, 1)
	assert_eq(by_id["nucleus"].requires_adjacent, "chromosomes")
	assert_gt(by_id["endoplasmic_reticulum"].protein_output, 0.0)
	assert_eq(by_id["golgi_apparatus"].protein_capacity, 50.0)
	assert_eq(by_id["lysosome"].protein_effect, "enzymes")
	assert_eq(by_id["membrane"].protein_effect, "repair")
	assert_eq(by_id["cell_wall"].protein_effect, "repair")
