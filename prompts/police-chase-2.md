# Wave 4 task: police-chase-2 (kind: new)

Branch `wt/police-chase-2`, stills on `shots/police-chase-2`.

A police chase that reads like GTA: cruisers that box the player's car in, a PIT manoeuvre at speed, spike strips at a roadblock, officers that take cover behind doors and advance, a helicopter spotlight that tracks (AirTraffic's does), radio chatter (synthesised bleeps + CC0 voice if any; else none). PoliceCar / PoliceOfficer / Police; the smoke test keeps Police.enabled off except in your checks. Another session (wanted-escalation) owns the per-star response caps and signatures in Police.gd: you own the cruisers' and officers' manoeuvres.

If `origin/wt/police-chase-2` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/police-chase-2`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
