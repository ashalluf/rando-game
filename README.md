# shots/rc2-airport (wave 5 refcam2: the airport apron from 25 m, noon, clear)

New reference camera `airport_apron` (tools/refcams/cameras_w5.json): eye (-410, 25 m over the
ground, 815), yaw 16, pitch -15, fov 55, a landed airliner taxiing to stand 16 (`air: taxi`).
"before" = this branch with `AIRPORT_APRON=0` (main's look); "after" = the branch.

- 01_before_airport_apron.jpg / 02_after_airport_apron.jpg - the refcam (opengl3).
- 03/04 - a stand at eye level (block_shot, opengl3): the lines, red envelopes, borders.
- 05/06 - the concourse at eye level: glass that shows its lit hall by day, the lines back.
- 07/08 - the airliner alone on Forward+ (lavapipe, tools/airport_apron/jet_shot.gd): title,
  dark fan face, seams.
- 09_after_title_closeup.jpg - the title up close (opengl3).
