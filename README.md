# Stills: utility-poles (wt/utility-poles)

opengl3 (Compatibility) stills, 1280x720. The street is a suburban block (block 21,32, the line on
road 32): `EYE=1997.7,6.5,4240.4,157,12 --hour=15` on tools/glshot/still_shot.gd.

- `01_before_street_1500.jpg` - before (UTILITY_POLES=0): a cylinder pole, box crossarms, a grey
  drum, 3.5 cm square box cables.
- `02_after_street_1500.jpg` - after, same camera: tapered wooden pole, crossarm on its face with
  braces and porcelain pins, the transformer can with cutout and arrester, comm bundles lower
  down, ribbon wires at real radius, service drops fanning out to the houses on both sides of the
  street (meter and mast on the red house).
- `03_after_pole_head_closeup.jpg` - the head close up: pins, braces, the can, the spool rack,
  the comm bundles' clamps.
- `04_after_junction_span.jpg` - the long span over a junction (sag grows with span length).
- `05_after_street_night_2130.jpg` - 21:30: the line against the night sky.
- `06_kit_alone_run.jpg` .. `09_kit_service_drop_mast.jpg` - tools/utility_poles/pole_shot.gd
  (the kit alone, seconds a shot): a run of three poles, the transformer close up, a cobra-head
  light and the comm bundles with a splice case, a house's mast with its weatherhead and drop.
- `10_debug_the_wire_width_bug_before_the_fix.jpg` - WIRE_DEBUG: on Compatibility the
  projection's [1][1] is negative, which made every wire a 0.5 m band; fixed with abs().
- `11_after_beachtown_run_end_guy_1500.jpg` - a line in the beach town ending at the freeway
  corridor: the down guy with its yellow guard (`EYE=-540.1,1.9,-181.1,67,14`).
- `12_after_beachtown_dusk_1818.jpg` - the same street at 18:18 under the freeway: the wires as
  dark hairlines against the dusk sky.
- `13_after_suburb_from_40m.jpg` - the suburb from 40 m up: poles and wires are near a pixel
  there (the wires fade out by 340 m).
- `06_kit_alone_run.jpg` was re-shot with the final wire shader (coverage gamma 0.75).

Frame cost at the across-street bookmark (GEO, opengl3 1280x720, whole frame):
UTILITY_POLES=0 4,953,347 tris / 2,080 draws -> 4,897,857 / 2,104.
