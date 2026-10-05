# airport-life stills (branch wt/airport-life, HANDOFF 9bq)

All opengl3 (Compatibility, the web/still path), 1280x720, `tools/glshot/still_shot.gd` with
`--nohud --quality=0`, rendered under Xvfb + llvmpipe:

```
OUT=<file>.png <env> xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
  --display-driver x11 --audio-driver Dummy --path . --script tools/glshot/still_shot.gd \
  --resolution 1280x720 -- --spawn=<x,z,yaw,pitch> --hour=<h> --nohud --quality=0
```

| file | what | env / spawn / hour |
|---|---|---|
| `airport_taxi.jpg` | an arrival taxiing east on the parallel taxiway, the concourse and the tower behind | `AIR=taxi AIR_DIST=72 AIR_SIDE=5 EYE=-470,3.5,815,-20,-3`, `--spawn=-480,840,0,0 --hour=10` |
| `airport_taxi_followme.jpg` | the same arrival seconds earlier: the follow-me car leading on the taxiway | `AIR_DIST=62`, same |
| `airport_pushback.jpg` | stand 15 pushing back: the bridge drawn in, the tug at the nose, the painted lead-in curves | `AIR=pushback AIR_DIST=34 AIR_SIDE=4 EYE=-418,9,818,-38,-7`, `--spawn=-420,820,0,0 --hour=10` |
| `airport_pushback_before.jpg` | the same view before (`AIRPORT_GROUND=0`): every stand static | same, `AIRPORT_GROUND=0` |
| `airport_apron_trains.jpg` | a baggage train on the service road behind the tails, the gate sets, a second train's tug | `AIR=apron AIR_DIST=58 EYE=-405,4.5,780,58,-5`, `--spawn=-420,800,0,0 --hour=10` |
| `airport_night_tower.jpg` | the field at 21:00 from the tower height: field lights, the floodlit stands, a jet on the taxiway | `AIR=taxi AIR_DIST=72 AIR_SIDE=5 EYE=-236,56,668,125,-16`, `--spawn=-300,700,0,0 --hour=21` |
