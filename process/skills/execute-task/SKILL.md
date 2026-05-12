---
name: execute-task
description: Implement the ready task at the top of BACKLOG.md (or the in-progress task in STATE.md). Walk the work-item checklist, run inner-loop tests, gate completion on make test-long, and move the entry from BACKLOG.md to docs/DONE.md when finished. Gaps discovered during execution file new tasks at the top of the backlog and return control to plan-task. TRIGGER when the user says "execute the task", "start working", "implement it", "/execute-task". SKIP if no task has status=ready.
---

You are implementing a single planned task from start to finish. Quality and correctness are the primary metric — see [.claude/CLAUDE.md](../../../.claude/CLAUDE.md) §"Code". Full process in [docs/process.md](../../../docs/process.md).

## Step 1 — Read STATE.md

- `activity=executing` and `task=<id>`: resume that task. Open `docs/backlog/<id>.md`, find the first unchecked work item, continue from there.
- `activity=planning`: ask the user — planning isn't finished. Should they finish first, or pick a different task?
- `activity=idle`: continue.

## Step 2 — Pick the task

Look at `STATE.md` first; if `task` is set and the file exists, use that. Otherwise read `BACKLOG.md` and take the top entry under `## Active`.

Open `docs/backlog/<id>.md`. Verify `status: ready`. Other statuses get a refusal:
- `unplanned` — *"Task `<id>` hasn't been planned yet. Run `/plan-task` first."*
- `planned` — *"Task `<id>` is planned but not yet reviewed. Run `/review-task`; if it passes, the task will move to `ready` and I can execute it."*
- `in-progress` — resume execution from the first unchecked work item.
- `done` / `punted` — task is closed; nothing to execute. Stop.

### Step 2a — Verify `depends_on` is satisfied (mandatory)

Read the task's `depends_on` frontmatter list. For each id in the list:

1. Open `docs/backlog/<dep-id>.md`.
2. Confirm its frontmatter says `status: done`.
3. **Verify the dependency's claimed deliverable actually exists in the current code.** A `done` task that shipped a function `X` should leave `X` greppable; a `done` task that wired a JSON field should leave the field present. The "verified in code" check from the user's plan-task model lives here.

If any dependency is not `done`, OR is `done` but its claimed deliverable is missing in code:
- Tell the user: *"Task `<id>` depends on `<dep-id>` which is `status: <X>` (or shipped artifact missing). Run `/plan-task` or `/execute-task` for `<dep-id>` first."*
- Do NOT modify STATE.md. Stop.

If the task has no `depends_on` (empty list or field absent), proceed.

## Step 2.4 — Read the docs (mandatory)

Self-containment of the task file does not mean "ignore the surrounding context." The task tells you what to do; the docs tell you what _correct_ looks like in this codebase. You will be making decisions during execution that the task file alone cannot disambiguate. Re-reading is cheap; guessing is not.

**Always read at the start of execution:**

1. [README.md](../../../README.md) — repo orientation.
2. [docs/system.md](../../../docs/system.md) — top-down architecture.
3. [docs/process.md](../../../docs/process.md) — the kanban + test-log discipline this skill enforces.
4. [.claude/CLAUDE.md](../../../.claude/CLAUDE.md) — invariants. The Build, Plan-lifecycle, Code, Debugging, Architecture, and gotch sections all bear directly on execution.
5. The task file itself, [docs/backlog/<id>.md](../../../docs/backlog/), in full — frontmatter, # Summary, # Context, # Work, # Success criteria, # Notes.
6. The parent user story (the `parent_story:` field path) so you understand the customer outcome the task ladders into.

**Conditionally read, driven by what the task touches:**

- Look at the file paths cited in the task's `# Context` and `# Work`. For each one, find its directory in the **Context routing table** in [.claude/CLAUDE.md](../../../.claude/CLAUDE.md) §"Context — read before working in an area" and read the mapped `docs/context/<topic>.md` file. That table is the single source of truth for which area-doc covers which directory; do not guess.
- If the task has a `parent_task:` or sibling tasks, read their `# Outcome` sections so you know what already shipped.
- If the task touches machining rules, read the relevant `tasks/stl2gcode/research/machinerys-handbook-32-*.md` summary cited in the task. Per `.claude/CLAUDE.md` §"Machining context", code that encodes machining rules must cite the Handbook section — you cannot do that without reading it.

**Re-read during execution, not just at the start.** When a work item moves you into a directory or area you have not touched yet, stop and re-check the routing table for that directory. Cold-context guessing is the failure mode this step exists to prevent.

## Step 2.5 — Fixed execution policy (do not ask)

This skill's policy is fixed; the user does not need to be asked. Two rules hold for every execution:

1. **Always end-to-end.** Run all work items in `# Work` from start to close-out in one execution. Do not ask the user to pick a stop point. Do not propose intermediate stops.  Long-running artifacts (multi-hour training, large downloads, schema migrations) still get done in this execution; flag them in your status update so the user knows what's underway, but do not pause to ask. The user can interrupt at any time if they want a stop.
2. **Always atomic commits.** After each green work item, create a separate commit. Atomic per `.claude/CLAUDE.md` §"Code" (mechanical moves separate from logic changes; never mix file-move with parameter-rename in one commit). The inner-loop test from Step 4 item 3 runs as a SEPARATE step BEFORE the commit — never `||`-chained, per `.claude/CLAUDE.md` §"Code" (the rule that produced the P3b 0.1 broken-commit incident).

Both rules carry across resumes; nothing to record in STATE.md.

## Step 3 — Sanity check the baseline (`make test`)

Every commit on this branch is green by invariant — the project's rule is **never break the build**, no exceptions. Pre-flight is not a bookend that re-proves what's already proven; it's a 3-second smoke check that `git` handed us a buildable HEAD and that no out-of-band change rotted the tree. Run the inner-loop tests:

```sh
make test 2>&1 | tee /tmp/exec-<id>-baseline.log | tail -5
```

- **exit 0** → proceed to Step 4 silently. Do not announce success; the user already knows the baseline is green from the invariant.
- **exit non-zero** → stop. Surface the failures to the user. Per `.claude/CLAUDE.md` §"Code", investigate and fix — never work around. The task does not start while the inner loop is red.

The wider `make test-long` (~72s, covers `train/` and other gotch packages) runs at task close-out (Step 6) as the release gate, not here. The invariant says every commit is green at release quality, so re-running test-long pre-flight is duplicate work that the daily flow does not need.

Test coverage of release-quality functionality is `/review-task`'s job — see [review-task SKILL.md](../review-task/SKILL.md) §"Release coverage" lens. If the work this task adds isn't covered by `make test`, that's a review-task finding, not an execute-task pre-flight problem.

Set STATE.md and flip the task status mechanically:

```sh
scripts/state.sh executing <id>
scripts/task-status.sh in-progress <id>
```

Both scripts validate the source state — `state.sh` requires `activity: idle` (or same activity for resume); `task-status.sh` requires `status: ready` for the `→ in-progress` transition.

## Step 4 — Walk the work-item checklist

For each unchecked `- [ ]` item in `# Work items`:

1. Implement it. Edit existing files in preference to creating new ones. Interface-driven dispatch over switches. Do not add features beyond what the task requires.

2. **Every changed or new function gets a test in the same change.** This is a hard rule, not a guideline. Recent retrospectives have flagged thinning test coverage — that ends here. The bar:

   - **Behavior, not smoke.** Assert _what the function returns or does_, not merely "did not panic." `assert.NotNil(result)` is not a test. A test that would pass against a stub `return nil` implementation is not a test.
   - **Degenerate / boundary cases are mandatory**, not optional, per `.claude/CLAUDE.md` §"Code" and §"Plan lifecycle". For geometric code: zero-width features, coincident boundaries, empty inputs, single-point clouds, off-by-cell quantization. For numerical code: NaN, ±Inf, zero, denormals, sign boundaries. For collection code: empty, length-1, capacity boundaries. If you cannot enumerate the degenerate cases for the function you wrote, you do not yet understand the function.
   - **File pairing**, per `.claude/CLAUDE.md` §"Code". `foo.go` pairs with `foo_test.go` in the same directory. New source file → new test file with the matching name in the same diff. ShapeSpec generators belong in `generation_test.go`, not `stl_test.go`.
   - **Hard-to-test = code smell, not test exemption.** If a function is awkward to test, refactor it (extract a seam, surface a dependency, narrow the contract) before writing the test. Do not wrap untestable code in a smoke test and move on.
   - **No smuggling test removal under "refactor".** If a refactor removes assertions, the assertions must reappear (in the same or a clearer form) in the same diff. Net assertion count must not drop.

3. Run the inner-loop tests, separately, before committing:

   ```sh
   make test 2>&1 | tee /tmp/<id>-step.log | tail -5
   ```

   Inspect the result. **Do not** chain the test into a `git commit` via `||` — see `.claude/CLAUDE.md` §"Code" for the safe pattern.

4. **Test-coverage self-check (mandatory before checkoff).** Before marking the work item done, audit:

   - Run `git diff --stat HEAD` (or against the work-item commit's parent if already committed). For each `*.go` file added or modified, confirm the matching `*_test.go` was added or modified in the same diff. If a source file changed and its paired test file did not, you owe a test — go write it.
   - For each new or modified function, point to the specific test (file + test name) that exercises it. If you cannot, the test is missing.
   - For each such test, point to the specific assertion or sub-case that covers a degenerate / boundary condition. "It tests the function" is not enough — name the case.
   - If any of these checks answer "no", the work item is **not** complete. Either ship the missing tests in this same work item or refactor the code so they are feasible.

5. If green and the work item is logically complete, commit per the fixed atomic-commit policy in Step 2.5. The inner-loop test from item 3 above is a SEPARATE step from `git commit` — never use `||` to chain them (per `.claude/CLAUDE.md` §"Code"). Mechanical moves separate from logic changes.
6. Check off the item in `docs/backlog/<id>.md`. Continue to the next work item — do not pause for user confirmation between items. Execute end-to-end per Step 2.5.

If a test fails: investigate and fix the underlying issue. Never skip tests, lower thresholds, mute warnings, or work around problems. If you can't reach root cause, stop and bring the user in.

## Step 5 — Handle gaps discovered during execution

**Decide first: is this a scope-bearing gap, or a small concrete fix?** This step is for *scope-bearing gaps* — a missing helper module, a redesign decision, an unscoped investigation, anything whose remediation is itself a planning artifact (≥30-min effort, multiple files, unclear approach, design tradeoffs). Filing such a gap stops the current task and forces it through `/plan-task` → `/review-task` → `/execute-task`. That ceremony pays for itself when the fix needs structured thought.

**Do NOT file a task for a small concrete fix on the critical path** when ALL of these hold:
- Root cause is already pinned (one or two files, specific lines).
- The fix is mechanical or near-mechanical (≤20 lines of code + a regression test).
- The current task cannot proceed without it (so deferring helps no one).
- No design decision is in play (you are not choosing between approaches).

In that case: just fix it inline as a separate atomic commit, add a short regression test, note the diversion in the current task's `# Notes` (one line: *"Detour: fixed <thing> at <commit>; root cause was <X>"*), and continue. This is the same detour discipline `.claude/CLAUDE.md` §"Code" describes for quality detours surfaced mid-execution. Mechanically filing every discovered bug as a new backlog task adds friction without signal — the user gets called back into a planning loop for what is effectively a typo-grade fix. **Surface, then choose**: tell the user what you found and what you intend to do; if they say "just fix it," do not re-file as a task.

If the gap IS scope-bearing (the case the rest of this step handles):

1. Generate a new id `YYYYMMDD<next-suffix>` (today's date + next free `aa..zz` from existing `docs/backlog/*.md`).
2. Create `docs/backlog/<new-id>.md` with `status: unplanned`, summary of the gap, and parent_story.
3. **Insert at the top of `## Active`** in `BACKLOG.md`.
4. In the current task's `# Notes`, record: "*Gap discovered during execution: <new-id>*".
5. Flip the current task back to `planned` mechanically — it is no longer in-progress; it is paused waiting on the new task:
   ```sh
   scripts/task-status.sh planned <current-id>
   ```
6. Reset STATE.md: `scripts/state.sh idle`.
7. Tell the user: "*Gap discovered; task `<new-id>` filed at the top. Run `/plan-task` for it before resuming `<id>`.*"
8. Stop.

The new task gets planned, executed, and completed. Then the user re-invokes `/execute-task` and this skill resumes the paused task.

## Step 6 — Verify success criteria

When all work items are checked off:

1. Re-read `# Success criteria` in the task file. Each criterion must be objectively satisfied — for each criterion, point to the **specific test name, metric, or observable outcome** that proves it. If a criterion has no test that covers it, the criterion is not verifiable as written: either add the test in this task, or file a follow-up child task per Step 5 with the missing coverage as its scope. "Verified by manual inspection" is not acceptable for a criterion that should be regression-protected.
2. **Run the plan-completion gate** per [docs/process.md](../../../docs/process.md) §"Test output capture" and trust the exit code:

   ```sh
   scripts/test-long.sh <id>     # exit 0 = green, continue to Step 7
   ```

   `make test-long` is the gate, not `make test`. Inner-loop `make test` excludes `train/` and other gotch packages — green there does not mean green overall (per `.claude/CLAUDE.md` §"Build"). The log overwrites `docs/backlog/last-test.log` (gitignored) and becomes the next session's baseline. **Don't read it on green.** Open the log only when the exit was non-zero — investigate the failures with the user, never work around them.
3. If `test-long` shows regressions: investigate and fix. Do not declare done with red tests.

## Step 7 — Close out

When success criteria pass and `test-long` is green:

1. **Doc-staleness sweep (mandatory).** Before flipping status to done, sweep
   `docs/*.md`, `docs/context/**.md`, `tasks/**/*.md`, the project-root
   `README.md`, and `.claude/CLAUDE.md` for references to anything this task
   changed:
   - Constants (e.g. `MaxFeatures`, `MaxSlots`) and their numeric values.
   - Function names, exported symbols, type names that were added, renamed,
     or removed.
   - File paths that were created, moved, or deleted.
   - Numbers that the task changed: corpus counts (training pairs, opplan
     counts), type counts, ShapeSpec counts, hyperparameter values.

   For each match that is now stale, update it in the close-out commit. If a
   match is large enough to be its own task (e.g. a multi-page rewrite), file
   a follow-up doc task per Step 5 instead.

   The rule per `README.md` §"Documentation as Source of Truth":
   *"Documentation must reflect the code as it exists at the time it is
   written. Docs are not aspirational — they describe current behavior,
   current interfaces, and current state."* This sweep is what enforces it
   on a per-task basis. The sweep also catches drift accumulated by *prior*
   tasks — if it surfaces stale references unrelated to the current task,
   fix them anyway while the file is open (or file the follow-up doc task).

   Useful sweep commands (adapt to what your task changed):
   ```sh
   grep -rn "<old-symbol-or-number>" docs/ tasks/ README.md .claude/CLAUDE.md
   ```

2. Update `docs/backlog/<id>.md`:
   - Add an `# Outcome` section: what shipped, what tests prove it, any
     follow-up tasks filed during execution. If the doc-staleness sweep
     surfaced anything, list the files updated (or follow-up tasks filed).
   - Flip status mechanically (validates `in-progress → done`):
     ```sh
     scripts/task-status.sh done <id>
     ```

3. **Catalog spot additions in [docs/ADDITIONS.md](../../../docs/ADDITIONS.md)**, if any occurred during this execution. A spot addition is any fix or change that deviated from the planned scope during `/execute-task` — inline mid-execution fixes, bonus tests, formula corrections, mid-execute pivots, etc. The convention lives at [docs/spot-additions.md](../../../docs/spot-additions.md); it covers what counts, what doesn't (plan/review iterations are NOT spot additions), and the one-line format.

   Append under today's date heading (newest at top of the day's group). One line per deviation, keyed by task id:

   ```
   ## YYYY-MM-DD
   - <id> -- <one-line description of what changed>
   ```

   If no deviations occurred during this execution, skip this step entirely — ADDITIONS.md does not need empty entries for clean executions.

4. **Remove the task entry from `BACKLOG.md`.**

5. **Append to `docs/DONE.md`** under today's date heading (create the heading if not present), newest at top of the day's group:

   ```
   ## YYYY-MM-DD
   - <id> **Title** — outcome hook → docs/backlog/<id>.md
   ```

6. Reset STATE.md: `scripts/state.sh idle`.

### Step 7a — Parent auto-promotion (when `parent_task` is set)

A parent that has been planned + reviewed clean sits at `status: ready` while its children execute one at a time. Children are at `ready` initially (they were reviewed together with the parent), then transition `ready → in-progress → done`. When the last child closes, this step decides whether the parent itself auto-promotes to `done`.

If the just-closed task has a `parent_task: <pid>` field, this may be the parent's last child. Check both gates:

1. **All children done.** Run `scripts/parent-task-completion.sh --children <pid>` — it walks every `docs/backlog/*.md` whose frontmatter has `parent_task: <pid>`, prints each child's status, and reports `X of Y completed (...)` plus `DONE` or `INCOMPLETE`. A child counts as completed when its status is `done` OR `punted` (both are closed branches). Exit codes: `0`=DONE, `1`=INCOMPLETE, `3`=no children found. If the script reports `INCOMPLETE`, the parent stays at `status: ready`; stop here for the parent.
2. **Parent's own success criteria pass.** Walk the parent's `# Success criteria (parent-level)` list. Each criterion is a falsifiable, task-specific outcome — verify it now (run the test, check the metric, observe the behavior). Capture each verification's outcome in /tmp logs.

If BOTH gates hold:
- Update parent `docs/backlog/<pid>.md`: add `# Outcome` summarizing the children + the parent-level verification results. The parent has been at `ready` while children executed; auto-promotion walks it to `done` mechanically:
  ```sh
  scripts/task-status.sh in-progress <pid>
  scripts/task-status.sh done <pid>
  ```
- Remove parent entry from `BACKLOG.md`.
- Append parent to `docs/DONE.md` under today's date.
- Tell the user: parent `<pid>` auto-promoted to done with all N children + own criteria verified.

If condition 1 holds but condition 2 fails:
- Parent stays at `status: ready` (children all done, but the parent's own integration gates failed; the next follow-up child is what closes this out).
- File a new follow-up child task per Step 5 (gap-discovered flow) with the failing criterion as its scope. Add the new id to the parent's `# Decomposition` table. Update the parent's frontmatter `notes` to record what failed.
- Tell the user: parent NOT auto-promoted; new follow-up child `<new-id>` filed for the failing criterion. Run `/plan-task` (the new child is `unplanned`) → `/review-task` → `/execute-task`.

6. Summarize back to the user: what shipped, which tests prove it, any follow-ups filed, and whether a parent auto-promoted. Suggest `/prioritize-backlog` if new tasks landed during execution.

## What this skill does NOT do

- Does not plan tasks (`/plan-task`).
- Does not ask the user about scope or commit policy — both are fixed in Step 2.5 (always end-to-end, always atomic commits per work item). The inner-loop test from Step 4 item 3 still runs as a SEPARATE step before each commit — never `||`-chained — per `.claude/CLAUDE.md` §"Code".
- Does not pause for user confirmation between work items. Run them all in one execution.
- Does not skip the `make test-long` gate. The release bar is "any commit pre-flighted with `test-long`".
