# shots/rc5-taco-truck-night

New reference camera `taco_truck_night` (tools/refcams/cameras_w8.json): BIRRIA LA CHAPARRITA at the
kerb on a midtown block (truck at x 703.4, z -113.5 on seed 1337), 23:00 clear, eye level in its
queue. opengl3 refcam stills (the Compatibility renderer), before = `RC5_TACO=0`.

- `01_before_taco_truck_night.jpg` / `02_after_taco_truck_night.jpg` - the camera, before / after.
- `03_before_crop_window.jpg` / `04_after_crop_window.jpg` - the menu box and window, cropped.
- `05_forwardplus_stand_before_after.jpg` - Forward+ (lavapipe), the truck alone
  (`tools/glshot/vendor_shot.gd NIGHT=1`): top RC5_TACO=0 (menu blooming white), bottom after
  (readable menu, steam off the stack, clearance lamps).
- `06_found_truck_in_bus_zone_before.jpg` - the first framing: a truck parked in a BUS ZONE on its
  red kerb, empty window and queue (the bug the bus-stop rule fixes).
- `07_found_truck_in_bike_lane_before.jpg` - the first site: a truck parked in a protected bike
  lane among the delineator posts (the bug the bike-lane rule fixes).
