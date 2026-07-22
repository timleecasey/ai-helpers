#!/usr/bin/env bash
# scripts/task-status.sh — mechanical task-frontmatter status transitions.
#
# Each task in docs/backlog/<id>.md carries a `status:` field cycling
# through unplanned → planned → ready → in-progress → done (or → punted).
# This script flips it deterministically and validates the source state.
#
# Usage:
#   scripts/task-status.sh <new-status> <id> [<id> ...]
#   scripts/task-status.sh --print <id>
#
# Statuses (per docs/process.md §"Task file format"):
#   unplanned | planned | ready | in-progress | done | punted
#
# Legal source → target transitions:
#   unplanned   → planned       (/plan-task full-plan mode)
#   planned     → ready         (/review-task pass)
#   planned     → unplanned     (/plan-task grill-and-update demotes a child back
#                                under the children-at-unplanned model — children
#                                start as unplanned siblings of a planned parent,
#                                each gets its own /plan-task pass later; see
#                                .claude/skills/plan-task/SKILL.md §"Step 4-bis")
#   ready       → in-progress   (/execute-task start)
#   in-progress → done          (/execute-task close-out)
#   in-progress → planned       (/execute-task gap discovered, task paused)
#   <any>       → punted        (give up)
#
# Anything else is refused.
#
# Special behavior for `ready`:
#   • Normally called with a single id — /review-task promotes parent
#     only (children stay `unplanned` and progress through their own
#     /plan-task → /review-task cycles per docs/process.md §"Parent /
#     child model"). Multi-id form is retained for ad-hoc batch promotion.
#   • After flipping all ids, stages docs/backlog/, BACKLOG.md, and
#     STATE.md, then creates a single commit:
#         "Ready <first-id> — <first-id title>"
#     This is the only commit point in the plan/review cycle — see
#     docs/process.md §Lifecycle.
#   • Set TASK_STATUS_NO_COMMIT=1 to skip the commit (tests, dry runs).
#
# All other transitions flip a single id and do NOT commit; commits for
# in-progress / done / punted are owned by /execute-task per its
# atomic-commit policy.

set -euo pipefail

BACKLOG_DIR="${BACKLOG_DIR:-docs/backlog}"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 2
}

if [[ $# -lt 2 ]]; then
    usage
fi

read_status() {
    local file="$1"
    awk '
        /^---[[:space:]]*$/ { delim++; if (delim==2) exit; next }
        delim==1 && /^status:/ {
            sub(/^status:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

read_title() {
    local file="$1"
    awk '
        /^---[[:space:]]*$/ { delim++; if (delim==2) exit; next }
        delim==1 && /^title:/ {
            sub(/^title:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

task_file() {
    echo "${BACKLOG_DIR}/$1.md"
}

is_legal() {
    local from="$1" to="$2"
    [[ "$to" == "punted" ]] && return 0
    [[ "$from" == "$to" ]] && return 0   # idempotent re-flip
    case "$from→$to" in
        unplanned→planned)   return 0 ;;
        planned→ready)       return 0 ;;
        planned→unplanned)   return 0 ;;  # /plan-task grill-and-update can demote a child back to unplanned (children-at-unplanned model; per .claude/skills/plan-task/SKILL.md Step 4-bis)
        ready→in-progress)   return 0 ;;
        in-progress→done)    return 0 ;;
        in-progress→planned) return 0 ;;
    esac
    return 1
}

flip_status() {
    local file="$1" new="$2"
    local tmp
    tmp=$(mktemp)
    awk -v s="$new" '
        BEGIN { delim=0; done=0 }
        /^---[[:space:]]*$/ { delim++; print; next }
        delim==1 && !done && /^status:/ {
            print "status: " s
            done=1
            next
        }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

if [[ "$1" == "--print" ]]; then
    id="$2"
    file="$(task_file "$id")"
    [[ -f "$file" ]] || { echo "task-status.sh: $file not found" >&2; exit 1; }
    cur=$(read_status "$file")
    title=$(read_title "$file")
    printf 'id: %s\nstatus: %s\ntitle: %s\n' "$id" "${cur:-?}" "${title:-?}"
    exit 0
fi

new_status="$1"
shift
ids=("$@")

case "$new_status" in
    unplanned|planned|ready|in-progress|done|punted) ;;
    *)
        echo "task-status.sh: unknown status '$new_status'" >&2
        echo "  valid: unplanned | planned | ready | in-progress | done | punted" >&2
        exit 2
        ;;
esac

# Multi-id only allowed for ready (parent + children promote together).
if [[ ${#ids[@]} -gt 1 && "$new_status" != "ready" ]]; then
    echo "task-status.sh: multiple ids only allowed for '→ ready' (parent + children)" >&2
    echo "  got status='$new_status' ids='${ids[*]}'" >&2
    exit 2
fi

# Validate every id, gather affected files.
files=()
for id in "${ids[@]}"; do
    if ! [[ "$id" =~ ^[0-9]{8}[a-z]{2}$ ]]; then
        echo "task-status.sh: id '$id' is not YYYYMMDDxx" >&2
        exit 2
    fi
    file="$(task_file "$id")"
    if [[ ! -f "$file" ]]; then
        echo "task-status.sh: $file not found" >&2
        exit 1
    fi
    cur=$(read_status "$file")
    if [[ -z "$cur" ]]; then
        echo "task-status.sh: $file has no 'status:' frontmatter field" >&2
        exit 1
    fi
    if ! is_legal "$cur" "$new_status"; then
        echo "task-status.sh: refusing $id transition '$cur' → '$new_status'" >&2
        echo "  Legal: unplanned→planned, planned→{ready,unplanned}, ready→in-progress," >&2
        echo "         in-progress→{done,planned}, *→punted" >&2
        exit 1
    fi
    files+=("$file")
done

# Apply the flips.
for i in "${!ids[@]}"; do
    file="${files[$i]}"
    cur=$(read_status "$file")
    if [[ "$cur" != "$new_status" ]]; then
        flip_status "$file" "$new_status"
        echo "task-status.sh: ${ids[$i]} $cur → $new_status" >&2
    else
        echo "task-status.sh: ${ids[$i]} already $new_status (no-op)" >&2
    fi
done

# Commit only on → ready, only when not suppressed, only when the commit
# bundle is non-empty.
if [[ "$new_status" == "ready" && "${TASK_STATUS_NO_COMMIT:-0}" != "1" ]]; then
    if ! command -v git >/dev/null 2>&1; then
        echo "task-status.sh: git not found; skipping commit" >&2
        exit 0
    fi
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "task-status.sh: not inside a git work tree; skipping commit" >&2
        exit 0
    fi

    git add "$BACKLOG_DIR" BACKLOG.md STATE.md 2>/dev/null || true

    if git diff --cached --quiet; then
        echo "task-status.sh: nothing staged; skipping commit" >&2
        exit 0
    fi

    first_id="${ids[0]}"
    first_title=$(read_title "$(task_file "$first_id")")
    msg_subject="Ready ${first_id} — ${first_title:-task}"

    git commit -m "$msg_subject" >&2
    echo "task-status.sh: committed: $msg_subject" >&2
fi
