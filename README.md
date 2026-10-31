# night-flight stills

The city at night from 160-800 m (opengl3, 1280x720, `tools/glshot/still_shot.gd` DIFF=1, one load,
`/home/user/nf/shoot.sh` SHOTS). Before = main 4cc3173d, after = wt/night-flight (the airport
after-still predates the last beam change, e4354e0d).

| file | EYE (x,y,z,yaw,pitch@hour) |
|---|---|
| 01/02 basin from the front range | 420,330,-1180,-119,-9@22 |
| 03/04 over downtown, 400 m | 2300,400,1700,0,-22@21 |
| 05/06 the 110 and the 10 from the south | 2100,260,3700,0,-10@23 |
| 07/08 the airport, 180 m | 600,180,780,90,-12@22 |
| 09/10 the port, 300 m | 3060,300,5300,180,-22@1 |
| 11/12 midtown, 160 m | 1200,160,700,60,-24@0.5 |
| 13/14 the basin, 800 m | 1900,800,2900,-8,-24@22 |
| 15/16 downtown in rain | 2300,400,1700,0,-22@23 rain |
| 17 crop: junction squares (left before, right after) | from 11/12 |
| 18 crop: the 110's light streams (left before, right after) | from 13/14 |

## Wave 4 set (2026-10-31): downtown and midtown at 150, 400 and 800 m, 22:00

opengl3 1280x720, `still_shot.gd` DIFF=1, one load each; before = the same build with
`NIGHT_FLIGHT=0` (every shader as on main), after = wt/night-flight merged with main e5bb9e4.
Cameras (EYE x,y,z,yaw,pitch, all looking grid-north, `--hour=22`):

| files | camera |
|---|---|
| 19/20 downtown 150 m | 2800,150,600,0,-30 |
| 21/22 downtown 400 m | 2800,400,1100,0,-26 |
| 23/24 downtown 800 m | 2800,800,1900,0,-25 |
| 25/26 midtown 150 m | 1000,150,1100,0,-30 |
| 27/28 midtown 400 m | 1000,400,1500,0,-26 |
| 29/30 midtown 800 m | 1000,800,2200,0,-25 |
| 31 crop: the 110 from midtown 800 m (left before, right after) | from 29/30 |

Frame cost (GEO): identical triangles, draws and objects in five of six; midtown 150 m +2.6k
triangles (0.1 %, the crowd's run-to-run noise; DIFF hides people but not their LOD picks).
