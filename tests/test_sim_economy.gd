extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL


func suite_name() -> String:
	return "sim_economy"


func _near(a: float, b: float, msg: String = "") -> void:
	assert_true(absf(a - b) < 0.001, "%s: %s != %s" % [msg, a, b])


func _sim() -> CellSim:
	var s := CellSim.new([
		DefsFactory.make("consumer", {"energy_use": 10.0, "water_use": 5.0, "waste_production": 2.0}),
		DefsFactory.make("hog", {"energy_use": 100.0, "water_use": 0.0}),
		DefsFactory.make("mito", {"max_load": 150.0, "needs_energy_link": false, "needs_water_link": false,
			"energy_output": 150.0, "food_use": 20.0}),
		DefsFactory.make("wall", {"water_output": 1.0, "needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("eater", {"waste_removal_animal": 3.0, "waste_to_food": 0.5,
			"needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("tank", {"water_capacity_bonus": 40.0, "needs_energy_link": false, "needs_water_link": false}),
	], ANIMAL)
	s.nucleus_required = false
	return s


func _powered_consumer(s: CellSim) -> int:
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var wall := s.add_organelle("wall", Vector2i(9, 9))
	var c := s.add_organelle("consumer", Vector2i(1, 0))
	s.add_link(c, mito)
	s.add_link(c, wall)
	return c


func test_unlinked_consumer_does_not_run() -> void:
	var s := _sim()
	var c := s.add_organelle("consumer", Vector2i.ZERO)
	s.tick(1.0)
	assert_false((s.organelles[c] as PlacedOrganelle).running)
	assert_eq(s.meters["energy"], 100.0)
	assert_eq(s.meters["waste"], 0.0)


func test_linked_consumer_runs_and_balances_meters() -> void:
	var s := _sim()
	var c := _powered_consumer(s)
	s.meters["energy"] = 0.0
	s.tick(1.0)
	assert_true((s.organelles[c] as PlacedOrganelle).running)
	_near(s.meters["food"], 30.0, "mito burned 20 food")
	_near(s.meters["energy"], 140.0, "150 made, 10 used")
	_near(s.meters["water"], 56.0, "60 + 1 collected - 5 used")
	_near(s.meters["waste"], 2.0, "waste produced")


func test_supplier_capacity_starves_extra_consumers() -> void:
	var s := _sim()
	var mito := s.add_organelle("mito", Vector2i(0, 0))
	var a := s.add_organelle("hog", Vector2i(1, 0))
	var b := s.add_organelle("hog", Vector2i(2, 0))
	s.add_link(a, mito)
	s.add_link(b, mito)
	s.tick(1.0)
	assert_true((s.organelles[a] as PlacedOrganelle).energy_ok)
	assert_false((s.organelles[b] as PlacedOrganelle).energy_ok, "second hog exceeds max_load 150")


func test_decayed_membrane_yields_one_sixteenth_water() -> void:
	var s := _sim()
	var wall := s.add_organelle("wall", Vector2i.ZERO)
	s.meters["water"] = 0.0
	s.tick(1.0)
	_near(s.meters["water"], 1.0, "healthy wall")
	s.meters["water"] = 0.0
	(s.organelles[wall] as PlacedOrganelle).health = 50.0
	s.tick(1.0)
	_near(s.meters["water"], 1.0 / 16.0, "decayed wall")


func test_dead_water_source_stops_supplying() -> void:
	var s := _sim()
	var wall := s.add_organelle("wall", Vector2i(5, 5))
	var c := s.add_organelle("consumer", Vector2i(0, 0))
	s.add_link(c, wall)
	(s.organelles[wall] as PlacedOrganelle).health = 0.0
	s.tick(1.0)
	assert_false((s.organelles[c] as PlacedOrganelle).water_ok)


func test_erasing_supplier_unpowers_dependents() -> void:
	var s := _sim()
	var c := _powered_consumer(s)
	s.tick(1.0)
	assert_true((s.organelles[c] as PlacedOrganelle).running)
	s.remove_organelle(s.organelle_at(Vector2i(0, 0)))
	s.tick(1.0)
	assert_false((s.organelles[c] as PlacedOrganelle).energy_ok)
	assert_false((s.organelles[c] as PlacedOrganelle).running)


func test_waste_removal_turns_waste_into_food() -> void:
	var s := _sim()
	s.add_organelle("eater", Vector2i.ZERO)
	s.meters["waste"] = 10.0
	s.meters["food"] = 0.0
	s.tick(1.0)
	_near(s.meters["waste"], 7.0)
	_near(s.meters["food"], 1.5)


func test_waste_removal_cannot_go_below_zero() -> void:
	var s := _sim()
	s.add_organelle("eater", Vector2i.ZERO)
	s.meters["waste"] = 1.0
	s.tick(1.0)
	_near(s.meters["waste"], 0.0)


func test_meters_stay_in_range_with_huge_dt() -> void:
	var s := _sim()
	_powered_consumer(s)
	s.add_organelle("eater", Vector2i(3, 3))
	s.tick(100000.0)
	var caps := s.capacities()
	for m in CellSim.METERS:
		assert_true(s.meters[m] >= 0.0 and s.meters[m] <= caps[m], "%s = %s" % [m, s.meters[m]])
		assert_false(is_nan(s.meters[m]), m + " is NaN")


func test_energy_shortage_scales_output_instead_of_going_negative() -> void:
	var s := _sim()
	var wall := s.add_organelle("wall", Vector2i(9, 9))
	var hog := s.add_organelle("hog", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	s.add_link(hog, mito)
	s.meters["food"] = 0.0
	s.meters["energy"] = 50.0
	s.tick(1.0)
	assert_true(s.meters["energy"] >= 0.0)
	assert_true(wall > 0)
