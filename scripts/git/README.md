# Git Author Management Scripts

This directory contains shell scripts for managing git author switching between human developers and Claude Code Assistant.

## Scripts

### git-author-claude.sh
Switches git author to Claude Code Assistant for AI-generated commits.

```bash
./scripts/git/git-author-claude.sh
```

### git-author-human.sh
Restores the human developer as git author.

```bash
./scripts/git/git-author-human.sh
```

Options:
- `--force`: Force restore from global git config if no saved config exists
- `--reset`: Clear configuration and require manual setup

### git-author-verify.sh
Verifies the current git author configuration.

```bash
./scripts/git/git-author-verify.sh
```

Options:
- `--quiet`: Suppress output (exit code indicates status)
- `--verbose`: Show detailed configuration information
- `--repair`: Attempt to fix configuration issues

## Configuration

The scripts maintain configuration in `.claude/git-authors.json`:

```json
{
  "human": {
    "name": "Developer Name",
    "email": "developer@example.com"
  },
  "claude": {
    "name": "Claude Code Assistant",
    "email": "claude-code@anthropic.com"
  },
  "current": "human",
  "last_updated": "2024-01-15T10:30:00Z"
}
```

## Workflow

1. Before AI commits: `./scripts/git/git-author-claude.sh`
2. Make commits with AI assistance
3. After AI commits: `./scripts/git/git-author-human.sh`

## Troubleshooting

### "No saved human author configuration found"
- Use `--force` to restore from global git config
- Or use `--reset` and manually configure

### "Git author configuration is incomplete"
- Set your git config:
  ```bash
  git config user.name "Your Name"
  git config user.email "your.email@example.com"
  ```

### Scripts not executable
- Run: `chmod +x scripts/git/*.sh`
- Or use verify with `--repair`: `./scripts/git/git-author-verify.sh --repair`
