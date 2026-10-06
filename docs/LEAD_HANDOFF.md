# Lead handoff: everything, as of 2026-10-06 08:50 UTC

One file for whoever leads next (any account, any session; every session starts with no memory).
Read this, then CLAUDE.md, then docs/HANDOFF.md section 0000000. The lead's working scripts, logs,
the per-session prompts and the full session roster are in `tools/fleet/lead/` (Godot ignores the
folder: `.gdignore`).

## 1. Where things stand (read first)

- **The whole fleet is STOPPED by the org's monthly spend limit.** Every running fleet session
  failed between 02:32 and 03:04 UTC on 2026-10-06 with "You've hit your org's monthly spend
  limit · ask your admin to raise it". Nothing restarts until the owner (or the org admin) raises
  the monthly spend limit. The account's seven-day limit was also at "allowed_warning" (it resets
  2026-10-06 15:00 UTC). After the limit is raised, resume as in section 6.
- **`main` = build 359** (commit `3840f94f`, released 2026-10-05 21:03 UTC, CI green):
  integration-a (19 branches) + wave 2's batches 1-8 + the CI fixes for runs 355-358.
  Download: https://github.com/ashalluf/rando-game/releases/latest
- **Batch 9 is merged but NOT on main yet**: branch `fleet/batch9` (pushed). Contents:
  apartments `b31feff3`, tower-gondolas `51bb02ab`, swimming `d6e06795`, freeway-incidents
  `1f5bb8c3`, street-furniture `fb9bdf72`, plus two fixes of the lead's: `90ea0d4e`
  (FreewayIncidents.current falls back to the node still in the tree - the plain run failed "the
  traffic carries the incidents node" because the smoke test's second city cleared it) and
  `ede1152f` (90ea0d4e's static list was named `_live`, which the script already uses: a parse
  error that took traffic.gd and the whole city down; the plain re-run caught it, 12 of 105
  checks). Sharded gate before the fixes: 2,472 passed, 0 failed (2.58 GB a shard). **Check the
  branch's last commit**: if it says the plain gate passed, main was fast-forwarded to it (see
  the build number there); if not, run `SHARDS=1 tools/fleet/lead/gate.sh <worktree> b9`, fix,
  and push with `git push origin <branch>:main`.
- **Batch 10 is ready to merge** (each finished, each gated green on its own branch with
  origin/main merged): car-panic `48313a47` (2,385/0), prop-destruction `3630cbaf` (2,399/0),
  lowriders `f4904fdd` (78/78 parts after the review fix; 2,390 full), walk-in-store `9b45bfb7`
  (2,393/0), engine-audio `a2d7183d` (2,416/0). Merge them onto main after batch 9 with
  `tools/fleet/merge_branch.py`, gate (sharded, then plain), push.

## 2. The owner

- Prompts from a phone; plays the Mac build from GitHub Releases; cannot open the editor.
- **Wants screenshots of everything as it lands** ("Don't forget about screenshots"): send a
  2x2 sheet of each session's best before/after (`tools/fleet/lead/drop.sh <slug> <files...>`,
  then SendUserFile) the moment its `shots/<slug>` moves; watch with
  `tools/fleet/lead/watch_shots.sh` under the Monitor tool (re-arm every 30 min).
- Said "Deploy 100 parallel agents use opus 5.5 strictly", later "keep it going" (resume the
  fleet) and "Can you just put everything into a handoff file" (this file).
- The bar: realistic, AAA (RDR2 / GTA V on PS5). Original names and designs only - no real
  brand, person, building, team or trade dress (see star-boulevard below).
- Push straight to `main`, no PRs. Always report the build number after a push.

## 3. The fleet (100 sessions, wave 2, started 2026-10-05 09:24 UTC)

Brief: `fleet/brief` branch (`BRIEF.md`, `tasks.tsv`, `sessions.tsv`). BRIEF.md was updated at
21:08 on 10-05: sessions start from `origin/main` (not fleet/base), `SHARDS=3` gates, checks
must stage what they place. Each session works on `wt/<slug>`, stills on `shots/<slug>`.
Full roster with session ids and last status: `tools/fleet/lead/roster_2026-10-06.tsv`; the
exact prompt each was created with: `tools/fleet/lead/prompts.json`.

**Merged on main (done):** alleys, cemetery, kerbs, rooftops, sky, stadium, wilshire-deco,
far-corners (batch 1); oom-fix + integration-b's 12 (construction, murals, signage, hospital,
la-trees, car-dealers, airport-life, golf, dogs, hill-homes, oil-fields, vacant-lots); batch 3
(fwd-review-a, road-detail, perf-audit, reservoir, ridges, service-vehicles); batch 4
(service-vehicles' bodies, farmers-market, freight-trains, fwd-review-b); batch 5 (road-detail,
memory-audit, shader-warm, load-time, occluders, gate-speed, texture-budget, reflection-probes,
web-build, fwd-review-c, far-landmarks, civic-buildings, scooters, driving-fx, traffic-ai);
batch 6 (fwd-review-a, utility-poles, churches, police-night, ref-cameras, color-grade,
street-life-2, road-wear, estate-night, chinatown, historic-core, film-studio); batch 7 (olvera,
shop-vinyl, roadside); batch 8 (street-signs, street-lamps). Their sessions can be archived once
the owner says "archive" (never archive without the owner's word).

**Batch 9 / 10:** see section 1.

**Stopped mid-work by the spend limit (resume these first, each with its open review point):**

| slug | branch head | state when it stopped / what is left |
|---|---|---|
| star-boulevard | `e0e65476` | **Do not merge as is.** Its stars copy the real walk of fame's trade dress (coral-pink 5-point star, brass rim, charcoal terrazzo, category emblem). Lead asked (01:08) for an original medallion (sunburst / compass / spotlight roundel, own colours and emblems); its final stills (01:53) still had the pink star - the note was queued behind its turn. Also: it reported `geo_count.gd` / `still_shot.gd` hanging after "LOADING far city" on its box (main thread in a WorkerThreadPool wait). |
| garage-drive-in | `4f21bfde` | Drivable car park works. Asked: real car bodies on the decks near the player (not ArenaGrounds' 260-triangle code cars), beams / pipes / level markings / oil stains under a flat ceiling. |
| fashion-district | `991aace0` | Garments read as flat candy cutouts: asked for cloth on hangers with drape, real wholesale colours, fabric rolls, more shoppers and clutter. |
| onlookers | `7746fdf9` | Works. Asked: the two-handed filming pose reads as a boxer's guard (elbows down, phone at eye height), and a real ring of 8-15 people at the wreck. |
| rain-crowd | `f9ce866a` | Works (umbrellas, hoods, sheltering). Asked: a staged BUSY street for the before / rain / storm frames (its frames show 2-3 people). |
| backyards | `23098df9` | Patio sets, grills with smoke, string lights, trampolines, pool floats. Asked: the "after" frames are globally darker than "before" (noon and 21:00): find what changes the whole image, re-shoot with `DIFF=1`. |
| motorcycles | `3ecf5d02` | Sport bike / cruiser / scooter, rideable, in traffic. Second pass (panelled fairings, livery) looked better; was rendering crash-throw shots. Finish, gate, report. |
| coast-highway | `1f5480b0` | PCH-style road under the bluffs, houses on pilings, shoulder parking. First set good; finish, gate, report. |
| parklets | `04782d7b` | Dining decks in the parking lane in front of cafes. First set good; night stills and gate left. |
| crowd-lookat | `60667089` | 1 commit: head-turn modifier just started. |
| heli-flyable | `7a11e21e` | 2 commits: flyable helicopter just started. |
| news-crews | `3be8efec` | 1 commit: just started. |
| wingsuit | `6e472da5` | 3 commits: just started. |
| car-cabins, foot-ik, metro-underground, ragdolls, speedboats, stunt-ramps | (none) | Started 01:00-02:30, no branch pushed yet: restart from their prompt. |

**Never started (24; created 09:30 on 10-05 but never got a container, "Sandbox allocation
failed: rate_limited"):** arroyos, beach-amenities, bonfires, buskers, car-radio, film-shoot,
fireworks, footbridges, garments-2, lighthouses, nightlife, ocean-traffic, offshore-island,
oil-islands, power-plant, refinery, rock-outcrops, sea-life, settings-menu, skate-park, sky-ads,
valets, wildlife, yard-sales. Their session ids are in `fleet-brief:sessions.tsv`; sending one a
message provisions its container.

## 4. How the lead works

- **Worktrees**: clone the repo, `git worktree add` one per batch (this container used
  /home/user/rando-b2..b5; they vanish with the container - everything that matters is pushed).
  Godot: `/home/user/godot/Godot_v4.7.2-stable_linux.x86_64` (GitHub releases; downloads.godotengine.org
  is blocked by the network policy).
- **Merge**: in the batch worktree, `FLEET_TRAILER="Co-Authored-By: ...\nClaude-Session: ..."
  python3 tools/fleet/merge_branch.py <slug> "Merge wt/<slug>"`. It renumbers each branch's
  `## 9d?.` HANDOFF section and `| ? |` roadmap row (next free: 9ez, row 145), resolves the
  smoke_test.gd list conflicts, exits 2 on a real conflict. Then grep for conflict markers.
- **Gate**: `SHARDS=3 tools/fleet/lead/gate.sh <worktree> <tag>` (~10 min, 3 x ~2.5 GB) and,
  before pushing to main, `SHARDS=1` (the plain order CI runs, ~20 min, ~3.2 GB). The shards and
  the plain run order the parts differently and have disagreed several times (order-dependent
  checks); the plain run is the one that matches CI. Never run two Godot cities at once (15 GB box);
  never edit res://scripts in any worktree while a gate runs (`user://load_cache` is shared and
  keyed on the scripts' md5).
- **CI**: every push to main runs `.github/workflows/godot-check.yml` (smoke test, Mac + web export,
  release). The integration's token can NOT re-run a job or dispatch the workflow (403): to re-run,
  push a real commit (a docs update), never an empty one. Run 358 was cancelled at 15 min with no
  log (a lost runner) and simply re-run that way.
- **Sessions**: tools are the claude-code-remote MCP server (`list_sessions` - its output is too big
  for the context, run `tools/fleet/lead/survey.py <saved file>` on it -, `list_events` with
  `kinds: ["result"]` for a session's final report, `send_message`, `send_later` for check-ins).
  Keep about 20 running while a usage limit is at warning; replace each finished one with a
  never-started one using the RESUME template: "RESUME (lead). This session never got a container
  ... start from origin/main ... Your branch / stills branch ... Your task: <tasks.tsv text> ...
  Work autonomously to the end ..." (see any message in `tools/fleet/lead/lead_log.txt`'s period).
- **Review**: look at every stills set before merging (drop.sh sheets). Send back anything below
  the bar with concrete asks; record it in `tools/fleet/lead/review_notes.txt`.

## 5. Known rare check failures (each passed alone; watch CI for them)

- dogs: "a round into a dog sends it running" / "the second walker is still there after 30 ticks"
  (a freed walker) - seen in street-furniture's, tower-gondolas' and lowriders' gates.
- police stations: the cruiser turning in through the station gate - tower-gondolas' gate.
- emergency: the paramedic stretcher pickup - tower-gondolas', prop-destruction's gates (and CI 350
  before the door-spot fix).
- photo mode: "leaving photo mode restores the grade, vignette, grain, player and HUD" - traffic-ai's gate.
- Fixed this round (for the pattern): CI 355 traffic overlap (a turning car's room in its new lane,
  traffic-ai `e8ae24d1`), CI 356 swerve (StreetErrands parked the check's own placed car), CI 357
  car lights (CarLights' 0.15 s pick race), batch 9 plain run (FreewayIncidents.current). **The
  pattern: a live system (errands, pull-outs, pick / survey timers, a second city) acting on what a
  check placed.** Look there first.

## 6. To resume after the limit is raised

1. Read this file, CLAUDE.md, docs/HANDOFF.md 0000000.
2. Check main's CI and `fleet/batch9`; land batch 9 (section 1), then batch 10.
3. Resume the stopped sessions in section 3 with one message each: "RESUME (lead). You stopped on
   the org's monthly spend limit. Pick up wt/<slug> (head <sha>), merge origin/main (never rebase),
   address <the open review point>, full gate green, push wt and shots, finish with the brief's
   report." Then start never-started ones as slots free up.
4. Forward screenshots to the owner as they land; tell the owner each build number.

## 7. Notes from the sessions not yet acted on

- HillHomeKit's far walls read pale under moonlight (estate-night: a lamp_factor dim in
  far_canopy's estate branch).
- `IndustrialKit.cyl` winds its walls inward (film-studio).
- tower-gondolas: past 240 m the low-detail ring still shows Rooftops' static cradle box at its old
  height on infill towers (a few pixels).
- freeway-incidents: debris has no collision; incidents skip ramps and the stack's connectors.
- car-panic: freeway / airport-loop / replica / stack traffic don't panic; the open door is a swung
  panel over the closed body door (car-cabins was to add a reusable door rig).
- prop-destruction: no night still in the city; bent posts aren't remembered across rebuilds.
- street-furniture: its "21:00" stills look like day (check the shot's hour); hydrants / meters can
  still stand close to a StreetLamps or StreetSignKit pole.
- star-boulevard: still_shot / geo_count hang after "LOADING far city" on its box (not reproduced on
  the lead's box, where main's stills load).
- Every feature this round was judged on opengl3 stills only; nothing has been seen on Forward+
  (the Mac's renderer).
