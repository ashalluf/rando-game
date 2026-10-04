# Houses in the suburbs and the beach town (branch `wt/houses`, docs/HANDOFF.md 9be)

opengl3 stills (the Compatibility renderer, 1280x720, `--quality=0`). "before" = main before the
house pass (the suburb and beach stills from 96f86f1, the 320 m aerial from c848ad4), "after" =
`wt/houses`. Noon is 12:30, dusk 18:24.

| File | View |
|---|---|
| before/after_suburb_street_corner(_dusk).jpg | street level at a suburban corner, `EYE=-292,1.7,307.5,-62,-4` (`EYE_AGL=1`), spawn `-290,307,-60,-3` |
| before/after_suburb_aerial(_dusk).jpg | the suburb from 85 m, `EYE=-345,85,385,-37,-33` |
| after_suburb_street_ranch(_dusk).jpg | a ranch house from the pavement, `EYE=-250,1.7,306,35,-3` |
| before/after_beach_street(_dusk).jpg | the beach town's street, `EYE=-652,1.7,95,70,-5`, spawn `-652,95,70,-5` |
| before/after_beach_aerial(_dusk).jpg | the beach town from 110 m, `EYE=-610,110,210,35,-39.3` |
| before/after_far_tier_320m.jpg | 320 m over the suburbs looking north over the LOD ring and the far city (`EYE=-300,320,600,-30,-24`): the suburban blocks bottom left now read as pitched roofs |
| after_block_suburb_garages.jpg | `block_shot.tscn`: garages where the drives end, `EYE=-262,1.7,304,20,-4` |
| after_block_suburb_midcentury.jpg | a mid-century house with a deep flat roof, `EYE=-230,1.7,304,-20,-4` |
| after_block_suburb_corner_air.jpg | a suburban corner from 14 m, `EYE=-270,14,330,30,-25` |
| after_block_beach_stucco_box.jpg | a two-storey stucco box with its balcony and garage, `EYE=-640,1.7,40,90,-4` |
| after_block_beach_craftsman.jpg | a craftsman bungalow with rafter tails, a chimney and a picket fence, `EYE=-650,1.7,150,70,-3` |
| after_block_beach_roofs.jpg | the beach town's roofs: clay, laminated shingle, solar, flat, `EYE=-670,9,60,60,-15` |

The block shots are from `tools/glshot/block_shot.tscn` (a few FULL blocks alone, no far city);
`after_block_suburb_*` were rendered before the last tweak (upper-floor windows, raised garage
panels), the rest after.
