# Setup guide HUD and membrane intro reveal

Date: 2026-10-03

## Goal

Teach a new player how to set up the most basic working cell, and make the
start of a run feel built rather than magically appearing.

1. At run start, the membrane (and, for plants, the cell wall) tiles pop in one
   at a time around the ring.
2. A checklist HUD then guides the player through placing and linking the
   core organelles themselves.
3. The game clock does not run until the core setup is done.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Who places the core | The player places nucleus, chromosomes and mitochondria (and the chloroplast for plants). `StarterLayout` no longer pre-places them. |
| Guide style | Checklist panel with a highlighted current step and one-line hint. |
| Ring pop-in | Tiles appear one at a time travelling around the ring (membrane first, then wall), each with a small scale/fade pop. |
| During the intro | Ticking, damage and building wait until the reveal finishes. |
| Core cost | Core pieces are unlocked while the guide is active. They already cost 0 energy (`placement_energy_cost` is 0 for nucleus, chromosomes, mitochondria, chloroplast), so no cost rule changes. |
| Clock | Frozen until the core steps are done (no tick, no attacks, no nucleus-loss countdown). |
| After setup | The checklist collapses to a small "Basics done" chip. |

## Checklist steps

The steps match the wiring the old starter cell used, because that is the
minimum wiring that keeps the nucleus running (a nucleus that does not run
for 3 seconds loses the run).

1. **Nucleus and chromosomes:** place a nucleus with a chromosomes tile
   touching it.
2. **Mitochondria:** place mitochondria and link it to a membrane tile
   (water link).
3. **Wire the core:** the nucleus has an energy link to a mitochondria and a
   water link to a membrane tile, and the chromosomes has a water link to a
   membrane tile.
4. **Plants only, chloroplast:** place a chloroplast with an energy link to a
   mitochondria and a water link to a membrane or wall tile.

Links go through the existing Link tool (drag from the consumer to its
supplier); `CellSim.infer_link_type` decides the link type. The guide only
observes the sim, it adds no input handling.

A "water source" is any organelle with `water_output > 0` (membrane or cell
wall). An "energy source" is any organelle with `max_load > 0` (mitochondria).

## Components

### `StarterLayout` (`scripts/sim/starter_layout.gd`)

- Split `build` into `build_shell(sim, rng)`, which places only the membrane
  ring and (plants) the wall ring, and `build_core(sim)`, which places and
  wires the old pre-built nucleus, chromosomes, mitochondria (and
  chloroplast). `build` calls both, so existing tests keep working.
  `CellGame` calls only `build_shell`. `build_core` stays as the reference
  wiring the guide teaches, used by tests and tools.
- Add `ring_ordered(half)`: the same cells as `ring`, walked clockwise (top
  row left to right, right column down, bottom row right to left, left
  column up), so consecutive cells touch.
- Add `shell_tiles(cell_type) -> Array[Dictionary]`: `{"id", "cell"}` entries
  for the reveal, membrane ring first, then the wall ring for plants.

### `IntroReveal` (`scripts/game/intro_reveal.gd`, new, scene-free)

- `class_name IntroReveal extends RefCounted`. Built from the ordered tile
  list, a `TOTAL_SECONDS = 2.5` duration and a `show` callable
  `(id, cell)`; `CellGame._process` calls `advance(delta)`.
- Reveals tiles at a fixed rate so the duration is the same for any cell
  size. Emits `finished` once every tile is shown. `skip()` shows the rest
  at once (used by tests and tools only, the player cannot skip).
- The pop effect is a short flash node spawned by `CellGame` inside the
  `show` callable (a white square that scales from 1.8 to 1.0 and fades over
  about 0.2 s). It is visual only and never changes tile data.

### `SetupGuide` (`scripts/sim/setup_guide.gd`, new, scene-free)

- `class_name SetupGuide extends RefCounted`, constructed with a `CellSim`.
- `steps()` returns `Array[Dictionary]` with `id`, `label`, `hint` (the
  chloroplast step only for plants). `step_done(id)` and `all_done()` read
  the sim live. `current_step()` is the first incomplete step (`{}` when none).
- `begin()` adds the core ids (nucleus, chromosomes, mitochondria, plus
  chloroplast for plants) to `sim.unlocked_ids`. Chromosomes normally need a
  water threshold, so without this its palette button would be disabled.
- `refresh()` returns true exactly once, the first time `all_done()` is true,
  and latches `core_done`. After that the clock does not stop again, even if
  the player erases something.

### `CellSim` changes (`scripts/sim/cell_sim.gd`)

- Add `signal links_changed`, emitted by `add_link` (when a link is added),
  `remove_link` and `remove_links_of`, so the game can re-check the guide
  when the player links or cuts links.

### `CellGame` changes (`scripts/game/cell_game.gd`)

- New signals: `intro_finished`, `guide_changed`, `setup_done`,
  `panels_toggled(shown: bool)`. New vars `guide: SetupGuide` and
  `intro_playing: bool`.
- `start_run`: stop the timer; create the sim; connect `organelle_added`
  only after `StarterLayout.build_shell` so the shell is not drawn at once;
  create the guide and `begin()` it; set `intro_playing = true`; build an
  `IntroReveal`; emit `run_started`. The timer is not started.
- `_process` advances the reveal. On `finished`: `intro_playing = false`,
  emit `intro_finished` and `guide_changed`.
- `skip_intro()` calls `IntroReveal.skip()` (tests and tools).
- `try_place` returns `"intro"` and `try_erase` does nothing while
  `intro_playing`; `BuildInput` ignores the mouse while it is true.
- On `organelle_added`, `organelle_removed` and `links_changed`, re-check the
  guide and emit `guide_changed`. When `guide.refresh()` first returns true,
  start `_timer` and emit `setup_done`.
- No tick, `DamageDirector.tick` or nucleus-loss countdown runs while the
  timer is stopped. Speed buttons have no visible effect until it starts.
- `Hud` emits `panels_toggled` when the player presses Tab.

### `GuideHud` (`scripts/ui/guide_hud.gd`, new)

- A `CanvasLayer` created with `UiRoot.attach(self)` and themed with
  `MetalUi.theme()`, added in `CellGame._build_children` with the other UI
  scripts. Its `setup(game)` takes the game untyped, per the existing
  convention.
- Layout: a `PanelContainer` anchored bottom-right (the stats tab is top
  right, the tool bar bottom centre, the palette top left), listing each step as a
  row with a tick (checked or unchecked) and the label. The current step is
  highlighted, and a hint line below the list shows `current_step().hint`.
- Hidden until `intro_finished`. Updated on `guide_changed`.
- On `setup_done`, the panel collapses to a "Basics done" chip and stays
  there for the rest of the run. The chip is a visual marker only.
- Follows the Tab (`open_buildings`) toggle via `panels_toggled`. An attack
  popping the stats tab open does not affect it.

## Data flow

```
start_run
  -> StarterLayout.build_shell (membrane/wall into sim)
  -> SetupGuide.begin (unlock core ids)
  -> IntroReveal plays (building blocked, no timer)
  -> intro_finished -> GuideHud shows, building allowed
  -> player places / links (free)
  -> guide_changed -> GuideHud ticks steps
  -> guide.refresh() first true -> timer starts, setup_done -> chip
```

## Edge cases

- Restarting a run resets the guide, the reveal and the HUD.
- Erasing a core piece mid-guide un-ticks its step (checks are live).
- Erasing a core piece after `core_done` does not re-freeze the clock.
- The nucleus-loss countdown cannot fire before the first nucleus exists
  because the sim does not tick during the guide.
- Core organelles cost no energy, so the player cannot run short of energy
  during setup. A test pins that cost at 0.
- Plant `in_bounds` padding (wall ring) is unchanged.
- Resizing the window during the reveal: tile positions are map cells, so
  the reveal is unaffected.

## Out of scope

- A second checklist for later goals (water/food/unlocks); later guidance
  stays in the existing unlock cards.
- Re-opening the "Basics done" chip, skipping the intro, or arrow/highlight
  overlays on palette buttons.
- Changing `HALF`, difficulty or organelle numbers.

## Testing

- Unit tests (`tests/test_setup_guide.gd`, `tests/test_intro_reveal.gd`, both
  extend `McpTestSuite`):
  - Step lists for animal and plant, each step's check for the right sim
    states, the current step, un-ticking on erase, and the `refresh()` latch.
  - `begin()` unlocks the core ids and they place with 0 energy cost.
  - The cell built by `StarterLayout.build_core` satisfies `all_done()`
    (keeps the steps honest against a cell known to survive).
  - `CellSim.links_changed` fires on add, remove and remove-all.
  - `IntroReveal` shows every tile exactly once, in order, in about
    `TOTAL_SECONDS` regardless of tile count, and `skip()` finishes it.
- `tests/test_starter.gd`: add tests for `ring_ordered`, `shell_tiles`,
  `build_shell`. Existing tests keep passing through `build`.
- `tools/smoke_game.gd`: start a run, check the clock is stopped and tiles
  are partly revealed, `skip_intro()`, place and wire the core by hand and
  check `setup_done` and that the timer starts. The rest of the smoke test
  then runs on that cell as before.
- Visual check with `tools/screenshot.gd` for animal and plant: mid-reveal,
  checklist visible, and the "Basics done" chip.

## Resolved items

- Building during the reveal is blocked with an `intro_playing` flag, not by
  reusing `paused`.
- The chloroplast step needs an energy link to a mitochondria and a water
  link to a membrane or wall tile (the old starter wiring).
- The checklist sits bottom-right; the screenshot check confirms it does not
  overlap other panels at the default window size.
