#!/usr/bin/env bash
# scripts/parent-task-completion.sh — roll up child statuses for a parent task.
#
# Walks docs/backlog/*.md for files whose frontmatter sets
#   parent_task: <PARENT_ID>
# and reports each child's status plus an "X of Y completed" summary.
#
# Usage:
#   scripts/parent-task-completion.sh --children <parent-id>
#
# Output (one child per line, then a summary):
#   20260509aj status: done
#   20260509ak status: done
#   ...
#   ---
#   13 of 13 completed (done=12, punted=1)
#   DONE
#
# A child is "completed" iff its status is `done` or `punted`. Both are
# closed branches from the parent's point of view — see /review-task and
# /execute-task lifecycle docs.
#
# Exit codes:
#   0 — all children completed (DONE)
#   1 — at least one child not completed (INCOMPLETE)
#   2 — usage / IO error
#   3 — no children found with parent_task: <id> (parent is a leaf or id wrong)
#
# This script REPLACES the manual "for each child id, open the child's
# frontmatter and confirm status: done" loop in the /execute-task
# parent-auto-promotion step. Callers can branch on the exit code:
#
#   if scripts/parent-task-completion.sh --children "$pid" >/dev/null; then
#       # parent's children are all done/punted — check parent's own gates
#   fi
#
# BACKLOG_DIR (default: docs/backlog) can be overridden for tests.

set -euo pipefail

BACKLOG_DIR="${BACKLOG_DIR:-docs/backlog}"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 2
}

read_field() {
    # read_field <file> <field-name> — print frontmatter field value (or empty).
    awk -v f="$2" '
        /^---[[:space:]]*$/ { delim++; if (delim==2) exit; next }
        delim==1 {
            if (match($0, "^" f ":[[:space:]]*")) {
                v = substr($0, RLENGTH + 1)
                sub(/[[:space:]]+$/, "", v)
                print v
                exit
            }
        }
    ' "$1"
}

[[ $# -ge 1 ]] || usage

case "$1" in
    --children) ;;
    -h|--help) usage ;;
    *)
        echo "parent-task-completion.sh: unknown subcommand '$1'" >&2
        echo "  expected: --children <parent-id>" >&2
        exit 2
        ;;
esac

shift
if [[ $# -ne 1 ]]; then
    echo "parent-task-completion.sh: --children requires exactly one parent id" >&2
    exit 2
fi
pid="$1"

if ! [[ "$pid" =~ ^[0-9]{8}[a-z]{2}$ ]]; then
    echo "parent-task-completion.sh: parent id '$pid' is not YYYYMMDDxx" >&2
    exit 2
fi

if [[ ! -d "$BACKLOG_DIR" ]]; then
    echo "parent-task-completion.sh: $BACKLOG_DIR not found (run from repo root?)" >&2
    exit 2
fi

# Collect every child file. Task ids are alphanumeric, so paths have no
# spaces — a plain newline-delimited sort is sufficient.
children=()
while IFS= read -r file; do
    pt=$(read_field "$file" "parent_task")
    if [[ "$pt" == "$pid" ]]; then
        children+=("$file")
    fi
done < <(find "$BACKLOG_DIR" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ${#children[@]} -eq 0 ]]; then
    echo "parent-task-completion.sh: no children found with parent_task: $pid" >&2
    exit 3
fi

# Per-status counts + completed roll-up.
declare -a status_keys=()
declare -a status_vals=()

bump_status() {
    local st="$1" i
    for ((i = 0; i < ${#status_keys[@]}; i++)); do
        if [[ "${status_keys[$i]}" == "$st" ]]; then
            status_vals[$i]=$(( ${status_vals[$i]} + 1 ))
            return
        fi
    done
    status_keys+=("$st")
    status_vals+=(1)
}

completed=0
total=0
for file in "${children[@]}"; do
    id=$(basename "$file" .md)
    st=$(read_field "$file" "status")
    [[ -n "$st" ]] || st="?"
    printf '%s status: %s\n' "$id" "$st"
    bump_status "$st"
    if [[ "$st" == "done" || "$st" == "punted" ]]; then
        completed=$(( completed + 1 ))
    fi
    total=$(( total + 1 ))
done

echo "---"

# Stable status-name order for the breakdown.
breakdown=""
for st in $(printf '%s\n' "${status_keys[@]}" | sort); do
    for ((i = 0; i < ${#status_keys[@]}; i++)); do
        if [[ "${status_keys[$i]}" == "$st" ]]; then
            if [[ -n "$breakdown" ]]; then
                breakdown="${breakdown}, "
            fi
            breakdown="${breakdown}${st}=${status_vals[$i]}"
            break
        fi
    done
done
printf '%d of %d completed (%s)\n' "$completed" "$total" "$breakdown"

if [[ "$completed" -eq "$total" ]]; then
    echo "DONE"
    exit 0
else
    echo "INCOMPLETE"
    exit 1
fi
