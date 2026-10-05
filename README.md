# far-corners stills (G7: cut-corner geometry on the far boxes)

All opengl3 (Compatibility renderer), so light and colour are not the Mac's; judge the shapes.

- `01_near_buildings_200m.jpg` - six downtown-style buildings with every corner cut (`CHAMFER=1`), the near Building, 200 m off (tools/glshot/far_building_shot.gd).
- `02_before_far_boxes_200m.jpg` - the same buildings as the far tiers drew them before: plain boxes, the cut bay painted as a pier (`FAR_CORNERS=0`).
- `03_after_far_boxes_cut_corners_200m.jpg` - after: the far boxes carry the near octagonal outline, cut faces lit by their own normals.

City stills, opengl3 1280x720, `still_shot.gd DIFF=1` (time, clock and signals held; people and cars hidden), `FAR_CORNERS=0` before / `1` after, one load each, from the south-west at 160 m up (EYE 1200,160,2900 looking at downtown), 13:00 unless named:

- `04/05` - the skyline from ~3 km, wide (frame 4.01 M -> 4.06 M triangles, 2,222 draws both).
- `06/07` - the same at 14 degrees (telephoto): tower corners cut, the old bright painted piers gone (2.27 M -> 2.32 M, 559 draws both).
- `08/09` - downtown from ~1.2 km (EYE 2150,120,1350), 22 degrees: the cut corners on the LOD ring and the near far city read clearly (1.16 M -> 1.18 M, 180 draws both).
- `10/11` - `06/07` at 17:36, low sun across the cut faces.
- `12` - crop of `06/07` scaled x3, before on top, after below.
- `13` - crop of `08/09` scaled x3, before on top, after below.
