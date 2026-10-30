# fwd-review-d stills (Forward+ under lavapipe vs opengl3; seed 1337)

Forward+ = `--rendering-driver vulkan` on lavapipe (Mesa's software Vulkan), small scenes only.
"before" = origin/main's shaders, "after" = wt/fwd-review-d. Downtown / midtown scenes were
rendered with unrelated systems off for memory (CLIMBERS, MURALS, STREET_WEAR, ROAD_WEAR,
BILLBOARDS, BOULEVARD_SIGNS, UTILITY_POLES, HISTORIC_CORE, BIRDS, KERBS, ROAD_DETAIL,
STREET_SIGNS, REFLECTION_PROBES, CROWD_LIFE, ALLEYS, MICROMOBILITY, STREET_FURNITURE = 0):
with everything on they peak over 13.6 GB and the box has 15.

- 01-03 a/b/c: the offshore island from the beach (-900, 0), yaw 115, at 14:00, 17:48, 21:30:
  Forward+ before (hidden by the cloud volume's composite), Forward+ after, opengl3.
  (`tools/offshore_island/island_shot.gd`)
- 04: the sea, ocean traffic close-up (`vessel_shot.tscn CAM=-25,6,30`): opengl3 / Forward+
  before (washed pale: sky_tint read as linear) / Forward+ after.
- 05: refinery flares at 21:00 (`fwd_block_shot EYE=2850,25,5905,0,14`): opengl3 / Forward+
  before (square halos) / Forward+ after.
- 06: refinery by day, Forward+ (process units, the cooling-tower plume).
- 07: power plant by day, Forward+ before / after (the glass's sky; small at this angle).
- 08: power plant at 21:00, opengl3 / Forward+ (stack lights stay red).
- 09: the lighthouse at 21:00, Forward+ (lantern, drawn beam, the house's windows).
- 10: the crowd in the rain (`crowd_lab.tscn SCENARIO=rain`), opengl3 / Forward+.
- 11: the wingsuit gliding (`tools/wingsuit/glide_shot.tscn`), opengl3 / Forward+ (crop).
- 12: motorcycles with riders, opengl3 / Forward+.
- 13: a footbridge, opengl3 / Forward+.
- 14: news vans, opengl3 / Forward+.
- 15: the coast highway, Forward+ 15:00 / 21:00.
- 16: the fashion district street at 21:00, Forward+ (the market alley was off: ALLEYS=0).
- 17-18: a parklet and the facade pass downtown, Forward+ 13:00 / 21:00.
