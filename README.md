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
