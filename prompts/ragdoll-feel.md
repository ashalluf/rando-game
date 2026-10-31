# Wave 4 task: ragdoll-feel (kind: new)

Branch `wt/ragdoll-feel`, stills on `shots/ragdoll-feel`.

Ragdolls that read right: a shot person staggers before falling (a short hit reaction clip per direction, then the doll), a knocked person flies with their limbs trailing (joint damping), a body hit by a car wraps over the bonnet and slides off, a doll on stairs rolls down. RagdollJoints / Ragdoll / Pedestrian.knock; keep the max_active cap and the freeze. tests/ragdolls_checks.gd must keep passing (the bonnet box is 6 m since 2026-10-31; the tumble gap tolerance 0.15). Another session (blood-gore-2) owns the blood.

If `origin/wt/ragdoll-feel` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/ragdoll-feel`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
