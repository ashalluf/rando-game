#!/usr/bin/env python3
"""Every script's static (compile-time) dependencies, and the cycles they make.

GDScript 4.7 compiles a script's dependencies IN FULL when the script compiles (measured with a
static-initialiser print in a scratch project, docs/HANDOFF.md "The boot compile"):
  * any mention of a global class name (a type, `X.f()`, `X.CONST`, `is X`, a bare `X`), in a
    signature or a function body alike;
  * `preload("res://...")` (a scene or resource preload compiles the scripts it holds);
  * `extends "res://..."` / `extends X`.
`load("res://...")` (a string) is NOT a compile edge. So a set of scripts that name each other is
ONE load() call however it is entered.

  python3 tools/boot_compile/deps.py                 # summary: scripts, SCCs, the biggest
  python3 tools/boot_compile/deps.py --list          # every script and what it compiles
  python3 tools/boot_compile/deps.py --closure res://scripts/util/boot.gd
                                                     # what loading that script compiles
  python3 tools/boot_compile/deps.py --cut           # edges whose removal shrinks the big SCC
  python3 tools/boot_compile/deps.py --why A B       # the dependency path A -> ... -> B
  python3 tools/boot_compile/deps.py --hook          # add the boot-frame hook to every script of
                                                     # the big SCC that lacks it (idempotent)
  python3 tools/boot_compile/deps.py --unhooked      # the big SCC's scripts without the hook

The hook (one line, placed after the class's header and doc block):
    static func _static_init() -> void: LoadPulse.compiled()  # the boot's frames
GDScript runs a script's static initialiser as soon as THAT script has compiled, inside the one
load() that compiles the whole cycle, so LoadPulse presents frames from inside it.
"""
import os, re, sys, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SKIP_DIRS = {".godot", "build", ".git", "addons_unused"}


def res(p):
    return "res://" + os.path.relpath(p, ROOT).replace(os.sep, "/")


def disk(r):
    return os.path.join(ROOT, r[len("res://"):])


def strip(src):
    """Source with comments and string contents blanked (keeps preload/extends paths apart)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "#":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if c in "\"'":
            q3 = src[i:i + 3]
            if q3 in ('"""', "'''"):
                j = src.find(q3, i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n and src[j] != c and src[j] != "\n":
                    j += 2 if src[j] == "\\" else 1
                j += 1
            out.append(c + " " * max(0, j - i - 2) + c)
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


PRELOAD = re.compile(r'preload\(\s*"([^"]+)"\s*\)')
EXTENDS_PATH = re.compile(r'^\s*extends\s+"([^"]+)"', re.M)
CLASS_NAME = re.compile(r'^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
WORD = re.compile(r'(?<![.\w])([A-Z][A-Za-z0-9_]*)\b')
EXT = re.compile(r'\[ext_resource[^\]]*path="([^"]+)"')


def scan():
    gd = []
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            if f.endswith(".gd"):
                gd.append(res(os.path.join(d, f)))
    gd.sort()
    src = {}
    classes = {}
    for r in gd:
        try:
            s = open(disk(r), encoding="utf-8").read()
        except OSError:
            continue
        src[r] = s
        m = CLASS_NAME.search(s)
        if m:
            classes[m.group(1)] = r
    return gd, src, classes


_res_scripts = {}


def resource_scripts(r, seen=None):
    """Scripts a .tscn / .tres compiles when it loads (its ext_resources, recursively)."""
    if r in _res_scripts:
        return _res_scripts[r]
    seen = seen or set()
    if r in seen:
        return set()
    seen.add(r)
    out = set()
    if r.endswith(".gd"):
        out.add(r)
    elif r.endswith((".tscn", ".tres", ".scn", ".res")) and os.path.exists(disk(r)):
        try:
            text = open(disk(r), encoding="utf-8", errors="ignore").read()
        except OSError:
            text = ""
        for p in EXT.findall(text):
            out |= resource_scripts(p, seen)
    _res_scripts[r] = out
    return out


def graph():
    gd, src, classes = scan()
    deps = {}
    why = {}
    for r, s in src.items():
        own = CLASS_NAME.search(s)
        own = own.group(1) if own else None
        code = strip(s)
        d = {}
        for p in PRELOAD.findall(s):
            for t in resource_scripts(p):
                if t != r:
                    d.setdefault(t, "preload " + p.split("/")[-1])
        for p in EXTENDS_PATH.findall(s):
            for t in resource_scripts(p):
                d.setdefault(t, "extends")
        for w in WORD.findall(code):
            if w != own and w in classes and classes[w] != r:
                d.setdefault(classes[w], w)
        deps[r] = d
    return deps, classes


def tarjan(deps):
    index, low, on, st, out = {}, {}, set(), [], []
    counter = [0]
    sys.setrecursionlimit(100000)

    def visit(v):
        index[v] = low[v] = counter[0]; counter[0] += 1
        st.append(v); on.add(v)
        for w in deps.get(v, ()):
            if w not in deps:
                continue
            if w not in index:
                visit(w); low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = st.pop(); on.discard(w); comp.append(w)
                if w == v:
                    break
            out.append(comp)
    for v in deps:
        if v not in index:
            visit(v)
    return out


def closure(deps, r):
    seen, todo = set(), [r]
    while todo:
        v = todo.pop()
        if v in seen:
            continue
        seen.add(v)
        todo.extend(deps.get(v, ()))
    return seen


def path(deps, a, b):
    prev, q = {a: None}, collections.deque([a])
    while q:
        v = q.popleft()
        if v == b:
            break
        for w in deps.get(v, ()):
            if w not in prev:
                prev[w] = v; q.append(w)
    if b not in prev:
        return None
    out, v = [], b
    while v is not None:
        out.append(v); v = prev[v]
    return out[::-1]


HOOK = "static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md \"The boot compile\"\n"
HOOK_MARK = "LoadPulse.compiled()"
HEADER = re.compile(r'^\s*(@tool|@icon|@abstract|class_name|extends)\b')


def add_hook(r):
    """Inserts HOOK after the header lines and the class's `##` doc block. False if present or
    the script already has a _static_init of its own."""
    text = open(disk(r), encoding="utf-8").read()
    if HOOK_MARK in text or "_static_init" in text:
        return False
    lines = text.splitlines(keepends=True)
    i = 0
    seen_header = False
    while i < len(lines):
        ln = lines[i]
        if HEADER.match(ln):
            seen_header = True
            i += 1
            continue
        if not seen_header and (ln.strip() == "" or ln.lstrip().startswith("#")):
            i += 1
            continue
        break
    # the class doc block right under the header
    while i < len(lines) and lines[i].lstrip().startswith("##"):
        i += 1
    ins = [HOOK]
    if i < len(lines) and lines[i].strip() != "":
        ins.append("\n")
    if i > 0 and lines[i - 1].strip() != "":
        ins.insert(0, "\n")
    lines[i:i] = ins
    open(disk(r), "w", encoding="utf-8").write("".join(lines))
    return True


def main():
    deps, classes = graph()
    sccs = tarjan(deps)
    sccs.sort(key=len, reverse=True)
    big = sccs[0]
    sizes = {r: os.path.getsize(disk(r)) for r in deps}
    args = sys.argv[1:]
    name = lambda r: r.replace("res://", "")
    def arg_res(a):
        if a in classes:
            return classes[a]
        return a if a.startswith("res://") else "res://" + a
    if "--hook" in args or "--unhooked" in args:
        n = 0
        for r in sorted(big):
            if "--hook" in args:
                n += add_hook(r)
            elif HOOK_MARK not in open(disk(r), encoding="utf-8").read():
                print(name(r)); n += 1
        print("%s: %d of the big SCC's %d scripts" % ("hooked" if "--hook" in args else "unhooked", n, len(big)))
        return
    if "--list" in args:
        for r in sorted(deps):
            print(name(r), "->", ", ".join(sorted(name(t) for t in deps[r])))
        return
    if "--closure" in args:
        r = arg_res(args[args.index("--closure") + 1])
        c = closure(deps, r)
        print("%s compiles %d scripts, %d KB of source" % (name(r), len(c), sum(sizes[x] for x in c if x in sizes) // 1024))
        for x in sorted(c):
            print("  ", name(x))
        return
    if "--why" in args:
        i = args.index("--why")
        p = path(deps, arg_res(args[i + 1]), arg_res(args[i + 2]))
        if not p:
            print("no path"); return
        for a, b in zip(p, p[1:]):
            print("%s  --[%s]-->  %s" % (name(a), deps[a][b], name(b)))
        return
    bigset = set(big)
    print("scripts: %d, global classes: %d, SCCs: %d" % (len(deps), len(classes), len(sccs)))
    print("biggest SCC: %d scripts, %d KB of source (next: %s)" % (
        len(big), sum(sizes[x] for x in big) // 1024, [len(s) for s in sccs[1:6]]))
    if "--cut" in args:
        # Greedy: remove, one at a time, the edge inside the big SCC whose removal leaves the
        # smallest biggest SCC. Prints the edges in order (a feedback-edge heuristic).
        sub = {v: {w: k for w, k in deps[v].items() if w in bigset} for v in big}
        steps = int(args[args.index("--cut") + 1]) if len(args) > args.index("--cut") + 1 and args[args.index("--cut") + 1].isdigit() else 15
        for _ in range(steps):
            # candidates: edges into the targets most named inside the SCC, then everything
            indeg = collections.Counter(w for v in sub for w in sub[v])
            best = None
            cands = [(v, w) for v in sub for w in sub[v]]
            # cut by TARGET (make one class lazy for all of its users) - that is what a refactor does
            targets = sorted(indeg, key=lambda t: -indeg[t])[:80]
            for t in targets:
                trial = {v: {w: k for w, k in e.items() if w != t} for v, e in sub.items()}
                m = max(len(c) for c in tarjan(trial))
                if best is None or m < best[0]:
                    best = (m, t)
            m, t = best
            users = [v for v in sub if t in sub[v]]
            print("cut all edges INTO %-50s (%d users) -> biggest SCC %d" % (name(t), len(users), m))
            sub = {v: {w: k for w, k in e.items() if w != t} for v, e in sub.items()}
        return
    for r in sorted(big, key=lambda r: -sizes[r])[:30]:
        print("  %6d B  %s" % (sizes[r], name(r)))


if __name__ == "__main__":
    main()
