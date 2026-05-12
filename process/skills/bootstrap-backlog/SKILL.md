---
name: bootstrap-backlog
description: One-time-ish migration that sweeps existing markdown files (`tasks/**/*.md`, `docs/**/*.md`, top-level `*.md`) for task-shaped content and routes each into docs/backlog/<id>.md, BACKLOG.md, docs/DONE.md, or docs/PUNT.md. Source files retain a back-pointer to the new location — nothing is dropped unless explicitly stale. Also walks docs/user-stories.md and grills each unmarked story to Status=unimplemented. Resumable across sessions via STATE.md. TRIGGER when user says "bootstrap the backlog", "/bootstrap-backlog", or this is the first time the kanban system is being used. Idempotent — safe to re-run; already-migrated items are skipped.
---

You are migrating dense, scattered task content into the kanban system without losing any of it. Full process in [docs/process.md](../../../docs/process.md). The user's directive: *"There is no desire to remove or drop tasks unless they are stale. If they are stale, then they are put in PUNT but retain their markers to docs/backlog/*.md"*.

This is the only skill that performs bulk file mutations. Be careful, surface progress to the user often, and **always offer dry-run before applying**.

## Step 1 — Read STATE.md

- `activity=bootstrapping`: resume. The state's free-form notes section should record which source file was last in-progress.
- Any other activity: ask the user before proceeding.

Set `STATE.md`:

```
activity: bootstrapping
task:
started: <ISO8601 timestamp>
```

## Step 2 — Stage 1: User stories

Open `docs/user-stories.md`. Walk leaf stories top-to-bottom. For any with no `**Status:**` line (or `Status: new`):

1. Use the grill discipline ([.claude/skills/grill-me/SKILL.md](../grill-me/SKILL.md)) — verify-by-grep first, judgment one question at a time. Grill until the story has a distinct, testable shape.
2. Append `**Status:** unimplemented` immediately after the story's last paragraph.
3. Save the file. Update STATE notes: `last user-story: <heading>`. This makes the operation resumable.

Do all of Stage 1 before Stage 2 — task triage in Stage 3 needs the user-story map to assign `parent_story`.

## Step 3 — Stage 2: Discover task candidates

**Read every `*.md` file in scope.** Don't filter by filename pattern — strategy docs, retrospectives, research notes, TODOs, READMEs, and exploration writeups all carry task-shaped content somewhere. The cost of reading one extra doc is one tool call; the cost of missing a buried task is losing it forever. The user-facing rule: *"There is no desire to remove or drop tasks unless they are stale."* You cannot honor that without reading the docs to know what's there.

Default scope is the whole working tree, with these explicit sources:

1. **`tasks/**/*.md`** — every plan, sub-plan, retrospective, session note, and research index. Each top-level "Phase" / "section" / "deliverable" is a candidate. Each "Future" / "Deferred" / "Punch list" / "Carryover" / "Next steps" section is a candidate.
2. **`docs/**/*.md`** — context files, architecture docs, off-ramps, exploration notes. Anywhere with `TODO`, `Next steps`, "could", "should", or unstruck checklist items.
3. **Top-level `*.md`** — README.md, anything else at the root.
4. **Anywhere else the user points at**, including narrowed scopes like `tasks/shapes/**` only.

The user may scope the bootstrap to a subset (e.g. *"bootstrap on `tasks/shapes/**`"*). When scoped, read every `.md` under that subset; don't filter further by filename.

For each file:
- Read it fully (or page through it if very large; never skip on the assumption that a filename like `scope.md` or `research.md` can't contain tasks).
- Identify candidate tasks: explicit bullets, "Next" / "Future" / "Carryover" sections, status tables with NOT DONE / TODO / PARTIAL entries, embedded "should X" sentences in narrative.
- Note when a candidate has already been migrated (search existing `docs/backlog/*.md` for `source: <same-path>:<same-marker>`).

Build a candidate list **in memory** first; do not write any files yet. Show the user a summary: *"Found N candidates across M files: K from tasks/, P from docs/, etc. Proceed to triage?"* If the volume is large (>30 candidates) propose grouping the user's first triage pass by source file rather than per-candidate.

## Step 4 — Stage 3: Triage and migrate

For each candidate, present to the user with the source quote and ask:

| Disposition | What it means |
|---|---|
| **keep-active** | Goes to BACKLOG.md `## Active`, status=unplanned |
| **keep-deferred** | Goes to BACKLOG.md `## Deferred`, status=unplanned |
| **done** | Goes to docs/DONE.md (already shipped) |
| **punt** | Goes to docs/PUNT.md (stale / no longer worth doing) |
| **merge** | Append to an existing docs/backlog/<id>.md `# Notes` (provide id) |
| **skip** | Do nothing — not actually a task |

Where the source uses status markers (e.g. legacy bullet conventions: `~~`/`+` for done, `x` for punt, `?` for needs-clarification), honor them as defaults — the user can override.

Batch UX: instead of asking for every candidate one at a time, group by source file and ask the user to disposition the file as a whole when entries share an obvious fate (e.g. "all of `docs/off-ramps.md` → keep-deferred"). Drop down to per-entry only when the user wants more control.

For every kept / done / punted candidate:

1. Generate id `YYYYMMDD<next-suffix>` (today + next free `aa..zz` from existing `docs/backlog/`).
2. Create `docs/backlog/<id>.md` with frontmatter:

   ```yaml
   ---
   id: <id>
   title: <imperative title extracted from source>
   status: unplanned | done | punted
   created: <today>
   parent_story: docs/user-stories.md#<section> (or "none" with rationale)
   source: <path>:<heading-or-bullet-marker>
   ---
   ```

3. Body: `# Summary` lifted from source (verbatim quote OK), `# Notes` listing the source link. For `done`, add `# Outcome` capturing what shipped (lift from source). For `punted`, add `# Punt reason`.
4. Add the appropriate index line:
   - `keep-active` → BACKLOG.md `## Active`
   - `keep-deferred` → BACKLOG.md `## Deferred`
   - `done` → docs/DONE.md (under today's date heading)
   - `punted` → docs/PUNT.md (under today's date heading)
5. **Annotate the source file with a back-pointer**, in-line where the original entry sits:

   ```
   → migrated to docs/backlog/<id>.md (<status>)
   ```

   Do not delete the original content. The user said the source must be preserved.

Resumability: every 5-10 candidates, save STATE notes (`last source: <path>, last bullet: <marker>`) so an interruption picks up cleanly.

## Step 5 — Stage 4: Verify nothing was lost

Walk the source files one more time. Every task-shaped entry should have either:

- A back-pointer to `docs/backlog/<id>.md`, or
- An explicit `skip` decision recorded in STATE notes.

If anything is unaccounted for, surface it to the user.

## Step 6 — Close out

- Reset `STATE.md`: `activity: idle`, empty notes (or keep a brief "last bootstrap: <date>, N tasks migrated").
- Summarize: how many tasks landed in Active vs Deferred vs Done vs Punt; how many user stories got grilled to `unimplemented`; what the user might want to do next (`/prioritize-backlog` is the natural follow-up).

## Idempotency rules

- Re-running this skill should not duplicate tasks. Before creating a new `docs/backlog/<id>.md` for a candidate, search existing backlog files for `source: <same-path>:<same-marker>`. If found, skip.
- Re-running should pick up any new task-shaped content added since the last run, plus any candidates the user previously marked `skip` if they explicitly ask to revisit.

## What this skill does NOT do

- Does not delete source content. Source files keep their original text plus a back-pointer.
- Does not plan tasks (`/plan-task`).
- Does not prioritize (`/prioritize-backlog`) — bootstrap leaves the order roughly source-derived; prioritize is the next step.
