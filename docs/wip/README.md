# Work in flight when the session of 2026-09-21 was paused

Three agent fleets were running and were stopped mid-task. Their finished output is on `main`;
what was still half-written is here as patches, so nothing was lost and nothing half-finished
landed in the game. `main` is green (190 checks) with none of these applied.

Apply one with `git apply docs/wip/<name>.patch` from the repo root, then read the notes below
before trusting any of it.

## wheels-in-flight.patch  (scripts/vehicles/vehicle.gd, scripts/world/prop_factory.gd)

**Read the correction at the end of `docs/GAME_PLAN.md` first.** The generated wheel MESH already
exists on `main` - `PropFactory.car_wheel()`, `car_caliper()`, `wheel_material()`, `WHEEL_KITS`,
`WHEEL_FACES`, the `WheelSlot` enum - it arrived in build 135 (`0ce833f`) inside a commit whose
message only mentions grass and palms. At `main` it is dead code: nothing calls it.

This patch is the missing half - `Vehicle` calling it, with a `WHEEL_POSE` table per body type.
It was in its REPAIR round when stopped, answering a review that correctly pointed out the
builder had re-described code that already existed.

What the review established, and what makes this worth finishing:
- The four Meshy bodies (sedan, pickup, van, sports) are **88% of traffic**, and each has its
  wheel modelled into the single painted body surface. So the wheel wore the car's paint and
  clearcoat. It was never a missing wheel; it was a wheel with the wrong material.
- `vehicle.gd` has `if _has_model: return  # the generated models have their own wheels`. A body
  model that does not carry wheel geometry therefore puts a car on the street with NOTHING under
  the arches. Any change here has to keep both paths working.
- Never give a kinematic VehicleBody3D VehicleWheel3D nodes (NaN). Traffic cars are kinematic;
  parked and driven ones are not. Check both.

Unverified: whether the wheels still rotate and steer, and the far-LOD cost with 150 traffic cars.

## signs-in-flight.patch  (scripts/world/building.gd, shaders/building.gdshader)

Shop names readable at any distance. Today each name is its own TextMesh that stops drawing at
`Building.SIGN_DRAW_DISTANCE` (75 m) and is skipped entirely on web, so every commercial strip has
blank fascias from the air - which is most of how the owner plays.

The approach: rasterise the whole `Building.SHOP_NAMES` list into one atlas at load and sample it
in the fascia branch of the building shader. No geometry, no extra draw calls, works on web.
`shaders/sign_letters.gdshader` (committed, inert until something uses it) is the near-view raised
relief that stands in front of the painted name.

**The trap, already recorded in CLAUDE.md:** the shader measures its `u` the opposite way round
the box from the script's `a` on every face, so a run's centre has to be mirrored. Get it wrong
and half the shops have backwards names. Blade signs on the plaza strips had exactly this bug and
it was fixed in build 132 - do not reintroduce it.

Unverified: whether the atlas name and the TextMesh name agree for the same shop, and whether
there is a pop at the swap.

## Character PBR maps (committed to assets/models/, NOT wired in)

`tools/make_character_maps.py` produced `pedestrian_{a,c}_mask.png` and `pedestrian_{a,c}_nrm.png`.
**`pedestrian_b` was never generated** - the track was stopped first - so the set is incomplete,
and `shaders/character.gdshader` and `scripts/npc/pedestrian.gd` are untouched on `main`.

Why this matters more than it looks: the character shader currently classifies every pixel as
skin / cloth / hair at runtime from hue, saturation and brightness, and that has already shipped
two defects - the colour-space bug that broke ALL clothing on the Mac build for weeks, and hair
detection that reached 0.8% of head pixels so the hair palette was dead code. Baking the masks
offline kills that entire class of bug and is cheaper per frame. The `mask` texture is RGB =
(skin, cloth, hair); the `nrm` is a synthesized normal map, since the rigs ship one flat colour
texture and no normal or roughness map at all.

To finish: generate `pedestrian_b`, sample the mask in `character.gdshader` instead of
classifying, delete `Pedestrian._texture_value()` and the colour-space plumbing that exists only
to serve the runtime classification, and keep the per-character garment recolouring and the
per-look material cache, which both work.

**Judge this one on a Forward+ render** (`tools/glshot/forward_shot.sh`). A normal map is nearly
invisible on the Compatibility renderer, and judging it there would repeat the exact mistake that
hid the clothing bug for weeks.
