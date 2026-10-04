extends McpTestSuite


func suite_name() -> String:
	return "intro_reveal"


func _tiles(n: int) -> Array[Dictionary]:
	var t: Array[Dictionary] = []
	for i in n:
		t.append({"id": "membrane", "cell": Vector2i(i, 0)})
	return t


func test_every_tile_shown_once_in_order() -> void:
	var seen: Array[Vector2i] = []
	var r := IntroReveal.new(_tiles(10), func(_id: String, cell: Vector2i) -> void: seen.append(cell), 1.0)
	for i in 100:
		r.advance(0.05)
	assert_eq(seen.size(), 10)
	for i in seen.size():
		assert_eq(seen[i], Vector2i(i, 0))
	assert_true(r.done)


func test_tiles_appear_gradually() -> void:
	var seen: Array[Vector2i] = []
	var r := IntroReveal.new(_tiles(10), func(_id: String, cell: Vector2i) -> void: seen.append(cell), 1.0)
	r.advance(0.5)
	assert_eq(seen.size(), 5)
	assert_false(r.done)


func test_finished_fires_once() -> void:
	var count := [0]
	var r := IntroReveal.new(_tiles(3), func(_id: String, _cell: Vector2i) -> void: pass, 1.0)
	r.finished.connect(func() -> void: count[0] += 1)
	r.advance(2.0)
	r.advance(2.0)
	r.skip()
	assert_eq(count[0], 1)


func test_duration_is_the_same_for_any_tile_count() -> void:
	for n in [10, 160]:
		var r := IntroReveal.new(_tiles(n), func(_id: String, _cell: Vector2i) -> void: pass)
		var steps := 0
		while not r.done and steps < 1000:
			r.advance(0.1)
			steps += 1
		assert_true(steps >= 25 and steps <= 26, "%d tiles took %d steps of 0.1s" % [n, steps])


func test_skip_shows_everything_at_once() -> void:
	var seen: Array[Vector2i] = []
	var r := IntroReveal.new(_tiles(7), func(_id: String, cell: Vector2i) -> void: seen.append(cell))
	r.skip()
	assert_eq(seen.size(), 7)
	assert_true(r.done)


func test_empty_list_finishes_on_the_first_advance() -> void:
	var r := IntroReveal.new(_tiles(0), func(_id: String, _cell: Vector2i) -> void: pass)
	r.advance(0.1)
	assert_true(r.done)
