#!/usr/bin/env bash

set -eu

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIANIST_WATCHDOG_SECONDS=2 source "$repo_dir/scripts/restart-plasma.sh"

sleep() { :; }
service_state() { printf 'active\n'; }
service_main_pid() { printf '%s\n' "$$"; }
plasma_responds() { return 0; }
service_memory() { printf '%s\n' $((256 * 1024 * 1024)); }

observe_plasma >/dev/null
[[ "$health_summary" == *"pid=$$"* ]]

plasma_responds() { return 1; }
if observe_plasma >/dev/null; then
    echo 'expected an unresponsive D-Bus check to fail' >&2
    exit 1
fi
[[ "$failure_reason" == *"D-Bus"* ]]

plasma_responds() { return 0; }
service_memory() { printf '%s\n' $((3 * 1024 * 1024 * 1024)); }
if observe_plasma >/dev/null; then
    echo 'expected the memory safety limit to fail' >&2
    exit 1
fi
[[ "$failure_reason" == *"2 GiB"* ]]

echo 'restart-plasma.sh: watchdog checks passed'
