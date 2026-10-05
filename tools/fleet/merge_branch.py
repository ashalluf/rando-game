#!/usr/bin/env python3
"""Merge origin/wt/<slug> into the current branch and fix the docs' numbering.

usage (run inside the checkout or worktree to merge into):
    python3 tools/fleet/merge_branch.py <slug> "<merge subject>"

- git merge --no-ff --no-commit origin/wt/<slug>
- conflicts in the docs (HANDOFF, VISUAL_ROADMAP, GAME_PLAN, CLAUDE.md, ASSETS.md) are resolved by
  keeping both sides, ours first
- the branch's own HANDOFF section(s) and roadmap row(s) are renumbered to the next free ids, and
  every line the branch added anywhere in the docs gets the same renaming ("9bq" -> "9bs",
  "#59" -> "#61", "9b?" placeholders too)
- any other conflicted file is left for a human: the script prints it and exits 2 (merge not
  committed)
"""
import os
import re
import subprocess
import sys

KEEP_BOTH = ["tests/smoke_test.gd", "tools/glshot/still_shot.gd", "scripts/world/city_chunk.gd", "scripts/world/city_plan.gd", "project.godot", "scripts/ui/loading_screen.gd", "scripts/util/sfx.gd", "scripts/ui/minimap.gd"]
DOCS = ["docs/HANDOFF.md", "VISUAL_ROADMAP.md", "docs/GAME_PLAN.md", "CLAUDE.md", "docs/ASSETS.md"]


def sh(*args, check=True):
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit(f"failed: {' '.join(args)}")
    return r.stdout


def sec_key(s):
    # "9bq" -> sortable tuple
    return (int(s[0]), s[1:])


def next_sec(s):
    d, a, b = s[0], s[1], s[2]
    if b < "z":
        return d + a + chr(ord(b) + 1)
    return d + chr(ord(a) + 1) + "a"


def main():
    slug, subject = sys.argv[1], sys.argv[2]
    ref = f"origin/wt/{slug}"
    base = sh("git", "merge-base", "HEAD", ref).strip()
    # What the branch added to each doc (relative to the merge base).
    added = {}
    for f in DOCS:
        diff = sh("git", "diff", f"{base}..{ref}", "--", f, check=False)
        lines = set()
        for ln in diff.splitlines():
            if ln.startswith("+") and not ln.startswith("+++"):
                lines.add(ln[1:])
        # A line our side already has is not the branch's own (it came in through a merge of main
        # into the branch): renaming it would renumber an older section.
        ours = sh("git", "show", f"HEAD:{f}", check=False)
        added[f] = lines - set(ours.splitlines())
    # Ids already used on our side.
    ours_handoff = sh("git", "show", "HEAD:docs/HANDOFF.md")
    ours_road = sh("git", "show", "HEAD:VISUAL_ROADMAP.md")
    # The newest section is the LAST one in the file (the ids are not in sort order: 9za sits
    # between 9z and 9aa).
    top_sec = re.findall(r"^## (9[a-z][a-z])\.", ours_handoff, re.M)[-1]
    used_rows = set(int(x) for x in re.findall(r"^\| *(\d+) *\|", ours_road, re.M))
    top_row = max(used_rows)

    r = subprocess.run(["git", "merge", "--no-ff", "--no-commit", ref], capture_output=True, text=True)
    out = r.stdout + r.stderr
    conflicted = sh("git", "diff", "--name-only", "--diff-filter=U").split()
    # The smoke test: every branch adds its checks at the end of the city tests, so both sides'
    # hunks are kept (ours first) - but only hunks where neither side deletes anything of the
    # base's (diff3 markers), which are printed for a look.
    for f in [c for c in conflicted if c in KEEP_BOTH]:
        subprocess.run(["git", "checkout", "--conflict=diff3", "--", f])
        s = open(f).read()
        hunks = re.findall(r"<<<<<<< [^\n]*\n(.*?)\|\|\|\|\|\|\| [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", s, flags=re.S)
        if all(b.strip() == "" or (b in o and b in t) for o, b, t in hunks):
            def keep(m):
                o, b, t = m.group(1), m.group(2), m.group(3)
                if b.strip():
                    return o + t.replace(b, "", 1)
                return o + t
            s = re.sub(r"<<<<<<< [^\n]*\n(.*?)\|\|\|\|\|\|\| [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", keep, s, flags=re.S)
            open(f, "w").write(s)
            sh("git", "add", f)
            print("kept both sides in", f, "-", len(hunks), "hunk(s)")
            for o, b, t in hunks:
                print("  ours:  ", " | ".join(x.strip() for x in o.strip().splitlines()[-2:])[:150])
                print("  theirs:", " | ".join(x.strip() for x in t.strip().splitlines()[-2:])[:150])
            conflicted = [c for c in conflicted if c != f]
    others = [c for c in conflicted if c not in DOCS]
    for f in conflicted:
        if f not in DOCS:
            continue
        s = open(f).read()
        s = re.sub(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n",
                   lambda m: m.group(1) + ("\n" if m.group(2).startswith("## ") and not m.group(1).endswith("\n\n") else "") + m.group(2), s, flags=re.S)
        open(f, "w").write(s)

    # The branch's section ids and row numbers -> new ones. A header whose title we already have is
    # one of ours the branch touched (a stale copy from its base): never renumber it, and put our
    # line back.
    def title(ln):
        m = re.match(r"^## 9[a-z][a-z?]\. (.*?)(?: \(agent branch.*)?$", ln)
        return m.group(1) if m else None
    ours_headers = {}
    for ln in ours_handoff.splitlines():
        t = title(ln)
        if t:
            ours_headers[t] = ln
    sec_map, row_map = {}, {}
    for ln in sorted(added["docs/HANDOFF.md"]):
        m = re.match(r"^## (9[a-z][a-z?])\.", ln)
        if m and title(ln) not in ours_headers and m.group(1) not in sec_map:
            sec_map[m.group(1)] = None
    for ln in sorted(added["VISUAL_ROADMAP.md"]):
        m = re.match(r"^\| *(\d+|\?+|#?\?) *\|", ln)
        if m and m.group(1) not in row_map:
            row_map[m.group(1)] = None
    nxt = top_sec
    for k in sorted(sec_map, key=lambda x: x):
        nxt = next_sec(nxt)
        sec_map[k] = nxt
    nr = top_row
    for k in sorted(row_map, key=lambda x: (len(x), x)):
        nr += 1
        row_map[k] = str(nr)

    def rename(line):
        for old, new in sec_map.items():
            if old != new:
                line = re.sub(r"(?<![0-9a-z])" + re.escape(old) + r"(?![a-z])", new, line)
        for old, new in row_map.items():
            if old == new:
                continue
            line = re.sub(r"^\| *" + re.escape(old) + r" *\|", f"| {new} |", line)
            line = re.sub(r"((?:ROADMAP|roadmap|row) #)" + re.escape(old) + r"(?!\d)", r"\g<1>" + new, line)
            line = re.sub(r"(#)" + re.escape(old) + r"(?=[),;. ]|$)", r"\g<1>" + new, line) if old.isdigit() and int(old) >= 40 else line
        return line

    for f in DOCS:
        try:
            s = open(f).read()
        except FileNotFoundError:
            continue
        if "<<<<<<<" in s:
            continue
        lines = s.split("\n")
        changed = False
        for i, ln in enumerate(lines):
            if f == "docs/HANDOFF.md" and title(ln) in ours_headers and ln != ours_headers[title(ln)]:
                lines[i] = ours_headers[title(ln)]
                changed = True
                continue
            if ln in added[f] and not (f == "docs/HANDOFF.md" and title(ln) in ours_headers):
                new = rename(ln)
                if new != ln:
                    lines[i] = new
                    changed = True
        if changed:
            open(f, "w").write("\n".join(lines))
        sh("git", "add", f, check=False)
    print("sections:", sec_map, "rows:", row_map)
    if others:
        print("CONFLICTS LEFT:", others)
        print(out[-2000:])
        sys.exit(2)
    left = sh("git", "diff", "--name-only", "--diff-filter=U").split()
    if left:
        print("CONFLICTS LEFT:", left)
        sys.exit(2)
    # The commit trailer: set FLEET_TRAILER to your own attribution lines ("\n"-separated).
    trailer = os.environ.get("FLEET_TRAILER", "Co-Authored-By: Claude <noreply@anthropic.com>").replace("\\n", "\n")
    msg = subject + "\n\n" + trailer
    sh("git", "commit", "-q", "-m", msg)
    print("merged", sh("git", "log", "--oneline", "-1").strip())


main()
