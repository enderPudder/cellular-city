extends McpTestSuite

const ANIMAL := OrganelleDef.CellType.ANIMAL


func suite_name() -> String:
	return "sim_proteins"


func _near(a: float, b: float, msg: String = "") -> void:
	assert_true(absf(a - b) < 0.001, "%s: %s != %s" % [msg, a, b])


func _sim() -> CellSim:
	var free := {"needs_energy_link": false, "needs_water_link": false}
	var s := CellSim.new([
		DefsFactory.make("er", {"protein_output": 2.0}.merged(free)),
		DefsFactory.make("er_needy", {"protein_output": 2.0}),
		DefsFactory.make("golgi", {"protein_capacity": 50.0, "dispatch_interval": 5.0, "dispatch_amount": 10.0}.merged(free)),
		DefsFactory.make("lyso", {"waste_removal_animal": 4.0, "protein_effect": "enzymes"}.merged(free)),
		DefsFactory.make("mem", {"water_output": 1.0, "protein_effect": "repair"}.merged(free)),
	], ANIMAL)
	s.nucleus_required = false
	return s


func _golgi_with_er(s: CellSim) -> Array:
	var er := s.add_organelle("er", Vector2i(0, 0))
	var g := s.add_organelle("golgi", Vector2i(1, 0))
	return [er, g]


func _collect(s: CellSim) -> Array:
	var got: Array = []
	s.shipment_dispatched.connect(func(sh: Shipment) -> void: got.append(sh))
	return got


func test_only_an_er_can_link_proteins_to_a_golgi() -> void:
	var s := _sim()
	var pair := _golgi_with_er(s)
	var mem := s.add_organelle("mem", Vector2i(5, 5))
	assert_eq(s.infer_link_type(pair[0], pair[1]), SimLink.Type.PROTEIN)
	assert_eq(s.infer_link_type(pair[1], pair[0]), -1)
	assert_eq(s.infer_link_type(mem, pair[1]), -1)


func test_linked_er_fills_the_golgi() -> void:
	var s := _sim()
	var pair := _golgi_with_er(s)
	s.add_link(pair[0], pair[1])
	s.tick(1.0)
	_near((s.organelles[pair[1]] as PlacedOrganelle).proteins, 2.0)


func test_unlinked_er_makes_no_proteins() -> void:
	var s := _sim()
	var pair := _golgi_with_er(s)
	s.tick(3.0)
	_near((s.organelles[pair[1]] as PlacedOrganelle).proteins, 0.0)


func test_er_that_is_not_running_makes_no_proteins() -> void:
	var s := _sim()
	var er := s.add_organelle("er_needy", Vector2i(0, 0))
	var g := s.add_organelle("golgi", Vector2i(1, 0))
	s.add_link(er, g)
	s.tick(1.0)
	_near((s.organelles[g] as PlacedOrganelle).proteins, 0.0, "no energy or water links, so the ER is idle")


func test_golgi_holds_at_most_its_capacity() -> void:
	var s := _sim()
	var pair := _golgi_with_er(s)
	s.add_link(pair[0], pair[1])
	s.tick(100.0)
	assert_true((s.organelles[pair[1]] as PlacedOrganelle).proteins <= 50.0)


func test_dispatch_splits_half_to_lysosome_and_half_to_the_weakest_membrane() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	var lyso := s.add_organelle("lyso", Vector2i(5, 0))
	var weak := s.add_organelle("mem", Vector2i(6, 0))
	var strong := s.add_organelle("mem", Vector2i(7, 0))
	(s.organelles[weak] as PlacedOrganelle).health = 40.0
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	var got := _collect(s)
	s.tick(5.0)
	assert_eq(got.size(), 2)
	var by_effect := {}
	for sh: Shipment in got:
		by_effect[sh.effect] = sh
	_near(by_effect["enzymes"].proteins, 5.0)
	assert_eq(by_effect["enzymes"].to_uid, lyso)
	_near(by_effect["repair"].proteins, 5.0)
	assert_eq(by_effect["repair"].to_uid, weak)
	assert_eq(by_effect["repair"].from_uid, g)
	_near((s.organelles[g] as PlacedOrganelle).proteins, 10.0, "10 proteins left the golgi")
	assert_true(strong > 0)


func test_with_only_a_membrane_everything_goes_there() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	var mem := s.add_organelle("mem", Vector2i(6, 0))
	(s.organelles[mem] as PlacedOrganelle).health = 50.0
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	var got := _collect(s)
	s.tick(5.0)
	assert_eq(got.size(), 1)
	_near(got[0].proteins, 10.0)
	assert_eq(got[0].effect, "repair")


func test_a_healthy_membrane_is_not_sent_repair_proteins() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	s.add_organelle("mem", Vector2i(6, 0))
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	var got := _collect(s)
	s.tick(5.0)
	assert_eq(got.size(), 0)
	_near((s.organelles[g] as PlacedOrganelle).proteins, 20.0)


func test_with_no_destination_the_proteins_stay_in_the_golgi() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	var got := _collect(s)
	s.tick(5.0)
	assert_eq(got.size(), 0)
	_near((s.organelles[g] as PlacedOrganelle).proteins, 20.0)


func test_a_golgi_that_is_not_running_does_not_dispatch() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	var mem := s.add_organelle("mem", Vector2i(6, 0))
	(s.organelles[mem] as PlacedOrganelle).health = 50.0
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	(s.organelles[g] as PlacedOrganelle).disabled = true
	var got := _collect(s)
	s.tick(10.0)
	assert_eq(got.size(), 0)


func test_no_dispatch_before_the_interval() -> void:
	var s := _sim()
	var g := s.add_organelle("golgi", Vector2i(0, 0))
	var mem := s.add_organelle("mem", Vector2i(6, 0))
	(s.organelles[mem] as PlacedOrganelle).health = 50.0
	(s.organelles[g] as PlacedOrganelle).proteins = 20.0
	var got := _collect(s)
	s.tick(4.0)
	assert_eq(got.size(), 0)


func test_delivered_proteins_repair_a_membrane_up_to_full_health() -> void:
	var s := _sim()
	var mem := s.add_organelle("mem", Vector2i(0, 0))
	var o := s.organelles[mem] as PlacedOrganelle
	o.health = 60.0
	var sh := Shipment.make(1, 99, mem, 5.0, "repair")
	s.deliver(sh)
	_near(o.health, 75.0, "5 proteins repair 15")
	s.deliver(Shipment.make(2, 99, mem, 50.0, "repair"))
	_near(o.health, 100.0, "capped")


func test_delivered_proteins_speed_up_a_lysosome() -> void:
	var plain := _sim()
	plain.add_organelle("lyso", Vector2i(0, 0))
	plain.meters["waste"] = 20.0
	plain.tick(1.0)
	_near(plain.meters["waste"], 16.0, "4/s without enzymes")
	var boosted := _sim()
	var lyso := boosted.add_organelle("lyso", Vector2i(0, 0))
	boosted.meters["waste"] = 20.0
	boosted.deliver(Shipment.make(1, 99, lyso, 5.0, "enzymes"))
	boosted.tick(1.0)
	_near(boosted.meters["waste"], 14.0, "6/s with enzymes")


func test_enzymes_run_out() -> void:
	var s := _sim()
	var lyso := s.add_organelle("lyso", Vector2i(0, 0))
	s.deliver(Shipment.make(1, 99, lyso, 1.0, "enzymes"))
	for i in 30:
		s.meters["waste"] = 20.0
		s.tick(1.0)
	_near((s.organelles[lyso] as PlacedOrganelle).enzymes, 0.0)
	s.meters["waste"] = 20.0
	s.tick(1.0)
	_near(s.meters["waste"], 16.0, "back to the normal rate")


func test_delivery_to_a_removed_target_is_harmless() -> void:
	var s := _sim()
	var mem := s.add_organelle("mem", Vector2i(0, 0))
	s.remove_organelle(mem)
	var delivered: Array = []
	s.shipment_delivered.connect(func(sh: Shipment) -> void: delivered.append(sh))
	s.deliver(Shipment.make(1, 99, mem, 5.0, "repair"))
	assert_eq(delivered.size(), 0)
