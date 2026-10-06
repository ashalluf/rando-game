# tower-gondolas stills

Window-washing gondolas on the downtown towers (branch `wt/tower-gondolas`). All opengl3
(Compatibility renderer, the stills path) - not what the Mac's Forward+ draws; judge geometry and
placement, not the light.

City (`tools/glshot/still_shot.gd`, 11:00, `GONDOLA_T=1000`; before = `GONDOLAS=0`):
- 01 / 02 - the black twins from 30 m out, EYE=2291.2,69.6,204.0,18.4,7.2
- 03 / 04 - the bronze slab, EYE=2416.5,138.2,-397.0,-161.6,7.2
- 05 / 06 - the granite slab, EYE=2454.0,158.9,189.1,-161.6,7.2

One tower alone (`tools/gondolas/gondola_shot.gd`, a plain sun and sky):
- 07 - the crew close up: squeegee strokes on the pane, the soap not yet cleared, lanyards, hard hats
- 08 - a cradle on the black twins' dark glass
- 09 - 2.5 s after a rocket's blast: swung out and twisted, both workers crouched with both hands on the rail
- 10 - the bronze slab's roof: helipad (Rooftops), the davit pair at the edge, the cradle part way down
- 11 - the granite slab from 80 m: the yellow cradle and its davits

- 12 - a glass infill tower: Rooftops' BMU on the roof, its cradle live under the jib, stopped over the setback roof (`EYE=2222.9,165,208.8,45,-8`, city)

Frame cost at the black twins EYE: 2.68 M -> 2.72 M triangles, 1,406 -> 1,446 draws (two cradles with crews live).

Merged with main (build 359 era, 2026-10-06), re-shot:
- 02_after_black_twins_noon_merged - the black twins' cradle mid-facade from the air (EYE=2291.2,69.6,204.0,18.4,7.2, GONDOLA_T=1000)
- 10_roof_davits_and_drop_merged - the bronze slab's roof, davits, cradle part way down (gondola_shot.gd VIEW=roof)
- 13_cradle_mid_facade_from_the_street - from the pavement below the black twins (EYE_AGL=1 EYE=2268,1.8,200,-12,58, fov 60)
