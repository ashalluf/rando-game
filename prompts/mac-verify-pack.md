# Wave 4 task: mac-verify-pack (kind: infra)

Branch `wt/mac-verify-pack`, stills on `shots/mac-verify-pack`.

The owner's Mac is the only true Forward+ check and nobody has seen wave 3 there. Build a one-key verification pack for the owner: a `--verify` launch mode (or pause-menu button) that teleports through the ten reference cameras at their hours, holds each 3 s, saves a PNG of each to Pictures/Rando Game/verify_<build>/ and a sheet, and shows a card at the end; plus a docs/VERIFY.md page telling the owner exactly what to do and what to send back. No new render features. The owner plays from the Mac app with no Terminal: the pause-menu button is the one they will use. Prove it on opengl3 with the harness.

If `origin/wt/mac-verify-pack` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/mac-verify-pack`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
