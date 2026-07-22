#!/usr/bin/env bash
# scripts/state.sh — mechanical STATE.md activity transitions + return-stack ops.
#
# v2 (process-v2): extends v1 with `push`/`pop`/`peek`/`stack` subcommands
# that maintain a YAML `return_stack:` field used by the router/specialized
# skill architecture (see tasks/process-v2/chain-architecture.md).
#
# All v1 behavior is preserved verbatim — this is a drop-in replacement.
#
# Usage (v1, unchanged):
#   scripts/state.sh <new-activity> [<task-id>]
#   scripts/state.sh idle
#   scripts/state.sh --print          # show current activity / task
#
# Usage (v2, new):
#   scripts/state.sh push <skill> <label>   # append a return frame
#   scripts/state.sh pop                    # remove + echo top frame
#   scripts/state.sh peek                   # echo top frame, no mutation
#   scripts/state.sh stack                  # print all frames, top-last
#   scripts/state.sh stack-clear            # remove the return_stack field
#
# Activities (per docs/process.md §STATE.md format):
#   idle | planning | reviewing | executing | prioritizing | bootstrapping
#
# Legal source → target transitions (v1):
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
#
# Return-stack frame format:
#   <skill>:<label>   where both match ^[a-z][a-z0-9-]*$
# Stack is stored inline as:
#   return_stack: frame1 frame2 frame3 ...
# Top of stack = last frame in the line. Empty stack = field absent OR empty.
#
# pop/peek output format (stdout):
#   <skill> <label>   (space-separated, one line)
# stack output format (stdout):
#   <skill> <label>   (one frame per line, bottom-first; top is LAST line)
#
# Exit codes:
#   0 — success
#   1 — runtime error (illegal transition, file missing, empty pop)
#   2 — usage error (bad args, unknown subcommand)

set -euo pipefail

STATE_FILE="${STATE_FILE:-STATE.md}"

# ---------------------------------------------------------------------------
# Event logging (forensic trail; see scripts/log-process-event.sh)
# ---------------------------------------------------------------------------
#
# Every mutating op (push, pop, stack-clear, activity transition, idle's
# implicit stack-clear) appends one tab-separated line to the path the
# helper writes to (default: data/process-events.log). Read-only ops
# (peek, stack, --print) do NOT log.
#
# Failures of the logger never break state.sh — the helper itself swallows
# errors, and the absence of the helper is silently treated as "logging
# disabled."

SCRIPT_DIR_FOR_LOG="$(cd "$(dirname "$0")" && pwd)"
LOG_HELPER="${LOG_HELPER:-$SCRIPT_DIR_FOR_LOG/log-process-event.sh}"

log_event() {
    if [[ -x "$LOG_HELPER" ]]; then
        "$LOG_HELPER" state.sh "$@" 2>/dev/null || true
    fi
}

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 2
}

if [[ $# -eq 0 ]]; then
    usage
fi

# ---------------------------------------------------------------------------
# Field readers / writers
# ---------------------------------------------------------------------------

read_field() {
    local key="$1"
    awk -v k="^${key}:" '$0 ~ k { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' "$STATE_FILE"
}

# Write or update a top-level YAML field. If the field exists, replaces
# the value verbatim. If not, inserts immediately after the `started:`
# line (which every well-formed STATE.md has).
write_field() {
    local key="$1" value="$2"
    local tmp
    tmp=$(mktemp)
    if grep -q "^${key}:" "$STATE_FILE"; then
        awk -v key="$key" -v val="$value" '
            BEGIN { done=0 }
            $0 ~ ("^" key ":") && !done { print key ": " val; done=1; next }
            { print }
        ' "$STATE_FILE" > "$tmp"
    else
        awk -v key="$key" -v val="$value" '
            /^started:/ { print; print key ": " val; next }
            { print }
        ' "$STATE_FILE" > "$tmp"
    fi
    mv "$tmp" "$STATE_FILE"
}

# Remove a top-level YAML field entirely.
remove_field() {
    local key="$1"
    local tmp
    tmp=$(mktemp)
    awk -v k="^${key}:" '$0 !~ k { print }' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Stack subcommands
# ---------------------------------------------------------------------------

validate_frame_part() {
    local part="$1" kind="$2"
    if ! [[ "$part" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "state.sh: $kind '$part' must match ^[a-z][a-z0-9-]*\$" >&2
        exit 2
    fi
}

# Stack ops use string-level operations (not arrays) for bash 3.2
# compatibility (macOS default ships 3.2.57).
#
# Stack representation: space-separated frames in the `return_stack:`
# field. Top of stack = last word. Empty stack = field absent or empty.

cmd_push() {
    if [[ $# -ne 2 ]]; then
        echo "state.sh: push requires <skill> <label>" >&2
        exit 2
    fi
    local skill="$1" label="$2"
    validate_frame_part "$skill" skill
    validate_frame_part "$label" label
    local frame="${skill}:${label}"
    local raw new
    raw=$(read_field return_stack)
    if [[ -z "$raw" ]]; then
        new="$frame"
    else
        new="$raw $frame"
    fi
    write_field return_stack "$new"
    log_event push "${skill}:${label}"
    echo "state.sh: push ${skill}:${label}" >&2
}

cmd_pop() {
    if [[ $# -ne 0 ]]; then
        echo "state.sh: pop takes no arguments" >&2
        exit 2
    fi
    local raw
    raw=$(read_field return_stack)
    if [[ -z "$raw" ]]; then
        echo "state.sh: stack is empty" >&2
        exit 1
    fi
    # Last frame = last word. Rest = everything before the last space, or
    # empty if there was no space (single-frame stack).
    local top="${raw##* }"
    local rest=""
    if [[ "$raw" == *" "* ]]; then
        rest="${raw% *}"
    fi
    if [[ -z "$rest" ]]; then
        remove_field return_stack
    else
        write_field return_stack "$rest"
    fi
    local skill="${top%%:*}"
    local label="${top#*:}"
    log_event pop "${skill}:${label}"
    echo "$skill $label"
}

cmd_peek() {
    if [[ $# -ne 0 ]]; then
        echo "state.sh: peek takes no arguments" >&2
        exit 2
    fi
    local raw
    raw=$(read_field return_stack)
    if [[ -z "$raw" ]]; then
        # An empty stack is a valid state (cold entry), not an error. Peek is a
        # pure query: emit nothing, exit 0. (pop differs — popping an empty stack
        # is a genuine underflow and stays an error.)
        exit 0
    fi
    local top="${raw##* }"
    local skill="${top%%:*}"
    local label="${top#*:}"
    echo "$skill $label"
}

cmd_stack() {
    if [[ $# -ne 0 ]]; then
        echo "state.sh: stack takes no arguments" >&2
        exit 2
    fi
    local raw
    raw=$(read_field return_stack)
    [[ -z "$raw" ]] && return 0
    local f
    for f in $raw; do
        local skill="${f%%:*}"
        local label="${f#*:}"
        echo "$skill $label"
    done
}

cmd_stack_clear() {
    if [[ $# -ne 0 ]]; then
        echo "state.sh: stack-clear takes no arguments" >&2
        exit 2
    fi
    local raw
    raw=$(read_field return_stack)
    remove_field return_stack
    log_event stack-clear "removed: ${raw:-<empty>}"
    echo "state.sh: stack cleared" >&2
}

# ---------------------------------------------------------------------------
# Subcommand dispatch (v2 ops + v1 fall-through)
# ---------------------------------------------------------------------------

if [[ "$1" == "--print" ]]; then
    cur_activity=$(read_field activity)
    cur_task=$(read_field task)
    cur_started=$(read_field started)
    cur_stack=$(read_field return_stack)
    printf 'activity: %s\ntask: %s\nstarted: %s\nreturn_stack: %s\n' \
        "${cur_activity:-idle}" "${cur_task:-}" "${cur_started:-}" "${cur_stack:-}"
    exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
    echo "state.sh: $STATE_FILE not found (cwd=$(pwd))" >&2
    exit 1
fi

case "$1" in
    push)        shift; cmd_push "$@"; exit 0 ;;
    pop)         shift; cmd_pop "$@"; exit 0 ;;
    peek)        shift; cmd_peek "$@"; exit 0 ;;
    stack)       shift; cmd_stack "$@"; exit 0 ;;
    stack-clear) shift; cmd_stack_clear "$@"; exit 0 ;;
esac

# ---------------------------------------------------------------------------
# v1 activity transitions (preserved verbatim from cnc/scripts/state.sh)
# ---------------------------------------------------------------------------

new_activity="$1"
new_task="${2:-}"

case "$new_activity" in
    idle|planning|reviewing|executing|prioritizing|bootstrapping) ;;
    *)
        echo "state.sh: unknown activity or subcommand '$new_activity'" >&2
        echo "  activities: idle | planning | reviewing | executing | prioritizing | bootstrapping" >&2
        echo "  subcommands: push | pop | peek | stack | stack-clear | --print" >&2
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

cur_activity=$(read_field activity)
cur_activity="${cur_activity:-idle}"

# Source → target validation
legal=0
if [[ "$new_activity" == "idle" ]]; then
    legal=1
elif [[ "$cur_activity" == "idle" ]]; then
    legal=1
elif [[ "$cur_activity" == "$new_activity" ]]; then
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
    # Idle also clears the return_stack — no in-flight call frames at idle.
    cleared_stack=$(read_field return_stack)
    remove_field return_stack
    if [[ -n "$cleared_stack" ]]; then
        log_event stack-clear "idle cleared: $cleared_stack"
    fi
else
    new_started="$(date '+%Y-%m-%dT%H:%M%z')"
fi

# Atomic in-place rewrite of the three v1 fields. Anything else (notes,
# lines, baseline, return_stack) is preserved verbatim.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

awk -v a="$new_activity" -v t="$new_task" -v s="$new_started" '
    /^activity:/ && !done_a { print "activity: " a; done_a=1; next }
    /^task:/     && !done_t { print "task: " t;     done_t=1; next }
    /^started:/  && !done_s { print "started: " s;  done_s=1; next }
    { print }
' "$STATE_FILE" > "$tmp"

mv "$tmp" "$STATE_FILE"

log_event transition "${cur_activity}->${new_activity} task=${new_task:--}"

printf 'state.sh: %s → %s' "$cur_activity" "$new_activity" >&2
if [[ -n "$new_task" ]]; then
    printf ' (task=%s)' "$new_task" >&2
fi
printf '\n' >&2
