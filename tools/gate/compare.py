#!/usr/bin/env python3
"""Compares the PASS / FAIL lists of two smoke-test runs (a plain run and the logs of a sharded one).

Usage: python3 tools/gate/compare.py <a.log>[,<a2.log>...] <b.log>[,<b2.log>...]
Numbers in the labels are masked (counts and distances differ from run to run), so it compares
which checks ran and whether each passed, as a multiset. Prints the differences; exit 1 if any.
"""
import collections
import re
import sys


def checks(paths):
    out = collections.Counter()
    for path in paths.split(","):
        for line in open(path, errors="replace"):
            if line.startswith(("PASS ", "FAIL ")):
                out[re.sub(r"-?\d+(\.\d+)?", "#", line.rstrip("\n"))] += 1
    return out


a, b = checks(sys.argv[1]), checks(sys.argv[2])
print("a: %d checks (%d FAIL), b: %d checks (%d FAIL)" % (
    sum(a.values()), sum(v for k, v in a.items() if k.startswith("FAIL")),
    sum(b.values()), sum(v for k, v in b.items() if k.startswith("FAIL"))))
only_a, only_b = a - b, b - a
for k, v in sorted(only_a.items()):
    print("only in a (x%d): %s" % (v, k[:160]))
for k, v in sorted(only_b.items()):
    print("only in b (x%d): %s" % (v, k[:160]))
sys.exit(1 if only_a or only_b else 0)
