# color-grade stills (G4: a grade tuned per hour)

All opengl3 (Compatibility renderer, the web's) at 1280x720 through `tools/glshot/still_shot.gd`,
`--weather=clear`, the default seed. "before" is `HOUR_GRADE=0` (the old single look LUT), "after"
is the per-hour grade (`HourGrade`). Same load, same camera, only the curve and saturation differ.

| file | what |
|---|---|
| 01 / 02 | downtown street (Flower at Olympic, looking north), 12:00 - crisper: firmer mids, cleaner blacks |
| 03 / 04 | same, 17:36 golden hour - the pink-mauve shadows go warm and golden |
| 05 / 06 | same, 18:18 blue hour - the magenta cast becomes a cool blue, lamps stay warm |
| 07 / 08 | same, 22:00 night - deeper blacks (p5 7 -> 3), less blue in the mids, no lavender |
| 09 / 10 | the hills from 260 m, 15:00 |
| 11 / 12 | hills, 17:36 golden hour |
| 13 / 14 | hills, 18:18 blue hour |
| 15 / 16 | hills, 22:00 night |

Luminance percentiles p5 / p50 / p95 (before -> after), street: noon 30/130/181 -> 24/133/186,
golden 23/65/139 -> 19/62/144, blue hour 8/38/117 -> 4/30/112, night 7/34/130 -> 3/24/129.
