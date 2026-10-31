# Wave 4 task: web-hero-rain (kind: resume)

Branch `wt/web-hero-rain`, stills on `shots/web-hero-rain`.

Resume wt/web-hero-rain (ba9a2284): the hero's tracksuit reads BLUE in rain on the WEB build only (native is fine). Cause not found yet. Suspects: wet_surface.gdshaderinc / hero_cloth.gdshader on the Compatibility renderer (colour space: cs_in on a texture that is raw there; a source_color uniform decoded twice; a vec3 vs Color uniform), the web's half-float instance data, a sampler over the WebGL2 cap. Reproduce with the opengl3_es driver or tools/webshot (CLAUDE.md web notes), fix the cause, prove with a before/after webshot in rain, gate, push.

If `origin/wt/web-hero-rain` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/web-hero-rain`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
