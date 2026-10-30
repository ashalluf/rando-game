# Oil islands stills (wt/oil-islands)

opengl3 (Compatibility) stills via tools/glshot/still_shot.gd, 1280x720, clear weather.
Shore camera: (3950, 5, 6300) on the Long Beach waterline looking south; air: (3950, 160, 6420).

- 01 / 02 - before / after, from the Long Beach shore at noon (OIL_ISLANDS=0 / on)
- 03 / 04 - before / after from the air at 17:30
- 05 - the shore at dusk (18:36)
- 06 - the shore at night (21:30): gelled floods on the towers, wall pools, the falls lit
- 07 - the air at night
- 08 - Kestrel Island from the water by the falls, noon (detailed copy)
- 09 - Kestrel from the air at 15:00 (detailed copy; far copies of the other two behind)
- 10 / 11 - the same two at night

Frame cost (GEO, shore camera, noon): before 696,802 tris / 221 draws; after 727,098 / 231.

Final set (after the screen reveals and lit slots, the interior works and the boulders round the falls):

- 12 - Kestrel from the water by the falls, noon
- 13 - Kestrel from the air, 15:00
- 14 - dusk (18:24) from 30 m up beside the island: the floods coming on
- 15 / 16 - the falls and the air at night (21:30)

Close camera frame cost (GEO, 12): 1,464,758 tris / 263 draws (the city's FULL chunks round a
spawn on the island included). Gate: SHARDS=3 tests/headless_check.sh, 2,696 checks, 0 failed.
