# Loop log (append-only)

One entry per item attempt: item, build number, before / after screenshot paths, perf delta,
result. Screenshots live in the session scratchpad (not committed); paths are for the session
that took them.

## Before the loop

- **Hero AAA pass** - build 250 - done. Collar shards fixed (neck ring, cloth-ray skin masking).
- **CI red on the car drive check** - build 251 - red; fixed in build 252 (car checks pin a sedan,
  a car wakes when entered).
- **Masjid Omar ibn Al-Khattab, 1:1 with interior; no weapon fires at it** - build 252 - done.
  50.7k triangles exterior, 9.1k collision. Stills in `<scratchpad>/masjid/`. NEEDS MAC CHECK.

## Wave 1 (2026-09-24)

Baseline bookmarks for main 18c1bcb: `<scratchpad>/bookmarks/base_18c1bcb/`.

- **MacArthur Park on** (roadmap #4) - build 254 - done, CI green.
  Before: park off. After: `<scratchpad>/park/park_aerial.png` (+ lake, camp stills). Perf: the
  park replaces blocks of buildings with lawn, lake and trees; not measured with geo_count yet.
  Gate 453/453. The same fix made the helicopter checks stop flaking (they were the offset bug).

- **Road patch decals** (roadmap #16) - build 257 (ec65e50) - done, clearly better. Before
  `<scratchpad>/park/park_camp.png`, after `<scratchpad>/patch/camp_after3.png`, crop
  `<scratchpad>/patch/ab_crop.png`. Perf: the patch batch moves to the transparent pass
  (one MultiMesh per chunk, no shadows); one texture + one normal fetch and two noise
  evaluations per fragment on small decals - negligible. Gate green.

- **Park lawn tint** (roadmap #15) - not shipped, reverted. Tried dryness 0.3 -> 0.48 / 0.62,
  wear 0.5-0.6, tint greyed. Before `<scratchpad>/park/park_lake.png`, afters
  `<scratchpad>/lawn/lake_after{,2,3}.png`. Lawn region HSV saturation 145 -> 153-155, value
  145 -> 130: darker, not less saturated, because the near lawn is the blade-grass multimesh.
  Not clearly better -> reverted.

## Wave 3 (2026-09-25)

- Hill road cut banks (roadmap #17) launched. New hills bookmark baseline: `<scratchpad>/bookmarks/base_18c1bcb/hills2.png`.

- **Street clutter** (roadmap #7) - merged 20e2169 - done, clearly better. Before
  `<scratchpad>/sc/before/{box,news,board,corner}.png`, after `<scratchpad>/sc/after3/`, A/B
  `<scratchpad>/sc/box_ab.png`, `board_ab.png`. geo_count street view 576.4,860.5: 4.641 M ->
  4.652 M tris (+0.23 %), 2169 -> 2190 draws (+1 %). Gate on the merged tree 456/456.

- **CI 265 red -> 266 green** (b581d15): one traffic car on the park's closed road on CI; the
  street tick now recycles any car found on a closed stretch.
- **Golden hour / LA haze** (roadmap #5) - merged ffc19f8 - done with NEEDS MAC CHECK. Fixes a
  real bug: at 17:36 (sun 9 deg up) the sky was already a full violet sunset and every shadow
  went lavender. Now a blue sky with a smog band and warm haze until the sun is low; noon and
  night pixel-identical. Forward+ stand-in `<scratchpad>/gh/fwd_sheet.png`, sky probes
  `<scratchpad>/gh/sky_sheet3.png`. Perf: ~25 ALU on sky pixels only while smoggy. Verdict:
  clearly better away from the sun, sideways toward it (hazier, less punchy).
- Street clutter and golden hour merged; PERF pass 1 and crowd skin/cloth launched.
- **Hill ground splat** (roadmap #1) - merged dfdeefa - done. Before `<scratchpad>/bookmarks/base_18c1bcb/hills2.png`, after `<scratchpad>/hills/final3/hills2.png`, A/B `<scratchpad>/hills/cmp_hills2_final.png`. Near/far mean albedo now within ~11 %. Perf: terrain fragment ~1.8-2x (7 fetches + 9 noises, was 4 + 2). Follow-ups: #19 (chaparral reads as cloud shadows), #18 (mipmaps off on 14 sets).
- **Hill road cut banks** (roadmap #17) - merged 42bf864 - done, clearly better. A/B
  `<scratchpad>/hcb/hills_ab.png`, `spur_ab.png`. Root cause: carve() blended every road over a
  fixed 14 m whatever the cut; canyon roads at 11 % in a range rising 560 m in 400 m sank into
  250-320 m trenches; estates started at the hillside height, not their road's; the boulevard
  rode a 60 m embankment. Now 1:1 cuts / 1:1.5 fills out to 46 m, unbuildable roads trimmed,
  boulevard moved downhill <= 96 m. Carved cells > 60 deg: 32.2 % -> 0.6 %. Terrain tris -3.4 %;
  load +190 ms. Content cost: mansions 468 -> 318 (front range ~150 -> 10) -> roadmap #20.
- **Crowd skin and cloth** (roadmap #11) - not merged (modest, not clearly better). Sheets
  `<scratchpad>/crowd/cmp6.png`, `cmp_faces_fp.png`. Screen-space SSS blurred the photo-baked
  eyes and stubble; the vinyl look comes from lighting baked into the textures. Kept the
  character_shot.gd LOOK fix (9ad44e7).

## Wave 4 (2026-09-25)

- Launched: downtown 1:1 re-lay (roadmap #13), hill vegetation (#6).
- **Vehicle grime** (roadmap #2) - not merged. Close-ups `<scratchpad>/grime/m2/z_sedan.png`,
  `z_pickup.png` (dirt 0 / 0.3 / 1). Real but subtle at the median car, ~+190 ALU per car
  fragment (paint code ~90 before). Found: the body meshes' faceting is the louder tell (#21).
- **Wall weathering** (roadmap #3) - not merged. `<scratchpad>/ww/cmp3_brick_close.png` (better
  up close), `cmp3_city_brick.png` (no difference at 40 m). +90-120 ALU per wall pixel.
- Render lock: `flock ... xvfb-run` handed the lock fd to Xvfb, and an orphaned Xvfb held every
  render for a while. bookmarks.sh now uses `flock -o` (the child never inherits the lock).
- **Texture mipmaps** (roadmap #18) - merged cb4e4e3 - done, clearly better at distance. A/B
  `<scratchpad>/mip/brick_crop.png` (brick mid-rise across the street: speckle -> even brick),
  high-frequency energy -3 %. 14 sets switched, RockyTerrain02 dropped (unused). Gate 456/456.
- **Car body faceting** (roadmap #21) - merged 331e450, gate 456/456 - clearly
  better. Root cause: the four Meshy bodies were exported with normals split at 30 deg and on
  every UV seam. tools/smooth_normals.py re-smooths by angle (45 deg), welds, never adds
  vertices. Forward+ sheets `<scratchpad>/smooth/ba_{0..3}.png`. Same triangles, ~0.2 % fewer
  vertices, LODs intact. Follow-up #22 (higher-poly bodies).

## Wave 5 (2026-09-25)

- Regression audit launched on main 75f4795 (every fifth wave).
- **PERF pass 1** - merged b612d55, gate 456/456. Static boxes per chunk and far
  landmark primitives merged into one mesh per material: draws hills 1,202 -> 942 (-21.6 %),
  downtown 4,679 -> 4,313 (-7.8 %), freeway 6,661 -> 6,485 (-2.6 %), triangles unchanged;
  pixel diffs only on clock-driven things (`<scratchpad>/perf/*_diff.png`). Baseline table in
  HANDOFF 9x. Found: trees (#23) and mid-range pedestrians (#24) are the triangle hogs.
- **Container restart** (~10:30): all five agents were killed. Night shopfronts had finished;
  re-lay, hill vegetation, pedestrian LOD and the audit were relaunched to resume from their
  worktrees.
- **Night shopfronts** (roadmap #8) - merged 5340b9b, gate 459/459. Root cause: an
  open shop fell through to a flat `lit_color` branch, so every tower base was one white band.
  Crop `<scratchpad>/nshop/cmp_rain_base2.png`, full `after2/night_rain.png`. geo_count night
  avenue +1 draw, +78 tris. Brightness p95 night rain 153 -> 128 (the white band came down);
  noon identical. Clearly better at tower bases, modest on side streets. NEEDS MAC CHECK.
- **CI 279 red -> 280 green** (dc83d4f): "live street traffic never drives into the car in
  front" failed at -3.8 m. Real bug on the park's closed roads: dead-end U-turns were dropped
  onto the other carriageway unasked, and two cars could turn into one lane in the same tick.
  Both now wait / register at once. Shotgun wound check made robust (strongest of 5 tries).
- **Pedestrian middle body** (roadmap #24, PERF) - merged 35efe0a, gate 459/459. Downtown noon
  crowd 1.88 M -> 1.10 M triangles (-42 %), frame 8.23 M -> 7.44 M (-9.5 %), draws and shadow
  pass unchanged. Bookmark crop `<scratchpad>/ped/city_ab3_C.png` (no visible change). Loading
  +415 ms CPU. Also fixed: the old far body had its own LOD chain and drew as an 18-35 triangle
  stick.

## Wave 6 (2026-09-25)

- Launched: wet streets that dry believably (#9). Tree LOD (#23) waits for hill vegetation (same batching code).
- **Hill vegetation** (roadmap #6) - merged 75902af, gate 464/464. Shrubs and oaks
  placed from a GDScript copy of the terrain shader's brush/dirt/rock field (checked against
  the shader by the smoke test); far mounds from the same field. North-face A/B
  `<scratchpad>/veg/nf_ab.png` (clearly better), hills bookmark `hills_ab.png` (neutral). GEO:
  hills +4.5 % tris / -0.3 % draws, city +1.2 % tris, among the stands +14-22 % tris and
  +5-10 % draws. Found: a floating hill chunk (#25).
- Launched: tree LOD (#23, PERF), floating hill chunk (#25), hi-fi sedan (#22).
- **CI 284 red** (blood-pool check, a 3 s wait vs the ragdoll 3.5 s fallback): test waits 7 s and prints diagnostics.
- **Floating hill props** (roadmap #25) - merged 2106e3e, gate 466/466. Root cause:
  relief added twice (height_at() already includes it; the batch's `ground = _gy` added it
  again). Probe: 700/1,597 hill chunks off, 367k instances, worst +144 m -> 0 chunks, worst
  1.2 m. A/B `<scratchpad>/float/slope_ab.png`. New smoke check + tools/float_probe.
- **Hi-fi sedan** (#22) - not merged yet: clean render and -6.5 % vehicle tris, but styling reads
  dated (bulb nose, tall slatted grille). Sent back for one styling pass. Sheets
  `<scratchpad>/sedan/ba_sedan_day.png`, `ba_police_day.png`.
- **Regression audit (wave 5)** - reported. No breakage; sanctuary checks all pass; web-safe.
  Regressions: MacArthur far palms +2 M tris toward the park (#32, to tree LOD); hill ground on
  Compatibility smoother/camo-ish (#33); front range emptier (intentional, WAITING ON ASH);
  closed-road recycle masks a root cause (traffic fixes since then address the real paths).
  Perf: downtown -7.9 % draws, hills -39 % draws, triangles flat except masjid view.
  Evidence `<scratchpad>/audit5/`.
- **OWNER reports** (2026-09-25): port in the middle of the city (#29), freeways through
  downtown buildings (#30) -> re-lay agent; more homeless downtown (#31) -> new agent.
- **CI 286 red** (police damage check, 0.7^5 chance of five misses): that phase now aims well.
  c08b87b.
- **Session ended by the owner** (2026-09-25 ~15:30). Agents stopped; unfinished branches
  pushed as wt/downtown-relay, wt/sedan-body, wt/downtown-homeless, wt/street-wear,
  wt/tree-lod, wt/wet-streets (see HANDOFF section 00). STOP file created.

## Wave 7 (2026-09-25, resumed at the owner's request)

- Owner: screenshots nonstop, work faster, downtown encampments x20, hills "look like garbage".
  Launched: encampments x20 (wt/downtown-homeless), real mountains (wt/real-mountains), port
  to Palos Verdes' east flank + freeway clearance (wt/downtown-relay). Agents drop every render
  in `<scratchpad>/screens/`, forwarded to the owner as they land.
- **Stopped at the owner's request** (wave 7). Unfinished work pushed: wt/downtown-relay (port moved to San Pedro Bay east of Palos Verdes, 110 clear of buildings; arena-district plazas still empty), wt/real-mountains (ridged heightfield, rounded summits, far-range banding fixed, chaparral palette - pass 2, not gated), wt/downtown-homeless (x20 encampments, WIP). STOP file set.
