# lod-pops stills (wave 5)

- `01_before_car_swap_29-31m_forward.jpg` - Forward+ (lavapipe), a parked pickup at 29 / 30 / 31 m:
  its near body cuts to the far twin at 30 m (the bumper, tail lamp and wheels jump).
- `02_after_car_dissolve_29-31m_forward.jpg` - the same with CarLodBlend: both bodies drawn
  opaque from 27 to 33 m, each pixel taken by one of them (screen door). No TAA in this probe, so
  the dither shows; the Mac's TAA turns it into a dissolve.
- `03_rejected_alpha_fade_on_cars_forward.jpg` - why cars do NOT use Godot's own range fade: it
  is an alpha blend and the car shows its underside and wheels through its paint.
- `04_drive_strip_late_full_chunk_f95-97_opengl3.jpg` - three consecutive frames of a drive strip
  (tools/lod_pops/pop_strip.gd): the block under the camera was still the LOD tier (black
  carriageway) until its FULL chunk arrived - a tool artifact (the strip started away from the
  load spawn; pass --spawn at the route's start), kept as an example of what pops.py finds.
