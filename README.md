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
