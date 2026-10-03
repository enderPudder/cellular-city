extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL
const PLANT := OrganelleDef.CellType.PLANT


func suite_name() -> String:
	return "organelle_tip"


func _by_id() -> Dictionary:
	var out := {}
	for d in OrganelleCatalog.load_all():
		out[d.id] = d
	return out


func test_nucleus_lists_everything_it_must_connect_to() -> void:
	var tip := OrganelleTip.build(_by_id()["nucleus"], ANIMAL)
	assert_contains(tip, "Connect it to:")
	assert_contains(tip, "mitochondria")
	assert_contains(tip, "membrane")
	assert_contains(tip, "chromosomes")


func test_water_source_says_what_connects_to_it() -> void:
	var tip := OrganelleTip.build(_by_id()["membrane"], ANIMAL)
	assert_contains(tip, "Connect to it:")
	assert_contains(tip, "water")
	assert_false(tip.contains("Connect it to:"), "membrane needs nothing itself")


func test_mitochondria_needs_water_and_offers_energy_and_fat() -> void:
	var tip := OrganelleTip.build(_by_id()["mitochondria"], ANIMAL)
	assert_contains(tip, "Connect it to:")
	assert_contains(tip, "membrane")
	assert_contains(tip, "Connect to it:")
	assert_contains(tip, "energy")
	assert_contains(tip, "ER")


func test_er_wants_an_adjacent_linked_mitochondria() -> void:
	var tip := OrganelleTip.build(_by_id()["endoplasmic_reticulum"], ANIMAL)
	assert_contains(tip, "Connect to it:")
	assert_contains(tip, "mitochondria")
	assert_contains(tip, "touching")


func test_golgi_and_er_mention_each_other() -> void:
	var by_id := _by_id()
	var golgi := OrganelleTip.build(by_id["golgi_apparatus"], ANIMAL)
	assert_contains(golgi, "Connect it to:")
	assert_contains(golgi, "mitochondria")
	assert_contains(golgi, "Connect to it:")
	assert_contains(golgi, "ER")
	assert_contains(OrganelleTip.build(by_id["endoplasmic_reticulum"], ANIMAL), "golgi")


func test_cytoplasm_needs_no_connections() -> void:
	assert_contains(OrganelleTip.build(_by_id()["cytoplasm"], ANIMAL), "Needs no connections")


func test_water_source_wording_depends_on_cell_type() -> void:
	var def: OrganelleDef = _by_id()["lysosome"]
	assert_false(OrganelleTip.build(def, ANIMAL).contains("cell wall"))
	assert_contains(OrganelleTip.build(def, PLANT), "cell wall")


func test_locked_organelle_shows_its_requirement() -> void:
	var tip := OrganelleTip.build(_by_id()["vacuole"], ANIMAL, {"water": [60.0, 150.0], "waste": [3.0, 20.0]})
	assert_contains(tip, "Locked")
	assert_contains(tip, "water 150")
	assert_contains(tip, "waste 20")


func test_every_tip_is_short_enough_to_fit_on_screen() -> void:
	for d in OrganelleCatalog.load_all():
		for ct in [ANIMAL, PLANT]:
			var n := OrganelleTip.build(d, ct, {"water": [0.0, 150.0], "food": [0.0, 180.0], "waste": [0.0, 40.0]}).length()
			assert_true(n <= 420, "%s tip is %d chars" % [d.id, n])
