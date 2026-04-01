# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this repository.

## Custom Commands

| Command | Purpose |
|---------|---------|
| `/prime` | Load project context — run this at the start of every session |
| `/security-scan` | Security scanning for malicious code and exposed secrets |
| `/update-agency` | Sync agent personas from agency-agents library |
| `/address-issue` | Autonomously implement a GitHub issue with agent team |
| `/refine-issue` | Refine a rough GitHub issue into an actionable spec |
| `/review-pr` | Review a PR for quality, correctness, and security |

> These commands survive `/clear` because they are documented here.
> If Claude says "unknown command" after `/clear`, restart the session — CLAUDE.md is re-loaded automatically.

---

## Repository Overview

**Project Name**: [Your Project Name]
**Purpose**: [Brief description of what this project does]
**Tech Stack**: [List primary technologies]

## Key Architecture

[Describe the main architectural patterns and directory structure]

## Development Guidelines

### Code Style
[Specify coding standards, linting rules, and formatting conventions]

### Git Workflow
[Explain branching strategy and commit message conventions]

## Important Context

[Add critical info: known gotchas, files not to touch, external deps, security requirements]
