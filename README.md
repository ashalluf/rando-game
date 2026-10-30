# shots/car-cabins

Real car interiors and hinged doors for the player's car (wave 3 task `car-cabins`, branch
`wt/car-cabins`). opengl3 (Compatibility) stills: the Mac draws Forward+.

- `01_before_parked_sedan_noon.jpg` - CAR_CABINS=0, the same frame as 02 (Flower at Olympic, 13:00).
- `02_after_driver_door_open_noon.jpg` - getting in: the driver's door cut out of the body and swung
  open, the real cabin behind it. (The hero hovers here: the still was held at the spawn's height;
  13 and 14 are the fixed ones.)
- `03_after_inside_through_passenger_door_noon.jpg` - the player at the wheel, seen through the open
  passenger door.
- `04_after_driver_door_open_night.jpg` - the same at 21:00.
- `05`-`08` - car_shot.gd close-ups: the sedan's door, the aperture (black and oxblood leather), every
  supported body with its driver's door open (sedan, crossover, pickup, van, hatchback, SUV, minivan,
  beater - the beater's odd green door is its existing wear).
- `09`-`12` - the cabin: dash, binnacle and lit cluster, navigation screen, wheel, seats; the traced
  player at the real wheel through the windscreen; the SUV at night (tan leather).

- `13_getting_in_hatchback_noon.jpg`, `14_getting_in_hatchback_night.jpg` - the hero at the open
  driver's door of a parked hatchback (CABIN_STAGE=0.85 on still_shot.gd), noon and 21:00.

Frame cost (same frame, 01 vs 02, Vehicle category in still_shot SPLIT): 628k -> 682k triangles,
98 -> 158 draws (two parked cars had rigs then; now one at a time).
Gate on the final merge (1aa28df3): 3,508 checks, 1 fail (memory_audit's TreeFire record count, an
order-dependent flake; it passes alone with the cabins on and off). car_shot GEO, one sedan at the
chase camera: 40 -> 54 draws, 184k -> 233k triangles.
