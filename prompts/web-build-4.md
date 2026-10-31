# Wave 4 task: web-build-4 (kind: infra)

Branch `wt/web-build-4`, stills on `shots/web-build-4`.

The web build after batch 25: export it, load every bookmark in tools/webshot (ONE tab at a time), fix any shader / WebGL / global-buffer error and anything that reads wrong there (except the hero in rain: web-hero-rain owns that), keep the pck under 650 MB (the exclude filter), update tests/web_build_checks.gd. Another session (web-hero-rain) owns the hero's blue tracksuit in rain on the web.

If `origin/wt/web-build-4` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/web-build-4`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
