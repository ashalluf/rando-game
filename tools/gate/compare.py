#!/usr/bin/env python3
"""Compares the PASS / FAIL lists of two smoke-test runs (a plain run and the logs of a sharded one).

Usage: python3 tools/gate/compare.py <a.log>[,<a2.log>...] <b.log>[,<b2.log>...]
Numbers and parenthesised details in the labels are masked (counts, distances and the names of
whatever was picked differ from run to run), so it compares
which checks ran and whether each passed, as a multiset. A sharded run repeats the city's setup
checks once per shard, so a check b has MORE times than a is listed as a note, not a difference.
Prints the differences; exit 1 if any.
"""
import collections
import re
import sys


def checks(paths):
    out = collections.Counter()
    for path in paths.split(","):
        for line in open(path, errors="replace"):
            if line.startswith(("PASS ", "FAIL ")):
                label = re.sub(r"\([^()]*\)", "(.)", line.rstrip("\n"))
                out[re.sub(r"-?\d+(\.\d+)?", "#", label)] += 1
    return out


a, b = checks(sys.argv[1]), checks(sys.argv[2])
print("a: %d checks (%d FAIL), b: %d checks (%d FAIL)" % (
    sum(a.values()), sum(v for k, v in a.items() if k.startswith("FAIL")),
    sum(b.values()), sum(v for k, v in b.items() if k.startswith("FAIL"))))
only_a = a - b
only_b = collections.Counter({k: v for k, v in (b - a).items() if k not in a})
repeated = collections.Counter({k: v for k, v in (b - a).items() if k in a})
for k, v in sorted(only_a.items()):
    print("only in a (x%d): %s" % (v, k[:160]))
for k, v in sorted(only_b.items()):
    print("only in b (x%d): %s" % (v, k[:160]))
if repeated:
    print("note: %d check lines repeat in b (the setup checks of each shard's city)" % sum(repeated.values()))
print("SAME" if not only_a and not only_b else "DIFFERENT")
sys.exit(1 if only_a or only_b else 0)
