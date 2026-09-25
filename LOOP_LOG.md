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
