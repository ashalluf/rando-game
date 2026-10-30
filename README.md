# night-atmos stills (wave 3)

opengl3 (Compatibility) city stills at 21:30, `NIGHT_ATMOS=0` (before) vs on (after):
Flower St looking north (EYE 2359.4,1.8,880,0,4) and 5th St under the freeway (2045,1.7,2,60,6).

- 01/02 Flower St, rain: sodium haze in the canyon, globe halos, light cones under the lamps.
- 03/04 5th St underpass, rain: LED globe halos, the lens streak on the lamp looked at, car lamp glints.
- 05/06 Flower St, marine air: big soft sodium halos.
- 07/08 Flower St, clear: only the lens glint (dry air, by design).
- 09/10, 11/12 5th St, clear and marine.
- fwd_* : Forward+ (lavapipe) of the FULL blocks round Flower St (fwd_block_shot.tscn), when present.
- 13 Compatibility, the atmosphere kit alone (tools/night_atmos/atmos_shot.gd, haze 0.9): before top, after bottom.
- 14 Forward+ (lavapipe), same scene: before / after / after with volumetric fog on (the drawn cones step aside, halos stay).
  The city and block_shot no longer fit lavapipe on this 16 GB box (OOM-killed at ~12.8 GB during the plan), so the
  Forward+ city frame is unverified.
