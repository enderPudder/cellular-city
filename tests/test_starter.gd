extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL
const PLANT := OrganelleDef.CellType.PLANT


func suite_name() -> String:
	return "starter"


func _built(cell_type: int) -> CellSim:
	var s := CellSim.new(OrganelleCatalog.load_all(), cell_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	StarterLayout.build(s, rng)
	return s


func _count(s: CellSim, id: String) -> int:
	var n := 0
	for o: PlacedOrganelle in s.organelles.values():
		if o.def.id == id:
			n += 1
	return n


func test_ring_has_the_expected_tile_count_and_no_duplicates() -> void:
	var cells := StarterLayout.ring(StarterLayout.HALF)
	assert_eq(cells.size(), 76)
	var unique := {}
	for c in cells:
		unique[c] = true
	assert_eq(unique.size(), 76)


func test_in_bounds() -> void:
	assert_true(StarterLayout.in_bounds(Vector2i(0, 0), ANIMAL))
	assert_true(StarterLayout.in_bounds(Vector2i(12, 7), ANIMAL))
	assert_false(StarterLayout.in_bounds(Vector2i(13, 0), ANIMAL))
	assert_true(StarterLayout.in_bounds(Vector2i(13, 8), PLANT))
	assert_false(StarterLayout.in_bounds(Vector2i(14, 0), PLANT))
	assert_false(StarterLayout.in_bounds(Vector2i(0, -9), PLANT))


func test_animal_layout_contents() -> void:
	var s := _built(ANIMAL)
	assert_eq(_count(s, "membrane"), 76)
	assert_eq(_count(s, "cell_wall"), 0)
	assert_eq(_count(s, "nucleus"), 1)
	assert_eq(_count(s, "chromosomes"), 1)
	assert_eq(_count(s, "mitochondria"), 1)
	assert_eq(_count(s, "chloroplast"), 0)


func test_plant_layout_adds_wall_and_chloroplast() -> void:
	var s := _built(PLANT)
	assert_eq(_count(s, "cell_wall"), 84)
	assert_eq(_count(s, "chloroplast"), 1)


func test_starting_organelles_are_all_running_after_one_tick() -> void:
	for ct in [ANIMAL, PLANT]:
		var s := _built(ct)
		s.tick(1.0)
		for o: PlacedOrganelle in s.organelles.values():
			if o.def.id in ["nucleus", "chromosomes", "mitochondria", "chloroplast"]:
				assert_true(o.running, "%s not running (cell type %d)" % [o.def.id, ct])


func test_untouched_cell_survives_thirty_seconds_with_positive_meters() -> void:
	for ct in [ANIMAL, PLANT]:
		var s := _built(ct)
		for i in 30:
			s.tick(1.0)
		assert_false(s.is_lost, "cell type %d lost: %s" % [ct, s.lost_reason])
		assert_gt(s.meters["energy"], 0.0)
		assert_gt(s.meters["food"], 0.0, "food, cell type %d" % ct)
		assert_gt(s.meters["water"], 0.0)
