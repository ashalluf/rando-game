# Rando Game

A 3D open-world chaos sandbox in Godot 4.7.2. Overpowered player, unlimited guns, a seeded low-poly
city to wreck.

- `CLAUDE.md` — how the project is built and how to work in it (read first).
- `docs/GAME_PLAN.md` — roadmap, current state, decisions log.
- `docs/ASSETS.md` — asset sources and licenses.

**Play it:** install Godot 4.7.2, clone this repo, open Godot, Import `project.godot`, press Play.

**Check it headless:** `GODOT=/path/to/godot tests/headless_check.sh`

## Wave 2: on the merged tree (wt/roadside merged with fleet/base and main), opengl3 1280x720

- `merged_01_gas_noon.jpg` - the gas station at (-64.6, 519.2), `EYE=-93,3.2,505,-118,-6`, 12:00
- `merged_02_gas_night_2100.jpg` - the same at 21:00 (canopy soffit, lit fascia, LED prices, shop)
- `merged_03_gas_under_canopy_night.jpg` - under the canopy at night `-82,2.0,512,-100,-2`
- `merged_00_before_gas_site_ROADSIDE0_noon.jpg` - the same EYE with `ROADSIDE=0` (the old pad), the before
- `merged_04_drivethru_queue_noon.jpg` / `merged_05_drivethru_night_2100.jpg` - the drive-thru lane at (-64.6, 1624.6), `-56,8.8,1640,-8,-6`
- `merged_06_tyre_shop_noon.jpg` - LUCKY TIRE & WHEEL from the street, `-8,7.5,1632,72,-6`
- `merged_07_cup_stand_noon.jpg` / `merged_08_cup_stand_night_2100.jpg` - the giant-cup stand, `-100,4.5,1470,-104,6`
- `merged_09_coffee_shop_noon.jpg` / `merged_10_coffee_shop_night_2100.jpg` - the Googie coffee shop COMET, `-95,15.5,1895,-110,6`
- `merged_11_carwash_noon.jpg` / `merged_12_carwash_night_2100.jpg` - SUDS CITY car wash across the street, `-412,15,-412,170,-13`
- `merged_13_carwash_queue_lane.jpg` - its queue lane and pay canopy, `-444.6,11.6,-381,-165,-3`

Frame cost (still_shot GEO, the gas EYE at noon): ROADSIDE=0 5,123,285 tris / 2,686 draws; on 5,084,623 / 2,559.

After the lead's review (the queue's cars were grey static boxes, the side wall a flat slab):
- `merged_04b_drivethru_queue_noon_real_cars.jpg` - same EYE as 04: the queued cars are real parked Vehicles with a driver seated and brake lamps on; the lane and back walls have a tile wainscot, brand pilasters, the dining room's windows, wall packs, a kerb with bollards; a lit canopy over the order point
- `merged_05b_drivethru_night_2100_real_cars.jpg` - the same at 21:00 (brake lamps and their red wash on the lane)
