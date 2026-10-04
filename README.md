# Car lights (wt/carlight) - before / after stills

All at 22:00, clear. "before" = base commit 28105b5 (city) or `NOLIGHTS=1` (small scene: the lamp
mesh alone, what the web and Compatibility draw); "after" = wt/carlight.

| file | what |
|---|---|
| street_before.jpg / street_after.jpg | Downtown pavement, Flower at Olympic (opengl3, `still_shot.gd --spawn=2372,840,-35,0,1.6 HIDE=Visual`, after with `CAR_LIGHTS=1`). The parked car at the kerb is dark now. |
| queue_before.jpg / queue_after.jpg | A queue at a red, from the pavement behind it (opengl3, `STREET=queue STREET_EYE=1`, same frame). After: brake lamps on the stopped cars with a red wash on the road, real headlight spots (forced on for opengl3) lighting the cars ahead; the parked white car on the left is dark. |
| wall_chase_before.jpg / wall_chase_after.jpg | The player's car facing a brick wall (Forward+, lavapipe, `tools/glshot/car_light_shot.gd`): its shadowed beam with the low-beam cut-off on the wall, the pickup's shadow, an oncoming traffic car's soft cone on the road. |
| wall_top_before.jpg / wall_top_after.jpg | The same from above: both beams on the road. |
| wall_rear_before.jpg / wall_rear_after.jpg | Behind the player's car on the brake: brake lamps, the red wash behind, the red glow light. |
