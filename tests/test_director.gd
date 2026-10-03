extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL


func suite_name() -> String:
	return "director"


func _near(a: float, b: float, msg: String = "") -> void:
	assert_true(absf(a - b) < 0.001, "%s: %s != %s" % [msg, a, b])


func _sim() -> CellSim:
	var s := CellSim.new([
		DefsFactory.make("plain", {"needs_energy_link": false, "needs_water_link": true}),
		DefsFactory.make("wall", {"water_output": 1.0, "needs_energy_link": false, "needs_water_link": false}),
	], ANIMAL)
	s.nucleus_required = false
	return s


func _director(s: CellSim, bacteria_chance: float) -> DamageDirector:
	var curve := DifficultyCurve.new()
	curve.first_event_delay = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var d := DamageDirector.new(s, curve, rng)
	d.bacteria_chance = bacteria_chance
	return d


func test_curve_values_ramp_and_clamp() -> void:
	var c := DifficultyCurve.new()
	_near(c.event_interval(0.0), 40.0)
	_near(c.event_interval(600.0), 12.0)
	_near(c.event_interval(99999.0), 12.0)
	_near(c.repair_window(0.0), 60.0)
	_near(c.repair_window(600.0), 20.0)
	_near(c.repair_window(99999.0), 20.0)
	assert_eq(c.event_size(0.0), 1)
	assert_eq(c.event_size(450.0), 3)
	assert_eq(c.event_size(99999.0), 5)
	_near(c.decay_multiplier(0.0), 1.0)
	_near(c.decay_multiplier(900.0), 2.0)


func test_no_event_before_the_first_delay() -> void:
	var s := _sim()
	s.add_organelle("plain", Vector2i(0, 0))
	var d := _director(s, 1.0)
	d._time_to_event = 5.0
	d.tick(1.0)
	assert_eq(d.timers.size(), 0)


func test_bacteria_disables_an_organelle_and_starts_a_repair_timer() -> void:
	var s := _sim()
	s.add_organelle("plain", Vector2i(0, 0))
	var d := _director(s, 1.0)
	var labels: Array = []
	d.event_fired.connect(func(l: String) -> void: labels.append(l))
	d.tick(1.0)
	assert_eq(d.timers.size(), 1)
	_near(d.timers[0]["remaining"], 60.0)
	assert_eq(labels.size(), 1)
	var disabled := 0
	for o: PlacedOrganelle in s.organelles.values():
		if o.disabled:
			disabled += 1
	assert_eq(disabled, 1)


func test_repairing_in_time_clears_the_timer() -> void:
	var s := _sim()
	var uid := s.add_organelle("plain", Vector2i(0, 0))
	var d := _director(s, 1.0)
	d.tick(1.0)
	assert_true(s.repair(uid))
	d.tick(1.0)
	assert_eq(d.timers.size(), 0)
	assert_false(s.is_lost)


func test_unrepaired_damage_loses_the_game_when_the_window_closes() -> void:
	var s := _sim()
	s.add_organelle("plain", Vector2i(0, 0))
	var d := _director(s, 1.0)
	d.tick(1.0)
	d.tick(30.0)
	assert_false(s.is_lost)
	d.tick(31.0)
	assert_true(s.is_lost)
	assert_eq(s.lost_reason, "repair_timeout")


func test_cut_removes_a_link_and_relinking_clears_the_timer() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var wall := s.add_organelle("wall", Vector2i(5, 5))
	assert_true(s.add_link(plain, wall))
	var d := _director(s, 0.0)
	d.tick(1.0)
	assert_eq(s.links.size(), 0)
	assert_eq(d.timers.size(), 1)
	s.add_link(plain, wall)
	d.tick(1.0)
	assert_eq(d.timers.size(), 0)


func test_event_with_nothing_to_damage_is_harmless() -> void:
	var s := _sim()
	var d := _director(s, 1.0)
	d.tick(1.0)
	assert_eq(d.timers.size(), 0)
	var d2 := _director(s, 0.0)
	d2.tick(1.0)
	assert_eq(d2.timers.size(), 0)
	assert_false(s.is_lost)


func test_removing_the_damaged_organelle_resolves_its_timer() -> void:
	var s := _sim()
	var uid := s.add_organelle("plain", Vector2i(0, 0))
	var d := _director(s, 1.0)
	d.tick(1.0)
	s.remove_organelle(uid)
	d.tick(1.0)
	assert_eq(d.timers.size(), 0)
