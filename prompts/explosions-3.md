# Wave 4 task: explosions-3 (kind: new)

Branch `wt/explosions-3`, stills on `shots/explosions-3`.

The explosion and fire at arm's length, third pass: the fireball's volume (lit puffs with real depth, not cards), the smoke's shading under sun and at night, debris that bounces and comes to rest, sparks that land, the scorch and crater's edge, the light's falloff on the facades, heat haze. BlastFX / WeaponFX; keep the web's cheap path. Strips with tools/glshot/fx_shot.gd on both renderers. Also BlastAftermath; keep the particle traps in CLAUDE.md's Effects note.

If `origin/wt/explosions-3` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/explosions-3`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
