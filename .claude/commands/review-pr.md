<!-- Source: https://github.com/Strode-Mountain/machine-shop -->
# Review PR

Review a pull request for code quality, correctness, security, and style. Optionally fix issues and merge.

## Usage

```
/review-pr <pr-number> [--fix] [--merge]
```

### Examples

```
/review-pr 42              # Review only — post comments
/review-pr 42 --fix        # Review, fix findings, push
/review-pr 42 --merge      # Review, squash merge if clean
/review-pr 42 --fix --merge # Review, fix, then squash merge
```

## Implementation

### Step 1: Fetch PR details

```bash
gh pr view <number> --json title,body,headRefName,baseRefName,labels,files,reviews,comments
gh pr diff <number>
```

If the PR doesn't exist or `gh` fails, report the error and stop.

### Step 2: Dispatch code-reviewer subagent

Delegate the review to a `superpowers:code-reviewer` subagent for an isolated, unbiased analysis. The subagent reviews in a fresh context without inheriting session history.

**Prepare review context for the subagent:**

1. Determine the base and head SHAs:
   ```bash
   BASE_SHA=$(gh pr view <number> --json baseRefName --jq '.baseRefName' | xargs git rev-parse)
   HEAD_SHA=$(gh pr view <number> --json headRefName --jq '.headRefName' | xargs git rev-parse)
   ```

2. **Load agent team context (persona-aware review):** If the PR body includes an "Agent Team" section (written by `/address-issue`), load the CR persona from `.claude/agent-teams.json` and pass it to the subagent. If the team included domain personas (SEC, A11Y, DB, etc.), pass those as supplementary review lenses — the reviewer checks the work from those perspectives too.

3. Dispatch the `superpowers:code-reviewer` subagent with:
   - **What was implemented**: PR title and description
   - **Plan/requirements**: Issue body (if linked) or PR description
   - **Base SHA / Head SHA**: From step above
   - **Agent personas**: CR persona plus any domain personas from the team
   - **Review criteria**: All items from the review checklist below

**Review checklist** (passed to the subagent):

1. **Code quality** — readability, naming, structure, DRY
2. **Correctness** — logic errors, edge cases, off-by-one, null handling
3. **Security** — injection, auth issues, secret exposure, OWASP top 10
4. **Style** — consistency with surrounding code, formatting
5. **Tests** — adequate coverage for changes, test quality
6. **Plan compliance** — if the PR references a plan file (from `/address-issue`), verify all planned tasks were completed and the implementation matches the plan
7. **Domain-specific criteria** — based on team personas (e.g., DB optimization if DB persona was on the team, accessibility if A11Y was included, security hardening if SEC was involved)

**Note:** Projects may extend this checklist with project-specific criteria in their CLAUDE.md (e.g., dual-storage consistency, query filter orphan checks).

### Step 3: Post review

Post the subagent's findings as a PR review using `gh`:

```bash
gh pr review <number> --comment --body "<review body>"
```

Or if no issues found:

```bash
gh pr review <number> --approve --body "LGTM — <brief summary>"
```

The review body should include:
- Summary of changes understood
- Issues found (categorized by severity: critical, suggestion, nit)
- Questions for the author (if any)

### Step 4: Detect release tracker (best-effort)

Check PR labels and body for cross-references to a release tracking issue. If found, note it for Step 7. If not found, skip silently.

### Step 5: Fix (if `--fix` flag)

If `--fix` is passed and issues were found:

1. Invoke `superpowers:receiving-code-review` to guide the fix process
2. Check out the PR branch: `gh pr checkout <number>`
3. **Verify each finding** against the codebase before acting — do not blindly implement suggestions that may be incorrect for the project context
4. **Push back** on findings that are technically wrong, break existing functionality, or violate YAGNI — note the reasoning in the follow-up comment
5. Fix verified findings **one at a time**, testing after each change to prevent regressions
6. For inline review comments, reply in the comment thread:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/comments/{comment-id}/replies \
     -f body="Fixed — <brief description of what changed>"
   ```
7. Commit fixes: `git commit -m "Address review feedback for PR #<number>"`
8. Push: `git push`
9. Post a follow-up summary comment noting what was fixed, what was pushed back on (with reasoning), and what was deferred

If no issues were found, skip this step.

### Step 6: Merge (if `--merge` flag)

If `--merge` is passed:

1. Verify the PR is in a mergeable state
2. If `--fix` was also passed, verify fixes are pushed
3. Squash merge: `gh pr merge <number> --squash --delete-branch`
4. Report success

If the PR has unresolved issues and `--fix` was not used, warn and do not merge.

### Step 7: Update release tracker (best-effort)

If a release tracker was found in Step 4, update the tracker body table (not just a comment). Fetch the current body with `gh issue view`, modify the relevant status cell, and write back with `gh issue edit --body`.

## Output Format

```
Reviewing PR #42: "Add user authentication"...

  Files changed: 5
  Additions: +142, Deletions: -23

  Findings:
    🔴 Critical: SQL injection risk in user_query() (auth.py:45)
    🟡 Suggestion: Consider using parameterized queries (auth.py:47)
    🔵 Nit: Trailing whitespace (auth.py:52)

  Review posted to PR #42.
```

## Error Handling

- `gh` not authenticated → report and stop
- PR not found → report and stop
- PR already merged → report and stop
- Merge conflicts during `--fix` → report, skip merge
- Merge blocked by branch protection → report, skip merge
- Network errors → report and stop

## Superpowers Integration

This command integrates with the `superpowers` plugin:

- **`superpowers:code-reviewer`** subagent — dispatched in Step 2 for isolated, unbiased review in a fresh context
- **`superpowers:receiving-code-review`** discipline — applied in Step 5 (`--fix`) to verify findings before acting, push back on incorrect suggestions, and fix one item at a time with testing
- **GitHub thread replies** — Step 5 replies inline to review comment threads rather than posting top-level comments

## Notes

- Reviews are posted as PR review comments, not issue comments
- `--merge` always uses squash merge with branch deletion
- Release tracker detection is best-effort — proceeds normally without one
- When `--fix --merge` is combined: review → fix → push → merge (sequential)
- The code-reviewer subagent reviews in isolation — it does not inherit the caller's session context, which prevents confirmation bias
