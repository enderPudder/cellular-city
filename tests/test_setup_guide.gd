extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL
const PLANT := OrganelleDef.CellType.PLANT
const ANCHOR := Vector2i(0, -7)


func suite_name() -> String:
	return "setup_guide"


func _shell(cell_type: int) -> CellSim:
	var s := CellSim.new(OrganelleCatalog.load_all(), cell_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	StarterLayout.build_shell(s, rng)
	return s


func _guided(cell_type: int) -> Array:
	var s := _shell(cell_type)
	var g := SetupGuide.new(s)
	g.begin()
	return [s, g]


## Places the nucleus, chromosomes and mitochondria like the guide teaches.
func _place_core(s: CellSim) -> Dictionary:
	return {
		"nucleus": s.add_organelle("nucleus", Vector2i(0, 0)),
		"chromosomes": s.add_organelle("chromosomes", Vector2i(1, 0)),
		"mito": s.add_organelle("mitochondria", Vector2i(-3, 0)),
		"anchor": s.organelle_at(ANCHOR),
	}


func test_animal_has_three_steps_and_plant_has_four() -> void:
	var animal := SetupGuide.new(_shell(ANIMAL)).steps()
	var plant := SetupGuide.new(_shell(PLANT)).steps()
	assert_eq(animal.size(), 3)
	assert_eq(plant.size(), 4)
	assert_eq(animal[0]["id"], "nucleus")
	assert_eq(animal[1]["id"], "power")
	assert_eq(animal[2]["id"], "wire")
	assert_eq(plant[3]["id"], "chloroplast")
	for step in plant:
		assert_true(String(step["label"]) != "" and String(step["hint"]) != "")


func test_begin_unlocks_the_core_and_it_places_with_no_energy() -> void:
	var s := _shell(ANIMAL)
	var g := SetupGuide.new(s)
	assert_eq(s.can_place("chromosomes", Vector2i(1, 0)), "locked")
	g.begin()
	s.meters["energy"] = 0.0
	for id in g.core_ids():
		assert_eq(s.defs[id].placement_energy_cost, 0.0, "%s must stay free to place" % id)
	var core := _place_core(s)
	for key in ["nucleus", "chromosomes", "mito"]:
		assert_gt(core[key], 0, "%s could not be placed" % key)
	assert_eq(s.meters["energy"], 0.0)


func test_steps_tick_one_by_one_for_an_animal() -> void:
	var pair := _guided(ANIMAL)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	assert_eq(g.current_step()["id"], "nucleus")
	var nucleus := s.add_organelle("nucleus", Vector2i(0, 0))
	assert_false(g.step_done("nucleus"), "a nucleus alone is not enough")
	var chromosomes := s.add_organelle("chromosomes", Vector2i(1, 0))
	assert_true(g.step_done("nucleus"))
	assert_eq(g.current_step()["id"], "power")
	var mito := s.add_organelle("mitochondria", Vector2i(-3, 0))
	var anchor := s.organelle_at(ANCHOR)
	assert_false(g.step_done("power"), "a mitochondria with no link is not powered")
	s.add_link(mito, anchor)
	assert_true(g.step_done("power"))
	assert_eq(g.current_step()["id"], "wire")
	s.add_link(nucleus, mito)
	s.add_link(nucleus, anchor)
	assert_false(g.step_done("wire"), "the chromosomes still has no water")
	s.add_link(chromosomes, anchor)
	assert_true(g.step_done("wire"))
	assert_true(g.all_done())
	assert_true(g.current_step().is_empty())


func test_chromosomes_must_touch_the_nucleus() -> void:
	var pair := _guided(ANIMAL)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	s.add_organelle("nucleus", Vector2i(0, 0))
	s.add_organelle("chromosomes", Vector2i(5, 0))
	assert_false(g.step_done("nucleus"))
	assert_eq(g.current_step()["id"], "nucleus")


func test_nucleus_energy_link_must_go_to_an_energy_source() -> void:
	var pair := _guided(ANIMAL)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	var core := _place_core(s)
	s.add_link(core["mito"], core["anchor"])
	s.add_link(core["nucleus"], core["anchor"])
	s.add_link(core["chromosomes"], core["anchor"])
	assert_false(g.step_done("wire"), "water links alone leave the nucleus without energy")
	s.add_link(core["nucleus"], core["mito"])
	assert_true(g.step_done("wire"))


func test_cutting_links_or_erasing_unticks_a_step() -> void:
	var pair := _guided(ANIMAL)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	var core := _place_core(s)
	s.add_link(core["mito"], core["anchor"])
	s.add_link(core["nucleus"], core["mito"])
	s.add_link(core["nucleus"], core["anchor"])
	s.add_link(core["chromosomes"], core["anchor"])
	assert_true(g.all_done())
	s.remove_links_of(core["nucleus"])
	assert_false(g.step_done("wire"))
	assert_false(g.all_done())
	s.remove_organelle(core["chromosomes"])
	assert_false(g.step_done("nucleus"))
	assert_eq(g.current_step()["id"], "nucleus")


func test_refresh_fires_once_and_latches() -> void:
	var pair := _guided(ANIMAL)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	assert_false(g.refresh())
	var core := _place_core(s)
	s.add_link(core["mito"], core["anchor"])
	s.add_link(core["nucleus"], core["mito"])
	s.add_link(core["nucleus"], core["anchor"])
	s.add_link(core["chromosomes"], core["anchor"])
	assert_true(g.refresh())
	assert_false(g.refresh())
	s.remove_links_of(core["nucleus"])
	assert_false(g.all_done())
	assert_true(g.core_done, "erasing later must not undo the latch")
	assert_false(g.refresh())


func test_plant_needs_a_linked_chloroplast_and_a_wall_tile_counts_for_water() -> void:
	var pair := _guided(PLANT)
	var s: CellSim = pair[0]
	var g: SetupGuide = pair[1]
	var core := _place_core(s)
	s.add_link(core["mito"], core["anchor"])
	s.add_link(core["nucleus"], core["mito"])
	s.add_link(core["nucleus"], core["anchor"])
	s.add_link(core["chromosomes"], core["anchor"])
	assert_false(g.all_done())
	assert_eq(g.current_step()["id"], "chloroplast")
	var chloroplast := s.add_organelle("chloroplast", Vector2i(3, 0))
	assert_false(g.step_done("chloroplast"))
	s.add_link(chloroplast, core["mito"])
	assert_false(g.step_done("chloroplast"), "energy alone is not enough")
	var wall := s.organelle_at(Vector2i(0, -8))
	assert_true(s.add_link(chloroplast, wall))
	assert_true(g.step_done("chloroplast"))
	assert_true(g.all_done())


func test_the_old_prebuilt_cell_satisfies_every_step() -> void:
	for ct in [ANIMAL, PLANT]:
		var s := _shell(ct)
		StarterLayout.build_core(s)
		assert_true(SetupGuide.new(s).all_done(), "cell type %d" % ct)
