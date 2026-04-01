<!-- Source: https://github.com/Strode-Mountain/machine-shop -->
# Address Issue

Autonomously implement a GitHub issue using an agent team and superpowers workflow.

## Usage

```
/address-issue <issue-number>
```

### Example

```
/address-issue 42
```

## Implementation

### Step 1: Fetch issue details

```bash
gh issue view <number> --json title,body,labels,comments
```

If the issue doesn't exist or `gh` fails, report the error and stop.

### Step 2: Parse agent team

Scan the issue body for persona abbreviations. These appear in the Agent Team table or inline text referencing agent roles.

**Agent team table format** (written by `/refine-issue`):

```markdown
## Agent Team

| Role | Persona | Responsibility |
|------|---------|----------------|
| SE   | Senior Developer | Core implementation |
| CR   | Code Reviewer | Quality gates |
```

**Resolution order:**
1. **Issue body** — look for an Agent Team table or persona abbreviations
2. **Parent release tracker** — if the issue references a tracking issue, check that issue's body
3. **Label-based inference** — map labels to default teams:
   - `bug` → `["SE", "QA", "CR"]`
   - `enhancement` → `["SE", "CR"]`
   - `security` → `["SE", "SEC", "CR"]`
   - `documentation` → `["TW", "CR"]`
4. **Default** — `["SE", "CR"]` (engineer + code reviewer)

**Always include `CR` (Code Reviewer)** regardless of team composition.

### Step 3: Load agent personas

Read `.claude/agent-teams.json` for abbreviation-to-file mappings. For each mapped persona file that exists, read it to inform behavior during implementation.

If `.claude/agent-teams.json` doesn't exist, warn the user and proceed with default behavior (no persona files loaded — just use the role names as context).

### Step 4: Claim issue + create branch

1. **Guard check:** Query the issue for `WIP` or `PR` labels. If either is present, report that the issue is already claimed and stop — do not proceed.
2. Add `WIP` label to claim the issue: `gh issue edit <number> --add-label "WIP"`
3. Create branch:
   ```bash
   git checkout -b issue-<number>-<slug>
   ```
   Where `<slug>` is the issue title lowercased, spaces replaced with hyphens, truncated to 40 chars, special characters removed.

### Step 5: Plan the work

- Invoke `superpowers:writing-plans` using the issue body as the spec
- The plan decomposes the issue into discrete tasks informed by the agent personas
- Each task identifies which persona(s) execute it
- Save the plan to `docs/superpowers/plans/<issue-number>-<slug>.md` and commit it to the branch
- This step is autonomous — the issue body IS the spec, no brainstorming or clarification cycle

### Step 6: Execute via subagent-driven development

- Invoke `superpowers:subagent-driven-development` (or `superpowers:executing-plans` if running across sessions)
- Each task dispatches with the relevant agent persona(s) as context
- After each task, dispatch `superpowers:code-reviewer` subagent for isolated review, passing the CR persona and any domain personas from the team
- Fix issues before proceeding to the next task
- Iterate until the reviewer approves each task
- **Safety valve:** If any single task exceeds 10 review-fix iterations, stop and surface the issue to the user rather than looping indefinitely

### Step 7: Final verification

- Invoke `superpowers:verification-before-completion`
- Run lint, type-check, tests — confirm passing output before claiming done
- If verification fails, fix and re-verify

### Step 8: Create pull request (MANDATORY — always runs automatically)

**This step is not optional and requires no user input.** After verification passes, immediately push the branch and create the PR. Do NOT invoke `superpowers:finishing-a-development-branch` or prompt the user for merge strategy — `/address-issue` always produces a PR.

```bash
gh pr create --title "Implement #<number>: <issue title>" --body "$(cat <<'PREOF'
## Summary
Closes #<number>

<bullet points describing changes>

## Plan
See `docs/superpowers/plans/<issue-number>-<slug>.md`

## Agent Team
| Role | Persona | Responsibility |
|------|---------|----------------|
<team table from the issue>

## Review Summary
<summary of code-reviewer findings and resolutions per task>

## Test Plan
<checklist based on issue requirements>

🤖 Generated with [Claude Code](https://claude.ai/code)
PREOF
)"
```

After PR creation:
- Replace `WIP` with `PR` label on the issue: `gh issue edit <number> --remove-label "WIP" --add-label "PR"`
- Add the version label to the PR (if the issue has one)

### Step 9: Update release tracker (best-effort)

If a parent release tracker was identified in Step 2, update the tracker body table (not just a comment). Fetch the current body with `gh issue view`, modify the relevant status cell, and write back with `gh issue edit --body`.

If no tracker found, skip silently.

### Step 10: Present summary

After all steps complete, present a brief summary to the user:
- PR number and title
- Issue label updates (WIP → PR)
- Tracker updates (if applicable)
- Bullet points of changes
- Verification results (lint, type-check, tests)

## Error Handling

- `gh` not authenticated → report and stop
- Issue not found → report and stop
- Issue already claimed (WIP/PR label) → report and stop
- `.claude/agent-teams.json` missing → warn, proceed without persona files
- Agent persona files missing → warn per file, proceed with available ones
- Git conflicts → report and stop, don't force
- PR creation fails → report error, leave branch for manual PR

## Superpowers Integration

This command integrates with the `superpowers` plugin:

- **`superpowers:writing-plans`** — decomposes the issue into executable tasks (Step 5)
- **`superpowers:subagent-driven-development`** — executes tasks with persona-informed subagents (Step 6)
- **`superpowers:executing-plans`** — alternative for cross-session execution (Step 6)
- **`superpowers:code-reviewer`** subagent — isolated review after each task (Step 6)
- **`superpowers:verification-before-completion`** — final lint/type-check/test gate before PR (Step 7)

## Notes

- The issue body IS the spec — no separate brainstorming or clarification step (use `/refine-issue` first if the issue needs refinement)
- All work happens on the feature branch, never on main
- The Code Reviewer persona is always included to ensure quality
- Each task gets an isolated code review — not self-review
- The plan file is committed to the branch and linked in the PR for traceability
- Always creates a PR — never prompt the user for merge strategy, never invoke `superpowers:finishing-a-development-branch`
- The PR body must include `Closes #<number>` so the issue auto-closes on merge
