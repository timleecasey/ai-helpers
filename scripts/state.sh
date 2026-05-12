#!/usr/bin/env bash
# scripts/state.sh — mechanical STATE.md activity transitions.
#
# The kanban skills (/plan-task, /review-task, /execute-task,
# /prioritize-backlog, /bootstrap-backlog) used to inline-edit STATE.md's
# `activity:` / `task:` / `started:` fields. That left room for typos and
# illegal transitions. This script does the edit deterministically and
# validates the source state.
#
# Usage:
#   scripts/state.sh <new-activity> [<task-id>]
#   scripts/state.sh idle
#   scripts/state.sh --print          # show current activity / task
#
# Activities (per docs/process.md §STATE.md format):
#   idle | planning | reviewing | executing | prioritizing | bootstrapping
#
# Legal source → target transitions:
#   any         → idle           (close-out is always allowed)
#   idle        → any non-idle   (start a new activity)
#   planning    → reviewing      (cross-skill jump for grill→review)
#   reviewing   → planning       (review fail; re-grill open issues)
#   executing   → planning       (gap discovered mid-execute)
#
# Anything else is refused; idle first if the user wants to switch tracks.
#
# task-id is required for planning/reviewing/executing, forbidden for
# idle, and optional for prioritizing/bootstrapping.

set -euo pipefail

STATE_FILE="${STATE_FILE:-STATE.md}"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 2
}

if [[ $# -eq 0 ]]; then
    usage
fi

read_field() {
    local key="$1"
    awk -v k="^${key}:" '$0 ~ k { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' "$STATE_FILE"
}

if [[ "$1" == "--print" ]]; then
    cur_activity=$(read_field activity)
    cur_task=$(read_field task)
    cur_started=$(read_field started)
    printf 'activity: %s\ntask: %s\nstarted: %s\n' \
        "${cur_activity:-idle}" "${cur_task:-}" "${cur_started:-}"
    exit 0
fi

new_activity="$1"
new_task="${2:-}"

case "$new_activity" in
    idle|planning|reviewing|executing|prioritizing|bootstrapping) ;;
    *)
        echo "state.sh: unknown activity '$new_activity'" >&2
        echo "  valid: idle | planning | reviewing | executing | prioritizing | bootstrapping" >&2
        exit 2
        ;;
esac

# Argument shape rules
case "$new_activity" in
    idle)
        if [[ -n "$new_task" ]]; then
            echo "state.sh: 'idle' takes no task-id (got '$new_task')" >&2
            exit 2
        fi
        ;;
    planning|reviewing|executing)
        if [[ -z "$new_task" ]]; then
            echo "state.sh: '$new_activity' requires a task-id" >&2
            exit 2
        fi
        if ! [[ "$new_task" =~ ^[0-9]{8}[a-z]{2}$ ]]; then
            echo "state.sh: task-id '$new_task' is not YYYYMMDDxx" >&2
            exit 2
        fi
        ;;
    prioritizing|bootstrapping)
        # task-id optional; ignore if absent
        ;;
esac

if [[ ! -f "$STATE_FILE" ]]; then
    echo "state.sh: $STATE_FILE not found (cwd=$(pwd))" >&2
    exit 1
fi

cur_activity=$(read_field activity)
cur_activity="${cur_activity:-idle}"

# Source → target validation
legal=0
if [[ "$new_activity" == "idle" ]]; then
    legal=1
elif [[ "$cur_activity" == "idle" ]]; then
    legal=1
elif [[ "$cur_activity" == "$new_activity" ]]; then
    # No-op resume (e.g. reviewing → reviewing on the same task).
    legal=1
elif [[ "$cur_activity" == "planning" && "$new_activity" == "reviewing" ]]; then
    legal=1
elif [[ "$cur_activity" == "reviewing" && "$new_activity" == "planning" ]]; then
    legal=1
elif [[ "$cur_activity" == "executing" && "$new_activity" == "planning" ]]; then
    legal=1
fi

if [[ "$legal" -ne 1 ]]; then
    cur_task=$(read_field task)
    echo "state.sh: refusing transition '$cur_activity' (task=${cur_task:-<none>}) → '$new_activity'" >&2
    echo "  Run 'scripts/state.sh idle' first if you want to switch tracks." >&2
    exit 1
fi

if [[ "$new_activity" == "idle" ]]; then
    new_task=""
    new_started=""
else
    new_started="$(date '+%Y-%m-%dT%H:%M%z')"
fi

# Atomic in-place rewrite of the three fields. Anything else (notes,
# last_close lines, baseline) is preserved verbatim.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

awk -v a="$new_activity" -v t="$new_task" -v s="$new_started" '
    /^activity:/ && !done_a { print "activity: " a; done_a=1; next }
    /^task:/     && !done_t { print "task: " t;     done_t=1; next }
    /^started:/  && !done_s { print "started: " s;  done_s=1; next }
    { print }
' "$STATE_FILE" > "$tmp"

mv "$tmp" "$STATE_FILE"

printf 'state.sh: %s → %s' "$cur_activity" "$new_activity" >&2
if [[ -n "$new_task" ]]; then
    printf ' (task=%s)' "$new_task" >&2
fi
printf '\n' >&2
