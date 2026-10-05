# shots/service-vehicles

Stills for the service vehicles (branch `wt/service-vehicles`, HANDOFF 9bs). All opengl3
(Compatibility) through `tools/glshot/still_shot.gd` / `car_shot.gd`, not the Mac's Forward+;
1600x900, 10:00, in the suburb west of downtown (`--spawn=-190,22,-90,-5 --hour=10`), staged with
`SERVICE=<scene>` (`ServiceFleet.stage_for_shot()`).

| file | what |
|------|------|
| `garbage.jpg` | `SERVICE=garbage`: the side-loader garbage truck at a house's carts, the black cart halfway up in its arm; the blue and green it has not taken stand in the gutter |
| `garbage_before.jpg` | the same camera with `SERVICE_VEHICLES=0` (no carts, no service vehicles): the before |
| `sweeper.jpg` | `SERVICE=sweeper`: the street sweeper running down the gutter of a street swept today (nothing parked along it), gutter broom down |
| `tow.jpg` | `SERVICE=tow`: the rollback tow truck with a burnt-out wreck on its bed |
| `ice_cream.jpg` | `SERVICE=ice_cream`: the ice-cream truck standing at the kerb, menu boards, awning, cone sign, flashers |
| `closeups.jpg` | `car_shot.gd SERVICE_WORK=0.55/0.7 --each=19,20,21,22,23`: the bodies alone at work - garbage truck mid-lift, sweeper with its dust, tow bed slid back and tilted, ice-cream truck, garbage truck side, delivery van (car_shot's own grey paint, no liveries) |

## Wave 2 (after merging fleet/base; opengl3 stills, suburb bookmark `--spawn=-190,22,-90,-5 --hour=10`)
- `10_wave2_before_suburb_1000.jpg` - SERVICE_VEHICLES=0, the garbage still's EYE: no carts, no truck.
- `11_wave2_garbage_lift_1000.jpg` - SERVICE=garbage: the arm mid-lift, the blue and green carts at the kerb.
- `12_wave2_sweeper_1000.jpg` - SERVICE=sweeper: brooms down in the gutter.
- `13_wave2_closeups_schoolbus_and_service_types_19_24.jpg` - car_shot.gd --each=19..24 (SERVICE_WORK=0.6): the school bus (19) beside the service vehicles, now body types 20-24.
- `14_wave2_tow_carrying_wreck_1000.jpg` - SERVICE=tow: a burnt-out wreck on the rollback's bed.
- `15_wave2_ice_cream_standing_1000.jpg` - SERVICE=ice_cream: standing at the kerb.
- `16_wave2_delivery_hazards_1000.jpg` - SERVICE=delivery: double-parked with its hazards on.

Frame cost (tools/geo_count.gd, opengl3, 800x600, same spawn): SERVICE_VEHICLES=0 3.586 M tris / 2,695 draws -> on 3.717 M / 2,702 (+3.7 %).
- `17_wave2_closeup_fullres_t20..t24_*.jpg` - the same close-ups at full 1280x720 (the composite in 13 is downscaled to 640x360 tiles). Bodies are Blender-built by tools/make_service_vehicles.py on make_big_vehicles / make_road_cars (loft, booleans, raycast parts, slots, far twin), 22-29k tris each; SERVICE_WORK=0.6, opengl3.

## Body rebuild (lead's review; tools/make_big_vehicles.py cab_hardware(), make_service_vehicles.py)
- `18_rebuild_<type>_<view>_before_left_after_right.jpg` - in game (car_shot.gd, opengl3, SERVICE_WORK=0.6): box truck, garbage, sweeper, tow; front 3/4 and rear 3/4; the committed models on the left, the rebuild on the right.
- `18_rebuild_blender_<type>_front3_{before,after}.jpg` - the generators' own Cycles previews (studio light), before and after.
