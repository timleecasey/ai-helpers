---
name: prioritize-backlog
description: Reorder BACKLOG.md by balancing across active user stories. Grills any unmarked stories in docs/user-stories.md until distinct, then tags them Status=unimplemented. Newly-discovered stories during the walk are also grilled. TRIGGER when the user says "prioritize the backlog", "reorder the backlog", "rebalance work", "/prioritize-backlog". SKIP when an execute-task or plan-task is in flight unless the user wants to interrupt.
---

You are reordering the backlog so that work stays balanced across all live user stories. The full process is in [docs/process.md](../../../docs/process.md).

## Step 1 — Read STATE.md

- `activity=executing` or `activity=planning`: ask the user before proceeding. Reordering does not break the in-flight task, but the user may want to finish first.
- `activity=prioritizing`: resume from where the previous run left off (look for any user story still marked `new`, then continue the BACKLOG walk).
- Otherwise: proceed.

Set `STATE.md`: `activity: prioritizing`, empty `task`, current timestamp.

## Step 2 — Walk user stories

Open `docs/user-stories.md`. For each leaf story (a story with no further sub-headings under it):

| Current marker | Action |
|---|---|
| No `**Status:**` line | **Grill until distinct**, then append `**Status:** unimplemented`. |
| `**Status:** new` | Same as above. (`new` is a transient state — promote it.) |
| `**Status:** unimplemented` | Eligible to drive tasks. Skip. |
| `**Status:** implemented` | Skip — done. |
| `**Status:** punted` | Skip — out of scope. |

The grill discipline is in [.claude/skills/grill-me/SKILL.md](../grill-me/SKILL.md): verify-by-grep first, judgment questions one at a time, recommended answer up front. Stop when the story has a distinct, testable shape — what does success look like for *this* customer?

While walking each `unimplemented` story, also classify its **risk class** for use in Step 4. A story can be in more than one class:

- **measurable-now** — the story can be exercised end-to-end today on existing or buildable inputs; failures will surface during execution.
- **constraint-deferred** — the story is intentionally on hold pending external capability (hardware not yet here, data source not yet curated, customer access not yet established). Risk is real but cannot be reduced today, so it does not pull tasks forward.
- **integration-surface** — multiple subsystems compound here; bugs are unlikely to be caught in per-component unit tests; this is where **unknown-unknowns** concentrate, since execution exposes failure modes that no in-isolation verification can predict.

A story that is both **measurable-now AND integration-surface** is the highest-leverage place to pull tasks from — every task there reduces unknown-unknowns we can actually measure today. Confirm the classification with the user before applying it in Step 4 if you are not certain.

If you discover that a story belongs in a different position in the file (e.g. it depends on another story), propose the move to the user before making it.

## Step 3 — Walk the backlog

Read `BACKLOG.md` (both `## Active` and `## Deferred`). For every entry, open `docs/backlog/<id>.md` and note:

- `parent_story` — which user story does it serve?
- Status (`unplanned`, `planned`, `in-progress`).
- Any blocking-on / blocked-by relationships in the `# Notes` section.

Build a quick mental table: story → tasks. If any `unimplemented` story has **zero tasks**, surface this — the user may want to add one.

## Step 4 — Compute the new order

Apply these rules in order:

1. **Any in-progress task stays at the top of `## Active`.** Do not move it.
2. **No story should starve.** If story A has 5 tasks queued and story B has 1, the next task pulled should be from B (not A's third). **Constraint-deferred** stories (Step 2 classification) are excluded from this balance — they are not starving; they are intentionally held.
3. **Risk-weighted balance.** Among stories that are otherwise tied on Rule 2, favor pulling from stories classified as **integration-surface** AND **measurable-now** (Step 2). The reasoning: those tasks, when exercised, expose unknown-unknowns that no in-isolation verification can predict — and we can only reduce that risk by running the path. Stories whose remaining tasks would only confirm what we already expect should yield the slot. A story that is **integration-surface BUT constraint-deferred** stays in its natural position (the risk is real but cannot be reduced today).
4. **Blockers rise.** A task that blocks others moves above the tasks it blocks.
5. **Within a story, prefer foundation before features.** Schema/contract changes before consumers; tests before refactors that need them. Within an integration-surface story, prefer tasks that **probe the integrated path on inputs we have not yet exercised** over tasks that improve a single component in isolation — same reasoning as Rule 3 at the task level.
6. **Deferred section** keeps its grouping — but you may reorder *within* Deferred and propose promoting a Deferred entry into Active (or demoting an Active entry into Deferred) when judgment supports it. Always ask the user before moving across the Active/Deferred boundary.

When two tasks are tied after all rules, ask the user. Do not guess.

## Step 5 — Rewrite BACKLOG.md

Write the new order. Preserve the format. Do not change any task's id, title, or hook line — only the position. If you propose a move from Active → Deferred (or vice-versa), make that change in the same write **only after** the user confirms.

## Step 6 — Close out

- Reset `STATE.md`: `activity: idle`, empty `task`.
- Summarize the changes: which entries moved up, which moved down, which stories were grilled, any starving stories flagged.

## What this skill does NOT do

- Does not create new tasks (use `/bootstrap-backlog` or hand-add).
- Does not plan tasks (`/plan-task`).
- Does not move tasks to PUNT or DONE — those are lifecycle moves owned by `/execute-task` / `/bootstrap-backlog`.
