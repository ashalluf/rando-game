# shots/sunset-clouds - the Los Angeles sunset (branch wt/sunset-clouds)

Every image is BEFORE (left) / AFTER (right). Sky alone: `tools/sky/sky_shot.gd` (the city's
Environment + DayNight, no city), camera 2 m up, pitch 8, toward the sun (west, yaw 90, top row)
and away from it (east, yaw 270, bottom row), clear weather.

- 01-09 `forward_sky_<hhmm>`: Forward+ (lavapipe, the Mac's renderer: volumetric cumulus), every 15 min 17:30-19:30.
- 10-18 `compat_sky_<hhmm>`: Compatibility (opengl3: the web and the opengl3 stills; painted cumulus), same times.
- 19-27 `city_beach_<hhmm>`: the city from the beach at z 800 looking west over the Pacific (opengl3, `SUNSET_CLOUDS=0` vs on).
- 28-32 `city_hills_<hhmm>`: from 260 m over the front range looking south-west across the basin to the sea.
- 33 `noon_identical`: 12:00 on Forward+ with shader TIME held: 0 pixels differ.

What to look at: 18:00-18:06 cumulus bases lit hot gold-orange from below toward the sun with
violet-dark crowns, red crowns away from it; the deck going dark from the bottom up after; pink
cirrus afterglow at 18:12-18:15; the blue hour after 18:30. 19:00-19:30 is night in this game's
sun path (the sun is 15-22 degrees under), unchanged.
