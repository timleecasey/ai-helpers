---
name: plan-task
description: Pull the top task from BACKLOG.md and decompose it into N ≈1-hour self-contained child tasks with explicit dependencies. Each child is its own file in docs/backlog/, pushed to the top of Active in dependency order. Parent stays as a tracking node with its own success criteria. On close-out, automatically chains into `/review-task` to audit the plan (same task) before execution. TRIGGER when the user says "plan a task", "plan the next task", "/plan-task", or asks what to work on next. SKIP when an execute-task is in flight unless the user explicitly wants to interrupt it.
---

You are decomposing a single backlog item into a stack of independently-executable child tasks. The full process lives in [docs/process.md](../../../docs/process.md). Quality is the metric, not speed.

The output of this skill is **not work items inside one file** — it is **N new task files** plus an updated parent that tracks them. Each child file must be self-contained: an executor opening it cold (no conversation history, no sibling context) has everything needed to ship the change.

## Step 1 — Read STATE.md

Always start here. The file is at `STATE.md` in the project root.

- `activity=planning` and `task=<id>`: this is a **warm resume**. The prior session was already mid-plan, almost always because `/coder` chained back via `Skill(plan-task)` at the end of its Step 8, or because a previous turn ran out of tool budget. **Do NOT re-enter Step 2's dispatch table** — its rows assume cold entry (idle STATE) and dead-end with "Stop. Tell the user to /review-task" on a planned-resume, which breaks the plan→review→execute chain. Route based on `docs/backlog/<id>.md`:
  - `status: unplanned` — mid-grill / mid-decomposition. Read the file plus any `docs/backlog/evidence/<id>/exploration.md` left by `/coder` plus the conversation context to find the next unfinished step among Step 3 → 4 → 4a → 4b → 5 → 6. Pick up there; do not restart from Step 2's full-plan-mode entry.
  - `status: planned` and no `# Open issues` — the prior session completed Step 5/6 (children written, parent updated). **Jump directly to Step 7 (Close out)** and chain into `/review-task`.
  - `status: planned` and has `# Open issues` — grill-and-update mode (Step 4-bis).
  - `status: ready` / `in-progress` / `done` / `punted` — wrong slot. Stop and tell the user.
- `activity=executing` and `task=<id>`: an execute is in flight. Ask the user: *"Task `<id>` is in-progress. Plan-task interrupts it. Continue executing, or pause to plan something else?"* Do not proceed without confirmation.
- `activity=prioritizing` or `bootstrapping`: ask the user whether to finish that activity first.
- `activity=idle`: proceed to step 2.

## Step 2 — Pick the parent task and pick a mode

**This step is for cold entries only (`activity=idle` in STATE.md).** If Step 1 detected a warm resume (`activity=planning task=<id>`), you have already routed past this step — do not re-enter the dispatch table. The table's "Stop. Tell the user to /review-task" outcomes assume the user is starting fresh; on a chain-back from `/coder` or a mid-flow resume, Step 7 owns the hand-off and stopping here is the bug.

Read `BACKLOG.md`. Take the first entry under `## Active`. If `## Active` is empty:

- Tell the user the active backlog is empty.
- Suggest `/bootstrap-backlog` (if `docs/backlog/` is empty) or `/prioritize-backlog` (if Deferred has candidates that should be promoted).
- Stop.

Set STATE.md mechanically — the script validates the source activity and refuses illegal transitions:

```sh
scripts/state.sh planning <id>
```

Open `docs/backlog/<id>.md`. This is the **parent** for the rest of this skill. The action depends on its current `status` and whether it carries a `# Open issues` block written by `/review-task`:

| Status | `# Open issues`? | Mode |
|---|---|---|
| `unplanned` | n/a | **Full-plan mode.** If the task is a parent (no `parent_task` frontmatter, or umbrella scope): run Steps 3–7 as written — gather context, grill, decompose into children, write children as `status: unplanned`, set parent to `status: planned`. If the task is a child (has `parent_task` set and was authored by an earlier parent decomposition): grill the existing `# Context` / `# Work` / `# Success criteria` against the current code, refresh any drift, then set this child to `status: planned`. No re-decomposition of a child into grandchildren unless the grill exposes that the child is genuinely two tasks. |
| `planned` | yes | **Grill-and-update mode.** Skip wholesale re-decomposition; jump to Step 4-bis below. |
| `planned` | no | Already planned and awaiting review. Tell the user to `/review-task`. Stop. |
| `ready` | n/a | Already reviewed clean. Tell the user to `/execute-task`. Stop. |
| `in-progress` / `done` / `punted` | n/a | Wrong lifecycle slot. Stop and tell the user. |

If status is `planned` AND `# Decomposition` exists with all children at `status: done` AND no `# Open issues`, defer auto-promotion to `/execute-task` and stop.

### Step 4-bis — Grill-and-update mode (planned + # Open issues)

When entering grill-and-update mode, the existing decomposition is the starting point — do **not** throw it out. The `# Open issues` block is the explicit agenda for the grill round. Walk it as follows:

1. Read every issue. For each, identify which artifact it targets: a parent-level success criterion, the parent's own `# Context` / `# Work`, the `# Decomposition` table, or one or more child files.
2. For each issue, apply the same verify-via-coder discipline as Step 3 — most issues will name a specific file, symbol, or contract that should be re-checked against current code (via the `coder` skill for symbol-shaped questions) before the user is grilled.
3. Grill the user only on the residual judgment calls per issue, one at a time, with a recommended answer up front. The lens-label in the issue tells you which class of problem it is (e.g., `criteria-alignment` issues usually need a re-think of which child owns which gate; `modeling-slice` issues usually need a child to be split).
4. Apply the resolution **in place**:
   - Edit the parent's `# Success criteria (parent-level)` if a `criteria-alignment` issue resolved against the parent.
   - Edit the affected child file(s) — `# Context`, `# Work`, `# Success criteria` — to reflect the resolution. Maintain the self-containment check from Step 5b for any child you touch.
   - Add new children if the resolution requires a missing preceding step (per Step 5c). Insert them in dep order at the top of `## Active`.
   - Update `# Decomposition` in the parent if children were added/split/merged.
5. **Clear the `# Open issues` block** from every file once each issue in it is addressed. The block must be empty (delete the section entirely) by the time this skill closes — its presence is the signal that work is unfinished.
6. Leave the parent at `status: planned`. Leave children at `status: unplanned` — each child will be planned individually later via its own `/plan-task` invocation. Do NOT promote the parent to `ready` — the next `/review-task` pass owns that transition. **Higher-order planning (parent: scope, decomposition shape, dep graph, parent-level success criteria) is separated from task-order planning (each child's own grill/confirm pass). The parent is not expected to hold the context of all children during review — each child carries its own context for its own planning pass.**

After grill-and-update is complete, jump to Step 7 (Close out). Do not re-run Steps 3, 4a, 4b, 5, 6 in full — they were done in the original plan-task pass and are not repeated for an issues-driven update unless an issue explicitly demands it.

## Step 3 — Gather information (refresh graph + verify via the `coder` skill)

**Mechanical first — refresh the graph.** `graphify update --no-vis .` is incremental (a `git diff-tree` against the manifest), so it picks up every out-of-band commit since the last refresh: terminal commits, doc-only commits the PostToolUse hook ignored, rebases, cherry-picks. The cost is small; the payoff is that the rest of this skill (and the chained `/review-task` and `/execute-task`) work off a current graph.

```sh
graphify update . 2>&1 | tee /tmp/graphify-refresh.log
```

Then read everything that bears on the parent **before** asking the user anything:

- The parent's `# Summary`, `# Context`, `# Notes`.
- The `parent_story` link in `docs/user-stories.md` — what is the user-visible outcome this task supports?
- Any `source` reference — read the original context.
- The project-root `README.md` is the **entry point into project intent** — start here to understand *why* the work exists before diving into *what* to do. Then **follow its links** out to whichever docs bear on the task: `docs/system.md`, `docs/context/<area>.md`, `tasks/<area>/*-plan.md`, package-level READMEs, etc. The aim is **full context to the extent possible** for the parent's scope: pull in linked docs greedily, prune only when a doc is clearly off-topic. If a doc you read links further, follow those too. Also read any README that sits with the code or docs the task touches (e.g. `lib/aid3/<pkg>/README.md`, `train/README.md`, `tasks/<area>/README.md`). If the root README does not yet point at a doc you found necessary, note that gap — it is a documentation defect worth surfacing back to the user.  You must read README.md.
- **Routing-table context docs are MANDATORY first reads — BEFORE any graphify query.** For every directory the parent touches (per file paths in `# Context` / `# Work`), find that directory in the **Context routing table** in `.claude/CLAUDE.md` §"Context — read before working in an area" and read the mapped `docs/context/<topic>.md` file in full. The first table in each such doc is a **"Package layout"** (or equivalent) — the **authoritative file inventory** for that package, listing every `.go` source file and what each contains. Reading this BEFORE running graphify catches existence facts the graph can miss — especially **free functions in leaf packages with small communities**. Graphify's `explain "<symbol>"` substring-matches on lowercase noise; `explain ".Symbol"` only matches methods (not free functions). The routing-table doc has the file inventory regardless of graph shape.

  *Worked example (2026-05-16, [20260515ax](../../../docs/backlog/20260515ax.md) # Outcome)*: planning for HydraulicManifold cross-bores filed a child task to ship new `MakeCylinderModelOnX/OnZ` STL primitives (~140 LOC + tests). The exploration ran `graphify explain ".Rotate"` and got substring-matched noise (`PackWriter.rotate`, etc.) and concluded "no Rotate helper exists". But [docs/context/stl.md](../../../docs/context/stl.md)'s very first table — "Package layout" — lists `rotate.go` explicitly. `rotate.go:9` defines `func RotateModel(m *Model, rot [3][3]float64) *Model` — a pre-existing well-tested helper that does exactly what the planned new primitives would have done. Execute-time Step 2.4 caught the miss before code shipped; if planning had read the routing-table doc first, the wasteful decomposition would never have been written.

- Adjacent code: for any symbol-shaped question (does function/type/method X exist? what does Y call? where is Z tested? what are the callers of W?), **invoke the `coder` skill** (`Skill(skill: "coder", args: "<question> for parent <id>")`) — AFTER the routing-table read above. Coder owns `graphify-out/`, queries the graph first, then verifies against source. It produces a durable exploration doc at `docs/backlog/<parent-id>-exploration.md` plus raw evidence under `docs/backlog/evidence/<parent-id>/` that this plan-task pass (and the chained `/review-task` and `/execute-task`) re-read as context. By the time you can phrase a grep precisely (you know the symbol and the relation), coder takes that same input and answers structurally — cheaper in tokens and reusable across the cycle. **Brief coder with the file inventory you already read from the routing-table doc** — that gives the librarian existence facts to verify, not just symbols to query.
- **Grep / Read is the fallback for genuinely non-symbolic searches** — hunting unstructured strings (TODO comments, magic numbers, build-flag spellings), scanning generated artifacts not covered by the graph (`generator/opplans/`, `generator/stl/`), checking file existence with no symbol involved. **Confirm what exists and what does not** before grilling the user.
- For machining rules: cite Machinery's Handbook 32e per `.claude/CLAUDE.md` §"Machining context".

Re-reading is encouraged. The first pass orients you; once the coder verification surfaces specific files, contracts, or gaps, return to the README / context docs / parent file and read them again with that lens. A second pass over a doc you already skimmed often surfaces a constraint that was invisible the first time. Cost is cheap; missed constraints become mid-execution interrupts.

The grill discipline ([.claude/skills/grill-me/SKILL.md](../grill-me/SKILL.md)) applies: every claim that can be confirmed by reading the codebase **must** be verified before it becomes a question to the user. Bring the user *the result of the verification*, not the verification itself.

## Step 4 — Grill the user on the open judgment calls

After verification, what remains is judgment. Use the grill-me discipline:

- One question at a time.
- For each, propose your recommended answer and the trade-off.
- Stop when the parent's scope is distinct enough to decompose.

### Step 4a — Map the larger context (mandatory; gap-hunting)

Before decomposing, **proactively map the larger context the parent sits inside**. Small ~1h tasks always inherit a bigger picture; if the grill doesn't surface it, decomposition produces children with hidden dependencies that show up as undiscovered holes during execution.

**If the parent touches code in a non-trivial way** (changes a symbol with many callers, introduces a new contract, removes or renames a public API, proposes shared abstraction across packages), invoke `Skill(skill: "coder", args: "map larger context for <parent-id>: <one-line summary>")` and let the librarian produce the context map. The exploration doc it writes IS the map for this step — read it, then surface the open judgment calls from the doc's `# Open questions` section as the grill agenda. This replaces hand-running the enumeration below for code-heavy parents.

For doc-only, machining-only, or trivially-scoped parents (where the question is not symbol-shaped), enumerate inline with `grep`/`Read`:

- **Data flow.** Which inputs feed the parent's scope? Which outputs does it produce? Where does each input come from in code? Where does each output go in code? Cite file paths.
- **Contracts.** Function signatures, type schemas, JSON schemas, file-format conventions that the parent's work must honor or change. Cite file + line.
- **Prior decisions.** Tasks that already shipped (in `docs/DONE.md`) and constrained design choices the parent inherits. Tasks already filed (in BACKLOG/Deferred) that overlap or block. Documents in `docs/context/<area>.md` or `tasks/<area>/*-plan.md` that fix design choices.
- **Cross-package or cross-frame implications.** STL frame ↔ machine frame mapping, gotch grad-mode threading, CGO flag inheritance, etc. — the load-bearing invariants from `.claude/CLAUDE.md` that the parent's work must not violate.

For each item in the map, ask explicitly: **is there a gap here?** A gap is anything the children will need that does not exist yet — a missing helper function, a missing JSON field, a missing fixture, a missing decision. Verify each candidate gap via the `coder` skill (for symbol-shaped gaps) or `grep`/`Read` (for non-symbolic ones). Two outcomes per gap:

- **Confirmed-not-a-gap** — the thing exists; cite where and move on.
- **Confirmed gap** — note it; it becomes a preceding child task in Step 5.

Do this BEFORE decomposing. The cost of finding gaps at grill time is one coder check; the cost of finding them mid-execution is a stop-and-replan interrupt. The user is paying for the proactive search.

### Step 4b — Surface the parent's own success criteria

**Mandatory: anchor to the user story before grilling on internal criteria.** Read [docs/user-stories.md](../../../docs/user-stories.md) and identify the user-story-level outcome this task ladders into. The project's success bar is unambiguous (user-stories.md §"Success Measurement"):

> the simulator output (the virtual machined part produced by the full chain) must match the original part description. This is the bar; everything else is internal to the chain. Per-model metrics (e.g. token accuracy in Model 1, primitive-extraction accuracy in Model 2) are training diagnostics, not story-level success criteria.

**At least ONE parent-level success criterion MUST be user-story-level.** A user-story-level criterion is a falsifiable, observable artifact tied to the chain's output matching the customer's description. Acceptable forms (per user-stories.md, two acceptable methods plus the demo pattern):

- **Raytracing** — diagnostic rays cast through the simulator point cloud verify wall counts and depths against expected geometry (see [lib/aid3/ray/](../../../lib/aid3/ray/)).
- **SymmetricRMS** — symmetric Hausdorff-like distance between simulator output and the target STL (see [lib/aid3/compare/](../../../lib/aid3/compare/)).
- **Demo verdict** — input text → rendered HTML → recorded human one-line judgment, captured in the task's `# Outcome` at close-out. See [20260502cc](../../../docs/backlog/20260502cc.md) §"Success criteria (parent-level)" criterion 4 for the canonical shape.

**The criterion stands as a gate even when today's chain cannot satisfy it.** A common failure mode: the chain is broken upstream (e.g., model class collapse from corpus under-representation), the planner anticipates the user-story criterion will record "output is garbage," and skips it as pointless. **Don't skip — record.** The measurement (whether passing or failing) becomes the baseline that future work measures improvement against. A criterion that says *"raytrace wall counts at task close-out: measured = N, expected = M, gap drives follow-up `<id>`"* is doing its job. A missing criterion is the failure mode this step exists to prevent.

**If the chain has no extant capability to take the measurement**, that is itself a gap to surface — it becomes a preceding child task (per Step 5c) or a filed peer task. Do not paper over the absence by writing only internal-metric criteria; missing measurement infrastructure IS the planning finding.

**If the parent's work cannot affect the chain output** (pure infrastructure, docs-only, test-only), the user-story anchor takes the shape *"this task does not affect the demo / chain output; its limit is X; story-level success is measured by `<named other task>`."* Declared explicitly so the limit is on record, not implicit.

Then grill the user on the **parent's own success criteria** — what specifically proves the umbrella scope was satisfied beyond "all children done." Examples that combine internal scaffolding with the mandatory user-story anchor:

- *Story-level + internal*: "After children land + retrain, `make pipeline-smoke` on input `<X>` produces a pointcloud.html that the user judges 'recognizable as `<X>`'. Internal preconditions: corpus regen byte-identical to projection; `make test-long` green."
- *Story-level when output is not yet acceptable*: "After children land, raytrace wall counts on `<reference part>` are recorded in `# Outcome`. If counts do not match expected, file a follow-up task with the gap and the next intervention. Falsifiable: missing measurement = failure."
- *Pure-infra task*: "This task ships test infrastructure. Its limit: passing the new tests is necessary but not sufficient for the user-story bar; story-level success is measured by `<other task>`."

Internal-metric criteria (corpus shifts, test-suite green, byte-identical regen, signature presence, `loop_report.json` shape, `[]Primitive` slice consumed without panic, etc.) belong in the criteria as well — they explain WHY the user-story criterion is expected to be approachable. They cannot stand alone.

The grill output is **threefold**:
- The proactive context map + verified gaps (input to Step 5).
- The **parent's own success criteria** (the integration / end-to-end gate that proves the umbrella scope was satisfied) — MUST include at least one user-story-level anchor per the above.
- A first-pass list of the **child tasks** the parent decomposes into.

## Step 5 — Decompose into N self-contained child tasks

This is where the new model lives. Do **not** write `# Work items` inside the parent file. Instead, for each child task identified during the grill:

**Context exploration continues here.** Step 3's reading was scoped to the parent; each child has its own narrower scope. As you write a child, re-read the docs and code that bear on *that child's* slice — and follow links you skipped earlier because they looked tangential to the parent but are central to this child. The README → linked-doc traversal is iterative, not a one-shot at Step 3. If a child's scope reveals a doc area you haven't touched yet, read it now before writing the child's `# Context`.

### 5a. Pick a fresh id and create the child file

Generate a new id: `YYYYMMDD<next-suffix>` (today's date + next free `aa..zz` from existing `docs/backlog/*.md`). Create `docs/backlog/<child-id>.md` with this format:

```markdown
---
id: <child-id>
title: Short imperative title (one line)
status: unplanned
created: YYYY-MM-DD
parent_story: docs/user-stories.md#section
parent_task: <parent-id>
depends_on: [<sibling-id>, <sibling-id>]   # empty if no preceding tasks
source: <where this came from, optional>
---

# Summary
One paragraph stating what this child task delivers and for whom. Self-contained:
a fresh reader needs no other context to understand what this task is and why.

# Context
Everything the executor needs to know to ship this change from cold context, with
no conversation history and no access to sibling task files. Include:
- Specific file paths with line numbers (e.g. `train/batch/feat_trainer/main.go:282-285`)
- Function signatures, type names, contract descriptions
- The relevant section of any `docs/context/<area>.md` if applicable
- Machinery's Handbook citation if a machining rule is involved
- Concrete artifacts produced by `depends_on` siblings: file paths, function names,
  data formats. Do NOT write "see sibling X for context" — copy the contract here.

# Work
What to do, in enough detail that a fresh executor knows where to make the change.
For a ~1h leaf task, this is typically a short paragraph plus a few bullets, NOT
a multi-step checklist. The size invariant: one focused commit when done.

# Success criteria
**Task-specific outcomes. Tests passing is a precondition, NOT the criterion.**
The criteria must say what concretely is true about the world after this task ships,
beyond "tests are green." Examples:
- "`per_epoch.csv` contains a header row plus N data rows after running `make -C train feat-train-mps ARGS='-epochs N'`"
- "`appendEpochCSV(path, epoch, ...)` returns nil and writes a row matching the schema for finite, NaN, and +Inf inputs"
- "Running `feat-infer` on `train/examples/00/01/solid-box.stl` produces a JSON with `pred_count >= 1`"

Each criterion must:
- Name a specific test, metric, or observable behavior the executor can check.
- Be falsifiable — there must be a way to FAIL it, not just a vibe.
- Cover degenerate / edge cases per [.claude/CLAUDE.md](../../.claude/CLAUDE.md) §Code.

The plan-completion gate `make test-long` is a separate precondition from CLAUDE.md
§"Plan lifecycle" — assume it; do not list it.

# Notes
Free-form rationale, dependencies, links. Optional.
```

### 5b. Self-containment check (mandatory)

Before saving each child file, re-read it and ask: **"Could a fresh executor — with NO prior conversation, NO access to sibling files, NO knowledge of the parent's grill — ship this change from this file alone?"** If the answer is no, the file is incomplete. Common failures:

- Cites a sibling artifact (file, function, format) without copying the relevant contract into `# Context`.
- Says "as discussed in the parent" or "see the planning conversation" — both forbidden.
- Refers to a code construct without a file path + line number that grep can find.
- Names a degenerate case ("handle the empty input") without specifying what the handling is.

Fix the file before moving on. The duplication this produces across siblings (multiple children may copy the same `# Context` paragraph about a shared file) is the *cost* of self-containment; pay it cheerfully.

### 5c. Verify gaps in code, then either skip them or file them as preceding children

For every dependency the executor would need (a function, a file, a flag, a data contract), verify via the `coder` skill (for symbol-shaped dependencies) or grep / read (for files, flags, configs) whether it exists in the current code. Two outcomes:

- **Exists in code**: cite it in the relevant child's `# Context`. No new task needed.
- **Does not exist**: file it as another child task in this decomposition. Add it to the dependency graph; downstream children list it in `depends_on`.

This replaces the old "gap discovered → restart planning" interrupt. Gaps are now the *normal output* of decomposition — they get expressed as preceding children, not as exceptions.

### 5d. Push children to the top of Active in dependency order

Add child entries to the top of `## Active` in `BACKLOG.md`. Order: foundational (no `depends_on`) first, then each subsequent child after its dependencies. Format unchanged from existing BACKLOG entries:

```
- <child-id> **Title** — one-line hook → docs/backlog/<child-id>.md
```

The parent stays where it was in BACKLOG (now buried below its children). Do not move the parent.

## Step 6 — Update the parent task file

The parent does NOT get `# Work items`. Instead:

```markdown
# Decomposition

Decomposed YYYY-MM-DD into N child tasks. Children execute top-down per their
`depends_on` lists.

**Parent auto-promotes to `done` only when BOTH conditions hold:**
1. Every child task is at `status: done`.
2. The parent's own success criteria (below) ALL pass — verified at the moment
   the last child closes out.

If condition 2 fails after condition 1 holds, the parent stays at `status: planned`
and the failing parent-level criterion gets filed as a new follow-up child task
(per the gap-discovery flow in `/execute-task` Step 5). The parent is NOT done
until both conditions hold simultaneously.

| Order | Child id | depends_on | Title |
|---:|---|---|---|
| 1 | 20260503aa | (none) | ... |
| 2 | 20260503ab | aa | ... |
| 3 | 20260503ac | ab | ... |

# Success criteria (parent-level)

These criteria are what proves the umbrella scope was satisfied. They are
**falsifiable, task-specific outcomes** — not "all children done" (that's
implicit) and not "tests are green" (that's a precondition assumed across the
whole system per CLAUDE.md). Examples of good parent-level criteria:

- Integration gates: "`make train-loop` produces non-empty `loop_report.json`
  with `stages_completed=[generate,train,eval,promote]` on a fresh run."
- End-to-end metric thresholds: "`SymmetricRMS(simulated_pcd, target_stl) < 5mm`
  on the 5 reference parts in `train/examples/`."
- Behavior the children individually cannot guarantee: "`feat-infer` followed by
  the new bridge produces a non-panicking `[]Primitive` slice on the 5
  non-synthetic STLs from `dh`'s curated set."

If a parent-level criterion is the same as a child's, demote it to the child and
remove it from here — the parent is for the integration / cross-child gates only.
```

Update parent frontmatter mechanically — flips `unplanned → planned` (or no-ops if already `planned` for the grill-and-update path):

```sh
scripts/task-status.sh planned <parent-id>
```

Keep the parent's existing `# Summary` and `# Notes`; they are the historical record of why the umbrella exists. New child files are written directly with `status: unplanned` (no script needed — they don't exist before this skill runs). Each child will be promoted unplanned → planned later when its own `/plan-task` pass runs.

## Step 7 — Close out

- **Grill must be complete before this step runs.** This step writes the parent file and chains into `/review-task`. Do not enter Step 7 while any Step 4 / Step 4-bis grill question is still open. Concretely: every `AskUserQuestion` invocation from the grill must have returned with a real answer (not an interruption, not a placeholder), and any in-chat clarification you asked the user must have a response in the transcript. If a grill question is still pending, stay in Step 4 / 4-bis until the user answers — the chain to `/review-task` fires only after the grill terminates cleanly.
- **Do NOT commit.** Plan/review iterations stay in the working tree as one uncommitted blob until `/review-task` promotes the bundle to `ready` (that's the only commit point in the plan/review cycle — see [docs/process.md](../../../docs/process.md) §Lifecycle). If review writes `# Open issues`, this skill re-enters in grill-and-update mode against an already-dirty tree; that's expected.
- Summarize back to the user in 3-5 sentences:
  - **Full-plan mode**: how many children were filed, the dependency shape (linear chain / fan-out / DAG), and the parent's own success criteria.
  - **Grill-and-update mode**: how many open issues were addressed and what changed in the parent or which children were edited / added / split.
- Transition STATE.md from `planning` to `reviewing` for the same parent id — `state.sh` explicitly allows `planning → reviewing` as the "cross-skill jump for grill→review" transition:

  ```sh
  scripts/state.sh reviewing <parent-id>
  ```

  Do **not** route through `idle` first — that would lose the task pointer and force `/review-task` to fall back to "first entry under `## Active`" in BACKLOG, which may not match the parent we just planned if Active has other items above it.
- **Invoke the `review-task` skill via the Skill tool, immediately, in the same response.** Do not ask the user first; the planned tree + `reviewing` state is the explicit hand-off, and the user can interrupt mid-review if they want to pause. One-line preface to the user is sufficient: *"Plan ready: `<N>` children. Chaining into `/review-task` to audit before execution."*

  Tool call shape: `Skill(skill: "review-task")`. The review-task skill's Step 1 will detect `activity=reviewing task=<parent-id>` and resume on that task. On pass it promotes the parent (and children) to `ready` and tells the user to run `/execute-task`. On fail it writes `# Open issues` and chains *back* into this skill in grill-and-update mode. The cycle terminates at the first review pass — i.e., when no findings remain.

## What this skill does NOT do

- Does not write code. Code happens in `/execute-task`.
- Does not reorder the BACKLOG beyond inserting the new children at the top in dep order. Cross-parent reordering happens in `/prioritize-backlog`.
- Does not skip the grill. The grill is what turns the parent's vague intent into N self-contained child tasks.
- Does not write `# Work items` checklists. The decomposition unit is a task file, not a checkbox.
- Does not let a child file ship if it is not self-contained. The self-containment check (5b) is mandatory.
