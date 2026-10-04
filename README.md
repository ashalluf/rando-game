# shots/ocean - the Pacific and the beach (branch wt/ocean, HANDOFF 9au)

Before = main at 6fb4fad, after = wt/ocean. opengl3 (Compatibility) under Xvfb + llvmpipe,
960x540, `tools/glshot/still_shot.gd`, `--nohud --quality=0`, FOV 60 unless noted. Lighting in
these stills is the Compatibility renderer's; judge shapes and materials, not exposure.

| file | view |
|------|------|
| esplanade_bluff_noon_* | `EYE=-458,15.5,3380,100,-14`, 12:00, the Esplanade bluff looking down at the surf |
| esplanade_bluff_zoom_* | `-458,15.5,3380,100,-9`, FOV 28, 12:00, the surf lines from the bluff |
| beach_noon_waterline_* | `-732,2.1,800,105,-4`, 12:00, standing 6 m up the beach at z 800. BEFORE: the camera stood in a street-end gap in the sand, in the sea plane (fixed: the sand now covers the strip) |
| golden_hour_18_* | `-732,2.1,800,92,-1`, `--hour=18` (sun on the horizon due west) |
| golden_hour_17_6_* | same view at 17.6, the glitter path and backlit faces |
| pier_night_* | `-712,2.2,1000,130,-2`, 21.5, the Manhattan pier's lamps mirrored in the water |
| storm_beach_* | beach view, `--weather=storm`, 13:00 |
| storm_bluff_* | bluff view, `--weather=storm`, 13:00 |

Command (one load per weather; SHOTS adds the other views):

    OUT=clear.png FOV=60 FRAMES=45 SHOT_FRAMES=30 EYE=-458,15.5,3380,100,-14 \
    SHOTS="-732,2.1,800,105,-4@12@60;-732,2.1,800,92,-1@18@60;-712,2.2,1000,130,-2@21.5@60;-732,2.1,800,92,-1@17.6@60;-458,15.5,3380,100,-9@12@28" \
    xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
    --audio-driver Dummy --path . --script tools/glshot/still_shot.gd --resolution 960x540 \
    -- --spawn=-458,3380,100,-14 --hour=12 --nohud --quality=0 --weather=clear

Frame cost, `tools/geo_count.gd` (opengl3 960x540, 12:00 clear), before -> after:
- beach z 800 (`--spawn=-732,800,105,-4`): 543,392 tris / 427 draws -> 544,032 / 431
- Esplanade bluff (`--spawn=-458,3380,100,-14,15`): 1,445,798 / 932 -> 1,446,070 / 937
- Manhattan pier (`--spawn=-712,1000,130,-2`): 815,832 / 1,893 -> 816,472 / 1,896

The spray (shader-driven quads puffing at the break line) is barely visible in a 1 fps still:
judge it in motion on the Mac.
