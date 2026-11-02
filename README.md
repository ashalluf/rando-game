# shots/rc3-broadway-night

The new wave-6 reference camera `broadway_night` (tools/refcams/cameras_w6.json): Broadway's theatre
district at 22:00, clear, eye level in the middle of Broadway at the 6th St crossing, looking south.
opengl3 (Compatibility) stills from tools/refcams/refcams.py, 1280x720. Before = origin/main 484a7897.

First batch (draft "after": the fire stair and the painted name were reworked after it):
- 01_before_broadway_night_2200.jpg - main: six solid white searchlight rods, the Empress' blade sign half spelt, its marquee hidden behind a street tree.
- 02_after_broadway_night_2200_draft.jpg - soft searchlight haze, the sign held lit, the marquee and its board in view (no tree on a palace frontage), brighter marquees.
- 03_before_empress_side_wall.jpg - main, the same load from 2999,1.7,190 (yaw 200): the Empress' auditorium side wall, a pale blank slab glowing blue-white.
- 04_after_empress_side_wall_draft.jpg - brick-red with pilasters, the palace's painted name, exit doors (the draft's fire stair read as a black Z; fixed in the final).

Final (branch head after merging origin/main):
- 05_after_broadway_night_2200_final.jpg - the camera with every fix: soft beams, EMPRESS / LA PALOMA held lit, the Empress marquee and board in view, marquees brighter.
- 06_after_empress_side_wall_final.jpg - brick auditorium: pilasters, a painted name (curved letters partly drop out - reads as worn paint; not fixed), exit doors, a switchback fire stair of thin stringers.
- 07_ten_refcams_main_vs_branch.jpg - the ten original cameras, main over branch: 3 flagged (street_noon, street_night, freeway), each by traffic only (a bus / truck elsewhere); street_night's searchlight glare is also softer.
- 08_before_over_after_broadway_night.jpg - before (top) over after (bottom).

Numbers (refcams, opengl3 1280x720): broadway_night p5/p50/p95 4/30/171 -> 5/33/189; triangles 6.07 M -> 6.01 M, draws 3018 -> 3031.
Not verified on Forward+: lavapipe OOM-killed (13.4 GB) on even three downtown blocks.
