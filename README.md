# Building damage stills (branch wt/building-damage)

opengl3 (Compatibility) via `tools/glshot/damage_shot.gd`, one building on a slab, damage dealt
through the real entry points (rounds as physics rays into BuildingDamage.bullet(), the rocket as
Explosion.blast()). Not the Mac's Forward+.

- storefront_before.jpg / storefront_after.jpg - shop windows shot up: crazed panes (spider web),
  panes gone (teeth in the frame, the shop open), scars on the wall above, glass on the pavement.
- storefront_night.jpg - the same after dark: lit shops through the broken glass, cracks lit.
- office_before.jpg / office_row_shot_out.jpg - a row of ribbon windows shot out on one floor.
- office_row_night_lit.jpg - the same at night (LIT=1: offices lit).
- brick_wall_before.jpg / brick_wall_rocket_hole.jpg - a rocket against a brick wall: the hole
  (traced break and burnt room), brick rim, soot plume, windows round it blown, glass below.
- brick_wall_rocket_hole_night.jpg - the hole at night, the room smouldering (NOFX=1).
- curtain_wall_blast.jpg - a blast on a curtain wall (taken before curtain walls stopped getting
  holes: now the blast only takes their glass, the rooms behind open).
