# Task Management Process

A kanban-style flow that focuses the entire team (human + Claude) on **one task at a time**. The goal is to stop losing work in dense, unstructured TODO files and to make every commit traceable to a planned, measurable task driven by a user story.

## Files

| File | Role |
|---|---|
| [BACKLOG.md](../BACKLOG.md) | Priority-ordered queue of work **to be done**. Two sections: `## Active` (current consideration) and `## Deferred` (intentionally postponed but still in scope). One-line entry per task pointing to its detail file. |
| [STATE.md](../STATE.md) | Single source of truth for the current activity. Survives session interruptions — any skill resumes by reading this first. |
| [docs/backlog/](backlog/) | One markdown file per task, named `<id>.md`. Holds the planned work items, success criteria, parent user story, and lifecycle notes. The file is the **persistent record** — it is never deleted, only moved between indexes. |
| `docs/backlog/last-test.log` | Most recent `make test-long` run (gitignored — regenerable working-tree artifact). Header records task id, git SHA, timestamp; body is the test output. Lets `/execute-task` verify the baseline without re-running. Written by [scripts/test-long.sh](../scripts/test-long.sh). |
| [docs/DONE.md](DONE.md) | Completed tasks, newest first, day-grouped. Pointer back to `docs/backlog/<id>.md`. |
| [docs/PUNT.md](PUNT.md) | Stale tasks no longer worth doing. Pointer back to `docs/backlog/<id>.md` (the marker is preserved so we don't lose the history). |
| [docs/user-stories.md](user-stories.md) | First-principles statements of what the system must do for which customer. Every backlog task has a parent user story. Stories carry a `**Status:**` line: `new` (just written, ungrilled), `unimplemented` (grilled, eligible to drive tasks), `implemented`, `punted`. |

## User stories describe intent, not scope

A user story states **what is intended** for a given customer — the end-state outcome the system delivers. Stories do not carry "in-scope" / "out-of-scope" markers; they describe the goal in full. Whether a particular piece of the intended outcome is being worked on now, later, or never is a **task and backlog decision**, not a property of the story.

Practical consequences:

- A story may describe outcomes the codebase does not yet deliver. That's expected — the story is the destination.
- "Forward direction" notes inside a story are fine for capturing intended pieces that haven't been grilled to a distinct shape yet, but they do not declare scope.
- Whether to file a backlog task against an intended outcome is a `/prioritize-backlog` decision, driven by which `unimplemented` stories are starving and what the success measurement says is missing.
- A story is `implemented` only when the success measurement confirms the entire intended outcome is delivered — not when a chosen subset has been built.

## Task identity

Every task gets an id of the form `YYYYMMDDxx` where `xx` is `aa..zz` (676/day). The date is the day the task entered the backlog (not the day it was planned or executed). The id never changes — a task that gets punted and later revived keeps its original id.

## Task file format (`docs/backlog/<id>.md`)

Two shapes: **leaf** tasks (no children, ~1 human-hour, executed directly) and **parent** tasks (decomposed by `/plan-task` into N children, parent stays as a tracking node).

```markdown
---
id: 20260502aa
title: Short imperative title
status: unplanned | planned | ready | in-progress | done | punted
created: 2026-05-02
parent_story: docs/user-stories.md#section  (or "none" with rationale)
parent_task: 20260502xx        # optional — set if this is a child of another task
depends_on: [20260502yy]       # optional — task ids that must be `done` before this one runs
source: tasks/shapes/p6-next.md#n1  (optional — where this came from at bootstrap)
---

# Summary
One paragraph stating what this task delivers and for whom. **Self-contained** —
a fresh executor reading only this file (no conversation history, no sibling
files) must understand what the task is and why.

# Context
Everything the executor needs to ship the change from cold context. File paths
with line numbers, function signatures, contract descriptions, relevant CLAUDE.md
invariants, MH32e citations for machining rules. **Do NOT reference sibling
tasks or "the planning conversation"** — copy the relevant contract here. The
duplication across siblings is the cost of self-containment; pay it cheerfully.

# Work
What to do, in enough detail that a fresh executor knows where to make the change.
For ~1h leaf tasks, this is a short paragraph plus a few bullets — NOT a multi-step
checklist. The size invariant: one focused commit when done. For parent tasks,
this section says "see # Decomposition for the child task list."

# Success criteria
**Task-specific outcomes. Tests passing is a precondition, NOT the criterion.**
Each criterion must be falsifiable — a way to FAIL it, not just a vibe. Examples:
- "`per_epoch.csv` contains a header row plus N data rows after `make -C train prim-train-mps ARGS='-epochs N'`"
- "Running `prim-infer` on `train/examples/00/01/solid-box.stl` produces JSON with `pred_count >= 1`"

`make test-long` green is a project-wide precondition (CLAUDE.md §"Plan lifecycle"),
assumed across every task — do not list it.

# Decomposition  (parent tasks only; written by /plan-task)
Ordered child task list with dep graph. Parent auto-promotes to `done` when
BOTH (a) every child is `status: done` AND (b) the parent's own success criteria
ALL pass — verified at the moment the last child closes out.

| Order | Child id | depends_on | Title |
|---:|---|---|---|
| 1 | 20260503aa | (none) | ... |
| 2 | 20260503ab | aa | ... |

# Notes
Free-form rationale, gaps discovered, dependencies, links.

# Outcome  (added when status=done)
What actually shipped, plus any follow-up tasks filed.

# Punt reason  (added when status=punted)
Why it is no longer worth doing.
```

### Self-containment requirement

Every task file must survive a context reset. An executor opening it cold should be able to ship the change without:
- Reading conversation history
- Reading sibling task files
- Asking the planner clarifying questions

Cited file paths must be reachable by `grep`/`Read`. Cited contracts must be copied into `# Context`, not pointed at from a sibling. This is what lets `/execute-task` run reliably across context windows and across separate Claude Code sessions.

### Parent / child model (post-2026-05-02 plan-task)

`/plan-task` decomposes a parent into N self-contained ~1h children. Children push to top of `## Active` in `depends_on` order; parent stays in BACKLOG at its existing position (now buried below children). Parent has its own `# Success criteria (parent-level)` for the integration / cross-child gates that no individual child guarantees.

`/execute-task` on the LAST child of a parent (when all sibling children are `done`) verifies the parent's own success criteria; if they pass, the parent auto-promotes to `done` and moves to `docs/DONE.md`. If they fail, the parent stays at `status: ready` and a new follow-up child is filed for the failing criterion.

## STATE.md format

```markdown
---
activity: idle | planning | reviewing | executing | prioritizing | bootstrapping
task: 20260502aa            # empty when activity is idle/prioritizing/bootstrapping
started: 2026-05-02T14:23
---

(optional free-form notes about resume context)
```

**Do not edit these three fields by hand.** The skills call `scripts/state.sh` to transition the activity; that script validates the source state (e.g. refuses `planning → executing` without going through `idle` first) and timestamps `started:` deterministically. Same for task `status:` — `scripts/task-status.sh` enforces the kanban cycle and is the only commit point for the plan/review path. See "Mechanical state transitions" below.

## Test output capture

The plan lifecycle bookends real work with `make test-long` (CLAUDE.md §"Plan lifecycle"). Each run is captured to `docs/backlog/last-test.log` so the next session can verify the baseline without re-running.

Format:

```
task: 20260502aa
sha: b3863a4
run time: 2026-05-03 14:23:00 PDT (epoch 1746309780)
---
<full make test-long output>
```

The header is three lines plus a `---` separator; the body is the verbatim test output (stdout+stderr). The `run time:` line is human-readable (local date + time + zone); the parenthetical epoch is optional but recommended so scripts can compare timestamps without parsing locale strings.

**Do not write this incantation by hand — use [scripts/test-long.sh](../scripts/test-long.sh):**

```sh
scripts/test-long.sh <task-id>
```

Writes the header + `make test-long` output to `docs/backlog/last-test.log`. **Exit status is the result.** Exit 0 means the suite passed — proceed; do not read the log. Non-zero means a failure — open the log, find the failures, surface them to the user. The log exists for diagnosing red runs, not for confirming green ones. Override the log path with `LOG=<path>` for ad-hoc runs.

Use:

- **Before executing a task**, read `docs/backlog/last-test.log`. If the recorded `sha` matches `git rev-parse HEAD` and the output is green, the baseline is locked — proceed.
- **Process-only drift since the recorded baseline: trust it, do not re-run, do not ask.** Run `git diff --name-only <log-sha>..HEAD`. **Strip `.claude/**` paths first** — that tree holds skill definitions, hooks, and commands; nothing under it runs during `make test-long`, so a new hook or skill change cannot have invalidated the green run. Then the check is a **denylist** on source-file extensions: re-run only if at least one remaining path is `*.go`, `*.sh`, `Makefile`, `*.mk`, `go.mod`, `go.sum`, `*.h`, `*.c`, `*.cpp`, or `train/environment.yml`. Otherwise — every returned path is a process file (any `*.md`, any `*.log`, `BACKLOG.md`, `STATE.md`, `docs/DONE.md`, `docs/PUNT.md`, `docs/backlog/*`, `tasks/**/*.md`, `.claude/**`, anything else outside the testing surface) — the baseline is still valid; move forward without stopping the human for confirmation. The testing gates only cover code; process-only commits cannot have invalidated a green test run. Re-run `make test-long` (and overwrite the log) only when the denylist fires or when the prior run was red.
- **After executing a task**, the closing `make test-long` overwrites the log with the new task id, the new HEAD sha, and the new timestamp.
- The file is overwritten, not appended — only the most recent run is kept. History lives in git via the task files in `docs/backlog/<id>.md`.
- **The log file is gitignored** (per `.gitignore`). It floats in the working tree as a regenerable artifact — a fresh clone has no `last-test.log`; the first task to need a baseline regenerates it via `scripts/test-long.sh`. Don't commit it.

## Lifecycle

```
   bootstrap-backlog ──► tasks land in BACKLOG.md (status=unplanned)
                                  │
                                  ▼
                         prioritize-backlog (reorders by user-story balance + risk)
                                  │
                                  ▼
                              plan-task ──► parent decomposed into N self-contained
                                            ~1h child tasks; children push to top of
                                            Active in dependency order; parent stays
                                            (status=planned) with own success criteria
                                  │
                       (gaps surfaced during context-mapping become preceding child
                        tasks rather than restart interrupts)
                                  │
                                  ▼
                            review-task ──► audits parent + each child under five
                                            risk lenses (complexity, customer impact,
                                            business risk, engineering reproducibility,
                                            modeling-slice isolation) + verifies each
                                            child's success criteria contributes to
                                            the parent's end-state
                                  │
                  ┌───────────────┴───────────────┐
            (no issues)                      (issues found)
                  │                               │
                  ▼                               ▼
          status=ready                   status stays planned + each
                  │                      affected file gets a # Open
                  │                      issues block; back to plan-task
                  │                      in grill-and-update mode, which
                  │                      addresses each issue and clears
                  │                      the block, then back to review
                  ▼
                            execute-task ──► picks top child (status=ready);
                                            verifies depends_on satisfied + claimed
                                            deliverables in code; ships one focused
                                            change; checks own success criteria;
                                            promotes child to done
                                  │
                       (last child of a parent? execute-task verifies parent-level
                        success criteria; auto-promotes parent if all gates hold,
                        else files a new follow-up child for the failing criterion)
                                  │
                       (gap discovered mid-execute? new task at top of Active,
                        return to plan-task for the gap)
                                  │
                                  ▼
                       success criteria met + make test-long green
                                  │
                                  ▼
                  status=done, removed from BACKLOG.md, appended to docs/DONE.md
```

## Mechanical state transitions

The skills do not hand-edit `STATE.md` or task-file `status:` frontmatter. Two scripts own those edits and validate every transition; the skill prose calls them.

### `scripts/state.sh <new-activity> [<task-id>]`

Flips `STATE.md`'s `activity:` / `task:` / `started:` fields. Refuses illegal source → target transitions. Legal transitions:

| From | Allowed targets |
|---|---|
| `idle` | any non-idle |
| `planning` | `idle`, `reviewing` |
| `reviewing` | `idle`, `planning` |
| `executing` | `idle`, `planning` (gap discovery) |
| `prioritizing` / `bootstrapping` | `idle` |

`scripts/state.sh idle` is always allowed (close-out). `scripts/state.sh --print` shows the current activity/task/started without modifying anything.

### `scripts/task-status.sh <new-status> <id> [<id> ...]`

Flips the `status:` field in `docs/backlog/<id>.md`. Refuses illegal transitions. Legal kanban cycle:

| From | Allowed targets |
|---|---|
| `unplanned` | `planned` |
| `planned` | `ready` |
| `ready` | `in-progress` |
| `in-progress` | `done`, `planned` (paused on gap) |
| any | `punted` |

Multiple ids are only accepted when the target is `ready` (parent + children promote together per `/review-task`).

**`→ ready` is the only commit point in the plan/review cycle.** The script stages `docs/backlog/`, `BACKLOG.md`, and `STATE.md` and commits as `Ready <first-id> — <first-id title>`. Set `TASK_STATUS_NO_COMMIT=1` to suppress the commit (tests, dry runs).

All other transitions flip the frontmatter and do not commit. `/execute-task` owns its own atomic-commit policy for `in-progress` / `done` work.

### Commit cadence under the new flow

- `/plan-task` (full or grill-and-update): edits files, **does not commit**.
- `/review-task` pass: calls `scripts/task-status.sh ready <ids...>` → single commit captures every plan/review iteration since the last `ready`.
- `/review-task` fail: writes `# Open issues`, **does not commit**. The dirty tree carries into the next `/plan-task` grill round and gets bundled into the eventual `Ready` commit.
- `/execute-task`: commits per work item (atomic) plus a close-out commit, unchanged from before.

Net effect: a planning/review cycle that takes three iterations to reach `ready` produces exactly one planning commit, not three.

## The five skills

| Skill | Purpose |
|---|---|
| `/bootstrap-backlog` | First-time-setup migration. Sweeps `tasks/**/*.md`, `docs/**/*.md`, and top-level markdown files. Each task-shaped item gets its own `docs/backlog/<id>.md` and a BACKLOG.md entry; stale items go to PUNT (with marker preserved); already-completed items go to DONE. Source files retain a back-pointer to their new home. Also walks `docs/user-stories.md`, grills each unmarked story, and tags it `Status: unimplemented`. |
| `/prioritize-backlog` | Reorders BACKLOG.md by balancing across `unimplemented` user stories. No story should starve. Newly-discovered stories are grilled here too. |
| `/plan-task` | Two modes: (a) **full-plan** — pulls the top `unplanned` parent task from `## Active`, maps the larger context to proactively hunt gaps, decomposes into N self-contained ~1h child tasks, sets parent + children to `status: planned`. (b) **grill-and-update** — re-entered when a `planned` task carries a `# Open issues` block written by `/review-task`; addresses each issue in place (editing parent or child files, splitting/adding children as needed) and clears the block. Status remains `planned` after either mode. |
| `/review-task` | Audits a `planned` task under five risk lenses (complexity, customer impact, business risk, engineering reproducibility, modeling-slice isolation) and verifies each child's success criteria contributes to the parent's end-state. On pass, promotes parent + every child from `planned` to `ready`. On fail, leaves status at `planned` and writes a `# Open issues` agenda into each affected task file for `/plan-task` to address. |
| `/execute-task` | Picks the top `ready` child task; verifies its `depends_on` are `done` AND their claimed deliverables exist in code. Ships one focused change (one commit per task per the user's commit policy). Runs `make test` for inner-loop iteration, runs `make test-long` as the completion gate. Verifies the task's own success criteria. On the LAST child of a parent, additionally verifies the parent-level success criteria — auto-promotes the parent to `done` if all gates hold, else files a follow-up child for the failing criterion. Gaps discovered mid-execute file new tasks at the top of `## Active` (`status: unplanned`) and return to planning. |

## Disruption + resume

Every skill's first step is to read STATE.md.

- `activity=planning` and `task=<id>` → resume planning that task. The work-items checklist already partially populated tells you where to pick up.
- `activity=reviewing` and `task=<id>` → resume reviewing. Continue at the next un-reviewed child or the next risk lens not yet applied.
- `activity=executing` and `task=<id>` → resume executing. Continue with the first unchecked work item.
- `activity=prioritizing` → resume the prioritize walk.
- `activity=bootstrapping` → resume the bootstrap sweep at the next un-triaged source file.
- `activity=idle` → start fresh according to the invoked skill.

Skills that would interrupt an active task (e.g. running `/prioritize-backlog` while `/execute-task` is mid-flight) ask the user to confirm before proceeding.

## Discipline crossovers

- The plan-completion gate is `make test-long`, not `make test` — see [.claude/CLAUDE.md](../.claude/CLAUDE.md) §"Plan lifecycle".
- Grilling follows the discipline in [.claude/skills/grill-me/SKILL.md](../.claude/skills/grill-me/SKILL.md): verify-by-grep first, ask judgment questions only.
- Machining-rule tasks must cite Machinery's Handbook 32e per [.claude/CLAUDE.md](../.claude/CLAUDE.md) §"Machining context".
- Tasks that change ShapeSpec counts, training data, or shape lists must update the docs called out in [.claude/CLAUDE.md](../.claude/CLAUDE.md) §"Code".
- **No backwards-compatibility constraints in task design or review** — see [docs/user-stories.md §"Release and versioning"](user-stories.md#release-and-versioning). Nothing has shipped, so tasks freely renumber, rename, restructure, retrain, and reshape internals. "ord-stable," "vocab-locked," and "don't break X" are not valid constraints in `/plan-task` or `/review-task`; if one appears, it is creep and must be removed.
- **Machinist-standard correctness is the only contract that supersedes everything else** — see [docs/user-stories.md §"Success Measurement"](user-stories.md#success-measurement). Release timing, schedule pressure, and "we already shipped X" do not lower it. `/review-task` must reject task framings that trade machinist correctness for delivery speed.
