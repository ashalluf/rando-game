# ground-shadow-contact stills (fleet wave 4)

opengl3 (Compatibility) block stills from tools/glshot/block_shot.tscn, noon, clear. "before" = origin/main
(or GROUND_CONTACT=0 for the contact quads), "after" = wt/ground-shadow-contact.

- 01 / 02: a LotFill raised planter on a 15 % slope (midtown, under the freeway). Before, the shrubs
  stood on the slope under each of them and the uphill ones hung in the air in front of the planter;
  after, the planter runs down to the paving and the shrubs stand in its soil.
- 03 / 04: a roadside pad's frontage planter on a slope: before, shrubs float over the soil (their
  shadows lie apart from them); after, rooted.
- 05 / 06 / 07: a person, a lantern lamp and a sign post on a downtown pavement: before nothing under
  any of them (the person reads as pasted on); after a soft contact blob under the feet, occlusion
  and grime round the lamp's base, a contact ring under the post.
- 08 / 09: the downtown pavement (Flower St) at noon, the wider view: blobs under the walkers.

Probe (tools/ground_contact/probe.tscn), four blocks, main -> this branch: 85 + 12 + 7 floating
shrubs (up to 0.56 m) -> 0, 12 palms (3.5 cm over their dirt wells) -> 0, 24 roadside shrubs -> 0,
5 parklet sets -> 0, guy guards 5 -> 1, merged boxes standing off the ground 46 corners -> 9.
