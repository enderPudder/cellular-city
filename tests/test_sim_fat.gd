extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL


func suite_name() -> String:
	return "sim_fat"


func _near(a: float, b: float, msg: String = "") -> void:
	assert_true(absf(a - b) < 0.001, "%s: %s != %s" % [msg, a, b])


func _sim() -> CellSim:
	var s := CellSim.new([
		DefsFactory.make("mito", {"max_load": 150.0, "needs_energy_link": false, "needs_water_link": false,
			"energy_output": 150.0, "food_use": 20.0}),
		DefsFactory.make("er", {"fat_access": true, "max_paired_mitochondria": 1,
			"needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("farm", {"food_output_animal": 50.0, "needs_energy_link": false, "needs_water_link": false}),
	], ANIMAL)
	s.nucleus_required = false
	s.meters["food"] = 0.0
	s.meters["fat"] = 50.0
	s.meters["energy"] = 0.0
	return s


func test_mitochondria_without_er_starves_when_food_is_gone() -> void:
	var s := _sim()
	s.add_organelle("mito", Vector2i(0, 0))
	s.tick(1.0)
	_near(s.meters["energy"], 0.0)
	_near(s.meters["fat"], 50.0, "fat untouched")


func test_adjacent_linked_er_lets_mitochondria_burn_fat() -> void:
	var s := _sim()
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var er := s.add_organelle("er", Vector2i(1, 0))
	assert_true(s.add_link(mito, er))
	s.tick(1.0)
	assert_true(s.is_fat_paired(mito))
	_near(s.meters["energy"], 150.0)
	_near(s.meters["fat"], 30.0)


func test_adjacent_but_unlinked_er_does_not_help() -> void:
	var s := _sim()
	s.add_organelle("mito", Vector2i(0, 0))
	s.add_organelle("er", Vector2i(1, 0))
	s.tick(1.0)
	_near(s.meters["energy"], 0.0)


func test_linked_but_not_adjacent_er_does_not_help() -> void:
	var s := _sim()
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var er := s.add_organelle("er", Vector2i(3, 0))
	assert_true(s.add_link(mito, er))
	s.tick(1.0)
	assert_false(s.is_fat_paired(mito))
	_near(s.meters["energy"], 0.0)


func test_one_er_pairs_with_only_one_mitochondria() -> void:
	var s := _sim()
	var m1 := s.add_organelle("mito", Vector2i(0, 0))
	var er := s.add_organelle("er", Vector2i(1, 0))
	var m2 := s.add_organelle("mito", Vector2i(2, 0))
	s.add_link(m1, er)
	s.add_link(m2, er)
	s.tick(1.0)
	assert_true(s.is_fat_paired(m1))
	assert_false(s.is_fat_paired(m2))
	_near(s.meters["energy"], 150.0, "only one mitochondria ran on fat")


func test_food_is_used_before_fat() -> void:
	var s := _sim()
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var er := s.add_organelle("er", Vector2i(1, 0))
	s.add_link(mito, er)
	s.meters["food"] = 20.0
	s.tick(1.0)
	_near(s.meters["fat"], 50.0, "food covered the need")


func test_partial_fuel_scales_energy() -> void:
	var s := _sim()
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var er := s.add_organelle("er", Vector2i(1, 0))
	s.add_link(mito, er)
	s.meters["food"] = 5.0
	s.meters["fat"] = 5.0
	s.tick(1.0)
	_near(s.meters["energy"], 75.0, "10 of 20 fuel = half output")


func test_surplus_food_converts_to_fat() -> void:
	var s := _sim()
	s.add_organelle("farm", Vector2i.ZERO)
	s.meters["food"] = 190.0
	s.meters["fat"] = 30.0
	s.tick(1.0)
	_near(s.meters["food"], 200.0)
	_near(s.meters["fat"], 50.0, "40 surplus * 0.5")
