# shots/street-life-2: street errands (StreetErrands)

opengl3 stills, 1280x720, `--quality=0`, 13:00, downtown on Flower near Olympic
(`--spawn=2359.4,880,0,12,2`), staged with `ERRAND=...` on tools/glshot/still_shot.gd:

- `bus.jpg` - ERRAND=bus: line 159 standing at its stop, doors open, the queue at the shelter and one walking up to the front door.
- `car.jpg` - ERRAND=car: a walker at a parked taxi's open driver's door, getting in (the door's inner card faces the camera).
- `jay.jpg` - ERRAND=jay: a jaywalker running across mid-block with a bag, a car held up behind them.
- `shop.jpg` - ERRAND=shop: somebody at the coffee shop's door going in, somebody else just out with a bag.
- `deliver.jpg` - ERRAND=deliver: a box truck parked at the kerb, its driver wheeling a hand truck of boxes to the shop door.
- `before_errands_off.jpg` / `after_errands_on.jpg` - the same EYE (2394.32,1.90,815.26,82.49,-2.75) with STREET_ERRANDS=0 and on, no staging: 6,521,721 -> 6,519,195 tris, 3,304 -> 3,306 draws (flat).

## Wave 2 (after the revert and the fixes; opengl3 1280x720, `--quality=0`, 13:00, same spawn)

- `10_wave2_bus_queue_boarding_1300.jpg` - ERRAND=bus: line 159 at its stop on Flower, doors open, the queue walking up to the front door.
- `11_wave2_jaywalker_midstreet_1300.jpg` - ERRAND=jay ERRAND_FRAMES=1 ERRAND_PROGRESS=0.3 ERRAND_EYE_LAT=7 ERRAND_EYE_AHEAD=14: a jaywalker running across mid-block, the crossover braked in front of them.
- `12_wave2_shop_door_in_use_1300.jpg` - ERRAND=shop (ERRAND_IN 0.75, now the default): somebody at the cafe's door going in, somebody just out of the next door with a bag.

Frame cost (GEO, these stills): bus 5.94 M tris / 2,938 draws; jay 5.95 M / 2,731; shop 2.78 M / 1,567. The fixes add no geometry.
