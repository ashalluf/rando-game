# Forward+ review h (fleet wave 8): waves 6-7 on the Mac's renderer

Each still stacks the same frame from a small scene: Forward+ under lavapipe (what the owner's Mac
draws) above opengl3 (the Compatibility renderer every refcam still uses). 01-03 also show the
Forward+ frame after the fix. Seed 1337. Details: docs/HANDOFF.md "Forward+ review h".

- 01_bonfire_2100 - the beach bonfires at 21:00 (bonfire_night eye). BEFORE: the fire's sand pool
  added in linear HDR spread an orange carpet over the whole beach. AFTER: added in display numbers
  on Forward+ (display_add_fwd); the warm pool left is the fire's real light.
- 02_refinery_2230 - the refinery at 22:30 (refinery_night eye). BEFORE: every tank orange from foot
  to roof (the flares' light level and the masts' sodium floods drawn ~level^0.45). The middle frame
  is with the flares fixed only; 04 has both.
- 03_port_2200 - the container terminal at 22:00 (port_night eye): the floods on the stacks, before
  and after (the far stacks now match opengl3).
- 10-16 - looked at, nothing to fix: the airliner at night under an apron mast, the pier at night,
  the ballpark at night, the marina at 18:00, the canals at 11:00, a car's blast at night (2 s).
