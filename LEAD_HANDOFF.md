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
