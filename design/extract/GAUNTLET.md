# Extraction forest: map gauntlet (agent D, 2026-10-16)

Reference: `design/ref/kit/campus.jpg` plus the built campus frames
(`design/shots/kit/r5_campus_eye_*.png`). Brief: visual interest at eye height
and clear landmarks; buildings in varying disrepair, tall forest, roads,
elevation, new each run. In scope: layout, landmarks, buildings and props,
terrain, roads, foliage, light and fog. Out of scope: `src/tourney/*`, guns,
characters, HUD.

Frames: `[SEED=7] TAG=r<n> --path . --script res://tools/extract_map_shots.gd`
saves `design/shots/extract/map/<tag>_s<seed>_<scene>.png`, seeds 7 and 3 each
round. Scenes: 0_plan, 0c_top (ortho, r1+), 0b_aerial, 1_spawn_0/3/5, 2_hilltop_*,
3_inside, 4_road_landmark, 5_lake, 6_junction, 7_valley, 8_forest_mid, 9_poi_*
(r1+). Contact sheets are `<tag>_s<seed>_sheet.png`; before/after composites
(r0 beside r4) are `before_after_s<seed>_<scene>.png`. The reviewer was a blind
subagent with the same prompt every round, plus the previous round's sheets.

## Scores

| Axis (0-10) | r0 | r1 | r2 | r3 | r4 |
|---|---|---|---|---|---|
| Visual interest at eye height | 5 | 6 | 6 | 6 | 6 |
| Landmark clarity | 6 | 7 | 7 | 7 | 7 |
| Building read / disrepair variety | 5 | 5 | 5 | 6 | 6 |
| Elevation use | 5 | 6 | 7 | 7 | 7 |
| Roads / connection read | 4 | 6 | 5 | 5 | 5 |
| Campus-baseline fidelity | 4 | 6 | 6 | 6 | 6 |
| Variety across seeds | 5 | 6 | 8 | 8 | 8 |
| **Total / 70** | **34** | **42** | **44** | **45** | **45** |

We stopped after r4. The score moved +1 and then 0, and the remaining top gaps
are layout decisions or hand-made art (parked below).

## Fixes per round
- **Tool, before r0:** spawn frames had looked into the pocket hedge. They are now shot from beside the pocket, and from r4 from past its hedge return, looking at the nearest landmark. Added the aerial, junction, valley and forest_mid scenes, then POI frames and an ortho top view (r1). Cameras pick a clear spot by a physics query (r2) and the densest stand for forest_mid (r3).
- **r1:**
  - The brick moire on the hall: a new role `brick_hall` replaces the fine `blocks` course on big faces.
  - Road shards: road beds are carved, and ribbons are resampled every 1.5 m and split across into 4 strips. Each road gets its own depth lift, and every door gets a paved forecourt.
  - Dirt trails run from every spawn to the road net.
  - Mid-forest POIs: a fire lookout (a new landmark), hunting stands, a wreck, a camp, ruined field walls, and a power-line cut across the map. They are listed in `meta.pois`.
  - The forest is varied by seeded fields: clearings, thick stands, birch groves (new role `bark_birch`), autumn patches with the season mix per seed, tall pines, ferns, fallen logs.
  - Halls and houses get white cornices and quoins. Ruins get a door. Cars are reshaped and tilt with the slope. Skirts are extended.
- **r2:**
  - The outer band of woods is thicker, with a leaf-litter floor.
  - Disrepair spreads wider. Windows can be boarded or sooted, and ruins use brick again.
  - Two lots sit out in the woods (site `outer`).
  - Trails are clamped to the map.
  - The skirt rises into distant wooded hills.
  - Pads on slopes keep a sharp bank, with a retaining wall on any uphill face.
  - Hills are taller (11 + 14 × hills m). The water tower and silo were raised to keep landmark coverage.
  - Wrecks follow the slope, the camp gets a tent, and asphalt roads get lamp rows.
- **r3:**
  - Ruins have ragged wall tops, scorch, fallen joists, debris and ash, and a new role `brick_ruin`.
  - The chapel's disrepair is capped at 0.4, so the landmark stays whole.
  - Road ribbons shade smooth with per-vertex ground normals, and the bed smoothing is wider.
  - Lot asphalt gets a centre line, and asphalt roads get sidewalks.
  - A sightline is cut from each spawn toward its nearest tall landmark.
  - A ring of distant trees stands on the skirt.
- **r4:**
  - kit_probe's 260k env budget: broadleaf crowns go from 8 to 7 segments (seed 7: 262k down to 223k). A folded trail quad was inverted; each ribbon triangle is now wound on its own.
  - Sightlines start from the trail exit.
  - Roads lift 0.16.
  - Mown lawns surround the lots, and the autumn stands get leaf litter.
  - More mid-state damage, red barns, a green-only backdrop, and the wreck pulled off the road.

## Checks every round
- `extract_map_probe`: green every round. At r4 it builds in 1.05-1.2 s for 213-244k tris; every spawn is hidden from every window; landmarks are seen from 48-80% of the sample and at least 4 of them from 50% or more.
- `kit_probe`: green at r1 and r2. It failed after r3 (262k tris against the kit's 260k env budget, plus one inverted trail triangle at seed 99999). Both were fixed in r4, and it is green at r4.
- The meta contract is unchanged. The additive keys are `pois`, the `fire lookout` entry in `landmarks`, and `site: "outer"` on buildings.

## Parked (needs hand-made art or an author decision)
1. **Campus core (decision).** Every reviewer asked for a quad: 3-5 halls round a mown lawn with a path web, near the centre. Today it is one lot per road node, which reads as a scattered village. This is a layout rule change, not a tuning pass.
2. **Roads on crests (code, bigger).** The asphalt still creases where a road crosses a lot pad's blend, because the carve skips pad nodes. A real fix grades the pad blend and the road together.
3. **POI and prop modelling (art).** The camp, wreck, bushes and halls are primitive-built. Reviewers wanted crumpled wrecks, a fire ring with crates, rounder bushes, and slate roofs with chimneys.
4. **Ruin brick scale (taste).** Reviewers flip-flopped between "no brick" (r1) and "bricks too big / wallpaper" (r3, r4). `brick_ruin` sits between the two; the reference shows no close-up ruin, so the author should call it.
5. **Probe honesty (note).** The landmark visibility rays ignore tree crowns (crowns don't collide), so the coverage percentages are optimistic at eye height in thick stands. The check was left as is; it was not loosened.
