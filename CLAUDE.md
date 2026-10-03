# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"cellular city" is a Godot 4.7 (GL Compatibility renderer) 2D city-builder-style game where the player places organelle tiles inside a cell. It is early-stage: the art is drawn and the gameplay code is just starting. There is no build or lint tooling; open the project in the Godot editor (or run `godot --path .`) and press play. Simulation unit tests live in `tests/` (see Tests below). The main scene is `scene/cell Node2D.tscn`.

## Architecture

- **`Globals` autoload** ([scripts/globals.gd](scripts/globals.gd)): global state. `player_plant_or_animal` (true = animal, false = plant) selects the cell type; the background animation (`veins` vs `plant leaf`) depends on it.
- **Main scene** (`scene/cell Node2D.tscn`): a `Node2D` with a `Camera2D`, a full-screen `AnimatedSprite2D` background ([scripts/backround.gd](scripts/backround.gd), rescales itself to the viewport on resize), and one `TileMapLayer` per organelle (membrane, nucleus, vacuole, cytoplasm, mitochondria, cell wall, chromosomes, chloroplast, endoplasmic reticulum, lysosomes, golgi, vesicles). All layers draw from the single atlas `assets/organelle tilemap.png`.
- **Simulation** (`scripts/sim/`): `CellSim` is scene-free game logic (meters food/energy/water/waste/fat, placement, links, tick, threshold unlocks, decay, repair, lose). `OrganelleDef` resources in `data/organelles/*.tres` hold all per-organelle numbers, atlas tile and teaching text. They are generated from the table in `tools/generate_organelle_defs.gd` (`godot --headless --path . --script res://tools/generate_organelle_defs.gd`), so tune values there and re-run it. `DamageDirector` + `DifficultyCurve` drive bacteria/cut events and the shrinking repair window. `StarterLayout` builds the pre-wired starting cell.
- **Game layer** (`scripts/game/`, `scripts/ui/`): `CellGame` (root node script) owns the sim, ticks it every second, mirrors it onto the `TileMapLayer`s and exposes player actions. `BuildInput` handles the mouse, `LinkLayer` draws links, and the UI scripts build their controls in code. `BuildMenu` binds the scene's own palette (`organell buttons and stuff`) to the sim, so edit those buttons in the scene, not in code.
- **`TileBase`** ([scripts/TileBase.gd](scripts/TileBase.gd)): thin renderer for one organelle layer (`organelle_id`, `terrain_id`; `terrain_id` 0 = membrane, 1 = cell wall). No input handling or rules. Each organelle layer needs the script attached and `organelle_id` set in the scene.
- **Which layer draws which tile**: two links. (1) Layer → organelle: each organelle `TileMapLayer` node has an `organelle_id` in the Inspector (set in the scene) that must match an `OrganelleDef.id` (`membrane`, `nucleus`, `vacuole`, `cytoplasm`, `mitochondria`, `cell_wall`, `chromosomes`, `chloroplast`, `endoplasmic_reticulum`, `lysosome`); `CellGame` finds layers by that id. (2) Organelle → atlas tile: the `atlas_tile` field (column, row in `assets/organelle tilemap.png`) of `data/organelles/<id>.tres`, which you can edit in the Inspector. Layers with `terrain_id >= 0` (membrane 0, cell wall 1) use terrain autotiling instead and `atlas_tile` is only the first tile placed. `tools/generate_organelle_defs.gd` rewrites every `.tres`, so after editing tiles in the Inspector either copy the change into that table or stop re-running the generator.
- **UI theme**: all UI built in code uses `MetalUi.theme()` ([scripts/ui/metal_ui.gd](scripts/ui/metal_ui.gd)), the scene's `custom metal plate theme.tres` extended for PanelContainer, labels and progress bars. Edit the theme file to restyle everything.
- **Panels toggle**: the `open_buildings` input action (Tab, defined in `project.godot`) shows/hides the buildings palette and the stats tab together (`Hud._input`). While any repair is pending the stats tab pops up even if hidden, and hides again once everything is fixed.
- **Cell size and pacing**: cell size is `StarterLayout.HALF` (membrane ring half-width/height in tiles; cell is 2*HALF+1 tiles across). Attack frequency, size and repair window are in `DifficultyCurve` (`first_event_delay`, `interval_*`, `size_*`, `repair_*`). If you change `HALF`, re-check balance with `tests/test_starter.gd`, since membrane tile count drives water and food income.
- **Unlock difficulty**: `unlock_thresholds` per organelle in `tools/generate_organelle_defs.gd` (meters needed, never spent). Raise numbers or add a second meter to make an organelle harder to get.
- **Other scenes (v2, not yet scripted)**: `scene/membrane truck.tscn` (delivers food to the cytoplasm delivery truck and water wherever it is needed) and `scene/vesicle train.tscn` (follows the `vesicles` layer tiles to its destination, or heads straight while the layer places track tiles under it). The `vesicles` and `golgoi apparatus` layers are teaching visuals for protein transport; the player cannot place them.
- **Input actions** (defined in `project.godot`): `click` (left mouse), `erase` (right mouse), `rotate` (R). `erase` and `rotate` are not yet handled in code.

## Notes

- `addons/godot_ai` is the Godot AI MCP plugin (editor-side bridge for MCP clients) and registers the `_mcp_game_helper` autoload; it is not game code.
- When the Godot editor is open with the plugin enabled, Claude Code can drive it through the `godot-ai` MCP tools (scene/node/tilemap edits, `project_run`, `test_run`, `logs_read`) instead of hand-editing `.tscn` files.
- `.godot/` is committed to git, so editor cache files show up as modified in `git status`; avoid including them in unrelated changes.
- File and node names contain spaces and some typos (`backround`, `endoplasmic reculum`, `golgoi apparatus`); use the exact existing names when referencing them in code or scene paths.

## Tests

- Unit tests: `res://tests/test_*.gd` extend `McpTestSuite`. Run headless with `godot --headless --path . --import` then `godot --headless --path . --script res://tools/run_tests.gd [-- suite_name]` (on macOS the binary is `/Applications/Godot.app/Contents/MacOS/Godot`). The godot-ai `test_run` tool works too but caches stale classes, so run `--import` or `filesystem_manage scan` after adding `class_name` scripts.
- Full-scene smoke test: `godot --headless --path . --script res://tools/smoke_game.gd` (prints `SMOKE OK`).
- Visual check: `godot --path . --script res://tools/screenshot.gd -- animal|plant out.png` (needs a window). The live game window freezes when unfocused, so use this for screenshots.
- In `--script` runs, avoid static references to `CellGame`/UI classes (they form a compile cycle with the `Globals` autoload); the tools use dynamic typing.
