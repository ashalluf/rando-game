#!/bin/bash
# gate_slot.sh <command...> - runs a headless smoke test / gate in one of two slots, so at most two
# run at once. Measure memory before trusting two slots: a full smoke test on main took ~3 GB,
# but wt/integration-b reached 10.9 GB at "city scene loads" and was OOM-killed beside another run
# on a 15 GB box (docs/HANDOFF.md 000000). Use one slot (FLEET_SLOTS=1) until that is fixed.
LOCKS="${FLEET_LOCKS:-/tmp/fleet_locks}"
mkdir -p "$LOCKS"
SLOTS="${FLEET_SLOTS:-1}"
while true; do
	for s in $(seq 1 "$SLOTS"); do
		exec 9>"$LOCKS/gate$s.lock"
		if flock -n 9; then
			"$@"
			exit $?
		fi
		exec 9>&-
	done
	sleep 10
done
