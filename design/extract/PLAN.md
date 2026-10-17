# FPS: Extraction — build plan (2026-10-16)

The author's brief: a Tarkov-style military-sim extract shooter on a
procedurally generated forest campus, campus-paintball look as the baseline.
Start at the edge of a big map with a pistol, loot chests and dead guards,
ammo scarce, dumb loud green guards protecting buildings, hills and valleys,
roads between buildings in varying disrepair, two variants of every gun.
The map must feel new each run; the player must not know where the enemies
are. Gauntlet the map for visual interest and clear landmarks.

Status of the brief's choices (Claude's calls, the author overrules):
- **Procedural at runtime, not 8 Blender maps.** A `GKDef` env built in
  GDScript from a seed (`GKExtractForest`, like `GKRooftop`), so every match
  seed is a new map and the bracket can roll it. Blender is offline, so it
  can't be new each time. The campus look is carried over by porting the
  campus script's dressing (halls, houses, trees, bushes, bunkers, road
  ribbons, lamps, benches, cars) to GKMesh.
- **Size:** play area 300 x 300 m (campus is 110 x 80 = 8,800 m²; this is
  ~10x). Tri budget: ≤ 600k tris, built in < 3 s; trees and bushes are
  low-poly and grouped into chunks (one part per 60 m cell) so culling works.
- **Two contestants, same seeded map, judged like OSRS:** both run the raid
  alone (the other seat is a bot roll); extracted beats died, then loot value
  ($), then faster. One life. 5-minute clock (`extract_time`), the extract
  zone is a marked spot on the far edge revealed at 2:30 (a flare), so the
  first half is looting and the second is the run.
- **Variants stay off the duel radial.** The duels keep their six primaries;
  the 14 variants appear as loot in Extraction (and the bot's loadout rolls
  there). Author may want them on the radial later: one list change.
- **Variants are dressed at runtime, not new Blender models:** the base
  asset plus kit-built attachments at markers (suppressor / brake / long
  barrel at `muzzle`, optic on the rail, drum or extended mag, stock) and a
  material recolour (`polymer_fde`, `polymer_olive`, `paint_army`,
  `steel_bright`...), so each variant reads at a glance in hand and on the
  ground. A Blender variant is allowed where a dressing can't do it.

## Contracts (agreed before parallel work; change only here)

### Map asset: `GKExtractForest` (id `extract_forest`, kind env)
Params: `seed` (int), `size` (m, default 300), `hills` (0..1, 0.6),
`density` (buildings, 0..1, 0.5), `disrepair` (0..1, 0.5), `scale` 1.0.
Real metres like the campus (Godot +Y up, ground near y 0, hills ±12 m).
Markers (Transform3D, in `asset.markers`):
- `spawn_a0..a7`: eight edge spawns around the perimeter (one per 45°), each
  in a tucked pocket (tree line / low wall) that no building window sees.
  `FpsWorld._spawn("a")` picks one by seed as it does today.
- `spawn_b0..b7`: the same points (FpsWorld needs a "b" side; Extraction
  ignores it).
- `extract0..extract3`: four extract pads; the match picks the one farthest
  from the spawn.
- `ref_cam`: the review camera.
Meta (`asset.meta`):
- `class: "map"`, `extract: true`, `play_area: [x0, z0, x1, z1]`,
  `bot_hunt: false`.
- `height`: `{ origin: [x, z], step: float, cols: int, rows: int,
  data: PackedFloat32Array }`; `GKExtractForest.height_at(meta, x, z) -> float`
  (static, bilinear) is the one way anyone asks the ground's height.
- `chests`: `[{ pos: Vector3, yaw: float, where: "building" | "car" | "bush",
  tier: 1..3 }]` — 30–45 per map; tier 3 only deep inside buildings.
- `guards`: `[{ pos: Vector3, building: int, patrol: [Vector3, ...] }]` —
  8–14 posts; `patrol` is a short loop (3–5 points) around / through the
  building, every leg straight-line walkable (bots have no pathfinding).
- `buildings`: `[{ id: int, name: String, aabb: AABB, kind: "hall" | "house"
  | "lodge" | "chapel" | "barn" | "watertower" | "ruin", disrepair: 0..1 }]`.
- `landmarks`: `[{ name: String, pos: Vector3 }]` — the tall things you can
  navigate by (the chapel tower, a water tower, a radio mast, a burnt barn
  on the hill, the lake): ≥ 4, each visible from ≥ 50% of the map at eye
  height (the probe checks a sample).
- `roads`: `[[Vector3, ...], ...]` polylines, for the minimap/debug.
- `hide_volumes`: bushes, as the campus has them (`{ center, half, basis }`).
- `lights`: a sun/sky block like the campus's (`GKStage.outdoor`).
Colliders: the terrain (a trimesh is fine via `add_part` + a
`ConcavePolygonShape3D`: extend `GKAsset` with `add_trimesh_collider(mesh)`
if boxes can't follow hills), walls, trunks, cars; `barrier` boxes around
the play area's edge (`GKAsset.BARRIER_LAYER`).
Buildings: interiors are enterable (door openings, a floor, a roof you can
see from outside); disrepair removes roof panels, knocks out wall segments,
scatters rubble boxes, darkens the role colours. Roads: ribbons following
the terrain between every building (an MST plus a loop), asphalt/gravel by
disrepair, a parked car or two per road leg (cars are box-built kit props
with COL).

### Weapons: `FpsWeapons` (file owner: agent B)
- Every SPECS entry gains `caliber: "rifle" | "shotgun" | "pistol"`
  (sniper, marksman, carbine, auto_rifle = rifle; shotgun = shotgun; pistol,
  deagle, dual_berettas = pistol) and `value` ($, for the verdict).
- Variants are SPECS entries too, `"<base>_<tag>"`, with `base: "<id>"`
  (the asset and `hip` default from the base) and `dress: { tint: role,
  mods: [ { kind, at, params } ] }` read by `FpsVariants.apply(asset, dress)
  -> GKAsset` (a copy with the attachment parts added and the body roles
  retinted). `FpsWeapons.spec(id)` returns the merged spec; viewmodel, bot
  and HUD go through it. Two per base, 14 total:
  one upgrade / downgrade / sidegrade each, visibly and numerically
  different (see the agent brief for the list).
- `FpsWeapons.VARIANTS` lists them; `PRIMARIES` is unchanged (duel radial).
- Ammo: `FpsPlayer.mags: { rifle: int, shotgun: int, pistol: int }`, cap
  `FpsTune.mag_cap` (3). `FpsPlayer.scarce := false`: when true a reload
  spends one mag of the gun's caliber and refuses when none is left; false
  keeps today's infinite duel reloads. Starting Extraction kit: pistol in
  hand, `mags.pistol = 1` (one in the gun plus one spare = "start with 2").

### Game: `FpsExtractModule` / `ExtractWorld` (owner: agent C)
- `src/tourney/extract/`: `extract_world.gd` (extends FpsWorld, overrides
  the duel bits: one life, no respawn, loadout menu skipped, `scarce` on,
  chests, guards, loot, extract, clock, verdict), `extract_guard.gd`
  (extends FpsBot: green cosmetics, a loud idle bark every 2–4 s audible
  past 40 m, `bot_reaction` x3, accuracy x0.5, patrols its post, drops a
  `Loot` on death), `extract_chest.gd` (a kit-built box, F within 2.5 m,
  opens with a lid tween, rolls contents by tier), `extract_loot.gd` (the
  tables and the pickup), `extract_hud.gd` (the FpsHud plus: mags per
  caliber, armour, money, the clock, the compass with the extract bearing
  once revealed, an interact prompt, a loot pop-up), `extract_tune.gd` keys
  in `FpsTune.ENTRIES` under section "Extract".
- `src/tourney/modules/fps_extract_module.gd`: id `fps_extract`,
  name "FPS: Extraction", blurb; `simulate()` rolls extracted/died + a $
  value; registered in `TourneyModules.POOL` after `FpsCampusModule`.
- Loot tables: a chest holds 1–3 of: a gun (variants included, by tier),
  a mag of a caliber (most common), a medkit (heal 60 over 4 s, F to use,
  slot on the HUD), body armour (one piece, 35% damage cut, worn until it
  soaks 100), money ($50–$400). Dead guards: their gun (half-full) and 0–1
  mags.
- The verdict `summary`: "<name> extracted with $1,250 at 3:12." /
  "<name> died in the lodge with $400."

## Agents (parallel, owned files; no commits; no edits to the OSRS/lobby
files already modified in the tree)
- **A — Map** (`src/kit/envs/gk_extract_forest.gd`, `gk_forest_lots.gd`
  (building/prop builders), `GKRegistry` one-line registration,
  `GKAsset.add_trimesh_collider` if needed, `tools/extract_map_probe.gd`,
  `tools/extract_map_shots.gd`).
- **B — Weapons** (`fps_weapons.gd`, new `fps_variants.gd`, the ammo bits
  of `fps_player.gd` and `fps_hud.gd`, `fps_viewmodel.gd`/`fps_bot.gd` only
  where `spec()`/`FpsVariants.apply` must be read; `tools/fps_probe.gd`
  additions; `fps_tune.gd` `mag_cap`).
- **C — Game** (`src/tourney/extract/*`, `fps_extract_module.gd`,
  `tourney_modules.gd` one line, `tools/extract_probe.gd`). Develops on the
  campus map plus a stub until A lands (chests/guards from a fallback
  scatter when `meta.extract` is missing), then switches to `extract_forest`.
- **D — Gauntlet** (after A): `reference-gauntlet` rounds on the map:
  fixed seeds, eye-height frames at the spawns and the hilltops plus a plan
  view; score visual interest, landmarks, readability of roads/buildings;
  one round of fixes; repeat to ~3 rounds.
- **Integration (me):** wire C onto A, run every FPS probe + tourney_probe,
  write DECISIONS (G-numbers), GAMES.md, PLAYTEST.md, CLAUDE.md, HANDOFF.

## Checks before hand-back
- `extract_map_probe`: 6 seeds build < 3 s each, ≤ 600k tris; ≥ 6
  buildings, ≥ 30 chests (each where it claims: inside a building AABB, within
  4 m of a car, within 1.5 m of a bush), ≥ 8 guard posts with every patrol
  leg clear; every spawn hidden from every building window at eye height;
  a landmark visible from ≥ 50% of a 15 x 15 sample; hills: height range
  ≥ 12 m; two seeds differ (building positions).
- `extract_probe`: a chest opens on F and yields; a mag reload spends a mag
  and refuses at zero; cap 3; a guard barks, reacts slow, drops loot; dying
  ends the run; standing on the pad after the reveal extracts; the verdict
  orders extracted > died, then $, then time; `simulate()` resolves.
- `fps_probe` still green; every variant builds, fires, and looks different
  (asset part count or role tints differ from the base).
