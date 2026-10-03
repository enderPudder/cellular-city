extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL
const PLANT := OrganelleDef.CellType.PLANT


func suite_name() -> String:
	return "sim_core"


func _sim(cell_type: int = ANIMAL) -> CellSim:
	var s := CellSim.new([
		DefsFactory.make("plain"),
		DefsFactory.make("plant_only", {"allowed_cell_types": PackedInt32Array([PLANT])}),
		DefsFactory.make("gated", {"unlock_thresholds": {"water": 80.0}}),
		DefsFactory.make("costly", {"placement_energy_cost": 30.0}),
		DefsFactory.make("blob", {"max_group_size_animal": 2}),
		DefsFactory.make("mito", {"max_load": 150.0, "needs_energy_link": false, "energy_output": 150.0}),
		DefsFactory.make("wall", {"water_output": 1.0, "needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("er", {"fat_access": true}),
	], cell_type)
	s.nucleus_required = false
	return s


func test_place_returns_uid_and_marks_cell() -> void:
	var s := _sim()
	var uid := s.add_organelle("plain", Vector2i(2, 3))
	assert_gt(uid, 0)
	assert_eq(s.organelle_at(Vector2i(2, 3)), uid)
	assert_eq(s.organelle_at(Vector2i(9, 9)), -1)


func test_occupied_cell_is_refused() -> void:
	var s := _sim()
	s.add_organelle("plain", Vector2i(0, 0))
	assert_eq(s.can_place("plain", Vector2i(0, 0)), "occupied")
	assert_eq(s.add_organelle("plain", Vector2i(0, 0)), -1)


func test_plant_only_refused_for_animal_but_not_plant() -> void:
	assert_eq(_sim(ANIMAL).can_place("plant_only", Vector2i.ZERO), "wrong_cell_type")
	assert_eq(_sim(PLANT).can_place("plant_only", Vector2i.ZERO), "")


func test_unknown_id_is_refused() -> void:
	assert_eq(_sim().can_place("nope", Vector2i.ZERO), "unknown")


func test_locked_until_threshold_met_without_spending_it() -> void:
	var s := _sim()
	var got: Array = []
	s.unlocked.connect(func(id: String) -> void: got.append(id))
	assert_eq(s.can_place("gated", Vector2i.ZERO), "locked")
	s.meters["water"] = 90.0
	s.refresh_unlocks()
	assert_eq(got, ["gated"])
	assert_eq(s.can_place("gated", Vector2i.ZERO), "")
	s.add_organelle("gated", Vector2i.ZERO)
	assert_eq(s.meters["water"], 90.0, "threshold is a gate, never spent")
	s.refresh_unlocks()
	assert_eq(got.size(), 1, "unlock signal fires only once")


func test_unlock_progress_reports_current_and_required() -> void:
	var s := _sim()
	assert_eq(s.unlock_progress("gated"), {"water": [60.0, 80.0]})


func test_placement_costs_energy_and_is_refused_when_short() -> void:
	var s := _sim()
	s.meters["energy"] = 20.0
	assert_eq(s.can_place("costly", Vector2i.ZERO), "no_energy")
	assert_eq(s.meters["energy"], 20.0, "refusal spends nothing")
	s.meters["energy"] = 50.0
	s.add_organelle("costly", Vector2i.ZERO)
	assert_eq(s.meters["energy"], 20.0)


func test_free_placement_skips_cost_and_lock() -> void:
	var s := _sim()
	s.meters["energy"] = 0.0
	assert_gt(s.add_organelle("costly", Vector2i(0, 0), true), 0)
	assert_gt(s.add_organelle("gated", Vector2i(1, 0), true), 0)
	assert_eq(s.meters["energy"], 0.0)


func test_group_size_limit_counts_connected_same_type_tiles() -> void:
	var s := _sim()
	s.add_organelle("blob", Vector2i(0, 0))
	s.add_organelle("blob", Vector2i(1, 0))
	assert_eq(s.can_place("blob", Vector2i(2, 0)), "group_full")
	assert_eq(s.can_place("blob", Vector2i(5, 5)), "", "a separate group is fine")


func test_infer_link_types() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	var wall := s.add_organelle("wall", Vector2i(2, 0))
	var er := s.add_organelle("er", Vector2i(3, 0))
	assert_eq(s.infer_link_type(plain, mito), SimLink.Type.ENERGY)
	assert_eq(s.infer_link_type(plain, wall), SimLink.Type.WATER)
	assert_eq(s.infer_link_type(mito, er), SimLink.Type.FAT)
	assert_eq(s.infer_link_type(wall, mito), -1)
	assert_eq(s.infer_link_type(plain, plain), -1)
	assert_eq(s.infer_link_type(plain, 999), -1)


func test_duplicate_link_rejected() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	assert_true(s.add_link(plain, mito))
	assert_false(s.add_link(plain, mito))
	assert_eq(s.links.size(), 1)


func test_removing_an_organelle_removes_its_links() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	var wall := s.add_organelle("wall", Vector2i(2, 0))
	s.add_link(plain, mito)
	s.add_link(plain, wall)
	var removed: Array = []
	s.organelle_removed.connect(func(uid: int, cell: Vector2i, id: String) -> void: removed.append([uid, cell, id]))
	s.remove_organelle(mito)
	assert_eq(s.links.size(), 1)
	assert_eq(s.organelle_at(Vector2i(1, 0)), -1)
	assert_eq(removed, [[mito, Vector2i(1, 0), "mito"]])


func test_remove_links_of_clears_both_directions() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	s.add_link(plain, mito)
	s.remove_links_of(mito)
	assert_eq(s.links.size(), 0)


func test_water_capacity_includes_bonus_from_alive_organelles() -> void:
	var s := CellSim.new([DefsFactory.make("tank", {"water_capacity_bonus": 40.0})], ANIMAL)
	s.nucleus_required = false
	assert_eq(s.capacities()["water"], 200.0)
	s.add_organelle("tank", Vector2i.ZERO)
	assert_eq(s.capacities()["water"], 240.0)
