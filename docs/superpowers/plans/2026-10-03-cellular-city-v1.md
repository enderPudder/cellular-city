# Cellular City v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 playable survival loop (animal and plant cells, food → energy economy, threshold unlocks, drawn links, decay, damage events, teaching UI) described in the spec.

**Architecture:** Game rules live in a scene-free `CellSim` (`RefCounted`) driven by data-driven `OrganelleDef` resources and a `DamageDirector` + `DifficultyCurve`. A thin `CellGame` node owns the sim, ticks it once per second, and mirrors it onto the existing `TileMapLayer`s. Input, link drawing and UI are separate small scripts that only call `CellGame` / `CellSim` APIs.

**Tech Stack:** Godot 4.7 (GL Compatibility), GDScript, the `godot-ai` addon's `McpTestSuite` for unit tests (`res://tests/test_*.gd`, run with the `test_run` MCP tool or the editor).

**Spec:** `docs/superpowers/specs/2026-10-03-cellular-city-game-design.md`

## Global Constraints

- Godot 4.7, GL Compatibility renderer. No new addons. No build/lint tooling exists.
- Use the exact existing node and file names, including typos and spaces: `cell Node2D.tscn`, `backround`, `endoplasmic reculum`, `golgoi apparatus`, `cell wall`, `scripts/organelle scripts/`.
- Sim tick is 1 second. Meters: `food`, `energy`, `water`, `waste`, `fat`. Meter and threshold keys are plain `String`s.
- Unlock thresholds are a gate and are never spent. They use `food`, `water`, `waste` only.
- A membrane tile at health ≥ 90 collects full water, below that 1/16 of it.
- A mitochondria may draw fat only if it is adjacent to an ER **and** has a FAT link to it. Each ER pairs with at most one mitochondria.
- Nucleus loss grace is 3 seconds. Repair window starts at 60 s and shrinks to a floor of 20 s with survival time.
- Vacuole group limit: 4 tiles (2×2) for animal, 25 tiles (5×5) for plant. Chloroplast and cell wall are plant-only.
- `Globals.player_plant_or_animal`: `true` = animal, `false` = plant.
- `.godot/` is committed to git. Only `git add` the specific files a task touched.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Scope Notes (deviations from the spec, decided while planning)

- **Per-tile model.** Every placed tile is one organelle instance with its own health. Sheet numbers for single-tile organelles are used as-is. Membrane, cell wall and cytoplasm are many-tile structures, so their per-tile values are scaled down. Waste figures are scaled by 0.1 for v1 balance. All values live in the generated `.tres` files and are meant to be tuned.
- **Deferred to v2 (not in this plan):** animal vacuole circular movement, the autophagosome as a roaming entity (the lysosome is modeled as a flat waste-removal rate), the cytoplasm bar, rotate (R), cell-size/organelle upgrade content (the shared threshold mechanism `CellSim.thresholds_met` is built).
- **Starter layout.** Because every tile needs links, a run starts with a pre-built ring of membrane tiles (plus a cell wall ring for plants) and a pre-wired nucleus, chromosomes and mitochondria (plus a chloroplast for plants). This teaches the link mechanic and keeps the first minute playable.

## Review Focus

Failure modes the spec implies but does not test directly. Each has a test in the task that owns the code.

1. Erasing a supplier that other organelles link to: dependents must lose supply and no dangling links may remain (Task 2, Task 3).
2. A mitochondria linked to an ER that is not adjacent, or two mitochondria linked to one ER: only a valid adjacent first pair may drain fat (Task 4).
3. Huge `dt` (a hidden window or lag spike): meters must stay within `[0, cap]` and never go negative or NaN (Task 3).
4. No running nucleus (destroyed or disabled by bacteria): lose after exactly 3 seconds, not instantly and not never (Task 5).
5. Placing outside the cell, on an occupied tile, a locked organelle, or a plant-only organelle in an animal cell: refused with a reason, no energy spent (Task 2, Task 7).

---

## File Structure

Create:
- `scripts/sim/organelle_def.gd` — `OrganelleDef` resource: all per-organelle data.
- `scripts/sim/organelle_catalog.gd` — `OrganelleCatalog.load_all()` loads every `.tres` in `data/organelles/`.
- `scripts/sim/placed_organelle.gd` — `PlacedOrganelle`: one placed tile's runtime state.
- `scripts/sim/sim_link.gd` — `SimLink`: `{from_uid, to_uid, type}`.
- `scripts/sim/cell_sim.gd` — `CellSim`: meters, placement, links, tick, unlocks, decay, repair, lose.
- `scripts/sim/difficulty_curve.gd` — `DifficultyCurve` resource.
- `scripts/sim/damage_director.gd` — `DamageDirector`: bacteria/cut events and repair timers.
- `scripts/sim/starter_layout.gd` — `StarterLayout`: ring geometry and the pre-built layout.
- `scripts/game/cell_game.gd` — `CellGame`: owns sim, ticking, layer mirroring, player actions.
- `scripts/game/build_input.gd` — `BuildInput`: mouse handling (place, erase, repair, link drag).
- `scripts/game/link_layer.gd` — `LinkLayer`: draws links, flow dots, link dots, damage markers.
- `scripts/ui/hud.gd`, `build_menu.gd`, `info_card.gd`, `encyclopedia.gd`, `start_screen.gd`, `game_over.gd`.
- `tools/generate_organelle_defs.gd` — headless generator that writes the `.tres` files.
- `data/organelles/*.tres` — generated, 10 files.
- `tests/defs_factory.gd` plus `tests/test_catalog.gd`, `test_sim_core.gd`, `test_sim_economy.gd`, `test_sim_fat.gd`, `test_sim_survival.gd`, `test_director.gd`, `test_starter.gd`.

Modify:
- `scripts/TileBase.gd` — becomes a thin renderer (no input polling).
- `scripts/backround.gd` — add `refresh()`.
- `scene/cell Node2D.tscn` — attach scripts, set `organelle_id` / `terrain_id`, camera zoom.
- `CLAUDE.md` — architecture section.

Test running: open the project in the Godot editor with the godot-ai plugin enabled, then call the `test_run` MCP tool (optionally with the suite name). Expected output shows each suite and `passed`/`failed` counts.

---

### Task 1: OrganelleDef, generator and catalog

**Files:**
- Create: `scripts/sim/organelle_def.gd`, `scripts/sim/organelle_catalog.gd`, `tools/generate_organelle_defs.gd`, `data/organelles/*.tres` (generated), `tests/defs_factory.gd`, `tests/test_catalog.gd`

**Interfaces:**
- Produces:
  - `OrganelleDef` (all fields below), `OrganelleDef.CellType {ANIMAL = 0, PLANT = 1}`, `food_output_for(cell_type: int) -> float`, `waste_removal_for(cell_type: int) -> float`.
  - `OrganelleCatalog.load_all() -> Array[OrganelleDef]`.
  - `DefsFactory.make(id: String, props: Dictionary = {}) -> OrganelleDef` (tests only).

- [ ] **Step 1: Write the def resource**

`scripts/sim/organelle_def.gd`:

```gdscript
class_name OrganelleDef extends Resource
## Static data for one organelle type. Stats are per placed tile, per second.

enum CellType { ANIMAL, PLANT }

@export var id: String = ""
@export var display_name: String = ""
@export var city_name: String = ""
@export_multiline var function_text: String = ""
@export_multiline var city_text: String = ""

@export_group("Consumption")
@export var energy_use: float = 0.0
@export var water_use: float = 0.0
@export var food_use: float = 0.0
@export var waste_production: float = 0.0

@export_group("Production")
@export var energy_output: float = 0.0
@export var water_output: float = 0.0
@export var food_output_animal: float = 0.0
@export var food_output_plant: float = 0.0
@export var waste_removal_animal: float = 0.0
@export var waste_removal_plant: float = 0.0
@export var waste_to_food: float = 0.0
@export var water_capacity_bonus: float = 0.0

@export_group("Supply rules")
@export var needs_energy_link: bool = true
@export var needs_water_link: bool = true
@export var max_load: float = 0.0
@export var fat_access: bool = false
@export var max_paired_mitochondria: int = 0
@export var requires_adjacent: String = ""

@export_group("Progression and upkeep")
@export var unlock_thresholds: Dictionary = {}
@export var allowed_cell_types: PackedInt32Array = PackedInt32Array([0, 1])
@export var placement_energy_cost: float = 0.0
@export var repair_energy_cost: float = 0.0
@export var decay_per_second: float = 0.0
@export var max_group_size_animal: int = 0
@export var max_group_size_plant: int = 0

@export_group("Art")
@export var atlas_tile: Vector2i = Vector2i.ZERO


func food_output_for(cell_type: int) -> float:
	return food_output_plant if cell_type == CellType.PLANT else food_output_animal


func waste_removal_for(cell_type: int) -> float:
	return waste_removal_plant if cell_type == CellType.PLANT else waste_removal_animal
```

`scripts/sim/organelle_catalog.gd`:

```gdscript
class_name OrganelleCatalog extends RefCounted

const DIR := "res://data/organelles/"


static func load_all() -> Array[OrganelleDef]:
	var out: Array[OrganelleDef] = []
	for file_name in ResourceLoader.list_directory(DIR):
		if file_name.ends_with(".tres"):
			var def := load(DIR + file_name) as OrganelleDef
			if def != null:
				out.append(def)
	return out
```

`tests/defs_factory.gd`:

```gdscript
class_name DefsFactory extends RefCounted
## Builds OrganelleDefs in code for unit tests. Defaults come from OrganelleDef.


static func make(id: String, props: Dictionary = {}) -> OrganelleDef:
	var d := OrganelleDef.new()
	d.id = id
	d.display_name = id
	for key in props:
		d.set(key, props[key])
	return d
```

- [ ] **Step 2: Write the failing catalog test**

`tests/test_catalog.gd`:

```gdscript
extends McpTestSuite

const EXPECTED_IDS := [
	"membrane", "nucleus", "cytoplasm", "mitochondria", "vacuole",
	"cell_wall", "chromosomes", "chloroplast", "endoplasmic_reticulum", "lysosome",
]


func suite_name() -> String:
	return "catalog"


func test_all_ten_v1_organelles_exist() -> void:
	var ids: Array[String] = []
	for d in OrganelleCatalog.load_all():
		ids.append(d.id)
	ids.sort()
	var expected := EXPECTED_IDS.duplicate()
	expected.sort()
	assert_eq(ids, expected)


func test_every_def_has_teaching_text() -> void:
	for d in OrganelleCatalog.load_all():
		assert_false(d.display_name.is_empty(), d.id + " display_name")
		assert_false(d.city_name.is_empty(), d.id + " city_name")
		assert_false(d.function_text.is_empty(), d.id + " function_text")
		assert_false(d.city_text.is_empty(), d.id + " city_text")


func test_thresholds_only_use_food_water_waste() -> void:
	for d in OrganelleCatalog.load_all():
		for key in d.unlock_thresholds:
			assert_contains(["food", "water", "waste"], key, d.id)


func test_plant_only_organelles() -> void:
	var by_id := {}
	for d in OrganelleCatalog.load_all():
		by_id[d.id] = d
	for id in ["cell_wall", "chloroplast"]:
		assert_eq(Array(by_id[id].allowed_cell_types), [OrganelleDef.CellType.PLANT], id)


func test_special_roles() -> void:
	var by_id := {}
	for d in OrganelleCatalog.load_all():
		by_id[d.id] = d
	assert_gt(by_id["mitochondria"].max_load, 0.0)
	assert_true(by_id["endoplasmic_reticulum"].fat_access)
	assert_eq(by_id["endoplasmic_reticulum"].max_paired_mitochondria, 1)
	assert_eq(by_id["nucleus"].requires_adjacent, "chromosomes")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `test_run` (suite `catalog`).
Expected: FAIL (`test_all_ten_v1_organelles_exist`: found `[]`; the `data/organelles/` directory does not exist yet).

- [ ] **Step 4: Write the generator**

`tools/generate_organelle_defs.gd` (a `SceneTree` script so it runs headless; re-run any time numbers change):

```gdscript
extends SceneTree
## Regenerates data/organelles/*.tres from the table below.
## Run: godot --headless --path . --script res://tools/generate_organelle_defs.gd
## Tune numbers HERE (or edit the .tres in the inspector), not in game code.

const OUT_DIR := "res://data/organelles/"
const ANIMAL := OrganelleDef.CellType.ANIMAL
const PLANT := OrganelleDef.CellType.PLANT


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var failed := false
	for row in _rows():
		var d := OrganelleDef.new()
		for key in row:
			d.set(key, row[key])
		var err := ResourceSaver.save(d, OUT_DIR + String(row["id"]) + ".tres")
		if err != OK:
			push_error("save failed for %s: %s" % [row["id"], error_string(err)])
			failed = true
	quit(1 if failed else 0)


func _rows() -> Array[Dictionary]:
	return [
		{
			"id": "membrane", "display_name": "Membrane", "city_name": "City limits",
			"function_text": "A semi-permeable layer that controls what enters and exits the cell. It collects water, and in animal cells it absorbs food.",
			"city_text": "City limits control what enters and exits a city, just like a membrane controls what enters and exits a cell.",
			"energy_use": 0.2, "water_output": 0.6, "food_output_animal": 0.25,
			"needs_energy_link": false, "needs_water_link": false,
			"decay_per_second": 0.1, "repair_energy_cost": 0.5, "atlas_tile": Vector2i(2, 0),
		},
		{
			"id": "nucleus", "display_name": "Nucleus", "city_name": "Municipal government",
			"function_text": "Controls the cell's actions and holds the chromosomes. Every cell needs one, and it only works beside its chromosomes.",
			"city_text": "The government creates laws and makes sure everything is in order, just like a nucleus. The DNA inside holds the instructions that tell the cell what to do.",
			"energy_use": 5.0, "water_use": 10.0, "waste_production": 0.5,
			"requires_adjacent": "chromosomes", "repair_energy_cost": 3.0, "atlas_tile": Vector2i(0, 0),
		},
		{
			"id": "cytoplasm", "display_name": "Cytoplasm", "city_name": "Delivery systems",
			"function_text": "A jelly-like substance that constantly moves around the cell, carrying food and oxygen to organelles. In plant cells its movement also carries waste away.",
			"city_text": "People who deliver food to people are like cytoplasm, except they aren't jelly.",
			"energy_use": 1.0, "water_use": 2.0, "waste_production": 0.1, "waste_removal_plant": 0.5,
			"needs_energy_link": false, "needs_water_link": false, "atlas_tile": Vector2i(0, 2),
		},
		{
			"id": "mitochondria", "display_name": "Mitochondria", "city_name": "Coal and oil power plant",
			"function_text": "Takes in food and breaks it down into chemical energy for the whole cell. Beside an endoplasmic reticulum it can also burn stored fat.",
			"city_text": "Power plants take in resources that burn hot to turn turbines and create energy. Mitochondria take in food to make the cell's chemical energy.",
			"energy_use": 20.0, "water_use": 15.0, "food_use": 20.0, "waste_production": 2.0,
			"energy_output": 150.0, "max_load": 150.0, "needs_energy_link": false,
			"repair_energy_cost": 5.0, "atlas_tile": Vector2i(0, 3),
		},
		{
			"id": "vacuole", "display_name": "Vacuole", "city_name": "Water tower",
			"function_text": "Stores water and liquid waste so the cell can use or expel it later. Animal vacuoles stay small, plant vacuoles can grow large.",
			"city_text": "Water towers store water or liquids for later use. A vacuole does the same, and can also expel waste water.",
			"energy_use": 5.0, "water_use": 15.0,
			"waste_removal_animal": 3.33, "waste_removal_plant": 3.33, "water_capacity_bonus": 40.0,
			"max_group_size_animal": 4, "max_group_size_plant": 25,
			"unlock_thresholds": {"water": 80.0}, "atlas_tile": Vector2i(0, 1),
		},
		{
			"id": "cell_wall", "display_name": "Cell wall", "city_name": "Flood gates",
			"function_text": "A thick, sturdy outer layer of plant cells that gives support and keeps the inside separate from the outside. It slowly wears down and must be replaced.",
			"city_text": "Flood gates protect a city from storms and tsunamis. A cell wall is sturdy and keeps the inside of the cell separated from the outside.",
			"energy_use": 0.1, "water_output": 0.4, "needs_energy_link": false, "needs_water_link": false,
			"allowed_cell_types": PackedInt32Array([PLANT]), "placement_energy_cost": 0.5,
			"decay_per_second": 0.05, "repair_energy_cost": 0.5, "atlas_tile": Vector2i(2, 3),
		},
		{
			"id": "chromosomes", "display_name": "Chromosomes", "city_name": "Library",
			"function_text": "Store, protect and spread your DNA around the cell. They wear down and need energy to repair, and must sit beside the nucleus.",
			"city_text": "A library holds information on how to do things, make things and where places are. Chromosomes store information on what the cell should do and look like.",
			"water_use": 3.0, "waste_production": 0.3, "needs_energy_link": false,
			"decay_per_second": 0.1, "repair_energy_cost": 3.0,
			"unlock_thresholds": {"water": 50.0}, "atlas_tile": Vector2i(0, 4),
		},
		{
			"id": "chloroplast", "display_name": "Chloroplast", "city_name": "Solar panels",
			"function_text": "Where photosynthesis happens. In plant cells this is where food comes from for the mitochondria to turn into energy.",
			"city_text": "Solar panels are chloroplasts of a city: they take sunlight and make it into usable energy.",
			"energy_use": 20.0, "water_use": 10.0, "waste_production": 1.0, "food_output_plant": 20.0,
			"allowed_cell_types": PackedInt32Array([PLANT]), "repair_energy_cost": 5.0,
			"atlas_tile": Vector2i(0, 5),
		},
		{
			"id": "endoplasmic_reticulum", "display_name": "Endoplasmic reticulum", "city_name": "Factory",
			"function_text": "Folded canals that make proteins and lipids. Here it stores fat: a mitochondria placed right beside it and linked to it can burn that fat when food runs short.",
			"city_text": "A factory quickly creates goods and sends them on their way. The ER makes proteins and lipids and holds the reserves that keep production going.",
			"energy_use": 10.0, "water_use": 10.0, "waste_production": 0.5,
			"fat_access": true, "max_paired_mitochondria": 1, "repair_energy_cost": 3.0,
			"unlock_thresholds": {"food": 80.0}, "atlas_tile": Vector2i(0, 6),
		},
		{
			"id": "lysosome", "display_name": "Lysosome", "city_name": "Waste processing facility",
			"function_text": "Takes in waste and turns it into usable nutrients or harmless particles. Its nutrients go back to the cell as food.",
			"city_text": "Waste processing facilities take in garbage and grind it up or burn it for energy. Lysosomes turn waste into usable nutrients.",
			"energy_use": 15.0, "water_use": 5.0,
			"waste_removal_animal": 3.0, "waste_removal_plant": 3.0, "waste_to_food": 0.5,
			"unlock_thresholds": {"waste": 25.0}, "repair_energy_cost": 5.0, "atlas_tile": Vector2i(0, 7),
		},
	]
```

- [ ] **Step 5: Import and run the generator**

```bash
cd "/Users/AlexTam/Desktop/cellular city"
godot --headless --path . --import
godot --headless --path . --script res://tools/generate_organelle_defs.gd
ls data/organelles
```

If `godot` is not on PATH, use `/Applications/Godot.app/Contents/MacOS/Godot` instead.
Expected: ten `.tres` files listed (`membrane.tres` … `lysosome.tres`) and exit code 0.

- [ ] **Step 6: Run test to verify it passes**

Run: `test_run` (suite `catalog`). Expected: 5 passed.

- [ ] **Step 7: Commit**

```bash
git add scripts/sim/organelle_def.gd scripts/sim/organelle_catalog.gd tools/generate_organelle_defs.gd data/organelles tests/defs_factory.gd tests/test_catalog.gd
git commit -m "feat: add data-driven organelle definitions and generator"
```

---

### Task 2: CellSim core — placement, removal, unlocks, links

**Files:**
- Create: `scripts/sim/placed_organelle.gd`, `scripts/sim/sim_link.gd`, `scripts/sim/cell_sim.gd`, `tests/test_sim_core.gd`

**Interfaces:**
- Consumes: `OrganelleDef` from Task 1.
- Produces (used by every later task):
  - `PlacedOrganelle`: `uid: int`, `def: OrganelleDef`, `cell: Vector2i`, `health: float`, `disabled: bool`, `energy_ok: bool`, `water_ok: bool`, `running: bool`, `alive() -> bool`.
  - `SimLink`: `from_uid`, `to_uid`, `type`, `SimLink.Type {ENERGY, WATER, FAT}`, `SimLink.make(from_uid, to_uid, type) -> SimLink`. A link always points from the consumer to its supplier (FAT: from the mitochondria to the ER).
  - `CellSim.new(defs: Array, cell_type: int)`; `signal unlocked(def_id: String)`, `signal lost(reason: String)`, `signal organelle_added(uid: int)`, `signal organelle_removed(uid: int, cell: Vector2i, def_id: String)`.
  - Fields: `cell_type`, `defs: Dictionary` (id → def), `meters: Dictionary`, `organelles: Dictionary` (uid → PlacedOrganelle), `links: Array[SimLink]`, `unlocked_ids: Dictionary`, `elapsed`, `is_lost`, `lost_reason`, `nucleus_required: bool = true`, `decay_multiplier: float = 1.0`.
  - Methods: `can_place(def_id, cell, free := false) -> String` (empty string = ok; otherwise one of `unknown`, `wrong_cell_type`, `locked`, `occupied`, `no_energy`, `group_full`), `add_organelle(def_id, cell, free := false) -> int` (uid or -1), `remove_organelle(uid)`, `organelle_at(cell) -> int` (-1 if none), `are_adjacent(a_uid, b_uid) -> bool`, `infer_link_type(from_uid, to_uid) -> int` (-1 invalid), `add_link(from_uid, to_uid) -> bool`, `has_link(from_uid, to_uid, type) -> bool`, `remove_link(from_uid, to_uid, type)`, `remove_links_of(uid)`, `refresh_unlocks(emit_signals := true)`, `static thresholds_met(current, thresholds) -> bool`, `unlock_progress(def_id) -> Dictionary` (`{meter: [current, required]}`), `capacities() -> Dictionary`.

- [ ] **Step 1: Write the failing tests**

`tests/test_sim_core.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `sim_core`). Expected: FAIL (suite fails to load: `CellSim` is not declared).

- [ ] **Step 3: Write the minimal implementation**

`scripts/sim/placed_organelle.gd`:

```gdscript
class_name PlacedOrganelle extends RefCounted
## Runtime state of one placed tile.

var uid: int = 0
var def: OrganelleDef
var cell: Vector2i = Vector2i.ZERO
var health: float = 100.0
var disabled: bool = false  # knocked out by a bacteria event until repaired
var energy_ok: bool = false
var water_ok: bool = false
var running: bool = false


func alive() -> bool:
	return health > 0.0 and not disabled
```

`scripts/sim/sim_link.gd`:

```gdscript
class_name SimLink extends RefCounted
## A drawn connection. `from_uid` is the consumer, `to_uid` its supplier
## (for FAT links: from the mitochondria to the ER).

enum Type { ENERGY, WATER, FAT }

var from_uid: int = 0
var to_uid: int = 0
var type: int = Type.ENERGY


static func make(p_from: int, p_to: int, p_type: int) -> SimLink:
	var l := SimLink.new()
	l.from_uid = p_from
	l.to_uid = p_to
	l.type = p_type
	return l
```

`scripts/sim/cell_sim.gd`:

```gdscript
class_name CellSim extends RefCounted
## All game rules. No scene dependencies, so it is unit-testable.

signal unlocked(def_id: String)
signal lost(reason: String)
signal organelle_added(uid: int)
signal organelle_removed(uid: int, cell: Vector2i, def_id: String)

const METERS: Array[String] = ["food", "energy", "water", "waste", "fat"]
const BASE_CAPS := {"food": 200.0, "energy": 500.0, "water": 200.0, "waste": 200.0, "fat": 100.0}
const STARTING := {"food": 50.0, "energy": 100.0, "water": 60.0, "waste": 0.0, "fat": 30.0}

var cell_type: int
var defs: Dictionary = {}
var meters: Dictionary = {}
var organelles: Dictionary = {}
var links: Array[SimLink] = []
var unlocked_ids: Dictionary = {}
var elapsed: float = 0.0
var is_lost: bool = false
var lost_reason: String = ""
var nucleus_required: bool = true
var decay_multiplier: float = 1.0

var _cell_index: Dictionary = {}
var _next_uid: int = 1


func _init(p_defs: Array, p_cell_type: int) -> void:
	cell_type = p_cell_type
	for d: OrganelleDef in p_defs:
		defs[d.id] = d
	meters = STARTING.duplicate()
	refresh_unlocks(false)


# ----- capacities and unlocks -----

func capacities() -> Dictionary:
	var caps := BASE_CAPS.duplicate()
	for o: PlacedOrganelle in organelles.values():
		if o.alive():
			caps["water"] += o.def.water_capacity_bonus
	return caps


static func thresholds_met(current: Dictionary, thresholds: Dictionary) -> bool:
	for key in thresholds:
		if float(current.get(key, 0.0)) < float(thresholds[key]):
			return false
	return true


func unlock_progress(def_id: String) -> Dictionary:
	var out := {}
	var d: OrganelleDef = defs[def_id]
	for key in d.unlock_thresholds:
		out[key] = [float(meters.get(key, 0.0)), float(d.unlock_thresholds[key])]
	return out


func refresh_unlocks(emit_signals: bool = true) -> void:
	for id in defs:
		if unlocked_ids.has(id):
			continue
		var d: OrganelleDef = defs[id]
		if not d.allowed_cell_types.has(cell_type):
			continue
		if thresholds_met(meters, d.unlock_thresholds):
			unlocked_ids[id] = true
			if emit_signals:
				unlocked.emit(id)


# ----- placement -----

func can_place(def_id: String, cell: Vector2i, free: bool = false) -> String:
	var d: OrganelleDef = defs.get(def_id)
	if d == null:
		return "unknown"
	if not d.allowed_cell_types.has(cell_type):
		return "wrong_cell_type"
	if not free and not unlocked_ids.has(def_id):
		return "locked"
	if _cell_index.has(cell):
		return "occupied"
	if not free and float(meters["energy"]) < d.placement_energy_cost:
		return "no_energy"
	var limit := d.max_group_size_plant if cell_type == OrganelleDef.CellType.PLANT else d.max_group_size_animal
	if limit > 0 and _group_size_with(def_id, cell) > limit:
		return "group_full"
	return ""


func add_organelle(def_id: String, cell: Vector2i, free: bool = false) -> int:
	if can_place(def_id, cell, free) != "":
		return -1
	var d: OrganelleDef = defs[def_id]
	if free:
		unlocked_ids[def_id] = true
	else:
		meters["energy"] = float(meters["energy"]) - d.placement_energy_cost
	var o := PlacedOrganelle.new()
	o.uid = _next_uid
	_next_uid += 1
	o.def = d
	o.cell = cell
	organelles[o.uid] = o
	_cell_index[cell] = o.uid
	organelle_added.emit(o.uid)
	return o.uid


func remove_organelle(uid: int) -> void:
	var o: PlacedOrganelle = organelles.get(uid)
	if o == null:
		return
	organelles.erase(uid)
	_cell_index.erase(o.cell)
	remove_links_of(uid)
	organelle_removed.emit(uid, o.cell, o.def.id)


func organelle_at(cell: Vector2i) -> int:
	return _cell_index.get(cell, -1)


func are_adjacent(a_uid: int, b_uid: int) -> bool:
	var a: PlacedOrganelle = organelles.get(a_uid)
	var b: PlacedOrganelle = organelles.get(b_uid)
	if a == null or b == null:
		return false
	return absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y) == 1


func _neighbors(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN]


func _group_size_with(def_id: String, cell: Vector2i) -> int:
	var seen := {cell: true}
	var stack: Array[Vector2i] = [cell]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for n in _neighbors(c):
			if seen.has(n):
				continue
			var uid: int = _cell_index.get(n, -1)
			if uid != -1 and (organelles[uid] as PlacedOrganelle).def.id == def_id:
				seen[n] = true
				stack.append(n)
	return seen.size()


# ----- links -----

func infer_link_type(from_uid: int, to_uid: int) -> int:
	var a: PlacedOrganelle = organelles.get(from_uid)
	var b: PlacedOrganelle = organelles.get(to_uid)
	if a == null or b == null or from_uid == to_uid:
		return -1
	if b.def.max_load > 0.0 and a.def.needs_energy_link:
		return SimLink.Type.ENERGY
	if b.def.water_output > 0.0 and a.def.needs_water_link:
		return SimLink.Type.WATER
	if a.def.energy_output > 0.0 and b.def.fat_access:
		return SimLink.Type.FAT
	return -1


func add_link(from_uid: int, to_uid: int) -> bool:
	var t := infer_link_type(from_uid, to_uid)
	if t == -1 or has_link(from_uid, to_uid, t):
		return false
	links.append(SimLink.make(from_uid, to_uid, t))
	return true


func has_link(from_uid: int, to_uid: int, type: int) -> bool:
	for l in links:
		if l.from_uid == from_uid and l.to_uid == to_uid and l.type == type:
			return true
	return false


func remove_link(from_uid: int, to_uid: int, type: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return not (l.from_uid == from_uid and l.to_uid == to_uid and l.type == type)))


func remove_links_of(uid: int) -> void:
	links.assign(links.filter(func(l: SimLink) -> bool:
		return l.from_uid != uid and l.to_uid != uid))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (suite `sim_core`). Expected: 14 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/placed_organelle.gd scripts/sim/sim_link.gd scripts/sim/cell_sim.gd tests/test_sim_core.gd
git commit -m "feat: CellSim core with placement, links and threshold unlocks"
```

---

### Task 3: CellSim tick — supply, economy, waste, caps

**Files:**
- Modify: `scripts/sim/cell_sim.gd`
- Test: `tests/test_sim_economy.gd`

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: `CellSim.tick(dt: float)`, plus the private steps `_resolve_supply()`, `_update_running()`, `_run_economy(dt)`, `_fuel_fraction(o, dt) -> float`, `_clamp_meters()` that Tasks 4 and 5 extend. After a tick, `PlacedOrganelle.energy_ok`, `water_ok`, `running` are current.

- [ ] **Step 1: Write the failing tests**

`tests/test_sim_economy.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `sim_economy`). Expected: FAIL (`tick` is not a method of `CellSim`).

- [ ] **Step 3: Write the minimal implementation**

Append to `scripts/sim/cell_sim.gd`:

```gdscript
# ----- tick -----

func tick(dt: float) -> void:
	if is_lost:
		return
	elapsed += dt
	_resolve_supply()
	_update_running()
	_run_economy(dt)


func _resolve_supply() -> void:
	for o: PlacedOrganelle in organelles.values():
		o.water_ok = not o.def.needs_water_link
		o.energy_ok = not o.def.needs_energy_link
	for l in links:
		if l.type != SimLink.Type.WATER:
			continue
		var consumer: PlacedOrganelle = organelles.get(l.from_uid)
		var source: PlacedOrganelle = organelles.get(l.to_uid)
		if consumer != null and source != null and source.def.water_output > 0.0 and source.alive():
			consumer.water_ok = true
	var used := {}
	for l in links:
		if l.type != SimLink.Type.ENERGY:
			continue
		var consumer: PlacedOrganelle = organelles.get(l.from_uid)
		var source: PlacedOrganelle = organelles.get(l.to_uid)
		if consumer == null or source == null:
			continue
		if source.def.max_load <= 0.0 or not source.alive() or not source.water_ok:
			continue
		var load_now: float = used.get(source.uid, 0.0)
		if load_now + consumer.def.energy_use <= source.def.max_load:
			used[source.uid] = load_now + consumer.def.energy_use
			consumer.energy_ok = true


func _update_running() -> void:
	for o: PlacedOrganelle in organelles.values():
		o.running = o.alive() and o.energy_ok and o.water_ok and _adjacency_ok(o)


func _adjacency_ok(o: PlacedOrganelle) -> bool:
	if o.def.requires_adjacent == "":
		return true
	for n in _neighbors(o.cell):
		var uid: int = _cell_index.get(n, -1)
		if uid == -1:
			continue
		var other: PlacedOrganelle = organelles[uid]
		if other.def.id == o.def.requires_adjacent and other.alive():
			return true
	return false


func _run_economy(dt: float) -> void:
	var active: Array[PlacedOrganelle] = []
	for o: PlacedOrganelle in organelles.values():
		if o.running:
			active.append(o)
	# 1. mitochondria turn fuel into energy
	for o in active:
		if o.def.energy_output > 0.0:
			meters["energy"] += o.def.energy_output * dt * _fuel_fraction(o, dt)
	# 2. energy is spent; a shortage scales everyone's output down
	var energy_demand := 0.0
	var water_demand := 0.0
	for o in active:
		energy_demand += o.def.energy_use * dt
		water_demand += o.def.water_use * dt
	var energy_factor := 1.0 if energy_demand <= 0.0 else minf(1.0, float(meters["energy"]) / energy_demand)
	meters["energy"] -= energy_demand * energy_factor
	# 3. water is collected, then spent
	for o in active:
		if o.def.water_output > 0.0:
			var yield_fraction := 1.0 if o.health >= 90.0 else 1.0 / 16.0
			meters["water"] += o.def.water_output * dt * energy_factor * yield_fraction
	var water_factor := 1.0 if water_demand <= 0.0 else minf(1.0, float(meters["water"]) / water_demand)
	meters["water"] -= water_demand * water_factor
	# 4. food and waste follow the slower of the two
	var rate := minf(energy_factor, water_factor)
	for o in active:
		var d := o.def
		meters["food"] += d.food_output_for(cell_type) * dt * rate
		meters["waste"] += d.waste_production * dt * rate
		var removal := minf(float(meters["waste"]), d.waste_removal_for(cell_type) * dt * rate)
		meters["waste"] -= removal
		meters["food"] += removal * d.waste_to_food
	_clamp_meters()


## Fraction (0..1) of a mitochondria's fuel need that was satisfied this tick.
func _fuel_fraction(o: PlacedOrganelle, dt: float) -> float:
	var need := o.def.food_use * dt
	if need <= 0.0:
		return 1.0
	var from_food := minf(float(meters["food"]), need)
	meters["food"] -= from_food
	return from_food / need


func _clamp_meters() -> void:
	var caps := capacities()
	for m in METERS:
		meters[m] = clampf(float(meters[m]), 0.0, float(caps[m]))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (suites `sim_core`, `sim_economy`). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/cell_sim.gd tests/test_sim_economy.gd
git commit -m "feat: CellSim tick with supply capacity, water, food and waste"
```

---

### Task 4: Fat reserve and ER pairing

**Files:**
- Modify: `scripts/sim/cell_sim.gd`
- Test: `tests/test_sim_fat.gd`

**Interfaces:**
- Consumes: `_resolve_supply`, `_fuel_fraction`, `_clamp_meters` from Task 3.
- Produces: `CellSim.is_fat_paired(mito_uid: int) -> bool` (used by the UI/tooltip and `LinkLayer`), private `_fat_paired: Dictionary` (mito uid → ER uid), surplus food converting to fat (`FAT_FROM_SURPLUS = 0.5`).

- [ ] **Step 1: Write the failing tests**

`tests/test_sim_fat.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `sim_fat`). Expected: FAIL (`is_fat_paired` is not a method of `CellSim`).

- [ ] **Step 3: Write the minimal implementation**

In `scripts/sim/cell_sim.gd`, add the constant and the field near the other declarations:

```gdscript
const FAT_FROM_SURPLUS := 0.5
```

```gdscript
var _fat_paired: Dictionary = {}
```

Add this method (public) next to `are_adjacent`:

```gdscript
func is_fat_paired(mito_uid: int) -> bool:
	return _fat_paired.has(mito_uid)
```

At the end of `_resolve_supply()`, append the pairing pass:

```gdscript
	_fat_paired.clear()
	var er_taken := {}
	for l in links:
		if l.type != SimLink.Type.FAT or _fat_paired.has(l.from_uid):
			continue
		var m: PlacedOrganelle = organelles.get(l.from_uid)
		var er: PlacedOrganelle = organelles.get(l.to_uid)
		if m == null or er == null:
			continue
		if m.def.energy_output <= 0.0 or not er.def.fat_access or not er.alive():
			continue
		if not are_adjacent(m.uid, er.uid):
			continue
		var taken: int = er_taken.get(er.uid, 0)
		if taken >= er.def.max_paired_mitochondria:
			continue
		er_taken[er.uid] = taken + 1
		_fat_paired[m.uid] = er.uid
```

Replace `_fuel_fraction` with the fat-aware version:

```gdscript
func _fuel_fraction(o: PlacedOrganelle, dt: float) -> float:
	var need := o.def.food_use * dt
	if need <= 0.0:
		return 1.0
	var from_food := minf(float(meters["food"]), need)
	var from_fat := 0.0
	if from_food < need and _fat_paired.has(o.uid):
		from_fat = minf(float(meters["fat"]), need - from_food)
	meters["food"] -= from_food
	meters["fat"] -= from_fat
	return (from_food + from_fat) / need
```

Replace `_clamp_meters` so surplus food becomes fat:

```gdscript
func _clamp_meters() -> void:
	var caps := capacities()
	var surplus := maxf(0.0, float(meters["food"]) - float(caps["food"]))
	meters["fat"] += surplus * FAT_FROM_SURPLUS
	for m in METERS:
		meters[m] = clampf(float(meters[m]), 0.0, float(caps[m]))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (suites `sim_core`, `sim_economy`, `sim_fat`). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/cell_sim.gd tests/test_sim_fat.gd
git commit -m "feat: fat reserve usable only by a mitochondria paired with an ER"
```

---

### Task 5: Decay, repair, toxic waste, nucleus loss, unlock-on-tick

**Files:**
- Modify: `scripts/sim/cell_sim.gd`
- Test: `tests/test_sim_survival.gd`

**Interfaces:**
- Consumes: `tick`, `decay_multiplier`, `nucleus_required`, `refresh_unlocks`.
- Produces: `CellSim.needs_repair(uid) -> bool`, `CellSim.repair(uid) -> bool`, `CellSim.force_lose(reason: String)`, constants `NUCLEUS_GRACE = 3.0`, `TOXIC_DAMAGE = 2.0`. `tick` now also decays health, checks the nucleus and refreshes unlocks.

- [ ] **Step 1: Write the failing tests**

`tests/test_sim_survival.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `sim_survival`). Expected: FAIL (`needs_repair` / `force_lose` missing).

- [ ] **Step 3: Write the minimal implementation**

Add constants and a field in `scripts/sim/cell_sim.gd`:

```gdscript
const NUCLEUS_GRACE := 3.0
const TOXIC_DAMAGE := 2.0
```

```gdscript
var _no_nucleus_time: float = 0.0
```

Replace `tick` with:

```gdscript
func tick(dt: float) -> void:
	if is_lost:
		return
	elapsed += dt
	_apply_decay(dt)
	_resolve_supply()
	_update_running()
	_run_economy(dt)
	refresh_unlocks()
	_check_nucleus(dt)
```

Append the new methods:

```gdscript
func _apply_decay(dt: float) -> void:
	var toxic := float(meters["waste"]) >= float(capacities()["waste"])
	for o: PlacedOrganelle in organelles.values():
		var loss := o.def.decay_per_second * decay_multiplier
		if toxic:
			loss += TOXIC_DAMAGE
		if loss > 0.0:
			o.health = maxf(0.0, o.health - loss * dt)


func needs_repair(uid: int) -> bool:
	var o: PlacedOrganelle = organelles.get(uid)
	return o != null and (o.disabled or o.health < 100.0)


func repair(uid: int) -> bool:
	var o: PlacedOrganelle = organelles.get(uid)
	if o == null or not needs_repair(uid):
		return false
	if float(meters["energy"]) < o.def.repair_energy_cost:
		return false
	meters["energy"] -= o.def.repair_energy_cost
	o.health = 100.0
	o.disabled = false
	return true


func _check_nucleus(dt: float) -> void:
	if not nucleus_required:
		return
	var has_nucleus := false
	for o: PlacedOrganelle in organelles.values():
		if o.def.id == "nucleus" and o.running:
			has_nucleus = true
			break
	_no_nucleus_time = 0.0 if has_nucleus else _no_nucleus_time + dt
	if _no_nucleus_time >= NUCLEUS_GRACE:
		force_lose("nucleus")


func force_lose(reason: String) -> void:
	if is_lost:
		return
	is_lost = true
	lost_reason = reason
	lost.emit(reason)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (all `sim_*` suites). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/cell_sim.gd tests/test_sim_survival.gd
git commit -m "feat: decay, repair, toxic waste, nucleus loss and unlocks on tick"
```

---

### Task 6: DifficultyCurve and DamageDirector

**Files:**
- Create: `scripts/sim/difficulty_curve.gd`, `scripts/sim/damage_director.gd`, `tests/test_director.gd`

**Interfaces:**
- Consumes: `CellSim` (`organelles`, `links`, `elapsed`, `remove_link`, `has_link`, `force_lose`, `is_lost`).
- Produces:
  - `DifficultyCurve` resource: `event_interval(t)`, `event_size(t) -> int`, `repair_window(t)`, `decay_multiplier(t)`, `first_event_delay`.
  - `DamageDirector.new(sim: CellSim, curve: DifficultyCurve, rng: RandomNumberGenerator)`, `tick(dt)`, `timers: Array[Dictionary]` (each has `label: String` and `remaining: float`), `signal event_fired(label: String)`, `bacteria_chance: float`.

- [ ] **Step 1: Write the failing tests**

`tests/test_director.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `director`). Expected: FAIL (`DifficultyCurve` / `DamageDirector` not declared).

- [ ] **Step 3: Write the minimal implementation**

`scripts/sim/difficulty_curve.gd`:

```gdscript
class_name DifficultyCurve extends Resource
## Every value that scales with survival time lives here, in seconds.

@export var first_event_delay: float = 45.0
@export var interval_start: float = 40.0
@export var interval_floor: float = 12.0
@export var interval_ramp_seconds: float = 600.0
@export var size_start: int = 1
@export var size_max: int = 5
@export var size_ramp_seconds: float = 900.0
@export var repair_start: float = 60.0
@export var repair_floor: float = 20.0
@export var repair_ramp_seconds: float = 600.0
@export var decay_multiplier_max: float = 2.0
@export var decay_ramp_seconds: float = 900.0


func _progress(t: float, ramp: float) -> float:
	return clampf(t / ramp, 0.0, 1.0)


func event_interval(t: float) -> float:
	return lerpf(interval_start, interval_floor, _progress(t, interval_ramp_seconds))


func event_size(t: float) -> int:
	return int(round(lerpf(float(size_start), float(size_max), _progress(t, size_ramp_seconds))))


func repair_window(t: float) -> float:
	return lerpf(repair_start, repair_floor, _progress(t, repair_ramp_seconds))


func decay_multiplier(t: float) -> float:
	return lerpf(1.0, decay_multiplier_max, _progress(t, decay_ramp_seconds))
```

`scripts/sim/damage_director.gd`:

```gdscript
class_name DamageDirector extends RefCounted
## Fires bacteria and cut events and tracks their repair timers.

signal event_fired(label: String)

var bacteria_chance: float = 0.6
var timers: Array[Dictionary] = []

var _sim: CellSim
var _curve: DifficultyCurve
var _rng: RandomNumberGenerator
var _time_to_event: float


func _init(sim: CellSim, curve: DifficultyCurve, rng: RandomNumberGenerator) -> void:
	_sim = sim
	_curve = curve
	_rng = rng
	_time_to_event = curve.first_event_delay


func tick(dt: float) -> void:
	if _sim.is_lost:
		return
	_update_timers(dt)
	if _sim.is_lost:
		return
	_time_to_event -= dt
	if _time_to_event <= 0.0:
		_fire_event()
		_time_to_event = _curve.event_interval(_sim.elapsed)


func _update_timers(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for t in timers:
		if _is_resolved(t):
			continue
		t["remaining"] = float(t["remaining"]) - dt
		if float(t["remaining"]) <= 0.0:
			_sim.force_lose("repair_timeout")
			return
		kept.append(t)
	timers = kept


func _is_resolved(t: Dictionary) -> bool:
	if t["kind"] == "organelle":
		var o: PlacedOrganelle = _sim.organelles.get(t["uid"])
		return o == null or not o.disabled
	if not _sim.organelles.has(t["from_uid"]) or not _sim.organelles.has(t["to_uid"]):
		return true
	return _sim.has_link(t["from_uid"], t["to_uid"], t["type"])


func _fire_event() -> void:
	var count := _curve.event_size(_sim.elapsed)
	var window := _curve.repair_window(_sim.elapsed)
	if _rng.randf() < bacteria_chance:
		_bacteria(count, window)
	else:
		_cut(count, window)


func _bacteria(count: int, window: float) -> void:
	var pool: Array[PlacedOrganelle] = []
	for o: PlacedOrganelle in _sim.organelles.values():
		if o.alive():
			pool.append(o)
	for i in mini(count, pool.size()):
		var victim: PlacedOrganelle = pool.pop_at(_rng.randi() % pool.size())
		victim.disabled = true
		var label := "Bacteria in %s" % victim.def.display_name
		timers.append({"kind": "organelle", "uid": victim.uid, "label": label, "remaining": window})
		event_fired.emit(label)


func _cut(count: int, window: float) -> void:
	var pool: Array[SimLink] = _sim.links.duplicate()
	for i in mini(count, pool.size()):
		var victim: SimLink = pool.pop_at(_rng.randi() % pool.size())
		_sim.remove_link(victim.from_uid, victim.to_uid, victim.type)
		var from_o: PlacedOrganelle = _sim.organelles[victim.from_uid]
		var label := "Cut link at %s" % from_o.def.display_name
		timers.append({
			"kind": "link", "from_uid": victim.from_uid, "to_uid": victim.to_uid,
			"type": victim.type, "label": label, "remaining": window,
		})
		event_fired.emit(label)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (all suites). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/difficulty_curve.gd scripts/sim/damage_director.gd tests/test_director.gd
git commit -m "feat: difficulty curve and bacteria/cut damage director"
```

---

### Task 7: StarterLayout and a balance smoke test

**Files:**
- Create: `scripts/sim/starter_layout.gd`, `tests/test_starter.gd`

**Interfaces:**
- Consumes: `CellSim.add_organelle(.., free=true)`, `add_link`, `OrganelleCatalog.load_all()`.
- Produces: `StarterLayout.HALF = Vector2i(20, 10)`, `StarterLayout.ring(half: Vector2i) -> Array[Vector2i]`, `StarterLayout.in_bounds(cell: Vector2i, cell_type: int) -> bool`, `StarterLayout.build(sim: CellSim, rng: RandomNumberGenerator) -> void`.

- [ ] **Step 1: Write the failing tests**

`tests/test_starter.gd`:

```gdscript
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
	assert_eq(cells.size(), 120)
	var unique := {}
	for c in cells:
		unique[c] = true
	assert_eq(unique.size(), 120)


func test_in_bounds() -> void:
	assert_true(StarterLayout.in_bounds(Vector2i(0, 0), ANIMAL))
	assert_true(StarterLayout.in_bounds(Vector2i(20, 10), ANIMAL))
	assert_false(StarterLayout.in_bounds(Vector2i(21, 0), ANIMAL))
	assert_true(StarterLayout.in_bounds(Vector2i(21, 11), PLANT))
	assert_false(StarterLayout.in_bounds(Vector2i(22, 0), PLANT))
	assert_false(StarterLayout.in_bounds(Vector2i(0, -12), PLANT))


func test_animal_layout_contents() -> void:
	var s := _built(ANIMAL)
	assert_eq(_count(s, "membrane"), 120)
	assert_eq(_count(s, "cell_wall"), 0)
	assert_eq(_count(s, "nucleus"), 1)
	assert_eq(_count(s, "chromosomes"), 1)
	assert_eq(_count(s, "mitochondria"), 1)
	assert_eq(_count(s, "chloroplast"), 0)


func test_plant_layout_adds_wall_and_chloroplast() -> void:
	var s := _built(PLANT)
	assert_eq(_count(s, "cell_wall"), 124)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test_run` (suite `starter`). Expected: FAIL (`StarterLayout` not declared).

- [ ] **Step 3: Write the minimal implementation**

`scripts/sim/starter_layout.gd`:

```gdscript
class_name StarterLayout extends RefCounted
## The pre-built cell a run starts with: a membrane ring (plus a wall ring for
## plants) and a pre-wired nucleus, chromosomes and mitochondria.

const HALF := Vector2i(20, 10)


static func ring(half: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-half.x, half.x + 1):
		cells.append(Vector2i(x, -half.y))
		cells.append(Vector2i(x, half.y))
	for y in range(-half.y + 1, half.y):
		cells.append(Vector2i(-half.x, y))
		cells.append(Vector2i(half.x, y))
	return cells


## Cells the player may build on: inside the outer ring (the wall ring for plants).
static func in_bounds(cell: Vector2i, cell_type: int) -> bool:
	var pad := 1 if cell_type == OrganelleDef.CellType.PLANT else 0
	return absi(cell.x) <= HALF.x + pad and absi(cell.y) <= HALF.y + pad


static func build(sim: CellSim, rng: RandomNumberGenerator) -> void:
	for c in ring(HALF):
		_place(sim, "membrane", c, rng.randf_range(90.0, 100.0))
	var plant := sim.cell_type == OrganelleDef.CellType.PLANT
	if plant:
		for c in ring(HALF + Vector2i(1, 1)):
			_place(sim, "cell_wall", c, rng.randf_range(90.0, 100.0))
	var nucleus := _place(sim, "nucleus", Vector2i(0, 0))
	var chromosomes := _place(sim, "chromosomes", Vector2i(1, 0))
	var mito := _place(sim, "mitochondria", Vector2i(-3, 0))
	var anchor := sim.organelle_at(Vector2i(0, -HALF.y))
	sim.add_link(nucleus, mito)
	sim.add_link(nucleus, anchor)
	sim.add_link(chromosomes, anchor)
	sim.add_link(mito, anchor)
	if plant:
		var chloroplast := _place(sim, "chloroplast", Vector2i(3, 0))
		sim.add_link(chloroplast, mito)
		sim.add_link(chloroplast, anchor)


static func _place(sim: CellSim, id: String, cell: Vector2i, health: float = 100.0) -> int:
	var uid := sim.add_organelle(id, cell, true)
	if uid != -1:
		(sim.organelles[uid] as PlacedOrganelle).health = health
	return uid
```

- [ ] **Step 4: Run test to verify it passes**

Run: `test_run` (suite `starter`, then all). Expected: all pass. If `test_untouched_cell_survives_thirty_seconds...` fails, the generated numbers are out of balance. Adjust the table in `tools/generate_organelle_defs.gd`, re-run the generator (Task 1, Step 5), and re-run the tests. Do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add scripts/sim/starter_layout.gd tests/test_starter.gd
git commit -m "feat: starter layout and balance smoke test"
```

---

### Task 8: CellGame, TileBase renderer and scene wiring

**Files:**
- Create: `scripts/game/cell_game.gd`
- Modify: `scripts/TileBase.gd`, `scripts/backround.gd`, `scene/cell Node2D.tscn` (via the godot-ai tools)

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces `CellGame` (root node script):
  - Signals: `run_started`, `ticked`, `run_lost(reason: String)`, `sim_unlocked(def_id: String)`, `event_fired(label: String)`.
  - State: `sim: CellSim`, `director: DamageDirector`, `tool: String` (`""`, `"link"`, `"repair"`, or an organelle id), `running: bool`, `paused: bool`, `link_drag_from: int`.
  - Methods: `start_run(is_animal: bool)`, `set_paused(p: bool)`, `cell_at_mouse() -> Vector2i`, `uid_at(cell) -> int`, `cell_center(cell) -> Vector2` (global position of the tile center), `try_place(def_id, cell) -> String`, `try_erase(cell)`, `try_repair(cell)`, `describe(uid) -> String`.
  - `TileBase` exports: `organelle_id: String`, `terrain_id: int = -1`, field `atlas_tile: Vector2i`, `show_tile(cell)`, `hide_tile(cell)`, `clear()` (built in).
  - `backround.refresh()`.

- [ ] **Step 1: Rewrite TileBase as a thin renderer**

`scripts/TileBase.gd`:

```gdscript
class_name TileBase extends TileMapLayer
## Draws the tiles of one organelle type. Game rules live in CellSim; CellGame
## tells this layer what to show.

@export var organelle_id: String = ""
@export var terrain_id: int = -1  # >= 0 uses terrain autotiling (membrane, cell wall)

var atlas_tile: Vector2i = Vector2i.ZERO


func show_tile(cell: Vector2i) -> void:
	set_cell(cell, 0, atlas_tile)
	if terrain_id >= 0:
		set_cells_terrain_connect([cell], 0, terrain_id)


func hide_tile(cell: Vector2i) -> void:
	erase_cell(cell)
	if terrain_id >= 0:
		set_cells_terrain_connect(get_used_cells(), 0, terrain_id)
```

`scripts/organelle scripts/membrane.gd` stays `extends TileBase`. The removed exports (`energy_consumption`, `water_consumption`, `waste_production`, `top_middle_tile`) now live in `OrganelleDef`. Remove their values from the scene in Step 4.

- [ ] **Step 2: Add `refresh()` to the background**

In `scripts/backround.gd` replace `_ready` with:

```gdscript
func _ready() -> void:
	refresh()
	# Connect to the window resize signal to keep it full-screen dynamically
	get_tree().root.size_changed.connect(scale_to_fullscreen)
	scale_to_fullscreen()


func refresh() -> void:
	if Globals.player_plant_or_animal:
		self.play("veins")
	else:
		self.play("plant leaf")
```

- [ ] **Step 3: Write CellGame**

`scripts/game/cell_game.gd`:

```gdscript
class_name CellGame extends Node2D
## Owns the CellSim, ticks it every second, mirrors it onto the TileMapLayers
## and exposes the player's actions. UI and input scripts talk to this node.

signal run_started
signal ticked
signal run_lost(reason: String)
signal sim_unlocked(def_id: String)
signal event_fired(label: String)

const TICK_SECONDS := 1.0

var sim: CellSim
var director: DamageDirector
var curve := DifficultyCurve.new()
var tool: String = ""
var running: bool = false
var paused: bool = false
var link_drag_from: int = -1

var _layers: Dictionary = {}  # organelle id -> TileBase
var _grid: TileBase
var _timer := Timer.new()


func _ready() -> void:
	for child in get_children():
		if child is TileBase and (child as TileBase).organelle_id != "":
			_layers[(child as TileBase).organelle_id] = child
	_grid = _layers["membrane"]
	_timer.wait_time = TICK_SECONDS
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_build_children()


func _build_children() -> void:
	var link_layer := LinkLayer.new()
	link_layer.setup(self)
	add_child(link_layer)
	var build_input := BuildInput.new()
	build_input.setup(self)
	add_child(build_input)
	for ui in [Hud.new(), BuildMenu.new(), InfoCard.new(), Encyclopedia.new(), GameOver.new(), StartScreen.new()]:
		add_child(ui)
		ui.setup(self)


func start_run(is_animal: bool) -> void:
	Globals.player_plant_or_animal = is_animal
	($backround as AnimatedSprite2D).call("refresh")
	for layer: TileBase in _layers.values():
		layer.clear()
	var cell_type := OrganelleDef.CellType.ANIMAL if is_animal else OrganelleDef.CellType.PLANT
	var defs := OrganelleCatalog.load_all()
	sim = CellSim.new(defs, cell_type)
	for d in defs:
		if _layers.has(d.id):
			(_layers[d.id] as TileBase).atlas_tile = d.atlas_tile
	sim.organelle_added.connect(_on_added)
	sim.organelle_removed.connect(_on_removed)
	sim.unlocked.connect(func(id: String) -> void: sim_unlocked.emit(id))
	sim.lost.connect(_on_lost)
	director = DamageDirector.new(sim, curve, RandomNumberGenerator.new())
	director.event_fired.connect(func(l: String) -> void: event_fired.emit(l))
	StarterLayout.build(sim, RandomNumberGenerator.new())
	tool = ""
	paused = false
	_timer.paused = false
	running = true
	_timer.start()
	run_started.emit()


func set_paused(p: bool) -> void:
	paused = p
	_timer.paused = p


func _on_tick() -> void:
	sim.decay_multiplier = curve.decay_multiplier(sim.elapsed)
	sim.tick(TICK_SECONDS)
	director.tick(TICK_SECONDS)
	ticked.emit()


func _on_lost(reason: String) -> void:
	running = false
	_timer.stop()
	run_lost.emit(reason)


func _on_added(uid: int) -> void:
	var o: PlacedOrganelle = sim.organelles[uid]
	if _layers.has(o.def.id):
		(_layers[o.def.id] as TileBase).show_tile(o.cell)


func _on_removed(_uid: int, cell: Vector2i, def_id: String) -> void:
	if _layers.has(def_id):
		(_layers[def_id] as TileBase).hide_tile(cell)


# ----- queries -----

func cell_at_mouse() -> Vector2i:
	return _grid.local_to_map(_grid.to_local(get_global_mouse_position()))


func uid_at(cell: Vector2i) -> int:
	return sim.organelle_at(cell) if sim != null else -1


func cell_center(cell: Vector2i) -> Vector2:
	return _grid.to_global(_grid.map_to_local(cell))


func describe(uid: int) -> String:
	var o: PlacedOrganelle = sim.organelles.get(uid)
	if o == null:
		return ""
	var status := "running"
	if o.disabled:
		status = "DAMAGED - repair it"
	elif o.health <= 0.0:
		status = "worn out - repair it"
	elif not o.energy_ok:
		status = "no energy link (or supplier full)"
	elif not o.water_ok:
		status = "no water link"
	elif not o.running:
		status = "waiting for its neighbour"
	if o.def.energy_output > 0.0 and sim.is_fat_paired(uid):
		status += ", burning fat via ER"
	return "%s (%s)\n%s\nhealth %d%%" % [o.def.display_name, o.def.city_name, status, int(o.health)]


# ----- player actions -----

func try_place(def_id: String, cell: Vector2i) -> String:
	if sim == null or not StarterLayout.in_bounds(cell, sim.cell_type):
		return "outside_cell"
	sim.add_organelle(def_id, cell)
	return sim.can_place(def_id, cell) if sim.organelle_at(cell) == -1 else ""


func try_erase(cell: Vector2i) -> void:
	var uid := uid_at(cell)
	if uid == -1:
		return
	if tool == "link":
		sim.remove_links_of(uid)
	else:
		sim.remove_organelle(uid)


func try_repair(cell: Vector2i) -> void:
	var uid := uid_at(cell)
	if uid != -1:
		sim.repair(uid)
```

`try_place` note: the final line returns the refusal reason (empty string when the placement succeeded).

- [ ] **Step 4: Wire the scene with the godot-ai tools**

Open `scene/cell Node2D.tscn` (`scene_open`). Then, with `script_attach` and `node_set_property` (batch with `batch_execute`):

| Node | Action |
|---|---|
| `cell Node2D` (root) | attach `res://scripts/game/cell_game.gd` |
| `membrane` | keep `membrane.gd`; set `organelle_id = "membrane"`, `terrain_id = 0`; clear `top_middle_tile` if the property still shows |
| `nucleus` | attach `res://scripts/TileBase.gd`; `organelle_id = "nucleus"` |
| `vacuole` | attach `TileBase.gd`; `organelle_id = "vacuole"` |
| `cytoplasm` | attach `TileBase.gd`; `organelle_id = "cytoplasm"` |
| `mitochondria` | attach `TileBase.gd`; `organelle_id = "mitochondria"` |
| `cell wall` | attach `TileBase.gd`; `organelle_id = "cell_wall"`, `terrain_id = 1` |
| `chromosomes` | attach `TileBase.gd`; `organelle_id = "chromosomes"` |
| `chloroplast` | attach `TileBase.gd`; `organelle_id = "chloroplast"` |
| `endoplasmic reculum` | attach `TileBase.gd`; `organelle_id = "endoplasmic_reticulum"` |
| `lysosomes` | attach `TileBase.gd`; `organelle_id = "lysosome"` |
| `Camera2D` | `zoom = Vector2(1.5, 1.5)` |

Leave `golgoi apparatus` and `vesicles` untouched (v2). Save with `scene_save`.

- [ ] **Step 5: Verify the atlas tiles against the art**

The `atlas_tile` values in `tools/generate_organelle_defs.gd` for single-tile organelles are a first guess: atlas column 0, rows 0–7, in the order nucleus 0, vacuole 1, cytoplasm 2, mitochondria 3, chromosomes 4, chloroplast 5, ER 6, lysosome 7. Open the TileSet atlas (select the `nucleus` layer → TileSet panel) or use `editor_screenshot`, and confirm each tile shows the right organelle. For any mismatch, fix the `atlas_tile` in the generator table, re-run the generator (Task 1, Step 5) and re-run `test_run`. The membrane `(2,0)` and cell wall `(2,3)` tiles are the top-middle terrain tiles of the orange and green frames.

- [ ] **Step 6: Verify the sim mirrors onto the layers**

Run the project (`project_run`), then read the logs (`logs_read`) for script errors. Since the UI does not exist yet, use `game_manage`/the debugger or a temporary one-line call (`$"/root/cell Node2D".start_run(true)` from the remote inspector) to start a run.
Expected: no errors, a rectangular membrane ring appears, plus the nucleus, chromosomes and mitochondria in the middle. Remove any temporary code afterward.

- [ ] **Step 7: Commit**

```bash
git add scripts/game/cell_game.gd scripts/TileBase.gd scripts/backround.gd "scene/cell Node2D.tscn" tools/generate_organelle_defs.gd data/organelles
git commit -m "feat: CellGame mirrors the sim onto the tilemap layers"
```

(`LinkLayer`, `BuildInput` and the UI classes referenced by `_build_children` are created in Tasks 9 and 10. Until then comment out those lines in `_build_children` for Step 6, and restore them in Task 10.)

---

### Task 9: Mouse input, link drawing and damage markers

**Files:**
- Create: `scripts/game/build_input.gd`, `scripts/game/link_layer.gd`

**Interfaces:**
- Consumes: `CellGame` API from Task 8, `CellSim.add_link`, `SimLink`, `PlacedOrganelle`.
- Produces: `BuildInput.setup(game)`, `LinkLayer.setup(game)`.

- [ ] **Step 1: Write BuildInput**

`scripts/game/build_input.gd`:

```gdscript
class_name BuildInput extends Node
## Mouse handling. `click` places/repairs (hold to paint), `erase` removes,
## and in link mode left-drag from one organelle to another draws a link.

var _game: CellGame
var _drag_uid: int = -1


func setup(game: CellGame) -> void:
	_game = game


func _blocked() -> bool:
	return not _game.running or _game.paused or _game.get_viewport().gui_get_hovered_control() != null


func _process(_delta: float) -> void:
	if _blocked():
		return
	var cell := _game.cell_at_mouse()
	if Input.is_action_pressed("click"):
		if _game.tool == "repair":
			_game.try_repair(cell)
		elif _game.tool != "" and _game.tool != "link":
			_game.try_place(_game.tool, cell)
	if Input.is_action_pressed("erase"):
		_game.try_erase(cell)


func _unhandled_input(event: InputEvent) -> void:
	if not _game.running or _game.paused or _game.tool != "link":
		return
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if (event as InputEventMouseButton).pressed:
		_drag_uid = _game.uid_at(_game.cell_at_mouse())
		_game.link_drag_from = _drag_uid
	else:
		if _drag_uid != -1:
			var target := _game.uid_at(_game.cell_at_mouse())
			if target != -1:
				_game.sim.add_link(_drag_uid, target)
		_drag_uid = -1
		_game.link_drag_from = -1
```

- [ ] **Step 2: Write LinkLayer**

`scripts/game/link_layer.gd`:

```gdscript
class_name LinkLayer extends Node2D
## Draws connection dots, links with animated flow dots, the link being
## dragged, and markers on damaged or worn organelles.

const COLORS := {
	SimLink.Type.ENERGY: Color("f2d64b"),
	SimLink.Type.WATER: Color("4aa3e0"),
	SimLink.Type.FAT: Color("d9c7a0"),
}
const FLOW_SPEED := 0.6

var _game: CellGame


func setup(game: CellGame) -> void:
	_game = game
	z_index = 10


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _game == null or _game.sim == null:
		return
	var sim := _game.sim
	var phase := Time.get_ticks_msec() / 1000.0 * FLOW_SPEED
	for i in sim.links.size():
		var l := sim.links[i]
		var consumer: PlacedOrganelle = sim.organelles.get(l.from_uid)
		var supplier: PlacedOrganelle = sim.organelles.get(l.to_uid)
		if consumer == null or supplier == null:
			continue
		var a := _game.cell_center(consumer.cell)
		var b := _game.cell_center(supplier.cell)
		var color: Color = COLORS[l.type]
		var live := supplier.alive()
		draw_line(a, b, color if live else color.darkened(0.6), 1.0)
		if live:
			var t := fmod(phase + i * 0.13, 1.0)
			draw_circle(b.lerp(a, t), 1.5, color)
	for o: PlacedOrganelle in sim.organelles.values():
		if o.def.needs_energy_link or o.def.needs_water_link or o.def.energy_output > 0.0:
			draw_circle(_game.cell_center(o.cell), 2.0, Color.WHITE)
		if o.disabled or o.health <= 0.0:
			draw_arc(_game.cell_center(o.cell), 6.0, 0.0, TAU, 16, Color("e03c3c"), 1.5)
		elif o.health < 50.0:
			draw_arc(_game.cell_center(o.cell), 6.0, 0.0, TAU, 16, Color("e0a43c"), 1.0)
	if _game.link_drag_from != -1 and sim.organelles.has(_game.link_drag_from):
		var start := _game.cell_center((sim.organelles[_game.link_drag_from] as PlacedOrganelle).cell)
		draw_line(start, get_global_mouse_position(), Color.WHITE, 1.0)
```

- [ ] **Step 3: Verify by running**

Run the project, start a run (temporary call as in Task 8 Step 6), and watch the viewport (`editor_screenshot` or the game window).
Expected:
- Colored lines connect the nucleus, chromosomes and mitochondria (and chloroplast for plants) to the mitochondria and to the top membrane tile. Small dots travel along them.
- White dots mark connectable organelles.
- No errors in `logs_read`.

- [ ] **Step 4: Commit**

```bash
git add scripts/game/build_input.gd scripts/game/link_layer.gd
git commit -m "feat: mouse input, link drawing and damage markers"
```

---

### Task 10: UI — start screen, HUD, build menu, info card, encyclopedia, game over

**Files:**
- Create: `scripts/ui/hud.gd`, `build_menu.gd`, `info_card.gd`, `encyclopedia.gd`, `start_screen.gd`, `game_over.gd`
- Modify: `scripts/game/cell_game.gd` (restore `_build_children` if commented out in Task 8)

**Interfaces:**
- Consumes: `CellGame` signals and state; `CellSim.meters`, `capacities()`, `unlock_progress`, `unlocked_ids`, `defs`; `DamageDirector.timers`.
- Produces: six `CanvasLayer` classes, each with `setup(game: CellGame)`.

- [ ] **Step 1: Start screen and game over**

`scripts/ui/start_screen.gd`:

```gdscript
class_name StartScreen extends CanvasLayer
## Pick animal or plant to begin a run.


func setup(game: CellGame) -> void:
	layer = 20
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Cell is a City\nKeep your cell alive for as long as you can."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for entry in [["Animal cell", true], ["Plant cell", false]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(func() -> void:
			visible = false
			game.start_run(entry[1]))
		box.add_child(b)
```

`scripts/ui/game_over.gd`:

```gdscript
class_name GameOver extends CanvasLayer
## Shown when a run is lost. Restart reloads the scene.

const REASONS := {
	"nucleus": "Your cell lost its nucleus.",
	"repair_timeout": "A repair ran out of time.",
}


func setup(game: CellGame) -> void:
	layer = 20
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(restart)
	game.run_lost.connect(func(reason: String) -> void:
		var seconds := int(game.sim.elapsed)
		label.text = "%s\nYou survived %d:%02d." % [REASONS.get(reason, reason), seconds / 60, seconds % 60]
		visible = true)
```

- [ ] **Step 2: HUD**

`scripts/ui/hud.gd`:

```gdscript
class_name Hud extends CanvasLayer
## Meters, survival timer, active repair timers, hover tooltip.

const METER_COLORS := {
	"food": Color("e8a33d"), "energy": Color("f2d64b"), "water": Color("4aa3e0"),
	"waste": Color("8a6d3b"), "fat": Color("d9c7a0"),
}

var _game: CellGame
var _bars: Dictionary = {}
var _time := Label.new()
var _alerts := Label.new()
var _tip := Label.new()


func setup(game: CellGame) -> void:
	_game = game
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_time)
	for m in CellSim.METERS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = m.capitalize()
		name_label.custom_minimum_size.x = 60
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 16)
		bar.show_percentage = false
		bar.modulate = METER_COLORS[m]
		row.add_child(name_label)
		row.add_child(bar)
		box.add_child(row)
		_bars[m] = bar
	box.add_child(_alerts)
	var book := Button.new()
	book.text = "Encyclopedia"
	book.pressed.connect(func() -> void: get_tree().call_group("encyclopedia", "toggle"))
	box.add_child(book)
	_tip.add_theme_color_override("font_color", Color.WHITE)
	_tip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tip.add_theme_constant_override("outline_size", 4)
	add_child(_tip)
	game.ticked.connect(_refresh)
	game.run_started.connect(_refresh)


func _refresh() -> void:
	var sim := _game.sim
	var caps := sim.capacities()
	for m in CellSim.METERS:
		var bar: ProgressBar = _bars[m]
		bar.max_value = caps[m]
		bar.value = sim.meters[m]
	var seconds := int(sim.elapsed)
	_time.text = "Survived %d:%02d" % [seconds / 60, seconds % 60]
	var lines: Array[String] = []
	for t in _game.director.timers:
		lines.append("%s: %ds left" % [t["label"], ceili(t["remaining"])])
	_alerts.text = "\n".join(lines)


func _process(_delta: float) -> void:
	if _game.sim == null or not _game.running:
		_tip.text = ""
		return
	var uid := _game.uid_at(_game.cell_at_mouse())
	_tip.text = _game.describe(uid) if uid != -1 else ""
	_tip.position = get_viewport().get_mouse_position() + Vector2(14, 14)
```

- [ ] **Step 3: Build menu**

`scripts/ui/build_menu.gd`:

```gdscript
class_name BuildMenu extends CanvasLayer
## Tool bar: Link, Repair, then one button per organelle. Locked organelles are
## disabled and show progress toward their thresholds.

var _game: CellGame
var _row := HBoxContainer.new()
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}  # tool id -> Button


func setup(game: CellGame) -> void:
	_game = game
	_group.allow_unpress = true
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(panel)
	panel.add_child(_row)
	game.run_started.connect(_rebuild)
	game.ticked.connect(_refresh)


func _rebuild() -> void:
	for c in _row.get_children():
		c.queue_free()
	_buttons.clear()
	_add_button("link", "Link", "Drag from an organelle to its supplier: a mitochondria for energy, a membrane or cell wall for water. Beside an ER, link a mitochondria to the ER to let it burn fat. Right-click an organelle in this mode to cut its links.")
	_add_button("repair", "Repair", "Click or drag over damaged or worn tiles to repair them. Costs a little energy.")
	var defs: Array = _game.sim.defs.values()
	defs.sort_custom(func(a: OrganelleDef, b: OrganelleDef) -> bool: return a.display_name < b.display_name)
	for d: OrganelleDef in defs:
		if d.allowed_cell_types.has(_game.sim.cell_type):
			_add_button(d.id, d.display_name, "%s\n\nIn a city: %s (%s)" % [d.function_text, d.city_name, d.city_text])
	_refresh()


func _add_button(id: String, text: String, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = tip
	b.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_game.tool = id
		elif _game.tool == id:
			_game.tool = "")
	_row.add_child(b)
	_buttons[id] = b


func _refresh() -> void:
	var sim := _game.sim
	for id in _buttons:
		if not sim.defs.has(id):
			continue
		var b: Button = _buttons[id]
		var d: OrganelleDef = sim.defs[id]
		var locked := not sim.unlocked_ids.has(id)
		b.disabled = locked
		if locked:
			var parts: Array[String] = []
			var progress := sim.unlock_progress(id)
			for meter in progress:
				parts.append("%s %d/%d" % [meter, progress[meter][0], progress[meter][1]])
			b.text = "%s (%s)" % [d.display_name, ", ".join(parts)]
		else:
			b.text = d.display_name
```

- [ ] **Step 4: Unlock card and encyclopedia**

`scripts/ui/info_card.gd`:

```gdscript
class_name InfoCard extends CanvasLayer
## Pops up when an organelle unlocks and pauses the sim until dismissed.

var _game: CellGame
var _queue: Array[String] = []
var _title := Label.new()
var _body := RichTextLabel.new()


func setup(game: CellGame) -> void:
	_game = game
	layer = 15
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_body.bbcode_enabled = true
	_body.fit_content = true
	box.add_child(_body)
	var ok := Button.new()
	ok.text = "Got it"
	ok.pressed.connect(_next)
	box.add_child(ok)
	game.sim_unlocked.connect(_on_unlocked)
	game.run_started.connect(func() -> void:
		_queue.clear()
		visible = false)


func _on_unlocked(def_id: String) -> void:
	_queue.append(def_id)
	if not visible:
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		_game.set_paused(false)
		return
	var d: OrganelleDef = _game.sim.defs[_queue.pop_front()]
	_title.text = "Unlocked: %s" % d.display_name
	_body.text = "[b]In your cell:[/b] %s\n\n[b]In a city, it's the %s:[/b] %s" % [d.function_text, d.city_name.to_lower(), d.city_text]
	visible = true
	_game.set_paused(true)
```

`scripts/ui/encyclopedia.gd`:

```gdscript
class_name Encyclopedia extends CanvasLayer
## Lists unlocked organelles with their city analogies; locked ones show only
## their unlock requirement. Toggled from the HUD button.

var _game: CellGame
var _list := VBoxContainer.new()


func setup(game: CellGame) -> void:
	_game = game
	layer = 12
	visible = false
	add_to_group("encyclopedia")
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 380)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 330)
	scroll.add_child(_list)
	box.add_child(scroll)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(toggle)
	box.add_child(close)


func toggle() -> void:
	if _game.sim == null:
		return
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var sim := _game.sim
	var defs: Array = sim.defs.values()
	defs.sort_custom(func(a: OrganelleDef, b: OrganelleDef) -> bool: return a.display_name < b.display_name)
	for d: OrganelleDef in defs:
		if not d.allowed_cell_types.has(sim.cell_type):
			continue
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		if sim.unlocked_ids.has(d.id):
			label.text = "[b]%s[/b] = %s\n%s\n[i]%s[/i]\n" % [d.display_name, d.city_name, d.function_text, d.city_text]
		else:
			var parts: Array[String] = []
			var progress := sim.unlock_progress(d.id)
			for meter in progress:
				parts.append("%s %d" % [meter, progress[meter][1]])
			label.text = "[b]???[/b] Reach %s to unlock.\n" % " and ".join(parts)
		_list.add_child(label)
```

- [ ] **Step 5: Restore `_build_children` and verify end to end**

Make sure `CellGame._build_children` (Task 8) creates `LinkLayer`, `BuildInput` and the six UI classes (uncomment anything disabled earlier). Then run the project (`project_run`) and check `logs_read` for errors. Manual playthrough, animal cell:

1. The start screen shows. Pick **Animal cell**: ring, nucleus, chromosomes and mitochondria appear, meters fill, the timer counts.
2. The Vacuole button is enabled (water already ≥ 80 after a few seconds) and the info card pops up and pauses the game until **Got it**.
3. Select **Vacuole**, click inside the ring: a tile appears. Hovering shows its status "no energy link". Select **Link**, drag from the vacuole to the mitochondria, then to a membrane tile. The tooltip now says "running". Waste stops rising.
4. Wait for a damage event (~45 s). A red ring appears on a tile (or a link vanishes) and a repair countdown shows. Use **Repair** (or Link) to fix it before the countdown ends.
5. Letting a countdown hit 0, or removing the nucleus with right-click, shows the game-over screen with the survival time. **Play again** reloads.
6. Reload, pick **Plant cell**: cell wall ring and chloroplast are present, food rises, and Chloroplast / Cell wall appear in the menu (not in the animal menu).
7. Open **Encyclopedia**: unlocked entries show text, locked ones show `???` and their requirement.

Expected: every step behaves as described and the log contains no script errors. Fix any failure before committing.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui scripts/game/cell_game.gd
git commit -m "feat: start screen, HUD, build menu, unlock cards, encyclopedia, game over"
```

---

### Task 11: Documentation and final verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Replace the **Architecture** section's `TileBase` bullet and add the sim bullets so they read:

```markdown
- **Simulation** (`scripts/sim/`): `CellSim` is scene-free game logic (meters, placement, links, tick, unlocks, decay, repair, lose). `OrganelleDef` resources in `data/organelles/*.tres` hold all per-organelle numbers and teaching text; they are generated from the table in `tools/generate_organelle_defs.gd` (`godot --headless --path . --script res://tools/generate_organelle_defs.gd`), so tune values there and re-run it. `DamageDirector` + `DifficultyCurve` drive bacteria/cut events and the shrinking repair window. `StarterLayout` builds the pre-wired starting cell.
- **Game layer** (`scripts/game/`, `scripts/ui/`): `CellGame` (root node script) owns the sim, ticks it every second, mirrors it onto the `TileMapLayer`s, and exposes player actions. `BuildInput` handles the mouse, `LinkLayer` draws links, and the UI scripts build their controls in code.
- **`TileBase`** ([scripts/TileBase.gd](scripts/TileBase.gd)): thin renderer for one organelle layer (`organelle_id`, `terrain_id`). It has no input handling or rules.
- **Tests**: `res://tests/test_*.gd` extend `McpTestSuite` (godot-ai addon). Run them with the `test_run` MCP tool with the editor open.
```

Also change the Project paragraph's "no build, lint, or test tooling" sentence to: "There is no build or lint tooling; unit tests for the simulation live in `tests/` and run through the godot-ai `test_run` tool."

- [ ] **Step 2: Full verification**

Run `test_run` for all suites. Expected: all suites pass (`catalog`, `sim_core`, `sim_economy`, `sim_fat`, `sim_survival`, `director`, `starter`). Then repeat the manual playthrough from Task 10 Step 5 once for each cell type, including the ER/fat check:

1. Unlock the ER (food ≥ 80, reached within a few seconds in an animal cell), place an ER directly beside the mitochondria, link mitochondria → ER, then hover the mitochondria: the tooltip should say "burning fat via ER" once food runs low.
2. Place the ER one tile away from the mitochondria and link them: the tooltip never shows the fat line.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: describe the simulation architecture in CLAUDE.md"
```

---

## Self-Review

**Spec coverage**
- Endless survival, score = time: Tasks 5, 6, 10 (HUD timer, game over).
- Threshold unlocks, never spent: Task 2 (`thresholds_met`, `unlock_progress`), Task 5 (unlock on tick), Task 10 (menu progress, info card).
- Food → energy chain, fat reserve, ER pairing rule: Tasks 3, 4.
- Drawn links, binary, capacity, visible flow: Tasks 2, 3, 9.
- Damage events, repair-only, repair window shrinking 60 → 20 s, decay: Tasks 5, 6.
- Both cell types, v1 organelle list incl. ER (fat access only): Tasks 1, 7, 8, 10.
- Teaching layer (unlock card, tooltips, encyclopedia, HUD): Task 10.
- Testing via `test_run`: Tasks 1–7.
- Gaps (documented in Scope Notes, not silently dropped): animal vacuole movement, autophagosome entity, cytoplasm bar, rotate (R), upgrade content.

**Placeholder scan:** no TBD/TODO; the only values left to confirm in the editor are the atlas tiles (Task 8, Step 5), which has an explicit procedure and a default.

**Type consistency:** `SimLink.Type`, `PlacedOrganelle` fields, `CellSim` method names, `OrganelleDef` field names and `CellGame` members match across tasks (`remove_links_of`, `is_fat_paired`, `unlock_progress`, `cell_center`, `link_drag_from`). `organelle_removed` carries `(uid, cell, def_id)` from Task 2 onward and is consumed that way in Task 8.
