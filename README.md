# chase-box-bug stills

The pale squares round the player's car's tail lamps (the chase camera), same frame, only
`shaders/car_lights.gdshader` swapped at runtime (tools/chase_box_bug/probe.gd, 16:00, 30 km/h up Flower St, opengl3):

- `01_before_chase_30kmh.jpg` - main's shader: a grey square round each tail lamp.
- `02_after_chase_30kmh.jpg` - the fix: gone.
- `03_before_above_after_below_crop.jpg` - the rear of the car, 3x, before (top) and after (bottom).

Cause: the lamps' halo quads (parts 6/7) are not collapsed by day and wrote only ALBEDO, so ALPHA
stayed 1 and the renderer added the fog colour over each whole quad. Fix: the coverage goes in
the alpha (shaders/additive_fog.gdshaderinc).
