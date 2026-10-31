# Wave 4 task: ambient-sound-2 (kind: new)

Branch `wt/ambient-sound-2`, stills on `shots/ambient-sound-2`.

The street's sound at eye level: footsteps of the crowd near the player, shop doors' bells, a dog's bark, the bus's air brakes, a car's door shutting when somebody gets in (StreetErrands), tyre noise by surface, the wind in the trees, the sea's distance. Ambience / Sfx with CC0 clips (docs/ASSETS.md), the loudness table rule, the bus routing. Checks on levels_for / rates_for purity. Record every source in docs/ASSETS.md; only clips named in Sfx.SAMPLES ship; every name needs its loudness in SAMPLE_LOUDNESS_DB; loop flags in code. Stills are not the point: a README on shots/ambient-sound-2 listing what plays where.

If `origin/wt/ambient-sound-2` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/ambient-sound-2`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
