# paving-aliasing stills

opengl3 (Compatibility), 1280x720, downtown 10:00-12:00, seed 1337. "before" = `PAVING_AA=0` or main.

The downtown "moire" was not texture aliasing: lot_ground.gdshader truncated its interpolated
paving kind (`int(kind)`), and an interpolated 3.0 reads 2.9999 on some pixel rows, so the red
forecourt pavers flipped to setts row by row (horizontal stripes at every distance, a hard
diagonal where the sign of the error flips per triangle).

- `01_before_city_forecourt_1000.jpg` / `02_after_city_forecourt_1000.jpg`: the forecourt of block (25,0), EYE 2700,1.7,20,180,-20, the city (DIFF=1)
- `03_before_city_plaza_1000.jpg`: same forecourt from 2630,1.7,100 looking east - the setts triangle and the row stripes
- `04/05`: the same forecourt in block_shot.tscn, before / after
- `06/07`: the same, lower pitch
- `08/09`: from (2630,100) in block_shot (the after camera stands in a podium column; the ground is clean)
- `10/11`: Hill St pavement looking south (slab joints box-filtered; the red frontage strip's stripes gone)
- `12`: crop of 10/11 - top before, bottom after
- `13/14`: from a car in the lane

## Wave 4 (texture fade, block_shot.tscn, PAVING_AA=0 before / on after, the merged main)
Laid paving textures (setts, pavers, bricks) now fade to their own last mip once a module is under
two pixels, on top of the rounded kind. 2 m and 20 m eyes over the forecourt at (2700, 20):
- `15/16`: eye 2 m, looking south - the row stripes and the setts wedge before, even red pavers after
- `17/18`: eye 20 m, looking down on the same forecourt
- `19/20`: eye 2 m at (2630, 100) looking east
