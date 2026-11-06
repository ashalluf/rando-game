#!/usr/bin/env python3
"""Run a command and print its peak resident memory (the biggest single process of it, from
wait4's ru_maxrss), like `/usr/bin/time -v` on a box that has none.

    python3 tools/peak_rss.py [--budget-mb N] [--trace SECONDS] -- godot --headless --path . res://tests/smoke_test.tscn

Prints "PEAK RSS <n> MB" on stderr after the command ends and exits with the command's status,
or 3 when --budget-mb is given and the peak went over it. --trace prints "RSSLOG <s> <MB>" lines
(the whole process tree) every SECONDS while it runs, interleaved with the command's output.
"""
import os
import subprocess
import sys
import threading
import time


def _tree_rss_kb(pid: int) -> int:
    """Resident memory of pid and its descendants, in kB."""
    total = 0
    todo = [pid]
    while todo:
        p = todo.pop()
        try:
            with open("/proc/%d/status" % p) as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
            with open("/proc/%d/task/%d/children" % (p, p)) as f:
                todo += [int(c) for c in f.read().split()]
        except OSError:
            pass
    return total


def _trace(pid: int, every: float) -> None:
    """Prints "RSSLOG <seconds> <MB>" on stderr every `every` seconds while pid runs."""
    t0 = time.time()
    while True:
        kb = _tree_rss_kb(pid)
        if kb == 0:
            return
        print("RSSLOG %.0f %d" % (time.time() - t0, kb // 1024), file=sys.stderr, flush=True)
        time.sleep(every)


def main() -> int:
    args = sys.argv[1:]
    budget = 0
    trace = 0.0
    while args[:1] in (["--budget-mb"], ["--trace"]):
        if args[0] == "--budget-mb":
            budget = int(args[1])
        else:
            trace = float(args[1])
        args = args[2:]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    proc = subprocess.Popen(args)
    if trace > 0:
        threading.Thread(target=_trace, args=(proc.pid, trace), daemon=True).start()
    _, status, usage = os.wait4(proc.pid, 0)
    code = os.waitstatus_to_exitcode(status)
    peak_mb = usage.ru_maxrss // 1024
    print("PEAK RSS %d MB" % peak_mb, file=sys.stderr)
    if budget and peak_mb > budget:
        print("PEAK RSS %d MB is over the budget of %d MB" % (peak_mb, budget), file=sys.stderr)
        return 3
    return code


if __name__ == "__main__":
    sys.exit(main())
