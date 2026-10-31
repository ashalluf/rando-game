# Wave 4 task: blood-gore-2 (kind: new)

Branch `wt/blood-gore-2`, stills on `shots/blood-gore-2`.

Blood and gore at arm's length (the owner asked for more): wounds that read on the body (an entry hole decal on the character via the shader's wound uniforms: bigger, darker rim, glossy), blood that pools and spreads on the ground with the camber, drips off a body carried on a bonnet, splatter on the hero's clothes when close, the gib stumps. WeaponFX.blood / Ragdoll; keep the caps; stills with still_shot.gd FX_SHOOT. CLAUDE.md's Effects note has the blood rules (satin roughness, coverage mips, the caps, the two traps). Another session (ragdoll-feel) owns RagdollJoints.

If `origin/wt/blood-gore-2` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/blood-gore-2`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
