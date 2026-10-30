# gi-review stills (fleet wave 3, branch wt/gi-review)

Forward+ under lavapipe (`tools/gi_review/gi_shot.tscn`, the FULL chunk round each eye, the city's
environment, the clock held at 12:00 clear, the player's auto exposure). Each image is a side-by-side
pair from ONE load: before (GI_REVIEW=0) | after. HIGH = SDFGI + volumetric fog; MEDIUM = no SDFGI.
12-13 are the Compatibility renderer (opengl3: the web and the stills), where only the contact quads act.

| file | what |
|---|---|
| 01 / 02 | a parked pickup on a sunny midtown avenue, HIGH / MEDIUM (under-car p10 27->34 / 57->41) |
| 03 | the tyres at MEDIUM, close: the contact quad grounds them |
| 04 / 05 | a downtown service alley in shade, HIGH (44->50, warmer off the brick) / MEDIUM |
| 06 / 07 | under the 110, HIGH (soffit 18->53 with the under-fill) / MEDIUM |
| 08 | the soffit fill tried at 0.22 (too bright, rejected) and 0.09 |
| 09 / 10 | Flower St storefronts, HIGH / MEDIUM |
| 11 | a wall foot and a car-park fence, HIGH |
| 12 / 13 | Compatibility: the same avenue, the cars on contact quads |
| 14 | the alley's SDFGI sweep: energy x1.0 bounce 0.5 against x1.3 bounce 0.9 |
| 15 | why the SDFGI cell stays 0.8 m: at 1.6 m the sunlit deck top leaks through the soffit |
