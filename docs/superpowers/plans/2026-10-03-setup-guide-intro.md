# Setup Guide HUD and Membrane Intro Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At run start the membrane and cell wall tiles pop in one at a time, then a checklist HUD guides the player through placing and wiring the core organelles, and the game clock stays stopped until that setup is done.

**Architecture:** Two new scene-free classes hold the logic (`IntroReveal` for the timed tile reveal, `SetupGuide` for the checklist rules) and are unit tested. `CellGame` wires them together (drawing, building lock, clock start) and a new `GuideHud` CanvasLayer shows the checklist. `StarterLayout` is split so the game builds only the membrane/wall shell, while the old full cell stays available as `build_core` for tests and tools.

**Tech Stack:** Godot 4.7 (GL Compatibility), GDScript, `McpTestSuite` unit tests run headless.

**Spec:** [docs/superpowers/specs/2026-10-03-setup-guide-intro-design.md](../specs/2026-10-03-setup-guide-intro-design.md)

## Global Constraints

- GDScript, tab indentation, matches the surrounding style (`##` doc comments, typed signatures, no trailing commentary).
- Helper scripts in `scripts/game/*` and `scripts/ui/*` hold the game as an untyped `_game` and never name `CellGame` as a type (compile-cycle rule from CLAUDE.md). `SetupGuide`, `IntroReveal` and `CellSim` may be named as types.
- All UI built in code uses `MetalUi.theme()` and adds its controls under `UiRoot.attach(self)`.
- Use the exact existing node and file names, including the typos and spaces (`backround`, `endoplasmic reculum`, `cell Node2D.tscn`, `organell buttons and stuff`).
- The Godot binary on macOS is `/Applications/Godot.app/Contents/MacOS/Godot`. After adding a script with `class_name`, run `godot --headless --path . --import` before running tests so the class is registered, and `git add` the generated `.uid` file next to each new script.
- `.godot/` is committed but editor cache changes are unrelated: never include `.godot/` files in these commits (use explicit `git add` paths).
- Core organelles (nucleus, chromosomes, mitochondria, chloroplast) already have `placement_energy_cost` 0, so no cost rules change.
- Intro length is `IntroReveal.TOTAL_SECONDS = 2.5` regardless of tile count. The player cannot skip the intro; `skip_intro()` exists for tests and tools only.
- The checklist steps match the wiring the old starter cell used: nucleus with adjacent chromosomes; mitochondria with a water link to a membrane tile; nucleus with an energy link to a mitochondria and a water link to a membrane tile, plus chromosomes with a water link to a membrane tile; plants also a chloroplast with an energy link to a mitochondria and a water link to a membrane or wall tile.

## Review Focus

Failure modes the spec implies that are most likely to bite, each pinned by a test in the owning task:

1. A chromosomes tile that is not touching the nucleus must not tick the first step (Task 4).
2. Erasing a core piece or cutting its links mid-guide un-ticks the step, but the first completion latches so the clock never stops again (Task 4).
3. Linking the chloroplast to a cell wall tile (not a membrane tile) counts as its water link (Task 4).
4. Clicking to build during the reveal is refused, and starting a second run (the "Play again" path through `start_run`) stops the clock and resets the guide again (Task 5).
5. Tab hides the checklist and the chip, and the checklist is hidden until the intro has finished (Task 6).

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `scripts/sim/cell_sim.gd` | modify | Add `links_changed` signal. |
| `scripts/sim/starter_layout.gd` | modify | `ring_ordered`, `shell_tiles`, split `build` into `build_shell` + `build_core`. |
| `scripts/game/intro_reveal.gd` | create | Timed one-by-one reveal logic, no scenes. |
| `scripts/sim/setup_guide.gd` | create | Checklist steps, live checks, latch. |
| `scripts/game/cell_game.gd` | modify | Shell-only start, reveal, building lock, guide checks, clock start, signals. |
| `scripts/game/build_input.gd` | modify | Ignore the mouse while the intro plays. |
| `scripts/ui/hud.gd` | modify | Emit `panels_toggled` on Tab. |
| `scripts/ui/guide_hud.gd` | create | Checklist panel and "Basics done" chip. |
| `tests/test_sim_core.gd` | modify | `links_changed` test. |
| `tests/test_starter.gd` | modify | `ring_ordered`, `shell_tiles`, `build_shell` tests. |
| `tests/test_intro_reveal.gd` | create | Reveal tests. |
| `tests/test_setup_guide.gd` | create | Guide tests. |
| `tools/smoke_game.gd` | modify | Guided setup instead of the pre-built core, new checks. |
| `tools/screenshot.gd` | modify | Use `build_core` for the default shot, add `reveal` and `guide` shots. |
| `CLAUDE.md` | modify | Document the new flow. |

---

### Task 1: `CellSim.links_changed` signal

**Files:**
- Modify: `scripts/sim/cell_sim.gd:6` (signals), `scripts/sim/cell_sim.gd:188-210` (`add_link`, `remove_link`, `remove_links_of`)
- Test: `tests/test_sim_core.gd`

**Interfaces:**
- Produces: `CellSim.links_changed` (no arguments), emitted after a link is added, after `remove_link`, and after `remove_links_of`. A refused or duplicate `add_link` does not emit. Task 5 connects to it.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_sim_core.gd`:

```gdscript
func test_links_changed_fires_on_add_and_remove() -> void:
	var s := _sim()
	var plain := s.add_organelle("plain", Vector2i(0, 0))
	var mito := s.add_organelle("mito", Vector2i(1, 0))
	var count := [0]
	s.links_changed.connect(func() -> void: count[0] += 1)
	assert_true(s.add_link(plain, mito))
	assert_eq(count[0], 1)
	assert_false(s.add_link(plain, mito))
	assert_eq(count[0], 1, "a refused duplicate must not fire")
	s.remove_link(plain, mito, SimLink.Type.ENERGY)
	assert_eq(count[0], 2)
	s.add_link(plain, mito)
	s.remove_links_of(plain)
	assert_eq(count[0], 4)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd -- sim_core`
Expected: a `FAIL  sim_core.test_links_changed_fires_on_add_and_remove` line (or a parse error mentioning `links_changed`), non-zero exit.

- [ ] **Step 3: Implement**

In `scripts/sim/cell_sim.gd`, add after `signal shipment_delivered(shipment: Shipment)`:

```gdscript
signal links_changed
```

Replace the three link functions so they read:

```gdscript
func add_link(from_uid: int, to_uid: int) -> bool:
	var t := infer_link_type(from_uid, to_uid)
	if t == -1 or has_link(from_uid, to_uid, t):
		return false
	links.append(SimLink.make(from_uid, to_uid, t))
	links_changed.emit()
	return true
```

```gdscript
func remove_link(from_uid: int, to_uid: int, type: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return not (l.from_uid == from_uid and l.to_uid == to_uid and l.type == type)))
	links_changed.emit()


func remove_links_of(uid: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return l.from_uid != uid and l.to_uid != uid))
	links_changed.emit()
```

(`has_link` stays as it is.)

- [ ] **Step 4: Run all tests to verify they pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT passed=N failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/cell_sim.gd tests/test_sim_core.gd
git commit -m "feat: CellSim.links_changed signal"
```

---

### Task 2: StarterLayout shell, ordered ring and core split

**Files:**
- Modify: `scripts/sim/starter_layout.gd`
- Test: `tests/test_starter.gd`

**Interfaces:**
- Consumes: `OrganelleDef.CellType`, `CellSim.add_organelle`, `CellSim.add_link`.
- Produces:
  - `StarterLayout.ring_ordered(half: Vector2i) -> Array[Vector2i]`: same cells as `ring`, clockwise from the top-left corner, consecutive cells (and last-to-first) touching.
  - `StarterLayout.shell_tiles(cell_type: int) -> Array[Dictionary]`: entries `{"id": String, "cell": Vector2i}`; membrane ring first (id `"membrane"`), then for plants the wall ring (id `"cell_wall"`).
  - `StarterLayout.build_shell(sim: CellSim, rng: RandomNumberGenerator) -> void`: membrane ring (+ wall ring for plants) only.
  - `StarterLayout.build_core(sim: CellSim) -> void`: the pre-built nucleus (0,0), chromosomes (1,0), mitochondria (-3,0), chloroplast (3,0, plants) and their links to the membrane tile at (0,-HALF.y). Requires the shell to exist.
  - `StarterLayout.build(sim, rng)` keeps its signature and calls `build_shell` then `build_core`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_starter.gd`:

```gdscript
func test_ring_ordered_is_a_loop_of_the_same_cells() -> void:
	var ordered := StarterLayout.ring_ordered(StarterLayout.HALF)
	assert_eq(ordered.size(), 76)
	var remaining := {}
	for c in StarterLayout.ring(StarterLayout.HALF):
		remaining[c] = true
	for c in ordered:
		assert_true(remaining.has(c), "unexpected or repeated cell %s" % [c])
		remaining.erase(c)
	assert_eq(remaining.size(), 0)
	for i in ordered.size():
		var d: Vector2i = ordered[(i + 1) % ordered.size()] - ordered[i]
		assert_eq(absi(d.x) + absi(d.y), 1, "cells after index %d do not touch" % i)


func test_shell_tiles_are_membrane_first_then_wall_for_plants() -> void:
	var animal := StarterLayout.shell_tiles(ANIMAL)
	assert_eq(animal.size(), 76)
	for t in animal:
		assert_eq(t["id"], "membrane")
	var plant := StarterLayout.shell_tiles(PLANT)
	assert_eq(plant.size(), 76 + 84)
	assert_eq(plant[75]["id"], "membrane")
	assert_eq(plant[76]["id"], "cell_wall")


func test_build_shell_places_only_membrane_and_wall() -> void:
	for ct in [ANIMAL, PLANT]:
		var s := CellSim.new(OrganelleCatalog.load_all(), ct)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		StarterLayout.build_shell(s, rng)
		assert_eq(_count(s, "membrane"), 76)
		assert_eq(_count(s, "cell_wall"), 84 if ct == PLANT else 0)
		assert_eq(_count(s, "nucleus"), 0)
		assert_eq(_count(s, "chromosomes"), 0)
		assert_eq(_count(s, "mitochondria"), 0)
		assert_eq(_count(s, "chloroplast"), 0)
		assert_eq(s.links.size(), 0)
```

- [ ] **Step 2: Run to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd -- starter`
Expected: the three new tests FAIL or the suite cannot parse (`ring_ordered`, `shell_tiles`, `build_shell` not found).

- [ ] **Step 3: Implement**

In `scripts/sim/starter_layout.gd`, update the header comment, add the two helpers after `ring`, and replace `build`:

```gdscript
class_name StarterLayout extends RefCounted
## The cell a run starts from. `build_shell` places the membrane ring (plus a
## wall ring for plants), which the game reveals tile by tile. `build_core` is
## the nucleus, chromosomes and mitochondria pre-wired: the player now builds
## those themselves, so only tests and tools use it as the reference wiring.
```

Add after `ring`:

```gdscript
## The same cells as `ring`, walked clockwise from the top-left corner so list
## neighbours are neighbours on screen (the intro reveal grows around the ring).
static func ring_ordered(half: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-half.x, half.x + 1):
		cells.append(Vector2i(x, -half.y))
	for y in range(-half.y + 1, half.y + 1):
		cells.append(Vector2i(half.x, y))
	for x in range(half.x - 1, -half.x - 1, -1):
		cells.append(Vector2i(x, half.y))
	for y in range(half.y - 1, -half.y, -1):
		cells.append(Vector2i(-half.x, y))
	return cells


## What the intro reveals, in order: `{"id", "cell"}` for the membrane ring, then
## the wall ring for plants.
static func shell_tiles(cell_type: int) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	for c in ring_ordered(HALF):
		tiles.append({"id": "membrane", "cell": c})
	if cell_type == OrganelleDef.CellType.PLANT:
		for c in ring_ordered(HALF + Vector2i(1, 1)):
			tiles.append({"id": "cell_wall", "cell": c})
	return tiles
```

Replace the old `build` with:

```gdscript
static func build(sim: CellSim, rng: RandomNumberGenerator) -> void:
	build_shell(sim, rng)
	build_core(sim)


static func build_shell(sim: CellSim, rng: RandomNumberGenerator) -> void:
	for c in ring(HALF):
		_place(sim, "membrane", c, rng.randf_range(90.0, 100.0))
	if sim.cell_type == OrganelleDef.CellType.PLANT:
		for c in ring(HALF + Vector2i(1, 1)):
			_place(sim, "cell_wall", c, rng.randf_range(90.0, 100.0))


## Needs the shell: links go to the membrane tile at the top centre.
static func build_core(sim: CellSim) -> void:
	var nucleus := _place(sim, "nucleus", Vector2i(0, 0))
	var chromosomes := _place(sim, "chromosomes", Vector2i(1, 0))
	var mito := _place(sim, "mitochondria", Vector2i(-3, 0))
	var anchor := sim.organelle_at(Vector2i(0, -HALF.y))
	sim.add_link(nucleus, mito)
	sim.add_link(nucleus, anchor)
	sim.add_link(chromosomes, anchor)
	sim.add_link(mito, anchor)
	if sim.cell_type == OrganelleDef.CellType.PLANT:
		var chloroplast := _place(sim, "chloroplast", Vector2i(3, 0))
		sim.add_link(chloroplast, mito)
		sim.add_link(chloroplast, anchor)
```

Leave `ring`, `in_bounds` and `_place` untouched.

- [ ] **Step 4: Run all tests to verify they pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT ... failed=0`. The existing starter tests (30-second survival, all running after one tick) still pass because `build` is unchanged in effect.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/starter_layout.gd tests/test_starter.gd
git commit -m "feat: StarterLayout shell, ordered ring and core split"
```

---

### Task 3: `IntroReveal`

**Files:**
- Create: `scripts/game/intro_reveal.gd`
- Test: `tests/test_intro_reveal.gd`

**Interfaces:**
- Consumes: tile entries shaped like `StarterLayout.shell_tiles` (`{"id": String, "cell": Vector2i}`).
- Produces: `IntroReveal` (RefCounted):
  - `IntroReveal.new(tiles: Array[Dictionary], show_tile: Callable, total_seconds: float = IntroReveal.TOTAL_SECONDS)` where `show_tile` is called as `show_tile.call(id: String, cell: Vector2i)`.
  - `advance(delta: float) -> void`, `skip() -> void`, `var done: bool`, `signal finished` (emitted exactly once).
  - `const TOTAL_SECONDS := 2.5`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_intro_reveal.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd -- intro_reveal`
Expected: FAIL (`IntroReveal` not found / cannot load), non-zero exit.

- [ ] **Step 3: Implement**

Create `scripts/game/intro_reveal.gd`:

```gdscript
class_name IntroReveal extends RefCounted
## Reveals a list of tiles one at a time over a fixed total time, so the intro
## lasts the same for any cell size. Scene-free: `show_tile` does the drawing.

signal finished

const TOTAL_SECONDS := 2.5

var done := false

var _tiles: Array[Dictionary]
var _show: Callable
var _total: float
var _elapsed := 0.0
var _shown := 0


func _init(tiles: Array[Dictionary], show_tile: Callable, total_seconds: float = TOTAL_SECONDS) -> void:
	_tiles = tiles
	_show = show_tile
	_total = total_seconds


func advance(delta: float) -> void:
	if done:
		return
	_elapsed += delta
	var target := _tiles.size() if _elapsed >= _total else int(_tiles.size() * _elapsed / _total)
	_reveal_to(target)


## Shows every remaining tile at once (tests and tools; the player cannot skip).
func skip() -> void:
	if not done:
		_reveal_to(_tiles.size())


func _reveal_to(target: int) -> void:
	while _shown < target:
		var t: Dictionary = _tiles[_shown]
		_show.call(t["id"], t["cell"])
		_shown += 1
	if _shown >= _tiles.size():
		done = true
		finished.emit()
```

- [ ] **Step 4: Import and run all tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT ... failed=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/game/intro_reveal.gd scripts/game/intro_reveal.gd.uid tests/test_intro_reveal.gd tests/test_intro_reveal.gd.uid
git commit -m "feat: IntroReveal timed tile reveal"
```

---

### Task 4: `SetupGuide`

**Files:**
- Create: `scripts/sim/setup_guide.gd`
- Test: `tests/test_setup_guide.gd`

**Interfaces:**
- Consumes: `CellSim` (`organelles`, `links`, `unlocked_ids`, `are_adjacent`, `cell_type`), `SimLink.Type`, `PlacedOrganelle.def`, `StarterLayout.build_shell/build_core` (tests).
- Produces: `SetupGuide` (RefCounted), constructed `SetupGuide.new(sim: CellSim)`:
  - `steps() -> Array[Dictionary]` entries `{"id", "label", "hint"}`; ids in order `"nucleus"`, `"power"`, `"wire"`, plus `"chloroplast"` for plants.
  - `step_done(id: String) -> bool`, `all_done() -> bool`, `current_step() -> Dictionary` (first incomplete, `{}` when none).
  - `core_ids() -> Array[String]`, `begin() -> void` (adds core ids to `sim.unlocked_ids`).
  - `refresh() -> bool`: true exactly once, the first time `all_done()` is true; sets `core_done`.
  - `var core_done: bool`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_setup_guide.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd -- setup_guide`
Expected: FAIL (`SetupGuide` not found / cannot load), non-zero exit.

- [ ] **Step 3: Implement**

Create `scripts/sim/setup_guide.gd`:

```gdscript
class_name SetupGuide extends RefCounted
## The basic-setup checklist: which steps a new player must finish before the
## clock starts. Reads the sim live and knows nothing about scenes.

const STEP_NUCLEUS := "nucleus"
const STEP_POWER := "power"
const STEP_WIRE := "wire"
const STEP_CHLOROPLAST := "chloroplast"

## True once every step has been done at least once; erasing later does not clear it.
var core_done := false

var _sim: CellSim


func _init(sim: CellSim) -> void:
	_sim = sim


func core_ids() -> Array[String]:
	var ids: Array[String] = ["nucleus", "chromosomes", "mitochondria"]
	if _sim.cell_type == OrganelleDef.CellType.PLANT:
		ids.append("chloroplast")
	return ids


## Unlocks the core organelles (chromosomes normally need a water threshold) so
## their palette buttons work from the start. They already cost no energy.
func begin() -> void:
	for id in core_ids():
		_sim.unlocked_ids[id] = true


func steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": STEP_NUCLEUS, "label": "Place a nucleus with chromosomes touching it",
			"hint": "Pick Nucleus in the palette and place it, then place Chromosomes right beside it."},
		{"id": STEP_POWER, "label": "Place mitochondria and link it to the membrane",
			"hint": "Place Mitochondria. Pick Link, then drag from the mitochondria to a membrane tile for water."},
		{"id": STEP_WIRE, "label": "Wire the nucleus and chromosomes",
			"hint": "With Link, drag from the nucleus to the mitochondria (energy) and to a membrane tile (water). Drag from the chromosomes to a membrane tile too."},
	]
	if _sim.cell_type == OrganelleDef.CellType.PLANT:
		out.append({"id": STEP_CHLOROPLAST, "label": "Place a chloroplast and link it",
			"hint": "Place a Chloroplast, then link it to the mitochondria (energy) and to a membrane or cell wall tile (water)."})
	return out


func step_done(id: String) -> bool:
	match id:
		STEP_NUCLEUS:
			return not _nucleus_pairs().is_empty()
		STEP_POWER:
			return _uids("mitochondria").any(func(m: int) -> bool: return _has_supply(m, SimLink.Type.WATER))
		STEP_WIRE:
			return _nucleus_pairs().any(func(p: Array) -> bool:
				return _has_supply(p[0], SimLink.Type.ENERGY) and _has_supply(p[0], SimLink.Type.WATER) \
						and _has_supply(p[1], SimLink.Type.WATER))
		STEP_CHLOROPLAST:
			return _uids("chloroplast").any(func(c: int) -> bool:
				return _has_supply(c, SimLink.Type.ENERGY) and _has_supply(c, SimLink.Type.WATER))
	return false


func all_done() -> bool:
	for step in steps():
		if not step_done(step["id"]):
			return false
	return true


## The first step still to do, or `{}` when everything is done.
func current_step() -> Dictionary:
	for step in steps():
		if not step_done(step["id"]):
			return step
	return {}


## True exactly once: the first time every step is done.
func refresh() -> bool:
	if core_done or not all_done():
		return false
	core_done = true
	return true


func _uids(def_id: String) -> Array[int]:
	var out: Array[int] = []
	for uid in _sim.organelles:
		if (_sim.organelles[uid] as PlacedOrganelle).def.id == def_id:
			out.append(uid)
	return out


## [nucleus uid, chromosomes uid] for every nucleus with a chromosomes touching it.
func _nucleus_pairs() -> Array:
	var pairs := []
	for n in _uids("nucleus"):
		for c in _uids("chromosomes"):
			if _sim.are_adjacent(n, c):
				pairs.append([n, c])
	return pairs


## Does `uid` have a link of `type` to something that can supply it (a water
## source for WATER, an energy source for ENERGY)?
func _has_supply(uid: int, type: int) -> bool:
	for l: SimLink in _sim.links:
		if l.from_uid != uid or l.type != type:
			continue
		var src: PlacedOrganelle = _sim.organelles.get(l.to_uid)
		if src == null:
			continue
		if type == SimLink.Type.WATER and src.def.water_output > 0.0:
			return true
		if type == SimLink.Type.ENERGY and src.def.max_load > 0.0:
			return true
	return false
```

- [ ] **Step 4: Import and run all tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT ... failed=0`. If `test_the_old_prebuilt_cell_satisfies_every_step` fails, the step checks disagree with the real wiring: fix the checks, not the test.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/setup_guide.gd scripts/sim/setup_guide.gd.uid tests/test_setup_guide.gd tests/test_setup_guide.gd.uid
git commit -m "feat: SetupGuide checklist rules"
```

---

### Task 5: CellGame intro, building lock and clock start (plus smoke test)

**Files:**
- Modify: `scripts/game/cell_game.gd`, `scripts/game/build_input.gd:25,43`, `scripts/ui/hud.gd:62-66`
- Modify: `tools/smoke_game.gd`, `tools/screenshot.gd`

**Interfaces:**
- Consumes: `StarterLayout.build_shell`, `StarterLayout.shell_tiles`, `IntroReveal`, `SetupGuide`, `CellSim.links_changed`, `TileBase.show_tile`.
- Produces (used by Task 6 and the smoke test):
  - `CellGame` signals `intro_finished`, `guide_changed`, `setup_done`, `panels_toggled(shown: bool)`.
  - `CellGame.guide: SetupGuide`, `CellGame.intro_playing: bool`, `CellGame.skip_intro() -> void`.
  - `try_place` returns `"intro"` while `intro_playing`.
  - The tick timer is not started by `start_run`; it starts when the guide first completes.

- [ ] **Step 1: Update the smoke test first (it is the failing test)**

In `tools/smoke_game.gd`, add this helper above `_button`, and add the helper `_find`:

```gdscript
func _find(game, global_name: StringName):
	for c in game.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == global_name:
			return c
	return null


## Starts from the revealed shell and sets the core up by hand, like the guide teaches.
func _setup_core(game, animal: bool, tag: String) -> void:
	var energy_before: float = game.sim.meters["energy"]
	var done_count := [0]
	game.setup_done.connect(func() -> void: done_count[0] += 1)
	_check(game.guide != null and not game.guide.core_done, tag + ": a fresh guide at the start of every run")
	_check(game.try_place("nucleus", Vector2i(0, 0)) == "", tag + ": nucleus placed")
	_check(game.try_place("chromosomes", Vector2i(1, 0)) == "", tag + ": chromosomes placed")
	_check(game.try_place("mitochondria", Vector2i(-3, 0)) == "", tag + ": mitochondria placed")
	var nucleus: int = game.uid_at(Vector2i(0, 0))
	var chromosomes: int = game.uid_at(Vector2i(1, 0))
	var mito: int = game.uid_at(Vector2i(-3, 0))
	var anchor: int = game.uid_at(Vector2i(0, -7))
	_check(game.guide.current_step()["id"] == "power", tag + ": guide moves on to the power step")
	_check(game._timer.is_stopped(), tag + ": clock still stopped mid-guide")
	game.sim.add_link(mito, anchor)
	game.sim.add_link(nucleus, mito)
	game.sim.add_link(nucleus, anchor)
	game.sim.add_link(chromosomes, anchor)
	if not animal:
		_check(game._timer.is_stopped(), tag + ": a plant also needs its chloroplast before the clock starts")
		_check(game.try_place("chloroplast", Vector2i(3, 0)) == "", tag + ": chloroplast placed")
		var chloroplast: int = game.uid_at(Vector2i(3, 0))
		game.sim.add_link(chloroplast, mito)
		game.sim.add_link(chloroplast, anchor)
	_check(done_count[0] == 1, tag + ": setup_done fired once, got %d" % done_count[0])
	_check(not game._timer.is_stopped(), tag + ": the clock starts once the core is set up")
	_check(game.sim.meters["energy"] == energy_before, tag + ": setting up the core cost no energy")
```

Replace the start of `_run_cell` (from `game.start_run(animal)` through the `cell wall` tile check, i.e. these existing lines):

```gdscript
	game.start_run(animal)
	await process_frame
	_check(game.running, tag + ": running after start_run")
	_check(_tiles(game, "membrane") == 76, tag + ": membrane tiles mirrored, got %d" % _tiles(game, "membrane"))
	_check(_tiles(game, "nucleus") == 1, tag + ": nucleus tile")
	_check(_tiles(game, "cell wall") == (84 if not animal else 0), tag + ": cell wall tiles, got %d" % _tiles(game, "cell wall"))
```

with:

```gdscript
	game.start_run(animal)
	await process_frame
	_check(game.running, tag + ": running after start_run")
	_check(game.intro_playing, tag + ": the intro is playing")
	_check(game._timer.is_stopped(), tag + ": clock stopped during the intro")
	_check(_tiles(game, "membrane") < 76, tag + ": membrane is still popping in, got %d" % _tiles(game, "membrane"))
	_check(game.try_place("nucleus", Vector2i(0, 0)) == "intro", tag + ": building is blocked during the intro")
	game.skip_intro()
	_check(not game.intro_playing, tag + ": intro over after skip")
	_check(_tiles(game, "membrane") == 76, tag + ": membrane tiles mirrored, got %d" % _tiles(game, "membrane"))
	_check(_tiles(game, "cell wall") == (84 if not animal else 0), tag + ": cell wall tiles, got %d" % _tiles(game, "cell wall"))
	_check(_tiles(game, "nucleus") == 0, tag + ": the core is not pre-placed")
	_setup_core(game, animal, tag)
	_check(_tiles(game, "nucleus") == 1, tag + ": nucleus tile")
```

(The second `_run_cell(game, false)` call restarts a run through `start_run`, so the "fresh guide", "clock stopped" and "building blocked" checks also cover the restart path.)

In `tools/screenshot.gd`, replace the lines

```gdscript
	game.start_run(animal)
	for i in 12:
		game._on_tick()
```

with:

```gdscript
	game.start_run(animal)
	var mode := OS.get_cmdline_user_args()
	if mode.has("reveal"):
		for i in 40:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
		return
	game.skip_intro()
	if mode.has("guide"):
		for i in 20:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
		return
	StarterLayout.build_core(game.sim)
	for i in 12:
		game._on_tick()
```

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/smoke_game.gd`
Expected: script errors or `FAIL` lines (`intro_playing`, `skip_intro`, `guide` do not exist yet), non-zero exit.

- [ ] **Step 3: Implement CellGame changes**

In `scripts/game/cell_game.gd`:

Add signals after `signal speed_changed(speed: int)`:

```gdscript
signal intro_finished
signal guide_changed
signal setup_done
signal panels_toggled(shown: bool)
```

Add constant after `REPAIR_RADIUS`:

```gdscript
## Seconds a freshly revealed membrane/wall tile flashes while it pops in.
const POP_SECONDS := 0.2
```

Add vars after `var speed: int = GameSpeed.NORMAL`:

```gdscript
## The basic-setup checklist for this run; the tick timer starts when it first completes.
var guide: SetupGuide
## True while the membrane and wall tiles are popping in; building is blocked.
var intro_playing: bool = false
```

and after `var _timer := Timer.new()`:

```gdscript
var _reveal: IntroReveal
```

Add `_process` after `_ready`:

```gdscript
func _process(delta: float) -> void:
	if intro_playing and _reveal != null:
		_reveal.advance(delta)
```

Replace `start_run` with:

```gdscript
func start_run(is_animal: bool) -> void:
	Globals.player_plant_or_animal = is_animal
	($backround as AnimatedSprite2D).call("refresh")
	_timer.stop()
	for layer: TileBase in _layers.values():
		layer.clear()
	var cell_type := OrganelleDef.CellType.ANIMAL if is_animal else OrganelleDef.CellType.PLANT
	sim = CellSim.new(OrganelleCatalog.load_all(), cell_type)
	sim.organelle_removed.connect(_on_removed)
	sim.unlocked.connect(func(id: String) -> void: sim_unlocked.emit(id))
	sim.lost.connect(_on_lost)
	sim.links_changed.connect(_check_guide)
	director = DamageDirector.new(sim, curve, RandomNumberGenerator.new())
	director.event_fired.connect(func(l: String) -> void: event_fired.emit(l))
	# The shell goes into the sim now but is drawn by the reveal, so connect
	# organelle_added only afterwards.
	StarterLayout.build_shell(sim, RandomNumberGenerator.new())
	sim.organelle_added.connect(_on_added)
	guide = SetupGuide.new(sim)
	guide.begin()
	intro_playing = true
	_reveal = IntroReveal.new(StarterLayout.shell_tiles(cell_type), _reveal_tile)
	_reveal.finished.connect(_on_intro_finished)
	tool = ""
	paused = false
	speed = GameSpeed.NORMAL
	_apply_speed()
	speed_changed.emit(speed)
	running = true
	run_started.emit()
```

Add after `start_run` (the timer is no longer started there):

```gdscript
## Finishes the intro at once. Tests and tools only; the player cannot skip it.
func skip_intro() -> void:
	if _reveal != null:
		_reveal.skip()


func _reveal_tile(id: String, cell: Vector2i) -> void:
	if not _layers.has(id):
		return
	(_layers[id] as TileBase).show_tile(cell)
	_spawn_pop(cell)


## A short white flash over a tile as it appears. Visual only.
func _spawn_pop(cell: Vector2i) -> void:
	var half := Vector2(_grid.tile_set.tile_size) / 2.0
	var pop := Polygon2D.new()
	pop.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	pop.color = Color(1, 1, 1, 0.8)
	pop.position = _grid.map_to_local(cell)
	pop.scale = Vector2.ONE * 1.8
	_grid.add_child(pop)
	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "scale", Vector2.ONE, POP_SECONDS)
	tween.tween_property(pop, "color:a", 0.0, POP_SECONDS)
	tween.chain().tween_callback(pop.queue_free)


func _on_intro_finished() -> void:
	intro_playing = false
	intro_finished.emit()
	guide_changed.emit()


## Re-checks the checklist after any build or link change. The first time every
## step is done the clock starts.
func _check_guide() -> void:
	if guide == null:
		return
	guide_changed.emit()
	if guide.refresh():
		_timer.start()
		setup_done.emit()
```

Update `_on_added` and `_on_removed`:

```gdscript
func _on_added(uid: int) -> void:
	var o: PlacedOrganelle = sim.organelles[uid]
	if _layers.has(o.def.id):
		(_layers[o.def.id] as TileBase).show_tile(o.cell)
	_check_guide()


func _on_removed(_uid: int, cell: Vector2i, def_id: String) -> void:
	if _layers.has(def_id):
		(_layers[def_id] as TileBase).hide_tile(cell)
	_check_guide()
```

Update `try_place` and `try_erase` to refuse during the intro:

```gdscript
func try_place(def_id: String, cell: Vector2i) -> String:
	if intro_playing:
		return "intro"
	if sim == null or not StarterLayout.in_bounds(cell, sim.cell_type):
		return "outside_cell"
	...
```

(keep the rest of `try_place` as it is) and

```gdscript
func try_erase(cell: Vector2i) -> void:
	if intro_playing:
		return
	var uid := uid_at(cell)
	...
```

(keep the rest of `try_erase` as it is).

- [ ] **Step 4: Block the mouse during the intro and emit panels_toggled**

In `scripts/game/build_input.gd`, change `_blocked` to:

```gdscript
func _blocked() -> bool:
	return not _game.running or _game.paused or _game.intro_playing or _game.get_viewport().gui_get_hovered_control() != null
```

and the first line of `_unhandled_input` to:

```gdscript
	if not _game.running or _game.paused or _game.intro_playing or _game.tool != "link":
		return
```

In `scripts/ui/hud.gd`, update `_input`:

```gdscript
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_buildings"):
		_panels_shown = not _panels_shown
		_update_panels()
		_game.panels_toggled.emit(_panels_shown)
		get_viewport().set_input_as_handled()
```

- [ ] **Step 5: Run unit tests and the smoke test**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT ... failed=0`.
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/smoke_game.gd`
Expected: `SMOKE OK`, exit 0. If a `FAIL` line appears for a pre-existing check, the cause is almost always a missing pre-built core link: compare with `StarterLayout.build_core` before changing the check.

- [ ] **Step 6: Commit**

```bash
git add scripts/game/cell_game.gd scripts/game/build_input.gd scripts/ui/hud.gd tools/smoke_game.gd tools/screenshot.gd
git commit -m "feat: membrane/wall intro reveal and clock that waits for core setup"
```

---

### Task 6: `GuideHud` checklist and "Basics done" chip

**Files:**
- Create: `scripts/ui/guide_hud.gd`
- Modify: `scripts/game/cell_game.gd` (`_build_children` UI list)
- Modify: `tools/smoke_game.gd` (GuideHud checks inside `_setup_core`)

**Interfaces:**
- Consumes: `CellGame.guide`, signals `run_started`, `intro_finished`, `guide_changed`, `setup_done`, `panels_toggled(shown: bool)`, `SetupGuide.steps/step_done/current_step/core_done`, `MetalUi.theme()`, `UiRoot.attach`.
- Produces: `GuideHud` (CanvasLayer) with private nodes `_panel`, `_chip`, `_rows` (step id to Label), used by the smoke test.

- [ ] **Step 1: Add the failing GuideHud checks to the smoke test**

In `tools/smoke_game.gd`, inside `_setup_core`, add right after the `done_count` line:

```gdscript
	var gh = _find(game, &"GuideHud")
	_check(gh != null, tag + ": guide HUD exists")
	if gh == null:
		return
	_check(gh._panel.visible and not gh._chip.visible, tag + ": checklist shows once the intro is over")
	_check(gh._rows.size() == (3 if animal else 4), tag + ": one row per step, got %d" % gh._rows.size())
	_check((gh._rows["nucleus"] as Label).text.begins_with("[ ]"), tag + ": first step starts unticked")
```

and after the `_check(game.guide.current_step()["id"] == "power", ...)` line:

```gdscript
	_check((gh._rows["nucleus"] as Label).text.begins_with("[x]"), tag + ": first step ticks off")
	_check(gh._hint.text.contains("Mitochondria"), tag + ": hint moves to the next step")
```

and at the very end of `_setup_core`:

```gdscript
	_check(gh._chip.visible and not gh._panel.visible, tag + ": checklist collapses to the Basics done chip")
	var hud = _find(game, &"Hud")
	hud._input(_action("open_buildings"))
	_check(not gh._chip.visible and not gh._panel.visible, tag + ": Tab hides the chip too")
	hud._input(_action("open_buildings"))
	_check(gh._chip.visible, tag + ": Tab shows the chip again")
```

Also add, in `_run_cell` right after the `intro_playing` check and before `game.skip_intro()`:

```gdscript
	var early_gh = _find(game, &"GuideHud")
	_check(early_gh != null and not early_gh._panel.visible, tag + ": checklist hidden until the intro finishes")
```

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/smoke_game.gd`
Expected: `FAIL  ...: guide HUD exists` (no `GuideHud` yet), non-zero exit.

- [ ] **Step 3: Implement `GuideHud`**

Create `scripts/ui/guide_hud.gd`:

```gdscript
class_name GuideHud extends CanvasLayer
## Checklist that walks a new player through the basic cell setup, then
## collapses to a small "Basics done" chip. Hidden until the intro has finished.

const DONE_COLOR := Color("8fd694")
const CURRENT_COLOR := Color("f2d64b")
const WIDTH := 230

var _game  # the CellGame node, untyped on purpose so helpers don't form a compile cycle with it
var _root: UiRoot
var _panel := PanelContainer.new()
var _list := VBoxContainer.new()
var _hint := Label.new()
var _chip := PanelContainer.new()
var _rows: Dictionary = {}  # step id -> Label
var _intro_done := false
var _basics_done := false
var _panels_shown := true


func setup(game) -> void:
	_game = game
	_root = UiRoot.attach(self)
	_panel.theme = MetalUi.theme()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Set up your cell"
	box.add_child(title)
	box.add_child(_list)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = WIDTH
	box.add_child(_hint)
	_chip.theme = MetalUi.theme()
	_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var chip_label := Label.new()
	chip_label.text = "Basics done"
	chip_label.add_theme_color_override("font_color", DONE_COLOR)
	_chip.add_child(chip_label)
	_root.add_child(_chip)
	game.run_started.connect(_on_run_started)
	game.intro_finished.connect(_on_intro_finished)
	game.guide_changed.connect(_refresh)
	game.setup_done.connect(_refresh)
	game.panels_toggled.connect(_on_panels_toggled)
	_update_visibility()


func _on_run_started() -> void:
	_intro_done = false
	_basics_done = false
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	for step in _game.guide.steps():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH
		_list.add_child(label)
		_rows[step["id"]] = label
	_refresh()


func _on_intro_finished() -> void:
	_intro_done = true
	_update_visibility()


func _on_panels_toggled(shown: bool) -> void:
	_panels_shown = shown
	_update_visibility()


func _refresh() -> void:
	var guide: SetupGuide = _game.guide
	if guide == null:
		return
	var current: Dictionary = guide.current_step()
	for step in guide.steps():
		var label: Label = _rows.get(step["id"])
		if label == null:
			continue
		var done := guide.step_done(step["id"])
		label.text = ("[x] " if done else "[ ] ") + String(step["label"])
		if done:
			label.add_theme_color_override("font_color", DONE_COLOR)
		elif not current.is_empty() and current["id"] == step["id"]:
			label.add_theme_color_override("font_color", CURRENT_COLOR)
		else:
			label.remove_theme_color_override("font_color")
	_hint.text = String(current.get("hint", ""))
	_basics_done = guide.core_done
	_update_visibility()


func _update_visibility() -> void:
	var show := _intro_done and _panels_shown
	_panel.visible = show and not _basics_done
	_chip.visible = show and _basics_done
```

In `scripts/game/cell_game.gd`, add `GuideHud.new()` to the UI list in `_build_children`:

```gdscript
	for ui in [SpeedControls.new(), Hud.new(), GuideHud.new(), BuildMenu.new(), InfoCard.new(), Encyclopedia.new(), GameOver.new(), StartScreen.new()]:
```

- [ ] **Step 4: Import, run unit tests and the smoke test**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/run_tests.gd`
Expected: `RESULT ... failed=0`.
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/smoke_game.gd`
Expected: `SMOKE OK`.

- [ ] **Step 5: Visual check (needs a window, so not headless)**

Run each, then open the PNG (the screenshot tool writes to the path you give; use the scratchpad or `/tmp` is not allowed, so pass a path inside the project's ignored area or the session scratchpad):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/screenshot.gd -- animal "$SCRATCH/animal_reveal.png" reveal
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/screenshot.gd -- plant "$SCRATCH/plant_guide.png" guide
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/screenshot.gd -- animal "$SCRATCH/animal_done.png"
```

where `$SCRATCH` is the session scratchpad directory. Check:
- `reveal`: some but not all membrane tiles are visible, partly around the ring.
- `guide`: the full ring is drawn, the checklist panel sits bottom-right with four rows for the plant and does not overlap the stats tab (top right), the tool bar (bottom centre) or the cell. If it overlaps the cell at the default window size, switch both `_panel` and `_chip` presets to `PRESET_CENTER_RIGHT` and re-shoot.
- default: the "Basics done" chip is visible bottom-right and the core organelles are drawn.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/guide_hud.gd scripts/ui/guide_hud.gd.uid scripts/game/cell_game.gd tools/smoke_game.gd
git commit -m "feat: GuideHud checklist and Basics done chip"
```

---

### Task 7: Document the new flow

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the **Architecture** list:

1. In the `Simulation` bullet, replace "`StarterLayout` builds the pre-wired starting cell." with "`StarterLayout` builds the membrane/wall shell (`build_shell`); `build_core` is the old pre-wired nucleus/chromosomes/mitochondria, kept as the reference wiring for tests and tools. `SetupGuide` holds the basic-setup checklist rules."
2. Add a bullet after the **Panels toggle** bullet:

```
- **Intro and setup guide**: `CellGame.start_run` puts only the membrane (and plant wall) ring into the sim and `IntroReveal` draws it tile by tile around the ring over `IntroReveal.TOTAL_SECONDS` (building is blocked while `intro_playing`). Then `GuideHud` (bottom right) shows the `SetupGuide` checklist: nucleus + touching chromosomes; mitochondria linked to the membrane; nucleus and chromosomes wired (energy from the mitochondria, water from the membrane); plants also a linked chloroplast. The tick timer does not start until `guide.refresh()` first returns true (`setup_done`), so there is no decay, damage or nucleus-loss countdown during setup. The checklist then collapses to a "Basics done" chip. `CellGame.skip_intro()` is for tests and tools only. If you change the starter wiring, update `SetupGuide` and keep `test_the_old_prebuilt_cell_satisfies_every_step` passing.
```

3. In the **Tests** section, add: "`tools/smoke_game.gd` and `tools/screenshot.gd` call `game.skip_intro()` after `start_run`; the screenshot tool takes `reveal` and `guide` arguments for the intro and the checklist."

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: describe the intro reveal and setup guide"
```

---

## Self-Review

**Spec coverage:** intro ring reveal with pop (Tasks 2, 3, 5); sim waits and building blocked (Task 5); player places the core with unlocks and zero cost (Task 4, cost pinned by a test); frozen clock until done with latch (Tasks 4, 5); checklist panel with current-step hint and tick marks (Task 6); plant chloroplast step (Tasks 4, 6); "Basics done" chip and Tab toggle (Tasks 5, 6); restart resets (Task 5 smoke second run); `links_changed` (Task 1); `build_core` kept as reference (Task 2, guarded by a Task 4 test); docs (Task 7). The spec's `refresh`/`finish` split was simplified: with no cost rules to restore, only `refresh` exists.

**Spec deviations, all deliberate:** the checklist needs the extra nucleus energy link and chromosomes water link (without them the nucleus never runs and the run is lost after 3 s); there is no `CellSim` free-placement change because core organelles already cost 0.

**Type consistency:** `IntroReveal.new(tiles, show_tile, total_seconds)`, `advance`, `skip`, `done`, `finished`; `SetupGuide.steps/step_done/all_done/current_step/refresh/begin/core_ids/core_done`; `CellGame.guide/intro_playing/skip_intro/setup_done/intro_finished/guide_changed/panels_toggled`; `GuideHud._panel/_chip/_rows/_hint` are used identically across tasks.
