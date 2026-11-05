# shots/explosions-4 (fleet wave 5, "make the explosions EXTREMELY AAA")

Batch 1 (first look, opengl3 = the Compatibility renderer, small street `tools/explosions_2/blast_room_shot.gd`, a rocket-sized blast of radius 9 m seen from 34 m):

- `01_before_rocket_day_strip.jpg` / `02_after_rocket_day_strip.jpg` - t = 0.03, 0.1, 0.3, 0.6, 1, 2, 4, 8, 14 s. Before: a salmon cotton ball, then a string of separate grey card balls. After: a fireball with white-hot crowns and black soot creases that lives on as a volumetric MUSHROOM (rolling vortex-ring cap over a wavering stem), cooling from fire to black soot to grey-brown smoke.
- `03_before_car_night_strip.jpg` / `04_after_car_night_strip_wip.jpg` - a car's own explosion at night. After: burning fuel pool left on the road for 15-25 s. (WIP: the night smoke is still unlit - next fix.)
- `05_before/after_rocket_day_t*.jpg` - single frames at 0.3, 1 and 4 s.

Batch 2 (Forward+, lavapipe - the Mac's renderer - and a car in daylight):

- `06_wip_car_night_forward_overlit.jpg` - the first pass on Forward+: the fires lit the whole mushroom orange-tan (fixed).
- `07_after_car_night_forward_strip.jpg` - t = 0.4, 1, 2, 4, 8 s: fireball with soot creases and secondary pops at its foot, then a dark mushroom silhouette lit from below by the burning fuel pool.
- `08_after_car_day_strip.jpg` - opengl3, t = 0.3 .. 5 s: fuel fireball, two secondary pops at the foot (1.0, 1.5 s), the car tossed through it, the mushroom, the pool burning on the road.

## Batch 3 (opengl3, noon)
- `09_after_gas_pump_strip.jpg` - a petrol pump's vapour blast (GAS=1) at 0.1 / 0.5 / 2 / 5 s.
- `10_after_rocket_5m_strip.jpg` - a rocket from 5 m (DIST=5) at 0.1 / 0.5 / 2 / 6 s: inside the
  fireball, then the stem's foot; the cap is above the frame.
- `11_after_rocket_60m_strip.jpg` - the same from 60 m: ball, roll-up, the mushroom standing.
- `12_after_wreck_smoke_4_9_16s.jpg` - a car blast's wreck at 4 / 9 / 16 s with the continuous
  smoke column (high up it still beads in stills: the harness emits in ~1 s bursts).

## Batch 4 (the lead's notes on batch 3)
- `13_mushroom_light_old2s_new2s_new4s.jpg` - opengl3, 60 m, zoomed: the old flat grey cap, then
  the new one lit like a cloud (sunlit shoulders, dark underside, sooty core, turreted edges).
- `14_mushroom_forward_2s_5s.jpg` - the same on Forward+ (lavapipe). The grain is the march's
  jitter, which TAA can't resolve at the harness's ~1 frame a second.
- `15_gas_first_frames_0.05_0.1_0.15_0.5.jpg` - the pump's gas ball: structure from ~0.1 s.
- `16_rocket_60m_new_0.5_2_4_8_old_2_6.jpg` - top and bottom-left new, bottom middle / right old.

## Batch 5
- `17_golden_car_0.3_1.5_4_9.jpg` - a car's blast at golden hour (GOLDEN=1, opengl3): the flash,
  the fireball rolling, the sooty brown mushroom catching the low sun, the wreck's column.
- `18_night_rocket_glow_old_top_new_bottom_1_2.5_5.jpg` - the flash's glow rising with the cap and
  lingering after dark (bottom) against before (top); the room's night sky is pure black (no city
  light dome), so the mushroom's silhouette shows less than in the game.

## Batch 6 (round 3)
- `19_city_night_car_0.3_2_6.jpg` - a car's blast in the real city at 22:00 (fx_shot.gd, opengl3,
  midtown): the flash lighting the street, the rolling mushroom lit orange from below, the dark
  plume over the burning wreck.
- `20_dither_old2_old4_new2_new4.jpg` - the screen door: left pair before, right pair with the march
  backing up and refining in dense smoke (60 m, 2 s and 4 s).
- `21_web_top_desktop_bottom_0.3_2_5.jpg` - the web fallback (WEB=1, cards: the volume is desktop
  only) over the desktop fourth pass, the same rocket at 0.3 / 2 / 5 s.

Frame cost with the blast in view (blast_room_shot GEO, opengl3, 1280x720), fourth pass vs
EXPLOSIONS_4=0: 0.3 s 409 / 411 draws, 505k / 506k tris; 2 s 402 / 406, 504.5k / 504.7k;
5 s 378 / 380, 502.0k / 502.0k. The volume's cost is ALU per covered pixel (40 steps, up to 16
refined), not geometry.

22: Forward+ car blast, top before / bottom after the depth heat and soot shell (0.3, 0.8, 3 s;
the shell's onset was moved later after this sheet). 23: opengl3, final numbers, 0.3 / 0.55 /
0.8 s: no crosshatch, fire then soot with fire in its gaps.

Round 4 (opengl3, the room): 24-26 the five-case strips before (top) / after (bottom) for gas
(0.3, 1, 2.5, 5, 8 s), rocket at 60 m and a chain of three cars (0.3, 1, 2, 3.5, 6 s); 27 the dust
at 2.5 s, before left / after right (gas, chain, rocket): one rolling lit front instead of three
layers standing up into a flat beige wall. 28 / 29 the golden-hour car at 20 m and the night car,
before. The daylight plume pales with age (value4): sunlit billows lighter, folds darker.

Round 12/13: 69 the debris smoke ribbons before (long straight grey wires across the sky) / after
(short broken puffs, under 8 m each, widening and fading with age). 70 the heavier masonry burst on
a facade at 30 m and 14 m (slabs, pale masonry dust, a rubble heap at the foot). 71 the 14 m view
at 0.6 s full size. 72 the 150 m aerial on Forward+ (lavapipe): 0.15, 0.6, 2 s.

## Wave 8 (resumed session): rounds 13-16
- `73_r13_air_150m_ground_flash_...` - from 150 m up: before (top) / after (bottom) the ground flash
  under the burst (0.05, 0.15, 0.4, 2 s), crops round the blast.
- `74_r14_5m_...` - the rocket from 5 m (opengl3) at 0.1 / 0.4 / 1.2 s: before (top) the trails' hard
  arcs and the shock ring + ground flash painting the whole road cream; after (bottom) soft torn
  trails, the ring and flash only from the air, the dust roll on a grey road.
- `75_r14_forward_plus_5m_...` - the same on Forward+ (lavapipe), 0.4 / 1.2 s: the pale horizon line
  and the big translucent arcs are gone.
- `76_r15_car_noon_...`, `77_r15_gas_night_...` - fuel and gas balls burn longer (top before).
- `78_r16_scorch_...` - the crater's soot: top row from 22 m up at 10 s (before left: a black
  spiky star; after right: a dark core with thinning streaks); bottom Forward+ at 5 m (before 1.2 s
  left, after 8 s right).
- `79_r17_chain_golden_...` - a three-car chain at golden hour (2, 3.5, 6 s): before (top) the third
  car's fireball fell back to cards (round orange balls); after (bottom) it is a volume.
- `80_r18_car_9m_...` - a car's blast from 9 m (1.2 and 3 s): before (top) the pool light's white hot
  spot on the road and flames all one height; after (bottom) the light up in the flames, softer,
  tongues of their own heights. The car body and fuse timing are random per run.
- `81_r18_before_flat_red_wedge_card_5m.jpg` - what the wedge debris looked like close up before
  round 18 (a flat red-brown card); it is a seven-sided broken lump now.

## Round 19 (the lead's review of 79)
- `82_r19_chain_golden_30m_...` - the same chain at golden hour, 1.6 / 2.4 / 2.8 / 3.6 / 6 s, before
  (top) / after (bottom): each chain car and pop flashes a hot white-yellow core before it browns;
  the burning fuel along the road is puddles of different sizes and heights.
- `84_r19_chain_crop_...` - crops of the fireballs at 1.6 / 2.4 / 2.8 s (fuse timing is random per run).
- `83_r19_fuel_16m_...` - a car's fuel from 16 m at 3 and 7 s: before (top) the trail's even fence of
  tongues (stretched pools); after (bottom) a deep puddle burning high by the car, smaller ones
  further out with dry road between.
