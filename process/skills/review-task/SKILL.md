---
name: review-task
description: Audit a planned task (or a parent task and all its children) under six risk lenses — complexity, customer impact, business risk, engineering reproducibility, modeling-slice isolation, and release coverage via `make test` — and verify each child's success criteria contributes to the parent's end-state. On pass, promotes the task from `planned` to `ready` in a single bundled commit (with STATE.md=idle), then automatically chains into `/execute-task`. On fail, leaves status at `planned`, writes a `# Open issues` agenda, then automatically chains into `/plan-task` (grill-and-update mode) to work the agenda. TRIGGER when the user says "review the task", "review this plan", "audit the task", "/review-task", or asks for a risk pass before execution. SKIP when /execute-task is in flight unless the user explicitly wants to interrupt.
---

You are the second gate in the planning pipeline: `/plan-task` (decompose + grill) → `/review-task` (this skill) → `/execute-task`. The aim is to surface bugs, gaps, and risks that the original plan-task pass missed — **while changes are still cheap**. Quality is the metric, not speed. Full lifecycle context: [docs/process.md](../../../docs/process.md).

This skill does **not** edit code, does **not** re-decompose, and does **not** invoke the grill itself. It walks six risk lenses against the task (and each child, if a parent), then either promotes the task to `ready` (no issues) or drops it back to `unplanned` with a `# Open issues` agenda for the next `/plan-task` cycle.

## Status lifecycle this skill participates in

The kanban statuses (per [docs/process.md](../../../docs/process.md)) form a strict cycle:

```
unplanned ──► planned ──► ready ──► in-progress ──► done
                ▲   │
                │   └── (review-task fail: stay planned + write # Open issues)
                │
                └── (plan-task on planned+issues: grill issues, update plan, clear block)
```

- `unplanned` — has not been planned. `/plan-task` runs in **full-plan mode**.
- `planned` — `/plan-task` has decomposed and grilled it. May or may not carry a `# Open issues` block:
  - **No `# Open issues`** — awaiting review. `/review-task` will run.
  - **Has `# Open issues`** — review found findings; `/plan-task` runs in **grill-and-update mode** against the listed agenda, then clears the block.
- `ready` — `/review-task` passed all six lenses + criteria-alignment; `/execute-task` will pick it up.
- `in-progress` — `/execute-task` is walking the work items.
- `done` — work items shipped, success criteria verified, `make test-long` green.

`/review-task` only ever transitions `planned → ready` (pass) or stays at `planned` while writing `# Open issues` (fail). The status itself never moves backwards; the presence/absence of `# Open issues` is the signal driving the next step.

## Step 1 — Read STATE.md

Always start here. The file is at `STATE.md` in the project root.

- `activity=executing` and `task=<id>`: an execute is in flight. Ask the user: *"Task `<id>` is in-progress. Reviewing now interrupts it. Continue executing, or pause to review?"* Do not proceed without confirmation.
- `activity=planning` and `task=<id>`: planning is mid-flight. Offer to review the parent under review now, then resume planning afterwards.
- `activity=reviewing` and `task=<id>`: this is a **warm resume**. Almost always either `/coder` chained back via `Skill(review-task)` at the end of its Step 8, or a previous turn ran out of tool budget. **Do NOT re-enter Step 2's dispatch table** — its rows assume cold entry and refuse on the very status (`planned`) that a resume normally arrives at. Route based on `docs/backlog/<id>.md` plus conversation context:
  - Lens walk not yet started (no findings recorded in conversation, no `# Open issues` block in the file): begin Step 3 (or resume from the gather-context point coder was invoked from).
  - Lens walk in progress (some findings recorded, others pending): continue from the next un-reviewed child or the next risk lens not yet applied.
  - Lens walk complete (all lenses applied, decision known): jump to Step 7 (write outcome) and then Step 8 (chain to `/execute-task` on pass or `/plan-task` on fail).
- `activity=idle` or other: proceed.

## Step 2 — Pick the task to review

**This step is for cold entries only (`activity=idle` in STATE.md).** If Step 1 detected a warm resume (`activity=reviewing task=<id>`), you have already routed past this step — do not re-enter the status-refusal table. The "Run /plan-task first" / "Run /execute-task" refusals below assume cold entry; on a chain-back from `/coder` they would dead-end the pipeline. Step 7/8 own the hand-off.

In order:

1. If the user named a task id, use that.
2. Else if `STATE.md` has a `task` field that points at a `planned` task, use that.
3. Else read `BACKLOG.md` and take the first entry under `## Active` whose detail file has `status: planned`.

Open `docs/backlog/<id>.md`. The task must be `status: planned`. Other statuses get a refusal:

- `unplanned` — *"This task has not been planned. Run `/plan-task` first."*
- `ready` — *"This task already passed review. Run `/execute-task`."*
- `in-progress` — *"This task is being executed. Reviewing now interrupts; confirm before proceeding."*
- `done` / `punted` — *"This task is closed; nothing to review."*

Set STATE.md mechanically — the script validates the source activity:

```sh
scripts/state.sh reviewing <id>
```

Determine the **shape** of what is under review:

- **Leaf task** — no `# Decomposition` section. Review the single file.
- **Parent task** — has `# Decomposition`. Review the parent AND each child file in the dependency-order shown in the table.

## Step 3 — Gather context (refresh graph + verify via the `coder` skill)

**Mechanical first — refresh the graph.** If `/review-task` was chained from `/plan-task`, the graph is already current; if invoked standalone, refresh now. `graphify update .` is incremental, so the cost is small and it picks up any out-of-band commits since the last refresh.

```sh
graphify update . 2>&1 | tee /tmp/graphify-refresh.log
```

Before applying any risk lens, read the surrounding context. The grill discipline applies — verifiable claims about the codebase get verified against current code (via the `coder` skill for symbol-shaped questions, via `grep`/`Read` for non-symbolic ones), not asked of the user.

For the task under review (and each child if a parent):

- The task's `# Summary`, `# Context`, `# Work` (or `# Work items`), `# Success criteria`, `# Notes`.
- The `parent_story` — what user-visible outcome does this task ladder into?
- The `depends_on` chain — open each dependency's file and verify the *deliverable claimed by that dependency actually exists in code today*. A `done` task is only as load-bearing as its still-greppable artifact. (Same check `/execute-task` Step 2a does, applied earlier.)
- File paths and function names cited in `# Context` and `# Work` — confirm each one exists. A reference to `foo.Bar()` that no longer compiles is a Class-A issue (engineering reproducibility).
- **Check for an existing exploration doc.** If `docs/backlog/<id>-exploration.md` exists (left behind by a prior `/plan-task` invocation of the `coder` skill), read it first — it is the librarian's authoritative answer to the code-shaped questions this task touches, and its `# Open questions` section flags judgment calls the planner already surfaced. If none exists AND a Step 4 lens (especially `complexity` or `reproducibility`) needs multi-symbol code evidence to decide whether a finding is real, invoke `Skill(skill: "coder", args: "verify <claim> for review of <id>")` to produce one. Single-grep verifications stay inline.
- The relevant `docs/context/<area>.md` per the routing table in [.claude/CLAUDE.md](../../../.claude/CLAUDE.md) §"Context — read before working in an area".
- For machining rules: confirm the Machinery's Handbook 32e citation per `.claude/CLAUDE.md` §"Machining context".

Re-reading is encouraged — the cost of re-skimming a doc is cheap; the cost of a missed constraint is a stop-and-replan interrupt mid-execution.

## Step 4 — Apply the six risk lenses

For each task under review (the leaf, or the parent + each child), walk these lenses **in order**. Record findings as numbered issues; do not write them into files yet — that is Step 7.

For each lens, propose your **best estimate** of where the task sits (low / medium / high) and **cite specific evidence** from the task file or from code. "Looks complex" without evidence is not a finding; "Step 3 unifies hybrid-head loss with Hungarian matching across 18 primitive types in one work item — three independent failure modes in one commit" is a finding.

**Grill hook — when a lens needs user judgment, ask before deciding.** Most findings are objective (a grep confirms or refutes them). But some lenses surface judgment calls the model cannot resolve from code alone — examples: "is the customer demo on a deadline this task is implicitly racing?" (customer-impact), "is this metric move acceptable, or does it need a deeper isolation gate?" (modeling-slice), "does the parent really want X gate, or did the user mean Y?" (criteria-alignment). For each such judgment:

- Phrase the question with a **recommended answer up front** (your best estimate based on the file + code + prior context), then ask via `AskUserQuestion` with 2–4 concrete options. Do not write the finding before the user answers — the answer determines whether it's a finding at all, and at what severity.
- One question at a time. Do not batch multiple unrelated judgment calls into one `AskUserQuestion` call; the user's answer to a customer-impact question doesn't tell you anything about a modeling-slice question.
- The grill blocks the chain. Step 8 (pass or fail) does not run while a Step 4 question is open. The model's tool loop is sequential; do not invoke `Skill(...)` until every question has returned.

Verifiable claims get checked against current code, not asked of the user: symbol-shaped questions (does function/type/method X exist? what calls Y? where is Z tested?) go through the `coder` skill; non-symbolic claims (file paths, build flags, generator output) use `grep`/`Read`.

### 4a. Complexity

- How many independent moving pieces does the task touch? Count: source files, packages, test files, contracts/schemas, build targets.
- Does any single work item couple ≥2 independent failure modes? (Example: "Wire X and refactor Y" — refactor and wiring failures look identical from a test failure.)
- Are work items truly ~1 commit each, or do any expand into multi-commit subtrees once you imagine implementing them?
- Are the cited file paths and line numbers all real and current? (verify via `coder` for symbol references; `grep`/`Read` for raw file paths)

A complexity finding looks like: *"Item 3 bundles encoder change + loss change + assertion change; recommend splitting into three work items so a regression localizes."*

### 4b. Risk to customer impact

- What does the parent_story promise the customer? (Pull the story and read it.)
- If this task ships exactly as written, does the customer see the promised outcome any sooner? Or does the task sit on a hidden critical path that has no one driving it?
- Conversely: if this task ships *broken*, what does the customer see? Does the breakage degrade an existing capability (regression — high impact), or does it merely fail to deliver a new one (slip — lower impact)?
- For pipeline tasks: which stages downstream are blocked or corrupted by a wrong output here?

### 4c. Business risk of failure

- If the task fails its success criteria entirely, what gets escalated? A retry on the same plan? A re-plan? An external dependency missed (customer demo, deadline)?
- Is there a deadline this task is implicitly racing? Check `parent_story` and project-level state in [STATE.md](../../../STATE.md), [.claude/CLAUDE.md](../../../.claude/CLAUDE.md), and `tasks/<area>/*-plan.md` retrospectives for time pressure.
- Is the work reversible? A failed code change is reversible (revert); a failed schema migration or dataset overwrite may not be. Flag any irreversible step.

### 4d. Engineering risk to reproducibility

- Can a fresh executor open this file cold (no conversation, no sibling files) and ship the change? Apply the self-containment check from `/plan-task` Step 5b. Cite each violation: *"Cites sibling `aa` for the FeatureMap contract without copying the schema here."*
- Are seeds pinned for any stochastic step? Tests that flake on seed change are a reproducibility hazard per `.claude/CLAUDE.md` §"Code".
- Are the success criteria **falsifiable** — i.e., is there a concrete way to FAIL each one, not just a vibe? An unfalsifiable criterion is unreviewable later.
- Are file pairings respected? `foo.go` paired with `foo_test.go` per `.claude/CLAUDE.md` §"Code". A work item that adds source files without matching test files is a reproducibility finding.
- Are CGO / Makefile / `make test-long` invariants honored? Per `.claude/CLAUDE.md` §"Build", any gotch-touching task that proposes bare `go test` is a finding.

### 4e. Modeling slice isolation (only if the task involves modeling)

A task is "modeling work" if it changes a model's architecture, loss, training loop, dataset construction, or evaluation metric. For non-modeling tasks, skip this lens.

The risk: when multiple unknown components change in the same training run, a metric move cannot be attributed to any one cause — you have a randomized A/B/C/D experiment with no controls. The lens:

- Enumerate the **slices** the task changes: architecture, loss, optimizer, data, evaluation. How many slices change in one work item? In one commit? In one training run that produces the recorded metric?
- For each slice that contains an **unknown** (a new component, a new hyperparameter range, a new data source you have not yet measured), is it being introduced *alone* with everything else held constant? If two unknowns ship in the same run, a regression has two suspects and you cannot localize.
- Is there an **isolation gate** before the integration run? Per `tasks/training/generative-training.md` and the architecture-overfit pattern in [docs/backlog/20260503al.md](../../../docs/backlog/20260503al.md), a small overfit (1 sample, 10 samples) catches wiring bugs in seconds; full-dataset training does not. Flag any modeling task that goes straight to the full run without a single-pair / small-sample gate.
- Is the metric being recorded **per-slice** so a future run can compare? Aggregate "loss=3.2" tells you nothing about which slice regressed.

A modeling-slice finding looks like: *"Item 2 introduces a new loss term AND a new data augmentation in the same training run; recommend splitting into two runs (loss change first against current data, then augmentation against the new loss baseline) so a metric regression has one suspect, not two."*

If the modeling-slice concern is **cumulative across many children** rather than localized to one — e.g., a chain of ShapeSpec adds that individually have no metric to gate but together shift the training corpus — defer the finding to the parent under the cross-child rule in Step 7 ("For a parent under review"). Do NOT silently skip the lens on the child as "N/A": that pattern lets cross-child concerns evaporate and leaves the eventual retrain task with no suspect set.

### 4f. Release coverage — `make test` proves the new functionality

The project's commits-are-green invariant means every release is verifiable from `make test` alone (the fast inner-loop gate, ~3s). `make test-long` covers more (gotch / `train/`) but is not the daily signal — it runs once at task close-out. So every task that adds functionality must add tests that **`make test` runs**, otherwise the new functionality has no daily release verification.

The lens, per task:

- For each `# Work` item, identify the test that proves it works. If the success criteria are *"X does Y under Z"*, the test is the falsifier — *"`TestXUnderZ` asserts that Y holds for Z"*.
- Confirm that test file lives in a package included in `BARE_PKGS_FAST` or `BARE_PKGS_SLOW` in the Makefile — i.e., reachable from `make test`. Packages in `train/` (gotch-dependent) are NOT in `make test`; they only run under `make test-long` and `make -C train test`.
- For each work item whose test is NOT in `make test`-reachable packages, decide:
  - Can the proof be restructured into a `make test`-reachable test? Often yes — split the verification into a pure-Go shim that exercises the logic without the gotch surface.
  - If genuinely not — e.g., the work is gotch-only by nature (a new layer in `lib/aid3/xformer/`) — that's a finding with severity = medium. The task should add a release-quality test that `make test-long` runs AND a smoke test in a `make test`-reachable package, so daily signal still catches gross regressions.
- Are success criteria **measurable by the listed test**? A criterion like "feature ships" with no test it fails on is unreviewable. Pair each criterion to a specific test assertion.

A release-coverage finding looks like: *"Items 2 and 3 add `lib/aid3/xformer/newhead.go` and tests in `train/stl2gcode/model/newhead_test.go`. The tests only run under `make test-long`; nothing in `make test`'s package set proves the new head produces non-NaN output. Recommend adding a pure-Go shim test in `lib/aid3/xformer/newhead_test.go` (no gotch, just shape/wiring) to give daily signal — severity medium."*

This lens applies to every task. Unlike modeling-slice (skipped for non-modeling tasks), release-coverage is universal: every change ships through `make test` or carries an explicit waiver.

## Step 5 — For parent tasks, walk every child

If the task under review is a parent (`# Decomposition` present), repeat Step 4 against **each child** in `# Decomposition` table order. Children are not exempt from the lenses just because the parent passed.

Per child, additionally check:

- The child's `depends_on` accurately reflects what its `# Context` and `# Work` actually need. Missing or extra dependencies are a finding.
- The child's success criteria are **disjoint** from sibling children — two children claiming the same outcome is a planning bug.
- The child's work, if it ships, leaves the next-in-dep-order child **executable**. If child B claims to consume a function that child A does not produce, A is incomplete or B is mis-scoped.

## Step 6 — Verify success-criteria alignment (parent ↔ children)

This is the cross-cutting check the user called out: *"For each of the plan tasks, go through and make sure the task success criteria matches what is produced at the end of the plan."*

For a parent + N children:

1. List the parent's `# Success criteria (parent-level)` items.
2. For each parent criterion, identify which child (or set of children) produces the artifact / behavior the criterion measures. Cite the specific child success-criterion line.
3. Find the gaps:
   - **Orphan parent criterion** — no child ships the artifact this criterion measures. The plan does not produce its claimed outcome. **High-severity finding.**
   - **Orphan child criterion** — a child ships an outcome that no parent criterion validates. Either the parent criteria are incomplete, or the child is doing scope outside the umbrella. Flag both possibilities.
   - **Mismatched gate** — a parent criterion says "X < 5mm" and the child that produces X measures "X = 12mm" or doesn't measure X at all. Either the threshold is wrong or the child needs measurement work added.
4. For a leaf task (no children), do the in-task version: list the success criteria and confirm each is produced by something in `# Work`. A criterion with no work item to drive it is a finding.

This is the most load-bearing step in the skill — a misaligned parent/child criterion set means the plan can ship every child green and still fail to deliver the umbrella outcome. Be exhaustive here.

## Step 7 — Write the outcome into the task file(s)

Two paths: pass (zero findings across all reviewed tasks) or fail (≥1 finding on any reviewed task). The status transition is **parent-only** — a parent promotes to `ready` when the parent itself AND every child reviewed clean. Children stay at `status: unplanned`; each child runs its own `/plan-task` → `/review-task` → `/execute-task` cycle individually. This skill audits children to confirm the parent's decomposition is sound, but does not advance their status.

### Pass path — zero findings

The pass path collapses plan/review/idle/commit into **one atomic bundle**: STATE goes to idle, the parent flips to `ready`, and a single commit captures all of it. Order matters — set idle *before* the commit so STATE.md=idle is what lands in the commit:

```sh
# 1. Clear the breadcrumb first (modifies STATE.md → idle).
scripts/state.sh idle

# 2. Flip the parent (or leaf) planned→ready and commit. Children stay
#    unplanned and are not in the batch — each child has its own
#    /plan-task pass coming.
#    task-status.sh stages docs/backlog/, BACKLOG.md, STATE.md (now idle)
#    and creates the single bundled commit.
scripts/task-status.sh ready <parent-id>
# leaf: scripts/task-status.sh ready <id>
```

This is the only commit point in the plan/review cycle (per [docs/process.md](../../../docs/process.md) §Lifecycle) — the **single commit** bundles every plan/review iteration since the last `ready` plus the state-to-idle transition. `task-status.sh ready`:

- Refuses if any id is not currently `planned` (caller error).
- Stages `docs/backlog/`, `BACKLOG.md`, `STATE.md`.
- Commits as `Ready <first-id> — <first-id title>`.

Post-commit the working tree is clean and STATE.md is idle. Do not add any `# Open issues` block. Absence is the all-clear.

### Fail path — one or more findings

For each task (leaf, parent, or any child) that has at least one finding from Steps 4–6, append a `# Open issues` section to its detail file. Format:

```markdown
# Open issues  (review YYYY-MM-DD)

Findings from `/review-task`. `/plan-task` will re-grill these as the explicit
agenda for the next planning round, then clear this block.

1. **[lens — short title]** — Evidence: cite file/line/work-item.
   Recommendation: what to change. Severity: low | medium | high.
2. ...
```

Lens labels: `complexity`, `customer-impact`, `business-risk`, `reproducibility`, `modeling-slice`, `release-coverage`, `criteria-alignment`. One issue per lens occurrence — do not consolidate across lenses. When promoting a child finding to the parent under the cross-child rule (see "For a parent under review" below), suffix the label with `[cross-child: <one-sentence-reason>]` and link the surfacing child — e.g. `modeling-slice [cross-child: cumulative-corpus-shift] — see child 20260509at`. The bracket is grep-able for parent close-out audits.

**Status is not changed by the fail path.** The parent (or leaf) stays at `planned` with the new `# Open issues` block; children stay at `unplanned` with their `# Open issues` block. The block is the signal — `/plan-task` checks for it on entry and switches to grill-and-update mode regardless of which status it finds. Decomposition, dependencies, and frontmatter otherwise remain untouched; the open issues are deltas to apply, not a reason to throw it all out.

**Do NOT commit on the fail path.** The dirty working tree carries over into the next `/plan-task` grill-and-update pass — repeated review failures are intentionally one big uncommitted blob, collapsed into a single commit when the cycle eventually reaches `ready`. (See [docs/process.md](../../../docs/process.md) §Lifecycle for the rationale: there's no value in checking in intermediate plan/review iterations.)

**The fail path then chains directly into `/plan-task`** (Step 8). The grill-and-update agenda is exactly the `# Open issues` blocks just written, so handing control over without a stop is the natural next step. The user can always interrupt mid-grill if they want to pause.

For a parent under review:

- Parent-scope findings (Steps 4 or 6 against the parent itself) go into the parent's `# Open issues` block. Add `(cross-decomposition)` to the heading for Step 6 alignment findings so the next `/plan-task` knows to walk the table, not just the parent body.
- Child-scope findings go into each affected child's `# Open issues` block.
- **Cross-child findings on a child** — when a lens question against a child cannot be answered from the child's diff *because the concern is structurally cross-child* (cumulative effect, sibling interaction, joint coverage of a parent criterion), write the finding into the **parent's** `# Open issues` block instead and pass the child on that lens. Eligibility test: state in one sentence why the issue is cross-child. "I can't tell from this child's diff" is NOT cross-child and stays at the child as a regular finding. Use the `[cross-child: <reason>]` label suffix (per the lens-labels paragraph above) so future readers can audit what was deferred. Canonical examples: modeling-slice cumulative-corpus-shift across many ShapeSpec adds; release-coverage on a feature that only ships when N siblings land; criteria-alignment requiring combined sibling output. A child may defer at most ONE finding per lens to the parent — keeps the "one issue per lens occurrence" rule intact.
- A child that reviewed clean stays `unplanned` with no `# Open issues` block — its own `/plan-task` → `/review-task` cycle will promote it later. A child that received findings stays `unplanned` *with* an `# Open issues` block; its own `/plan-task` will address the agenda when the child is picked up. Either way, children do not move during the parent's review.

## Step 8 — Surface and hand off

**Grill must be complete before this step runs.** This step performs the chain (to `/execute-task` on pass, to `/plan-task` on fail). Do not enter Step 8 while any Step 4 grill question (per the "Grill hook" note in Step 4) is still open. Every `AskUserQuestion` invocation from the lens grills must have returned with a real answer; the chain `Skill(...)` invocation comes AFTER. If a grill question is still pending, stay in Step 4 until the user answers.

Summarize back to the user in 5–10 lines:

- N tasks reviewed (1 leaf, or 1 parent + M children).
- Per-lens issue counts (e.g., `complexity: 0, customer-impact: 1, business-risk: 0, reproducibility: 3, modeling-slice: 2, release-coverage: 1, criteria-alignment: 1`).
- The single highest-severity finding, in one sentence.
- Which task files transitioned to `ready`, and which stayed `planned` with a `# Open issues` block.

Then take the next action based on outcome:

### Pass path — zero findings

State and commit were already handled atomically in Step 7 (idle + bundled commit; STATE.md is now `idle` and the working tree is clean).

Pick the next handoff based on what was reviewed:

- **Leaf task (no children)** — chain to `/execute-task` on this task. Transition STATE.md `idle → executing` for the leaf id, then invoke the execute-task skill.
- **Parent task (had children)** — the parent is now `ready`, but children are `unplanned` and need their own `/plan-task` passes before anything can execute. Pick the first child in dep order (no unmet `depends_on`), transition STATE.md `idle → planning` for that child id, then invoke the `plan-task` skill. That child's plan-task will grill its decomposition-time content, set it to `planned`, and chain to its own `/review-task`. The chain continues child-by-child until every child is `done`; the parent auto-promotes on the last child's close-out.

```sh
# leaf
scripts/state.sh executing <leaf-id>
# parent
scripts/state.sh planning <first-unplanned-child-id>
```

**Invoke the next skill via the Skill tool, immediately, in the same response.** Do not ask the user first; the explicit hand-off is the `ready`/`planning` STATE transition, and the user can interrupt if they want to pause. One-line preface:
- Leaf: *"Task `<id>` is now `ready`. Chaining into `/execute-task`."*
- Parent: *"Parent `<id>` is `ready`. Chaining into `/plan-task` on first child `<child-id>`."*

Tool call shape: `Skill(skill: "execute-task")` or `Skill(skill: "plan-task")`. The next skill's Step 1 will detect the STATE transition and resume on the right task. If a gap is discovered mid-execution, execute-task chains back to `/plan-task` on its own (per its skill description), which re-enters the plan→review→execute cycle.

### Fail path — issues written

Transition STATE.md from `reviewing` to `planning` for the same parent id — `state.sh` explicitly allows `reviewing → planning` as the "review fail; re-grill open issues" transition:

```sh
scripts/state.sh planning <parent-id>
```

This is the breadcrumb that ties the freshly-written `# Open issues` blocks to the next planning round. Do **not** route through `idle` first — that would lose the task pointer and force `/plan-task` to fall back to "first entry under `## Active`" in BACKLOG, which may not match the parent we just reviewed if Active has other items above it.

Then **invoke the `plan-task` skill via the Skill tool, immediately, in the same response**. Do not ask the user first; the issues block + `planning` state is the explicit hand-off, and the user can interrupt the grill if they want to pause. One-line preface to the user is sufficient: *"`<N>` findings written. Chaining into `/plan-task` to grill and update."*

Tool call shape: `Skill(skill: "plan-task")`. The plan-task skill's Step 1 will detect `activity=planning task=<parent-id>` and resume on that task; Step 2 will see `status: planned` + `# Open issues` and route to grill-and-update mode (Step 4-bis), work the agenda, clear the blocks, and leave the task at `status: planned` for a re-review.

## Notes

- This skill is **read-only against code** and **append-only against task files** (only adds an `# Open issues` block and flips `status` from `planned` to `ready` on pass). It never deletes existing content from a task file. It never moves status backwards.
- The `ready` status is the only new state introduced by adding this skill into the pipeline. `/plan-task` emits `planned` in both modes (full plan from `unplanned`, or grill-and-update on `planned + # Open issues`). `/execute-task` picks `ready` and refuses `planned` ("run `/review-task` first").

## What this skill does NOT do

- Does not write code or edit code files.
- Does not re-decompose the task — that is `/plan-task`.
- Does not interview the user — that is `/grill-me` (or the grill discipline inside `/plan-task`).
- Does not reorder the backlog or move tasks between Active/Deferred/DONE/PUNT.
- Does not lower or skip the project's quality bar. Per `.claude/CLAUDE.md` §"Plan lifecycle", findings must be surfaced, not worked around.
