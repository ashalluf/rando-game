# Wave 8 lead handoff (2026-11-06 ~12:15 UTC: the owner is moving to a NEW account)

Read CLAUDE.md, docs/HANDOFF.md (section 00000000000 and the newest 9n*/9o* sections) and this.
Roster: sessions_w8.tsv (status per slug; "merged bNN (main <sha>)" or "running").
Tasks: tasks_w8.tsv (every row's brief; a new session uses the same create_session prompt shape).

## main
`a870978b` = batch 67 (see below); batch 66 was `8c0de652`. Batches 52-66 landed this wave; CI builds
425-438 (438 = batch 66, was building at handoff). The Mac launch fix (mac-launch, boot-compile,
first-use-w8) is in.

## Batch 67 - ON MAIN
`a870978b` = batch 67 (gated green, 6,620 checks; peaks 3,726 / 3,899 / 3,543 MB) + a CLAUDE.md
line pointing here: rc5-freight-trench, coast-houses, rc5-stunt-jump, rc5-bus-stop-rain,
web-review-5, perf-audit-6 (street_errands passed: perf-audit-6's shard-0 failure was a flake).
CI build 439 = batch 67. Next batch is 68.

## Batch 68 candidates (all sessions were told to WRAP UP: commit, push, state gate status in HANDOFF)
Take only heads whose HANDOFF / report says gated green; re-gate the batch as always.
- rc5-tower-gondola 1a049fb4 (wrapped up; code 337a047a NOT full-gated, last full gate a46cfc7e had 1 pedestrian_flow flake)
- rc5-buskers-plaza, rc5-fire-station-night, rc5-school-morning, rc5-airport-final, rc5-car-wash,
  rc5-news-live: refcam5 views, mostly done, were in final A/B renders / gates.
- gate-flakes-3 (16 commits: many flakes fixed at source incl. CI 429's pedestrian_flow pair),
  memory-audit-w8 (teleport free, memory-heavy parts dealt first; shard 2 still ~3.8 GB),
  gate-speed-3 (final gate was running), cinematic-review-w8 (early: runner + family analysis).
- Wave 8f, started 11:57, just begun: rc5-arts-district, rc5-church-sunday, rc5-switchback-night,
  rc5-pool-underwater, rc5-surf-dawn, rc5-alley-noon, rc5-storm-sea, rc5-sea-of-clouds,
  rc5-laundromat-night, web-bonfire (web-only bonfire flames bug; web-review-5 left probes).
  These will have little or nothing pushed: restart them on the new account (same slug and
  tasks_w8.tsv row; continue the branch if it exists).

## Known open items
- Gate memory: shards peak ~3.85-4.0 GB against the 4,000 MB budget (memory_audit_checks) - a
  re-deal or memory-audit-w8's work is needed before much more lands.
- Pedestrian_flow passing pair flakes under load (gate-flakes-3 has the fix, not merged yet).
- Web: bonfire flames do not draw in the browser (web-bonfire task).
- Coast highway: houses rebuilt (coast-houses, batch 67); pier-end surf foam thin (sea-life note).

## The lead loop (unchanged)
gate-wt worktree: `git checkout -B gate-bNN origin/main`; `FLEET_TRAILER=... python3
tools/fleet/merge_branch.py <slug> "Merge wt/<slug> (batch NN)"` per branch; fix docs numbering
(`## 9??` / duplicate headers / `| ? |` rows), JSON, conflict markers (a branch whose code is already
merged: keep main's smoke_test.gd); `--import`; SHARDS=3 gate (~40 min); a check failing only in the
gate: run it alone, harden or fix at source, re-run that shard; push main and the dev branch; update
the roster; tell the owner the build number.

# Wave 8 lead (2026-11-05, new account)
Batch 51 is ON MAIN (2f2fb8f5; shard 2 re-gated green, 2,241 checks, 3.8 GB). Wave 8 = 25 sessions,
roster sessions_w8.tsv, tasks tasks_w8.tsv. The wave-7 sessions below were on the old account: their
open branches are resumed by wave-8 sessions of the same slug. Next batch is 52.

# Lead handoff (paused 2026-11-02 ~22:50 UTC, usage limit)

Everything is PAUSED: the local gate killed, every fleet session interrupted. Read CLAUDE.md,
docs/HANDOFF.md section 0000000000 and this file. Rosters: sessions_w5/w6/w7.tsv, tasks: tasks_w7.tsv.

## main
`b45ba911` = batch 50 (gated green). Batches 45-50 landed today: fashion district, marina golden,
explosions rounds 6-10, airport night, ridge sign, palm shimmer, pier night 2, bonfires, Broadway
night, canals day, port night, stack aerial, film lot, gate-flakes-2 fixes.

## Batch 51 - staged, NOT on main
Branch `gate-b51` (pushed, head 841b5d65) = main + explosions-4 round 11 (d36fa890) + gate-flakes-2
(3ea21acc) + my two flake fixes (shotgun crate retry/diagnostic, hero head-pop judged on frames near
the step). Its full gate failed only in shard 2 (those two checks); room part passes with the fixes.
TO DO: `SMOKE_SHARD=2/3 GODOT=... tests/headless_check.sh` on gate-b51; green -> `git push origin
gate-b51:main` (check origin/main is still its ancestor).

## Ready to merge after that (batch 52)
- explosions-4: 6008ed49 = rounds 12 (wire-ribbon bug fixed, heavy masonry) + 13 in progress
  (petal wedges, aerial ground flash). Its "gate passed" for 6008ed49 was FALSE (session said so);
  take only a commit it reports green from the log. Round-13 note in HANDOFF 9ky.
- rc4-terminal-curb a5750676, rc4-heli-night bbe28245, rc4-river-night d78d4bea,
  rc4-hospital-er b53397de, rc4-freight-yard ca64c6e0: pushed work, sessions were finishing
  (refcam compares / gates) when interrupted. rc4-lowrider-meet: nothing pushed yet.
- rc4-refinery-road 66c81cf0 (gate passed 5,699; was checking refinery_night camera).
- rc4-metro-station 715af2d9 (gate re-running when interrupted).
- web-hero-blue: still bisecting the web hero blue in rain (merge #31 neutral, #20 blue), probe
  tools on 36773ec0; no fix yet.
- gate-flakes-2 open: follower lag, ragdoll_feel stair roll, pedestrian_flow passing pair under
  3 parallel shards.

## Resume a session
Each session_id is in the roster tsv; send_message it "resume where you stopped" (or start a fresh
session with the same slug/prompt: see the create_session prompt shape - wave-N, slug, BRIEF.md,
tasks_wN.tsv row, push only wt/<slug> and shots/<slug>).

## Lead loop (unchanged)
Branch gate-bNN off origin/main; `python3 tools/fleet/merge_branch.py <slug> "Merge wt/<slug> (batch NN)"`
per branch (for a specific commit: `git update-ref refs/remotes/origin/wt/<tmp> <sha>` and merge
<tmp>); check for conflict markers (smoke_test.gd load lists and tools/refcams/README.md conflict
often: keep both sides, one line each); `--import`; `SHARDS=3 GODOT=/opt/godot/Godot_v4.7.2-stable_linux.x86_64
tests/headless_check.sh` (~35-45 min); a check failing only in the gate: run it alone
(`SMOKE_PARTS=<file>`, or the part that holds it), harden the test, rerun that one shard
(`SMOKE_SHARD=i/3` WITHOUT SHARDS=3); green -> push to main; send the owner stills from shots/<slug>.
Pitfalls: pkill -f matches your own shell (use pgrep "[G]odot..."); never start a gate before the
merge's conflicts are resolved; HANDOFF "9??" headings need hand numbering.

## Owner's standing asks
AAA / "GTA 6" graphics, explosions top priority, push to main always, screenshots in chat along the way.
