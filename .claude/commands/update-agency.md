<!-- Source: https://github.com/Strode-Mountain/machine-shop -->
# Update Agency Personas

Sync agent persona files from the [agency-agents](https://github.com/msitarzewski/agency-agents) library into `.claude/agents/`.

## Usage

```
/update-agency [categories...] [--list]
```

### Examples

```
/update-agency                      # Sync all categories
/update-agency engineering testing  # Sync only these categories
/update-agency --list               # Show available categories without syncing
```

## Implementation

### Step 1: Read configuration

Check for `.claude/agency-config.json`. If it exists, read it for the source URL. Default source:

```
https://github.com/msitarzewski/agency-agents
```

### Step 2: Handle `--list` flag

If `--list` is passed:
1. Shallow-clone the repo to a temp directory
2. List all top-level subdirectories containing `.md` files
3. Print the category names and file counts
4. Clean up temp clone
5. Stop here (do not sync)

### Step 3: Clone and sync

1. Create a temp directory
2. Shallow-clone the agency-agents repo: `git clone --depth 1 <source_url> <temp_dir>`
3. Determine categories to sync:
   - If category arguments provided, use only those
   - Otherwise, sync all subdirectories containing `.md` files
4. For each category:
   - Create `.claude/agents/<category>/` if it doesn't exist
   - For each `.md` file in the source category:
     - Compare with existing file (if any)
     - Copy file to `.claude/agents/<category>/`
     - Track: **added** (new file), **updated** (content changed), **unchanged**
5. Report results per category

### Step 4: Update configuration

Create or update `.claude/agency-config.json`:

```json
{
  "source_url": "https://github.com/msitarzewski/agency-agents",
  "last_sync": "2025-01-15T10:30:00Z",
  "synced_categories": ["engineering", "testing", "..."]
}
```

### Step 5: Clean up

Remove the temp clone directory.

## Output Format

```
Syncing agent personas from agency-agents...

  engineering/: 3 added, 1 updated, 2 unchanged
  testing/:     0 added, 1 updated, 4 unchanged
  design/:      5 added, 0 updated, 0 unchanged

  Total: 8 added, 2 updated, 6 unchanged
  Config: .claude/agency-config.json updated
```

## Error Handling

- If `git clone` fails, report the error and suggest checking the source URL
- If a category argument doesn't match any source directory, warn and skip it
- If `.claude/agents/` doesn't exist, create it

## Notes

- Agent persona files are `.md` files defining roles, expertise, and behavioral guidelines
- The source repository is configurable via `.claude/agency-config.json`
- This command does not modify any existing project code — it only manages `.claude/agents/`
