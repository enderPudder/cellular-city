extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL


func suite_name() -> String:
	return "sim_survival"


func _sim(extra: Array = []) -> CellSim:
	var defs: Array = [
		DefsFactory.make("nucleus", {"needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("rusty", {"decay_per_second": 1.0, "repair_energy_cost": 5.0,
			"needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("plain", {"needs_energy_link": false, "needs_water_link": false}),
		DefsFactory.make("late", {"unlock_thresholds": {"waste": 25.0}}),
	]
	defs.append_array(extra)
	return CellSim.new(defs, ANIMAL)


func test_decay_scales_with_multiplier() -> void:
	var s := _sim()
	s.nucleus_required = false
	var uid := s.add_organelle("rusty", Vector2i.ZERO)
	s.decay_multiplier = 2.0
	s.tick(1.0)
	assert_eq((s.organelles[uid] as PlacedOrganelle).health, 98.0)


func test_health_never_goes_below_zero() -> void:
	var s := _sim()
	s.nucleus_required = false
	var uid := s.add_organelle("rusty", Vector2i.ZERO)
	s.tick(500.0)
	assert_eq((s.organelles[uid] as PlacedOrganelle).health, 0.0)
	assert_false((s.organelles[uid] as PlacedOrganelle).alive())


func test_waste_at_cap_damages_everything() -> void:
	var s := _sim()
	s.nucleus_required = false
	var uid := s.add_organelle("plain", Vector2i.ZERO)
	s.meters["waste"] = 200.0
	s.tick(1.0)
	assert_eq((s.organelles[uid] as PlacedOrganelle).health, 98.0)


func test_repair_restores_health_and_spends_energy() -> void:
	var s := _sim()
	s.nucleus_required = false
	var uid := s.add_organelle("rusty", Vector2i.ZERO)
	var o := s.organelles[uid] as PlacedOrganelle
	o.health = 10.0
	o.disabled = true
	assert_true(s.needs_repair(uid))
	assert_true(s.repair(uid))
	assert_eq(o.health, 100.0)
	assert_false(o.disabled)
	assert_eq(s.meters["energy"], 95.0)
	assert_false(s.needs_repair(uid))
	assert_false(s.repair(uid), "healthy organelle needs no repair")


func test_repair_refused_without_energy() -> void:
	var s := _sim()
	s.nucleus_required = false
	var uid := s.add_organelle("rusty", Vector2i.ZERO)
	(s.organelles[uid] as PlacedOrganelle).health = 10.0
	s.meters["energy"] = 4.0
	assert_false(s.repair(uid))
	assert_eq(s.meters["energy"], 4.0)


func test_losing_without_a_nucleus_takes_exactly_three_seconds() -> void:
	var s := _sim()
	var reasons: Array = []
	s.lost.connect(func(r: String) -> void: reasons.append(r))
	s.tick(1.0)
	s.tick(1.0)
	assert_false(s.is_lost)
	s.tick(1.0)
	assert_true(s.is_lost)
	assert_eq(reasons, ["nucleus"])
	assert_eq(s.lost_reason, "nucleus")


func test_running_nucleus_keeps_the_cell_alive_and_ticks_stop_after_loss() -> void:
	var s := _sim()
	s.add_organelle("nucleus", Vector2i.ZERO)
	for i in 10:
		s.tick(1.0)
	assert_false(s.is_lost)
	s.force_lose("test")
	var before := s.elapsed
	s.tick(1.0)
	assert_eq(s.elapsed, before, "tick is a no-op after losing")


func test_disabled_nucleus_counts_as_missing() -> void:
	var s := _sim()
	var uid := s.add_organelle("nucleus", Vector2i.ZERO)
	(s.organelles[uid] as PlacedOrganelle).disabled = true
	s.tick(1.0)
	s.tick(1.0)
	s.tick(1.0)
	assert_true(s.is_lost)


func test_repairing_the_nucleus_in_time_resets_the_grace_period() -> void:
	var s := _sim()
	var uid := s.add_organelle("nucleus", Vector2i.ZERO)
	var o := s.organelles[uid] as PlacedOrganelle
	o.disabled = true
	s.tick(1.0)
	s.tick(1.0)
	s.repair(uid)
	s.tick(1.0)
	s.tick(1.0)
	s.tick(1.0)
	assert_false(s.is_lost)


func test_unlock_fires_during_tick_when_threshold_is_reached() -> void:
	var s := _sim()
	s.nucleus_required = false
	var got: Array = []
	s.unlocked.connect(func(id: String) -> void: got.append(id))
	s.tick(1.0)
	assert_eq(got, [])
	s.meters["waste"] = 30.0
	s.tick(1.0)
	assert_eq(got, ["late"])
