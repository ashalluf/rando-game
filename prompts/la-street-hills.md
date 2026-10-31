# Wave 4 task: la-street-hills (kind: world)

Branch `wt/la-street-hills`, stills on `shots/la-street-hills`.

Owner, 2026-10-31: "capture the proper vertical recreations of streets - not every street in Los Angeles is flat. It doesn't need to be 1:1 copies, just throw stuff in there to give it the Los Angeles feel and vibe. Make the geography as realistic as possible."

Today the city's ground is `MacroMap._relief_natural()`: ONE seeded noise up to `relief_height` 22 m, squared, so it reads as gentle swells. Downtown is held dead flat inside 320 m, and every landmark flattens a disc. Real LA is a flat basin broken by named hills with steep street grids running straight up them. Give the city those hills, in roughly their real places relative to the 1:1 downtown (`DowntownReal.game_xz()`, compressed where the map is compressed, like the masjid and the ballpark):

- **Bunker Hill**: downtown's west side stands ~25-30 m over Hill St / Broadway. The real grid is pinned, so this must be a terrace in the relief that the 1:1 towers and civic sites sit on. Its east face is the steep drop toward Hill St: a stair or funicular-style incline form (invented name, original model) and short steep blocks (the real 1st-4th St climbs).
- **Echo Park / Silver Lake / Elysian Heights**, north-west of downtown toward the ballpark ravine: steep residential grids on knolls, streets at 15-30 % grade running straight up the fall line, public stair streets between blocks where a street is too steep (the real hillside stairways), houses stepping down the slopes on stilts / tall foundations, retaining walls along the kerbs.
- **Mount Washington / El Sereno / Boyle Heights**-style bluffs east of the river, and the **San Pedro** bluffs over the port: a few steep streets and a bluff edge with a view.
- **Baldwin Hills** already exists (the oil field): blend its edges into rolling streets rather than a mesa.
- The rest of the basin stays the flat plain it really is (midtown, the Westside, the south): do not raise the noise everywhere.

Rules: hills are a DATA TABLE (centre, footprint, height, steepness, grade cap per street) like the replica areas, folded into `_relief_natural()` after the noise; hashes, never new rolls on any existing rng; a street's own grade comes from the relief along it (check the street slabs, kerbs, parking, crosswalks, traffic placement, pedestrians, the light rail, freight rail, freeways' `_clear_ground()`, LaRiver's terrace, Hospital/School/etc. `_suitable()` level tests, LotFill's planar quads, HouseKit / Apartments on slopes, Building plinths on a slope, the far city plates and the horizon bake all still agree). Buildings on a steep lot need their downhill foundation shown (plinth to the low side), not floating corners. Every place that holds itself level (sites, landmarks) must keep doing so. Measure the grades you made (a probe printing each hill's steepest street) and keep drivable streets under ~30 %; steeper links become stairs and are closed to cars via `CityPlan.road_open()`.

`LA_HILLS=0` in the environment is the A/B (the city exactly as before). Stills from the street looking up and down a hill street, from the stairs, and aerial at golden hour; checks in `tests/la_street_hills_checks.gd`. Coordinate nothing with other sessions; if a merge with main conflicts in macro_map.gd, keep both.

If `origin/wt/la-street-hills` already exists, CONTINUE it: check it out and merge origin/main into it. Same for `shots/la-street-hills`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
