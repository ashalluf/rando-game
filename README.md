# shots/rc5-rail-crossing

The new wave-8 refcam `rail_crossing` (tools/refcams/cameras_w8.json): River Blvd at Harbor Blvd, 17:30 clear, from the first car of the southbound queue as a Coral Line train crosses.

- 01_before_rail_crossing.jpg - main (9edd6b1e) + the camera row only.
- 02_after_rail_crossing.jpg - wt/rc5-rail-crossing: catenary as ribbons, red flashers with glows, tinted LRV glass with passengers, crossbuck legend.
- 03/04 - before / after crop: the train and the overhead wires (dashes -> continuous lines; tan window boards -> tinted glass with people).
- 05/06 - before / after crop: our gate's flasher (AgX-white disc -> held red with a glow).
- 02 is the final build (7a267f00: flasher lens energy 1.5, the glow carries the light).
- 07_final_crop_gate.jpg - the final gate, arm lamps and train, 2x.
- 08_ten_cameras_off_vs_on.jpg - the ten original refcams, RC5_RAIL_CROSSING=0 (top) vs on: street_noon, street_night and freeway flagged only by live traffic placement.

Numbers (opengl3 refcam rail_crossing, 1280x720): before p50 52, 6,907,097 tris, 3,829 draws; final p50 48, 6,872,328 tris, 3,817 draws. Gate: SHARDS=3 passed, 6187 checks.
