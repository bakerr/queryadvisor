<!-- Source: https://github.com/Strode-Mountain/machine-shop -->
# Refine Issue

Take a rough GitHub issue and refine it into an actionable, well-structured issue ready for `/address-issue`.

## Usage

```
/refine-issue <issue-number>
```

### Example

```
/refine-issue 42
```

## Implementation

### Step 1: Fetch issue

```bash
gh issue view <number> --json title,body,labels,comments
```

If the issue doesn't exist or `gh` fails, report the error and stop.

### Step 2: Determine refinement team

Select agent personas based on issue domain:

- Read labels and body to classify the issue
- Label-based inference:
  - `bug` → `["SE", "QA", "CR"]`
  - `enhancement` → `["SE", "CR"]`
  - `security` → `["SE", "SEC", "CR"]`
  - `documentation` → `["TW", "CR"]`
- Extend with domain specialists based on content analysis: if it touches UI add UX, data issues add DB, performance add PERF, accessibility add A11Y
- Always include SE (feasibility/approach) and CR (testability/review criteria)

### Step 3: Load agent personas

Read `.claude/agent-teams.json` for abbreviation-to-file mappings. For each mapped persona file that exists, read it to inform behavior during refinement.

If `.claude/agent-teams.json` doesn't exist, warn the user and proceed without persona files.

### Step 4: Investigate the codebase

Before asking the user clarifying questions, explore the codebase to understand the issue domain:

- Search for relevant files, types, services, and patterns
- Read key files to understand the current implementation
- Check git history for recent changes in the affected area
- Identify all code paths relevant to the issue (storage, backup/restore, migration, UI, etc.)

This investigation informs your questions and prevents asking the user things you could answer yourself.

### Step 5: Ask clarifying questions

Use the brainstorming approach to refine the issue:

- Ask questions one at a time to clarify requirements
- Prefer multiple choice questions when possible
- Identify root cause (for bugs) or clarify requirements (for features)
- Propose approaches with trade-offs and get user approval
- Keep the conversation focused — you're refining an issue, not designing an entire system

### Step 6: Decompose into sub-tasks

Break the refined understanding into discrete, implementable sub-tasks. Each sub-task should be concrete enough for a single agent iteration in `/address-issue`.

### Step 7: Define agent team composition

Based on what the work requires, write the agent team table in standard format:

```markdown
## Agent Team

| Role | Persona | Responsibility |
|------|---------|----------------|
| SE   | Senior Developer | Core implementation |
| QA   | Reality Checker | Test coverage and validation |
| CR   | Code Reviewer | Quality gates |
```

The `Role` column contains abbreviations from `.claude/agent-teams.json`. The `Responsibility` column describes what that persona owns for this specific issue.

### Step 8: Update the GitHub issue

The primary output of this command is the refined GitHub issue. Update the issue title (if it can be made more specific) and body via `gh issue edit`.

**Issue body format** — preserve the original text in a collapsible block:

```markdown
<details>
<summary>Original issue</summary>

> (original issue text preserved verbatim)

</details>

## Root Cause Analysis
(if bug — omit section for enhancements)

## Requirements
(refined, specific requirements)

## Sub-tasks
- [ ] Task 1 description
- [ ] Task 2 description
- [ ] ...

## Agent Team
| Role | Persona | Responsibility |
|------|---------|----------------|
| ...  | ...     | ...            |

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Detailed Spec
(only if the issue is complex enough to warrant one — see Step 9)
```

**Labels**: Apply appropriate labels (type, version) per CLAUDE.md labeling standards if not already set.

### Step 9: Write detailed spec (complex issues only)

If the investigation and brainstorming produced detailed design decisions, file/line references, or architectural notes that are too extensive for an issue body:

1. Create a feature branch (e.g., `fix/<number>-<slug>` or `feature/<number>-<slug>`)
2. Write the spec to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` on that branch
3. Commit and push the branch
4. Add a "Detailed Spec" section at the bottom of the issue body linking to the spec file on the branch:
   ```markdown
   ## Detailed Spec
   Full design spec on branch [`fix/123-feature-name`](https://github.com/<owner>/<repo>/tree/fix/123-feature-name) at:
   `docs/superpowers/specs/YYYY-MM-DD-topic-design.md`
   ```

For simple issues (single-file fix, straightforward logic), skip the spec entirely — the issue body is sufficient.

### Step 10: Update release tracker (best-effort)

If a tracker exists for this issue's version label, update the tracker body table (not just a comment). Fetch the current body with `gh issue view`, modify the relevant status cell, and write back with `gh issue edit --body`.

If no tracker or version label exists, skip silently.

## Error Handling

- `gh` not authenticated → report and stop
- Issue not found → report and stop
- `.claude/agent-teams.json` missing → warn, proceed without persona files
- Agent persona files missing → warn per file, proceed with available ones

## What this command does NOT do

- Write implementation code
- Create sub-issues (keeps everything in one issue body for `/address-issue`)
- Make changes without user approval — major decisions go through brainstorming approval gates
- Write local-only specs without pushing them (specs must be on a branch and linked from the issue)

## Notes

- This command is interactive — it asks the user clarifying questions during brainstorming
- The refined issue body uses a standard format that `/address-issue` can parse autonomously
- The original issue text is always preserved in a collapsible block
- The agent team table uses the same format and abbreviations as `.claude/agent-teams.json`
- The primary deliverable is the updated GitHub issue — everything flows back to GitHub
