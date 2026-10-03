# Cellular City: Game Design (v1)

Source material: `documents/Alex Tam - Cell is a City.ods` (rough mechanics and per-organelle stats), plus the design conversation of 2026-10-03.

## 1. Purpose and success criteria

A 2D tile-based game that teaches what each organelle does and how they work together, by comparing a cell to city infrastructure (nucleus = municipal government, lysosome = waste processing facility, and so on). The player manages the food, energy, water and waste of a small organism.

Success for v1:
- A player can start a run as either an animal or a plant cell and survive for a measurable time.
- Each organelle the player unlocks is introduced with its real function and its city analogy.
- The player's own resource stats guide them to the next organelle they need.

## 2. Decisions

| Topic | Decision |
|---|---|
| Objective | Endless survival. Score is time survived. Difficulty ramps with time. |
| Unlocks | Each organelle and upgrade has minimum stored food/water/waste thresholds. The thresholds are a gate and are not spent. |
| Resources | Food → energy chain. Meters: food, energy, water, waste, plus a fat reserve. A mitochondria can draw on fat when food is short only if it is placed directly beside an endoplasmic reticulum and linked to it. |
| Connections | Player-drawn links from organelle dots to suppliers. Links are binary (connected or not), with animated dots showing flow. Suppliers have a capacity. |
| Threats | Damage events (bacteria, cuts) destroy or disable tiles and links, and the player repairs them before a timer ends. Background decay applies to some tiles. No combat. |
| v1 scope | Both cell types, core loop. The ER is included in v1 as the fat-access organelle. The Golgi, vesicle and protein transport chain is deferred to v2. |
| Architecture | Data-driven `Resource` definitions per organelle plus a central `CellSim` that ticks the economy. |

## 3. Data model

### `OrganelleDef` (Resource, one `.tres` per organelle)
- `id`, display name, city analogy name, real function text, city analogy text.
- Per-second `energy_use`, `water_use`, `waste_production`. These start from the sheet values and are tunable in a 1–15 base range.
- Producer values: energy output and food input (mitochondria), food output (chloroplast), water collection (membrane), waste handling (vacuole, lysosome).
- `unlock_thresholds`: dictionary such as `{food: 40, water: 60}`.
- `allowed_cell_types`: animal, plant, or both.
- Size limits per cell type (vacuole: 2×2 animal, 5×5 plant).
- Placement energy cost (for example cell wall 5).
- Mitochondria also define a max load (the supplier capacity).
- ER defines `fat_access` (a mitochondria paired with it may drain fat) and `max_paired_mitochondria` = 1.

### `CellSim` (single node, 1 s tick, no scene dependency in its core logic)
State: `food`, `energy`, `water`, `waste`, `fat`, each with a cap.

Per tick:
1. Determine which organelles are connected to a valid supplier. Unconnected organelles do not run.
2. Apply supplier capacity. Links over a mitochondria's max load are starved.
3. Sum production and consumption per meter and clamp between 0 and the cap.
4. Mitochondria convert food to energy. When food is short, a mitochondria draws on `fat` only if it is adjacent to an ER and linked to it. Each ER supports at most one mitochondria. A mitochondria without that pairing starves instead.
5. Handle waste removal (vacuoles, lysosomes, autophagosomes, plant cytoplasm movement).
6. Check unlock gates. When all thresholds are met, move the entry from locked to available and emit an `unlocked` signal.
7. Check lose conditions.

Lose conditions: the nucleus is destroyed (the sheet gives 3 seconds to recover), or any repair timer reaches zero.

### `DifficultyCurve` (Resource)
One place for every value that scales with survival time: damage event frequency, damage event size, repair window, decay rate.

## 4. Links and placement

### Links
- Each placed organelle exposes connection dots: input for energy and water, and an output where applicable.
- Dragging from a dot to a supplier creates a `Link {from, to, type}`.
- A `LinkLayer` draws links with `Line2D` and animates dots along them, with flow speed following the actual flow.
- Erase (right mouse) removes a link or tile. Damage events can break links.
- Water comes from membrane tiles. A tile above 90% health collects full water, below that it collects 1/16 of the normal amount.

### Placement
- Builds on the existing `TileBase` (click places a tile if the cell is empty, then `set_cells_terrain_connect`).
- The build menu shows locked organelles greyed out with a progress bar toward their thresholds.
- Placement is blocked on occupied cells or disallowed cell types. Placing an organelle costs energy where the sheet says so.
- Rotate (R) is reserved for multi-tile shapes.

### Plant vs animal (`Globals.player_plant_or_animal`)

| | Animal | Plant |
|---|---|---|
| Food source | Absorbed through the membrane | Made by chloroplasts |
| Outer layer | Membrane | Membrane and cell wall |
| Vacuole | Max 2×2, can move in a circle | Max 5×5, fixed |
| Waste removal | Autophagosomes to lysosome, vacuoles | Cytoplasm movement, plus the same |
| Background | `veins` | `plant leaf` |

## 5. Threats

- Damage events (bacteria waves, cuts) disable or destroy specific tiles and links and start a repair timer for each one.
- Event frequency and size increase with survival time.
- The repair window starts at 60 s and shrinks with survival time to a floor (initially 20 s, tunable in `DifficultyCurve`).
- Background decay: membrane tiles, cell wall and chromosomes lose health over time and must be replaced or repaired (chromosomes cost 3 energy to repair, cell wall 5 energy to regrow).

## 6. Teaching layer

- **Unlock card:** a short pause with the organelle, its city analogy and why the cell needs it, generated from `OrganelleDef`.
- **Hover tooltips:** real role, city counterpart, current inputs and outputs, and starvation state.
- **Encyclopedia:** a screen listing unlocked organelles next to their city analogies. Locked entries show only their unlock requirement.
- **Teach by problem:** thresholds are tuned so each unlock answers a problem the player is already feeling (waste piling up leads to lysosomes, low water leads to vacuoles).
- **HUD:** meters for food, energy, water and waste, the fat bar, the survival timer, and a list of active repair timers.

## 7. v1 scope

In:
- Animal and plant cell types.
- Organelles: membrane, nucleus, cytoplasm, mitochondria, vacuole, lysosome (with autophagosomes), cell wall and chloroplast (plant), chromosomes, endoplasmic reticulum (fat access only, no protein output).
- Meters, threshold unlocks, drawn links, decay, damage events, info cards, encyclopedia, HUD.

Out (v2):
- ER protein and lipid production, Golgi apparatus, vesicles and the protein transport lines.
- Organelle and cell-size upgrades beyond the shared threshold mechanism (the mechanism is built in v1, the upgrade content comes later).
- Save files.

## 8. Error handling and edge cases

- Meters never drop below 0 or exceed their caps.
- Destroying an organelle removes its links.
- A cell type can't place organelles it doesn't allow.
- No persistence in v1. A run is one session.

## 9. Testing

- `CellSim` core logic has no scene dependency and is covered by unit tests through the Godot `test_run` tooling: tick math, unlock gates, supplier capacity, fat fallback, and repair-window scaling.
- Placement, link drawing and the UI are verified by running the game.

## 10. Open questions and sheet issues to resolve in balancing

- The sheet's totals row (115 energy, 143 water, 58 waste) does not obviously match the per-organelle rows. Balancing should recompute it from the final `.tres` values.
- The sheet's note on the base amount is cut off mid-sentence. The 1–15 range is assumed to be the tuning range for per-organelle costs.
- Unlock threshold values are not defined yet and will be set during balancing.
- The repair window is assumed to shrink with survival time (confirmed direction pending review of this spec).
- How the fat reserve refills (for example from surplus food) is not defined. The default is that surplus food above the food cap converts to fat at a tunable rate.
- The ER is v1-only as a fat-access organelle. Its sheet behaviour of sending proteins to a Golgi arrives in v2.
