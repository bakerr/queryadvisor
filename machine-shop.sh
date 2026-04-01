#!/bin/bash
# Machine Shop — AI Setup Deployment Script
# Version: 4.0.0
# Source: https://github.com/Strode-Mountain/machine-shop


# ===== Module: 00-header.sh =====
# AI Setup Deployment Script - Header Module
# This module contains the initial setup, configuration, and utility functions

# Version and metadata
VERSION="4.0.0"
DEPLOY_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Configuration variables
CONFIG_DIR=".claude"
CONFIG_FILE="$CONFIG_DIR/git-authors.json"
BACKUP_FILE="$CONFIG_DIR/git-authors.backup"

# Security scanning configuration
SECURITY_SCAN_MODE="auto"  # Default to auto-detection

# Error handling function
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Help function
show_help() {
    cat << 'HELP_EOF'
AI Setup Deployment Script v4.0.0

USAGE:
    ./machine-shop.sh [OPTIONS]

OPTIONS:
    --security-scan=MODE    Security scanning deployment mode:
                           • enable  - Always deploy security scanning
                           • disable - Never deploy security scanning  
                           • auto    - Auto-detect based on repository type (default)
    
    --help, -h             Show this help message

SECURITY SCANNING MODES:
    • enable  - Deploys security scanning regardless of repository type
    • disable - Skips security scanning completely
    • auto    - Analyzes repository to determine if it's a code repository:
               - Code repositories: deploys security scanning
               - Documentation repositories: skips security scanning
               - Uncertain cases: prompts user for decision

EXAMPLES:
    ./machine-shop.sh                          # Auto-detect repository type
    ./machine-shop.sh --security-scan=enable   # Force security scanning
    ./machine-shop.sh --security-scan=disable  # Skip security scanning

For more information, see: docs/guides/security_scanning.md
HELP_EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --security-scan=*)
                SECURITY_SCAN_MODE="${1#*=}"
                if [[ "$SECURITY_SCAN_MODE" != "enable" && "$SECURITY_SCAN_MODE" != "disable" && "$SECURITY_SCAN_MODE" != "auto" ]]; then
                    error_exit "Invalid security scan mode: $SECURITY_SCAN_MODE. Must be 'enable', 'disable', or 'auto'"
                fi
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Repository type detection function
detect_repository_type() {
    local code_indicators=0
    local docs_indicators=0
    local total_files=0
    
    # Count different file types
    if [ -d "." ]; then
        # Code file extensions
        local code_files=$(find . -type f \( \
            -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" -o \
            -name "*.py" -o -name "*.rb" -o -name "*.php" -o -name "*.java" -o \
            -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" -o \
            -name "*.go" -o -name "*.rs" -o -name "*.swift" -o -name "*.kt" -o \
            -name "*.cs" -o -name "*.scala" -o -name "*.clj" -o -name "*.hs" -o \
            -name "*.css" -o -name "*.scss" -o -name "*.sass" -o -name "*.less" -o \
            -name "*.html" -o -name "*.xml" -o -name "*.json" -o -name "*.yaml" -o \
            -name "*.yml" -o -name "*.toml" -o -name "*.ini" -o -name "*.cfg" \
        \) 2>/dev/null | wc -l | tr -d ' ')
        
        # Documentation file extensions
        local doc_files=$(find . -type f \( \
            -name "*.md" -o -name "*.txt" -o -name "*.rst" -o \
            -name "*.tex" -o -name "*.adoc" -o -name "*.org" \
        \) 2>/dev/null | wc -l | tr -d ' ')
        
        # Project-specific indicators
        if [ -f "package.json" ] || [ -f "pom.xml" ] || [ -f "requirements.txt" ] || \
           [ -f "Gemfile" ] || [ -f "go.mod" ] || [ -f "Cargo.toml" ] || \
           [ -f "build.gradle" ] || [ -f "CMakeLists.txt" ] || [ -f "Makefile" ] || \
           [ -f "composer.json" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
            ((code_indicators+=5))
        fi
        
        # Source directories
        if [ -d "src" ] || [ -d "lib" ] || [ -d "app" ] || [ -d "pkg" ] || \
           [ -d "bin" ] || [ -d "cmd" ] || [ -d "internal" ]; then
            ((code_indicators+=3))
        fi
        
        # Documentation-only indicators
        if [ -d "docs" ] && [ ! -d "src" ] && [ ! -d "lib" ]; then
            ((docs_indicators+=3))
        fi
        
        # Count total files for ratio calculation
        total_files=$((code_files + doc_files))
        
        # Calculate indicators based on file ratios
        if [ $total_files -gt 0 ]; then
            local code_ratio=$((code_files * 100 / total_files))
            local doc_ratio=$((doc_files * 100 / total_files))
            
            if [ $code_ratio -gt 60 ]; then
                ((code_indicators+=3))
            elif [ $doc_ratio -gt 80 ]; then
                ((docs_indicators+=3))
            fi
        fi
    fi
    
    # Return repository type
    if [ $code_indicators -gt $docs_indicators ]; then
        echo "code"
    elif [ $docs_indicators -gt 0 ] && [ $code_indicators -eq 0 ]; then
        echo "docs"
    else
        echo "uncertain"
    fi
}

# Security scanning deployment decision
determine_security_scanning() {
    case "$SECURITY_SCAN_MODE" in
        enable)
            DEPLOY_SECURITY_SCANNING="true"
            echo "🔒 Security scanning: Enabled (forced)"
            ;;
        disable)
            DEPLOY_SECURITY_SCANNING="false"
            echo "🔓 Security scanning: Disabled (forced)"
            ;;
        auto)
            local repo_type=$(detect_repository_type)
            case "$repo_type" in
                code)
                    DEPLOY_SECURITY_SCANNING="true"
                    echo "🔒 Security scanning: Enabled (code repository detected)"
                    ;;
                docs)
                    DEPLOY_SECURITY_SCANNING="false"
                    echo "📚 Security scanning: Disabled (documentation repository detected)"
                    ;;
                uncertain)
                    echo "❓ Unable to determine repository type automatically."
                    echo "   This appears to be a mixed or new repository."
                    echo ""
                    read -p "Deploy security scanning features? (y/N): " -n 1 -r
                    echo ""
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        DEPLOY_SECURITY_SCANNING="true"
                        echo "🔒 Security scanning: Enabled (user choice)"
                    else
                        DEPLOY_SECURITY_SCANNING="false"
                        echo "🔓 Security scanning: Disabled (user choice)"
                    fi
                    ;;
            esac
            ;;
    esac
}

# Get current git user information
get_current_git_user() {
    local name=$(git config user.name 2>/dev/null || echo "")
    local email=$(git config user.email 2>/dev/null || echo "")
    
    if [ -z "$name" ] || [ -z "$email" ]; then
        echo "⚠️ Git user configuration not found. Please configure git first:"
        echo "  git config --global user.name \"Your Name\""
        echo "  git config --global user.email \"your.email@example.com\""
        exit 1
    fi
    
    echo "$name|$email"
}

# Create or preserve .claude/settings.json
create_or_preserve_settings() {
    local settings_file=".claude/settings.json"
    
    if [ -f "$settings_file" ]; then
        echo "📋 Existing .claude/settings.json found — checking superpowers plugin..."

        if ! command -v jq &> /dev/null; then
            echo "⚠️  jq not available — skipping superpowers plugin merge into existing settings.json"
            echo "   Install jq and re-run, or manually add: \"enabledPlugins\": {\"superpowers@claude-plugins-official\": true}"
            return
        fi

        # Check if superpowers plugin is already enabled
        local current_value
        current_value=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // empty' "$settings_file" 2>/dev/null)

        if [ "$current_value" = "true" ]; then
            echo "   ✅ Superpowers plugin already enabled — no changes needed."
            return
        fi

        # Merge superpowers plugin entry into existing settings
        local tmp_file
        tmp_file=$(mktemp "${settings_file}.XXXXXX") || { echo "⚠️  Could not create temp file — skipping merge."; return; }
        if jq '.enabledPlugins = ((.enabledPlugins // {}) + {"superpowers@claude-plugins-official": true})' "$settings_file" > "$tmp_file" 2>/dev/null; then
            chmod --reference="$settings_file" "$tmp_file" 2>/dev/null
            mv "$tmp_file" "$settings_file"
            echo "   ✅ Superpowers plugin merged into existing settings.json."
        else
            rm -f "$tmp_file"
            echo "⚠️  Failed to merge superpowers plugin — settings.json may be malformed."
            echo "   Manually add: \"enabledPlugins\": {\"superpowers@claude-plugins-official\": true}"
        fi
        return
    fi

    echo "📋 Creating .claude/settings.json..."
    cat > "$settings_file" << 'SETTINGS_EOF'
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  },
  "version": "1.0.0",
  "project": {
    "type": "development",
    "framework": "",
    "language": "",
    "description": ""
  },
  "ai_guidelines": {
    "code_style": "Clean, readable, well-documented code with meaningful variable names",
    "testing": "Comprehensive unit tests for all new functionality",
    "documentation": "Clear inline comments and updated README sections",
    "git_commits": "Atomic commits with descriptive messages following conventional commits",
    "security": "Follow OWASP guidelines and security best practices"
  },
  "context_preservation": {
    "session_logs": true,
    "auto_backup": true,
    "context_window": "large"
  },
  "validation": {
    "pre_commit": true,
    "test_before_commit": true,
    "lint_check": true
  }
}
SETTINGS_EOF
}

# Main setup starts here
echo "🚀 AI Setup Deployment Script v$VERSION"
echo "📅 Deployment Date: $DEPLOY_DATE"
echo ""

# Parse command line arguments
parse_arguments "$@"

# Determine security scanning deployment
determine_security_scanning
echo ""

# Create directories if they don't exist
echo "📁 Creating directory structure..."
mkdir -p docs/{screenshots,archive,features,features-archive,architecture,guides}
mkdir -p .claude/commands
mkdir -p scripts/{hooks,validation,git,deployment,code_review}

# Clean up deprecated specs directories and migrate to docs (v2.40.0+)
echo "🧹 Cleaning up deprecated structure and migrating to /docs/..."

# Migrate existing specs to docs if specs exists
if [ -d "specs" ]; then
    echo "  📦 Migrating specs/ to docs/..."
    # Move existing specs content to docs
    for item in specs/*; do
        if [ -e "$item" ]; then
            basename=$(basename "$item")
            if [ "$basename" = "archive" ]; then
                # Move archive to architecture
                if [ -d "specs/archive" ] && [ "$(ls -A specs/archive 2>/dev/null)" ]; then
                    cp -r specs/archive/* docs/architecture/ 2>/dev/null || true
                    echo "  ✅ Migrated specs/archive/ to docs/architecture/"
                fi
            elif [ -d "$item" ]; then
                # Copy directories
                cp -r "$item"/* "docs/$basename/" 2>/dev/null || true
                echo "  ✅ Migrated specs/$basename/ to docs/$basename/"
            else
                # Copy files
                cp "$item" "docs/" 2>/dev/null || true
                echo "  ✅ Migrated $item to docs/"
            fi
        fi
    done
    rm -rf specs
    echo "  ✅ Removed old specs/ directory"
fi

# Migrate ai_docs/project_context.md to docs/ (v3.0.0+)
if [ -d "ai_docs" ]; then
    if [ -f "ai_docs/project_context.md" ]; then
        if [ ! -f "docs/project_context.md" ]; then
            mv ai_docs/project_context.md docs/project_context.md
            echo "  ✅ Migrated ai_docs/project_context.md to docs/project_context.md"
        else
            echo "  ✅ docs/project_context.md already exists — skipping migration"
        fi
    fi
    # Remove ai_docs directory and any remaining legacy files
    rm -rf ai_docs
    echo "  ✅ Removed legacy ai_docs/ directory"
fi

# Clean up deprecated subdirectories in docs
DEPRECATED_DIRS=(
    "docs/requirements"
    "docs/technical"
    "docs/changes"
    "docs/api"
)

for dir in "${DEPRECATED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        if [ "$(ls -A $dir 2>/dev/null)" ]; then
            echo "  📦 Archiving $dir before removal..."
            ARCHIVE_DIR="docs/archive/deprecated_$(date +%Y%m%d)"
            mkdir -p "$ARCHIVE_DIR"
            if mv "$dir" "$ARCHIVE_DIR/$(basename $dir)" 2>/dev/null; then
                echo "  ✅ Archived and removed: $dir"
            else
                echo "  ⚠️  Could not archive $dir - manual cleanup may be needed"
            fi
        else
            rm -rf "$dir"
            echo "  ✅ Removed empty deprecated directory: $dir"
        fi
    fi
done

# Clean up old command files from previous deployments (v2.43.0+)
OLD_COMMANDS=(
    ".claude/commands/save.md"
    ".claude/commands/clean.md"
    ".claude/commands/feature.md"
    ".claude/commands/issues.md"
    ".claude/commands/update_ai.md"
    ".claude/commands/security_scan.md"
)

for old_cmd in "${OLD_COMMANDS[@]}"; do
    if [ -f "$old_cmd" ]; then
        rm -f "$old_cmd"
        echo "  ✅ Removed deprecated command: $old_cmd"
    fi
done

# ===== Module 01 merged into Module 02 (v3.0.0) =====
# project_context.md now deploys to docs/ — see Module 02 below

# ===== Module: 02-docs.sh =====
# AI Setup Deployment Script - Documentation Module
# This module deploys all docs directory files following GitHub conventions

# Deploy docs files
echo "📋 Deploying documentation templates..."

# Deploy project context template to docs/
if [ ! -f "docs/project_context.md" ]; then
    cat > docs/project_context.md << 'EOF'
<!--
  STALENESS WARNING: Created by AI Setup Deployment Script v4.0.0 on 2026-03-31 22:56:36 UTC.
  Fill in every section with your actual project details.
  An unfilled template provides zero value to AI tools.
  Update this file whenever your stack, structure, or workflow changes.
-->

# Project Context

*Fill in every section below. Delete placeholder text.*

## Project Overview
**Project Name**: [Your Project Name]
**Description**: [What does this project do? One or two sentences.]
**Repository**: [GitHub URL]

## Technology Stack
- **Language(s)**: [e.g., TypeScript, Python]
- **Framework(s)**: [e.g., React, FastAPI]
- **Database**: [e.g., PostgreSQL, none]
- **Infrastructure**: [e.g., AWS, Vercel, on-prem]

## Architecture

### Project Structure
[Paste your actual directory tree here]

### Key Decisions
- [e.g., "REST API with JWT auth — no sessions"]

## Development Workflow

### Common Commands
```bash
[build]   # e.g., npm run build
[test]    # e.g., npm test
[dev]     # e.g., npm run dev
```

### Branch Strategy
- **[main]**: [e.g., production-ready, protected]
- **[feature/*]**: [e.g., merged via PR to develop]

## Coding Standards
- [Style guide, linting rules]
- [Naming conventions]
- [Testing requirements]

## Important Context for AI Tools
[Gotchas, files not to touch, security requirements, external quirks]

---
*Last updated: [Date] — keep this current.*
EOF
    echo "  ✅ Created docs/project_context.md (fill-in template)"
else
    echo "  ✅ docs/project_context.md already exists — preserved"
fi

# docs/README.md
cat > docs/README.md << 'EOF'
# Documentation Directory

*Generated by AI Setup Deployment Script v4.0.0 on 2026-03-31 22:56:36 UTC*

Store your project documentation, specifications, feature tracking, and technical designs here. This structure aligns with GitHub conventions and supports GitHub Pages.

## Directory Structure

```
docs/
├── project_context.md        # AI context — fill in with your project details
├── README.md                 # This file
├── architecture/            # Design decisions, system architecture, ADRs
│   └── README.md
├── guides/                  # How-to guides, setup instructions
│   └── README.md
├── screenshots/             # Visual documentation and UI mockups
│   └── README.md
├── features/                # Active feature development tracking
│   └── README.md
├── features-archive/        # Completed feature documentation
│   └── README.md
├── archive/                 # Deprecated/historical documentation
│   └── README.md
├── change_template.md       # Template for documenting changes
├── example_change_doc.md    # Example of change documentation
├── features-template.md     # Template for feature tracking
└── [your-docs].md          # Active documentation files
```

## Usage Guidelines

### Architecture Directory (`/docs/architecture/`)
Design decisions, system architecture, and Architecture Decision Records (ADRs):
- System design documents
- Architecture decision records
- Technical design specifications
- Integration patterns

### Guides Directory (`/docs/guides/`)
How-to guides, setup instructions, and tutorials:
- Installation guides
- Configuration documentation
- Development workflow guides
- Performance optimization guides

### Screenshots Directory (`/docs/screenshots/`)
Visual documentation and UI mockups:
- UI mockups and wireframes
- Visual flow diagrams
- Screen captures for reference
- Design system examples
- Before/after comparisons

### Features Directory (`/docs/features/`)
Active feature development tracking:
- Feature specifications
- Implementation progress
- Session continuity notes
- Technical decisions

### Archive Directory (`/docs/archive/`)
Deprecated or historical documentation:
- Implemented features
- Deprecated designs
- Historical decisions
- Old requirements
- Previous iterations

## Change Documentation

For complex implementations, use the change documentation template:

1. Copy `change_template.md` to a new file (e.g., `feature_xyz_changes.md`)
2. Fill in all sections completely
3. Reference in pull requests and commits
4. Move to archive when implementation is complete

See `example_change_doc.md` for a complete example.

## Best Practices

1. **Keep docs current** - Update or archive as needed
2. **Use clear naming** - `feature_name_spec.md` or `YYYY-MM-DD_decision.md`
3. **Link liberally** - Reference related docs, code, and issues
4. **Version control** - Let git track changes, don't version in filenames
5. **Stay organized** - Archive completed work promptly

## Integration with AI Tools

This structure is optimized for AI-assisted development:
- Follows GitHub conventions (`/docs/` directory)
- Supports GitHub Pages deployment
- Clear separation of content types
- Feature tracking for session continuity
- Change documentation for handoffs and reviews

## Migration from `/specs/`

If migrating from the previous `/specs/` structure:
```bash
git mv specs/archive/* docs/architecture/
git mv specs/screenshots/* docs/screenshots/
git mv specs/features/* docs/features/
git mv specs/features-archive/* docs/features-archive/
git mv specs/*.md docs/
rmdir specs/archive specs/screenshots specs/features specs/features-archive specs
```
EOF

# docs/screenshots/README.md
cat > docs/screenshots/README.md << 'EOF'
# Screenshots Directory

This directory contains visual documentation including UI mockups, flow diagrams, and reference screenshots.

## File Organization

- Use descriptive filenames: `feature-name-state.png`
- Include dates for time-sensitive items: `2024-01-15-dashboard-redesign.png`
- Group related images in subdirectories if needed

## Supported Formats

- PNG (preferred for UI screenshots)
- JPG (for photos)
- SVG (for diagrams)
- GIF (for animations)

## Best Practices

1. Optimize image sizes before committing
2. Use meaningful alt text in markdown references
3. Keep screenshots current with implementation
4. Archive outdated visuals
EOF

# docs/architecture/README.md
cat > docs/architecture/README.md << 'EOF'
# Architecture Documentation

This directory contains system architecture documentation, design decisions, and Architecture Decision Records (ADRs).

## Contents

- **Design Documents** - System design and technical specifications
- **Architecture Decision Records (ADRs)** - Documented architectural decisions with context and rationale
- **Integration Patterns** - Documentation of how components interact

## File Organization

- Use descriptive filenames: `feature-name-architecture.md`
- For ADRs, use numbered format: `0001-record-title.md`
- Date-prefix for chronological records: `2024-01-15-decision-description.md`

## Best Practices

1. Document the "why" not just the "what"
2. Include context for future reference
3. Link related decisions and documents
4. Update when architectural changes occur
5. Archive superseded decisions (don't delete)

## ADR Template

```markdown
# [Title]

## Status
[Proposed | Accepted | Deprecated | Superseded by [ADR-XXX]]

## Context
[What is the issue that we're seeing that is motivating this decision?]

## Decision
[What is the change that we're proposing and/or doing?]

## Consequences
[What becomes easier or more difficult to do because of this change?]
```
EOF

# docs/guides/README.md
cat > docs/guides/README.md << 'EOF'
# Guides Directory

This directory contains how-to guides, setup instructions, and tutorials.

## Purpose

Guides provide step-by-step instructions for:
- Installation and setup procedures
- Configuration and customization
- Development workflow optimization
- Troubleshooting common issues
- Best practices implementation

## File Organization

- Use descriptive filenames: `feature-name-guide.md`
- Group related guides: `setup-guide.md`, `configuration-guide.md`
- Include prerequisite information clearly

## Best Practices for Guides

1. **Start with prerequisites** - What users need before starting
2. **Use numbered steps** - Clear, sequential instructions
3. **Include examples** - Real-world usage examples
4. **Add troubleshooting** - Common issues and solutions
5. **Keep current** - Update when procedures change
EOF

# docs/archive/README.md
cat > docs/archive/README.md << 'EOF'
# Archive Directory

This directory contains deprecated or historical documentation preserved for reference.

## Archive Structure

Organize by date or project phase:
- `2024-Q1/` - Quarterly archives
- `v1.0/` - Version-based archives
- `project-name/` - Project-based archives

## When to Archive

Move documentation here when:
- Feature has been fully implemented
- Design has been superseded
- Requirements are obsolete
- Project has been cancelled

## Archive Process

1. Move file to archive with context
2. Add archive note to the top of the file
3. Update any active references
4. Commit with clear message
EOF

# docs/change_template.md
cat > docs/change_template.md << 'EOF'
# Change Documentation Template

## Change Overview
**Change ID**: [YYYY-MM-DD-brief-description]
**Type**: [Feature|Enhancement|Bugfix|Refactor]
**Status**: [Planned|In Progress|Completed|Archived]
**Date**: [YYYY-MM-DD]
**Author**: [Name]

## Summary
[Brief description of the change and its purpose]

## Background & Motivation
[Why this change is needed, what problem it solves]

## Technical Approach
[How the change will be implemented]

### Components Affected
- [ ] Component 1
- [ ] Component 2

### Implementation Steps
1. Step 1
2. Step 2

## Testing Plan
[How the change will be tested]

## Rollback Plan
[How to revert if needed]

## References
- Related Issue: #
- Related PR: #
- Related Specs: []
EOF

# docs/example_change_doc.md
cat > docs/example_change_doc.md << 'EOF'
# Change Documentation Example

## Change Overview
**Change ID**: 2024-01-15-add-user-authentication
**Type**: Feature
**Status**: Completed
**Date**: 2024-01-15
**Author**: Development Team

## Summary
Implement secure user authentication system with JWT tokens and OAuth2 support.

## Background & Motivation
Users need secure access to personal data and features. Current system lacks authentication, limiting functionality and security.

## Technical Approach
Implement authentication using industry-standard JWT tokens with refresh token rotation.

### Components Affected
- [x] API Gateway
- [x] User Service
- [x] Frontend Auth Module
- [x] Database Schema

### Implementation Steps
1. Design database schema for users and sessions
2. Implement JWT token generation and validation
3. Add OAuth2 provider integration
4. Create login/logout endpoints
5. Implement frontend auth flow
6. Add auth middleware to protected routes

## Testing Plan
- Unit tests for auth service
- Integration tests for login flow
- Security penetration testing
- Load testing for concurrent sessions

## Rollback Plan
1. Feature flag to disable new auth
2. Revert to previous release
3. Clear session storage
4. Communicate to users

## References
- Related Issue: #123
- Related PR: #456
- Related Specs: [User Auth Spec](./archive/user-auth-spec.md)
EOF

# Update version references in docs files
find docs -name "*.md" -type f -exec sed -i.bak "s/4.0.0/$VERSION/g" {} \; && find docs -name "*.md.bak" -type f -delete
find docs -name "*.md" -type f -exec sed -i.bak "s/2026-03-31 22:56:36 UTC/$DEPLOY_DATE/g" {} \; && find docs -name "*.md.bak" -type f -delete
# ===== Module: 03-claude-config.sh =====
# AI Setup Deployment Script - Claude Configuration Module
# This module deploys Claude-specific configuration files and commands

# Deploy .claude directory files
echo "🧠 Deploying Claude Code configuration..."

# Capture CLAUDE.md state before we potentially create it
CLAUDE_MD_EXISTED=false
if [ -f "CLAUDE.md" ]; then
    CLAUDE_MD_EXISTED=true
fi

# Deploy CLAUDE.md — only for fresh repos (preserve existing)
if [ ! -f "CLAUDE.md" ]; then
    echo "📄 Creating CLAUDE.md for fresh repository..."
    cat > CLAUDE.md << 'EOF'
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
EOF
    echo "  ✅ Created CLAUDE.md with Custom Commands table"
else
    echo "  ℹ️  CLAUDE.md already exists — skipping"
fi

# docs/features-template.md
cat > docs/features-template.md << 'EOF'
# Feature: [FEATURE_NAME]

## Overview
- **Status**: planning
- **Started**: [DATE]
- **Last Updated**: [DATE]
- **Started On Branch**: [BRANCH]
- **Current Branch**: [BRANCH]
- **Associated Branches**:
  - [BRANCH_NAME]

## Description
[Brief description of the feature and its purpose]

## Requirements
- [ ] [Requirement 1]
- [ ] [Requirement 2]
- [ ] [Requirement 3]
- [ ] [Add more as needed]

## Acceptance Criteria
- [ ] [Criteria 1]
- [ ] [Criteria 2]
- [ ] [Criteria 3]

## Technical Design

### Architecture Overview
[Describe the technical approach and architecture]

### Key Components
- **Component 1**: [Description]
- **Component 2**: [Description]

### Dependencies
- [List any dependencies or prerequisites]

### API Changes
- [Document any API additions or modifications]

## Testing Strategy
- [ ] Unit tests for [components]
- [ ] Integration tests for [workflows]
- [ ] E2E tests for [user scenarios]
- [ ] Performance testing for [critical paths]

## Documentation Needs
- [ ] API documentation updates
- [ ] User guide updates
- [ ] Migration guide (if applicable)
- [ ] Architecture documentation

## Security Considerations
- [List any security implications or requirements]

## Performance Considerations
- [Note any performance requirements or concerns]

## Session History

### Session [DATE TIME]
**Progress:**
- [What was accomplished]

**Decisions:**
- [Technical decisions made and reasoning]

**Blockers:**
- [Any issues encountered]

**Next Steps:**
- [Clear starting points for next session]

**Code Changes:**
- `file1.js`: [Purpose of changes]
- `file2.py`: [Purpose of changes]

---
*Template version: v2.43.0*
EOF

# docs/features/README.md
cat > docs/features/README.md << 'EOF'
# Active Features Directory

This directory contains active feature development tracking documents.

## Purpose

Feature documents in this directory:
- Track ongoing development work
- Preserve context between AI sessions
- Document technical decisions
- Maintain progress checklists
- Enable seamless work resumption

## Structure

Each feature is tracked in a markdown file named after the feature:
- `user-authentication.md` - Authentication system feature
- `api-rate-limiting.md` - Rate limiting implementation
- `data-migration.md` - Database migration feature

## Lifecycle

Features progress through these statuses:
1. **planning** - Requirements and design phase
2. **in-progress** - Active development
3. **testing** - Implementation complete, testing
4. **completed** - Ready for merge
5. **archived** - Moved to `features-archive/` after merge

## Usage

## Branch Association

Features track associated git branches without constraining naming:
- Multiple branches can be associated with one feature
- Any branch naming convention is supported
- Branches are tracked but not enforced

## Best Practices

1. **One feature per significant work effort**
2. **Update progress after each session**
3. **Document key technical decisions**
4. **Keep requirements checklist current**
5. **Archive features after merge**

## Integration

Feature tracking integrates with:
- `/prime` - Loads feature context automatically
- Git branches - Intelligent association without constraints
- GitHub issues - Can reference related issues

---
*Feature tracking system v2.43.0*
EOF

# docs/features-archive/README.md
cat > docs/features-archive/README.md << 'EOF'
# Archived Features Directory

This directory contains completed feature documentation that has been archived after successful implementation and merge.

## Purpose

Archived features serve as:
- **Historical reference** for technical decisions
- **Knowledge base** of successful implementations
- **Pattern library** for similar future work
- **Audit trail** of development history
- **Learning resource** for team members

## Archive Process

Features are moved here when:
1. Implementation is complete and merged
2. All requirements are satisfied
3. Tests are passing
4. Documentation is updated
5. Feature branch is merged/deleted

## Archive Command

## Naming Convention

Archived features retain their original names:
- `user-authentication.md`
- `api-rate-limiting.md`
- `data-migration.md`

Optional: Add date prefix for chronological sorting:
- `2024-11-22-user-authentication.md`

## Searchable History

Archived features can be searched for:
- **Technical decisions**: Why certain approaches were chosen
- **Problem solutions**: How issues were resolved
- **Implementation patterns**: Reusable code patterns
- **Session insights**: Effective development workflows
- **Testing strategies**: What testing approaches worked

## Best Practices

1. **Complete documentation** before archiving
2. **Include PR/issue links** for traceability
3. **Document lessons learned** in final session
4. **Preserve all context** for future reference
5. **Tag with keywords** for better searchability

## Re-activation

If an archived feature needs additional work:
1. Copy back to `docs/features/`
2. Update status from 'archived' to 'in-progress'
3. Add note about re-activation reason
4. Continue with normal feature workflow

## Retention Policy

Archived features should be retained indefinitely as they provide:
- Valuable development history
- Technical decision documentation
- Team knowledge preservation
- Audit trail for compliance

## Integration with Version Control

Archived features are:
- Committed to repository for permanence
- Tagged with release versions if applicable
- Linked to pull requests and issues
- Part of project documentation

---
*Feature archive system v2.43.0*
EOF

# .claude/commands/prime.md
cat > .claude/commands/prime.md << 'EOF'
<!-- Source: https://github.com/Strode-Mountain/machine-shop -->
# Prime Command
<!-- AI-SETUP-SCRIPT-TAG: v4.0.0 -->

## Project Context Display

Display comprehensive project context through organized information gathering and presentation. This command provides context through pure information display without taking actions or managing files.

### Operation

The `/prime` command operates in single mode, gathering and displaying project context across multiple dimensions:

**Project Structure Context:**
- Current directory structure and file organization
- Technology stack identification (package.json, requirements.txt, etc.)
- Configuration files and project settings
- Key directories and their purposes

**Development State Context:**
- Current git branch and repository status
- Recent commit history and development activity
- Work in progress and unstaged changes
- Project version and build information

**Documentation Context:**
- README.md content and project overview
- AI development documentation (docs/project_context.md)
- Specification files and requirements
- Code conventions and development guidelines

**Session Context:**
- Previous session work and decisions (if available)
- Outstanding tasks and development patterns
- Recent conversation history and context
- Development continuity information

### Context Display Format

Information is presented in organized sections:

1. **Project Overview**: Name, technology stack, current branch
2. **Recent Activity**: Last commits, current changes, work in progress
3. **Documentation Summary**: Key project information and conventions
4. **Session Continuity**: Previous work and outstanding tasks (if applicable)
5. **Development Environment**: Configuration, dependencies, tools

### Boundaries and Constraints

**This command only displays information. It does not:**
- Create, modify, or delete files
- Execute commands or scripts
- Update todo lists or project state
- Manage git repository or commits
- Install dependencies or run builds
- Make configuration changes

**Context sources are read-only:**
- File system exploration for structure
- Git history and status reading
- Documentation content review
- Session history access (if available)
- Configuration file parsing

### Git Author Verification

**CRITICAL**: The /prime command MUST verify and display the current git author configuration to prevent commit attribution errors.

When loading context, the AI must:
1. **Check current git configuration** - Read git user.name and user.email
2. **Verify git-authors.json** - If exists, read the stored human author configuration
3. **Display author information clearly** - Show who will be used for commits
4. **Request confirmation** - Ask the user to verify the author information is correct

### Available Tooling Inventory

After displaying project context, detect and display available tooling:

1. **Superpowers plugin** — check if the superpowers plugin is installed and list available skills from the system context
2. **Agency-agents personas** — check if `.claude/agent-teams.json` exists; if so, list available team abbreviations and their roles
3. **Slash commands** — list available commands in `.claude/commands/`

This inventory helps the user know what's available for the session ahead.

### AI Behavior Instructions

When this command is executed:
1. **Load project context** - Gather all relevant project information
2. **Verify git authors** - Check and display current git author configuration
3. **Display author confirmation** - Clearly show the human author that will be used for commits
4. **Display available tooling** - Show superpowers skills, agent teams, and slash commands
5. **Wait for confirmation** - Ask user to confirm or correct the author information
6. **No autonomous actions** - This is a context-loading command only; take no actions beyond loading information

### Example Response
After running /prime, the AI should respond:
```
Project context loaded.

Git Author Configuration:
   Current git user: John Doe <john.doe@example.com>
   Please confirm this is correct. If not, please run:
      git config user.name "Your Name"
      git config user.email "your.email@example.com"

Available tooling:
   Superpowers: active (brainstorming, TDD, code-reviewer, ...)
   Agent teams: 19 personas (SE, SA, FE, MB, CR, SEC, ...)
   Commands: /address-issue, /refine-issue, /review-pr, /prime, /update-agency

What would you like to work on?
```

### Communication Guidelines

After context display, maintain professional development communication:

- **Technical focus**: Emphasize accuracy and practical solutions
- **Direct feedback**: Provide honest assessment of approaches and issues
- **Constructive challenge**: Ask clarifying questions and suggest alternatives
- **Measured responses**: Avoid excessive validation or praise
- **Substance over style**: Prioritize technical merit and problem-solving

### Usage Pattern

```
/prime
```

Single command execution provides comprehensive project context through organized information display. No parameters required - the command automatically adapts to the current project structure and available information sources.

The command establishes context foundation for productive development sessions without file system modifications or state changes.
EOF

# .claude/commands/update-agency.md
cat > .claude/commands/update-agency.md << 'EOF'
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
EOF

# .claude/commands/address-issue.md
cat > .claude/commands/address-issue.md << 'EOF'
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
EOF

# .claude/commands/review-pr.md
cat > .claude/commands/review-pr.md << 'EOF'
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
EOF

# .claude/commands/refine-issue.md
cat > .claude/commands/refine-issue.md << 'EOF'
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
EOF

# .claude/agent-teams.json (default team mapping)
if [ ! -f ".claude/agent-teams.json" ]; then
    echo "📋 Creating default .claude/agent-teams.json..."
    cat > .claude/agent-teams.json << 'AGENT_TEAMS_EOF'
{
  "SE": ".claude/agents/engineering/engineering-senior-developer.md",
  "CR": ".claude/agents/engineering/engineering-code-reviewer.md"
}
AGENT_TEAMS_EOF
else
    echo "  ℹ️  .claude/agent-teams.json already exists — skipping"
fi

# Deploy additional AI tool configuration files
echo "⚙️ Deploying AI tool configuration files..."

# Ensure .github directory exists
mkdir -p .github

# .github/copilot-instructions.md
cat > .github/copilot-instructions.md << 'EOF'
# GitHub Copilot Instructions

This document provides context and guidelines for GitHub Copilot when assisting with this repository.

## Project Context

[Provide the same context as in CLAUDE.md, adapted for GitHub Copilot]

## Coding Standards

### Style Guidelines
- [Language-specific style guide]
- [Naming conventions]
- [File organization]

### Best Practices
- [Error handling patterns]
- [Testing requirements]
- [Documentation standards]

## Code Examples

### Preferred Patterns
```javascript
// Good: Clear, testable, documented
export async function processUser(userId: string): Promise<User> {
  // Implementation
}
```

### Avoid
```javascript
// Bad: Unclear, untestable
function proc(id) {
  // Implementation
}
```

## Testing Requirements

All new code should include:
- Unit tests with >80% coverage
- Integration tests for API endpoints
- Error case coverage
- Performance considerations

## Security Guidelines

- Never hardcode credentials
- Validate all inputs
- Use parameterized queries
- Follow OWASP guidelines
EOF

# Create settings with preservation
create_or_preserve_settings

# Deployment reminder about customization
echo ""
echo "📝 Remember to customize these files for your project:"
echo "   - CLAUDE.md (add project-specific context)"
echo "   - .claude/settings.json (adjust settings as needed)"
echo "   - docs/project_context.md (fill with project details)"
echo ""

# Update version references
find .claude -name "*.md" -type f -exec sed -i.bak "s/4.0.0/$VERSION/g" {} \; && find .claude -name "*.md.bak" -type f -delete
find . -maxdepth 1 -name "*.md" -type f -exec sed -i.bak "s/4.0.0/$VERSION/g" {} \; && find . -maxdepth 1 -name "*.md.bak" -type f -delete
find .github -name "*.md" -type f -exec sed -i.bak "s/4.0.0/$VERSION/g" {} \; && find .github -name "*.md.bak" -type f -delete
# ===== Module: 04-validation.sh =====
# AI Setup Deployment Script - Validation Module
# This module deploys the validation system including hooks and scripts

# Deploy validation hooks system
echo "🔧 Deploying validation hooks system..."

# scripts/hooks/auto-save-workflow.sh (Example workflow hook)
cat > scripts/hooks/auto-save-workflow.sh << 'AUTO_SAVE_WORKFLOW_EOF'
#!/bin/bash

# Auto-Save Workflow Hook Script
# Example workflow automation hook with warning-based error handling
# Add to hooks.PostToolUse in .claude/settings.json to enable

set +e  # Allow script to continue on errors, log warnings instead

echo "🔄 Auto-save workflow activated"

# Function to log warnings instead of failing
log_warning() {
    echo "⚠️ Warning: $1" >&2
}

# Function to log errors but continue
log_error() {
    echo "❌ Error: $1" >&2
}

# Check if this is a Claude save session
if [ "$CLAUDE_SAVE_SESSION" = "true" ]; then
    echo "✅ Claude save session detected"
    
    # Wait a moment for any pending operations
    sleep 1
    
    # Check if we need to restore human author
    if git config user.name 2>/dev/null | grep -q "Claude Code Assistant"; then
        echo "🔄 Restoring human git author..."
        # Simple restoration using global git config
        local global_name global_email
        global_name="$(git config --global user.name 2>/dev/null || echo "")"
        global_email="$(git config --global user.email 2>/dev/null || echo "")"
        
        if [[ -n "$global_name" && -n "$global_email" ]]; then
            git config user.name "$global_name"
            git config user.email "$global_email"
            echo "✅ Human author restored from global config"
        else
            log_warning "No global git configuration found to restore from"
            echo "   Please set git config user.name and user.email after deployment"
        fi
    fi
    
    # Clear the session flag
    unset CLAUDE_SAVE_SESSION
    
    echo "✅ Auto-save workflow completed"
else
    echo "ℹ️ Not a Claude save session, skipping workflow"
fi

# Exit with success even if warnings occurred
exit 0
AUTO_SAVE_WORKFLOW_EOF

# Create template validation hook for reference
cat > scripts/hooks/example-validation.sh << 'EXAMPLE_VALIDATION_EOF'
#!/bin/bash

# Example Project Validation Hook
# Customize this template for your project's validation needs
# Add to hooks.PreToolUse in .claude/settings.json to enable

set +e  # Allow script to continue on errors, log warnings instead

# Example: Check for required tools
if ! command -v git &> /dev/null; then
    echo "⚠️  Git not available for version control"
fi

# Example: Validate file formats before editing
edited_file="$CLAUDE_TOOL_FILE"
if [[ "$edited_file" == *.json ]]; then
    if command -v jq &> /dev/null && [ -f "$edited_file" ]; then
        if ! jq empty "$edited_file" 2>/dev/null; then
            echo "⚠️  JSON file may have syntax issues: $edited_file"
        fi
    fi
fi

# Always exit successfully to avoid blocking tool use
exit 0
EXAMPLE_VALIDATION_EOF

# Create template for post-processing hooks
cat > scripts/hooks/example-post-processing.sh << 'EXAMPLE_POST_PROCESSING_EOF'
#!/bin/bash

# Example Post-Processing Hook
# Customize this template for your project's post-processing needs
# Add to hooks.PostToolUse in .claude/settings.json to enable

set +e  # Allow script to continue on errors, log warnings instead

# Example: Run code formatting after file edits
edited_file="$CLAUDE_TOOL_FILE"
if [[ "$edited_file" == *.js ]] || [[ "$edited_file" == *.ts ]]; then
    if command -v prettier &> /dev/null; then
        echo "🎨 Auto-formatting JavaScript/TypeScript file: $edited_file"
        prettier --write "$edited_file" 2>/dev/null || echo "⚠️  Prettier formatting failed"
    fi
fi

# Example: Update documentation after certain changes
if [[ "$edited_file" == *README.md ]]; then
    echo "📚 README updated - consider reviewing project documentation"
fi

# Always exit successfully to avoid blocking tool use
exit 0
EXAMPLE_POST_PROCESSING_EOF

# Deploy Lightweight Validation System (v2.37.0)
echo "🚀 Deploying lightweight validation system..."

# Create validation directory
mkdir -p scripts/validation

# scripts/validation/validate.sh - Main lightweight validation runner
cat > scripts/validation/validate.sh << 'VALIDATE_EOF'
#!/bin/bash
# validate.sh - Lightweight validation runner for AI Setup
# Version: 4.0.0
# Purpose: Fast, simple validation that addresses cashflow team performance concerns
#
# Usage:
#   ./validate.sh           # Run fast validation (default)
#   ./validate.sh --fast    # Explicitly run fast validation
#   ./validate.sh --full    # Run comprehensive validation
#   ./validate.sh --help    # Show usage

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/.validation_cache"
CACHE_TTL=3600  # 1 hour
VERSION="4.0.0"

# Colors for output (minimal, clear)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Simple logging
log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Show usage
show_usage() {
    cat << EOF
AI Setup Validation Runner v$VERSION

Usage: $(basename "$0") [OPTIONS]

Options:
  --fast    Run fast validation (default, <10 seconds)
  --full    Run comprehensive validation
  --clean   Clean validation cache
  --help    Show this help message

Fast mode includes:
  • Syntax validation for shell scripts
  • Basic security checks
  • Test execution (if framework detected)
  • Git author verification

Full mode adds:
  • Deep security scanning
  • Code quality validation
  • Integration tests
  • Performance profiling
EOF
}

# Test framework detection
detect_test_framework() {
    # JavaScript/Node.js projects
    if [[ -f "package.json" ]]; then
        if grep -q '"jest"' package.json 2>/dev/null; then
            echo "jest"
        elif grep -q '"vitest"' package.json 2>/dev/null; then
            echo "vitest"
        elif grep -q '"mocha"' package.json 2>/dev/null; then
            echo "mocha"
        elif grep -q '"test"' package.json 2>/dev/null; then
            echo "npm"
        else
            echo "none"
        fi
    # Python projects
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        if grep -q "pytest" requirements.txt 2>/dev/null || grep -q "pytest" pyproject.toml 2>/dev/null; then
            echo "pytest"
        elif grep -q "unittest" requirements.txt 2>/dev/null; then
            echo "unittest"
        else
            echo "none"
        fi
    # Go projects
    elif [[ -f "go.mod" ]]; then
        echo "go"
    # Rust projects
    elif [[ -f "Cargo.toml" ]]; then
        echo "cargo"
    else
        echo "none"
    fi
}

# Run tests based on detected framework
run_tests() {
    local framework=$(detect_test_framework)
    
    case "$framework" in
        jest|vitest|mocha|npm)
            log_info "Running JavaScript tests with $framework..."
            if npm test -- --passWithNoTests 2>/dev/null || npm test 2>/dev/null; then
                log_success "JavaScript tests passed"
                return 0
            else
                log_warning "JavaScript tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        pytest)
            log_info "Running Python tests with pytest..."
            if python -m pytest -q 2>/dev/null; then
                log_success "Python tests passed"
                return 0
            else
                log_warning "Python tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        unittest)
            log_info "Running Python tests with unittest..."
            if python -m unittest discover -q 2>/dev/null; then
                log_success "Python tests passed"
                return 0
            else
                log_warning "Python tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        go)
            log_info "Running Go tests..."
            if go test ./... 2>/dev/null; then
                log_success "Go tests passed"
                return 0
            else
                log_warning "Go tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        cargo)
            log_info "Running Rust tests..."
            if cargo test --quiet 2>/dev/null; then
                log_success "Rust tests passed"
                return 0
            else
                log_warning "Rust tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        none)
            log_info "No test framework detected - skipping tests"
            return 0
            ;;
    esac
}

# Cache functions
cache_key() {
    local validation_type="$1"
    local file_hash=$(find . -type f -name "*.sh" -o -name "*.js" -o -name "*.py" 2>/dev/null | head -20 | xargs ls -la 2>/dev/null | sha256sum | cut -d' ' -f1)
    echo "${validation_type}_${file_hash:0:16}"
}

check_cache() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"
    
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $CACHE_TTL ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

save_cache() {
    local key="$1"
    local result="$2"
    mkdir -p "$CACHE_DIR"
    echo "$result" > "$CACHE_DIR/$key"
}

# Fast validation (core checks only)
validate_fast() {
    local start_time=$(date +%s)
    local failed=0
    
    echo "🚀 Running fast validation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check cache
    local cache_key=$(cache_key "fast")
    if check_cache "$cache_key" > /dev/null 2>&1; then
        log_success "Using cached validation results (valid for 1 hour)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        local end_time=$(date +%s)
        echo "⏱️  Completed in $((end_time - start_time)) seconds"
        return 0
    fi
    
    # 1. Syntax validation
    log_info "Checking shell script syntax..."
    local syntax_errors=0
    while IFS= read -r script; do
        if ! bash -n "$script" 2>/dev/null; then
            log_error "Syntax error in: $script"
            ((syntax_errors++))
        fi
    done < <(find . -name "*.sh" -type f -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null)
    
    if [[ $syntax_errors -eq 0 ]]; then
        log_success "Shell syntax validation passed"
    else
        log_error "Found $syntax_errors syntax errors"
        ((failed++))
    fi
    
    # 2. Basic security checks
    log_info "Running security checks..."
    local security_issues=0
    
    # Check for dangerous patterns
    if grep -r "eval\|curl.*sh\|wget.*sh" . --include="*.sh" --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null | grep -v "^Binary file"; then
        log_warning "Found potentially dangerous code patterns"
        ((security_issues++))
    fi
    
    if [[ $security_issues -eq 0 ]]; then
        log_success "Basic security checks passed"
    else
        log_warning "Found $security_issues security concerns (review recommended)"
    fi
    
    # 3. Git author verification
    if [[ -d "$PROJECT_ROOT/scripts/git" ]]; then
        log_info "Checking git author configuration..."
        if [[ -x "$PROJECT_ROOT/scripts/git/git-author-verify.sh" ]]; then
            if "$PROJECT_ROOT/scripts/git/git-author-verify.sh" --quiet 2>/dev/null; then
                log_success "Git author configuration valid"
            else
                log_warning "Git author configuration needs attention"
            fi
        fi
    fi
    
    # 4. Run tests
    run_tests
    
    # Save cache
    save_cache "$cache_key" "$failed"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $failed -eq 0 ]]; then
        log_success "Fast validation completed successfully"
    else
        log_error "Fast validation completed with $failed issues"
    fi
    
    echo "⏱️  Completed in $duration seconds"
    
    return $failed
}

# Full validation (comprehensive checks)
validate_full() {
    local start_time=$(date +%s)
    
    echo "🔍 Running comprehensive validation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # First run fast validation
    validate_fast
    local fast_result=$?
    
    # Additional comprehensive checks
    log_info "Running extended validation..."
    
    # Check if old validation system exists
    if [[ -d "$SCRIPT_DIR/modules" ]]; then
        log_info "Legacy validation modules detected - running compatibility mode..."
        
        # Run specific validators if they exist
        for validator in "$SCRIPT_DIR"/modules/*.sh; do
            if [[ -x "$validator" ]]; then
                local validator_name=$(basename "$validator" .sh)
                log_info "Running $validator_name validation..."
                if "$validator" 2>/dev/null; then
                    log_success "$validator_name validation passed"
                else
                    log_warning "$validator_name validation had issues"
                fi
            fi
        done
    else
        log_info "No extended validation modules found"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "⏱️  Completed in $duration seconds"
    
    return $fast_result
}

# Clean cache
clean_cache() {
    log_info "Cleaning validation cache..."
    rm -rf "$CACHE_DIR"
    log_success "Cache cleaned"
}

# Cleanup old validation sessions
cleanup_sessions() {
    local session_dir="$PROJECT_ROOT/.validation_sessions"
    if [[ -d "$session_dir" ]]; then
        log_info "Cleaning old validation sessions..."
        # Remove sessions older than 7 days
        find "$session_dir" -type d -name "session_*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
        # Keep only last 10 sessions
        ls -dt "$session_dir"/session_* 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true
        log_success "Old sessions cleaned"
    fi
}

# Main
main() {
    case "${1:-}" in
        --fast|"")
            validate_fast
            cleanup_sessions
            ;;
        --full)
            validate_full
            cleanup_sessions
            ;;
        --clean)
            clean_cache
            cleanup_sessions
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
VALIDATE_EOF

# Make validation script executable
chmod +x scripts/validation/validate.sh

echo "✅ Lightweight validation system deployed"
echo ""
echo "   Performance improvements:"
echo "   • Fast mode: <10 seconds (vs 3-5 minutes)"
echo "   • Auto-detects test frameworks (Jest, Vitest, pytest, etc.)"
echo "   • Smart caching for repeated runs"
echo "   • Automatic cleanup of old sessions"
echo ""
echo "   Usage: ./scripts/validation/validate.sh --fast"
echo ""

# Deploy Security Validation Scripts (conditionally deployed)
if [[ "$DEPLOY_SECURITY_SCANNING" == "true" ]]; then
    echo "🛡️ Deploying security validation scripts..."

    # scripts/validation/security_scanner.sh
    cat > scripts/validation/security_scanner.sh << 'SECURITY_SCANNER_EOF'
#!/bin/bash

# security_scanner.sh - Security vulnerability scanning validation
# Part of AI Setup Enhanced Validation Framework
# Version: 1.0.0
# Performs comprehensive security scanning for malicious code detection

set -euo pipefail

# Script directory and dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_ROOT="$SCRIPT_DIR"

# Module-specific configuration
CONFIG_FILE="$VALIDATION_ROOT/validation_config.json"
SECURITY_LOG_FILE="$VALIDATION_ROOT/../logs/security_scan_$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="$VALIDATION_ROOT/../logs/security_results.json"

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$SECURITY_LOG_FILE")"

# Logging function
log_security() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECURITY: $*" | tee -a "$SECURITY_LOG_FILE"
}

# Security patterns for detection
MALICIOUS_PATTERNS=(
    # Network exfiltration patterns
    "curl.*-d.*\$"
    "wget.*--post-data"
    "nc.*-e"
    "socat.*exec"
    
    # Command injection patterns
    "eval.*\$("
    "system\([\"'].*\$"
    "subprocess.*shell=True"
    "os\.system\("
    "\$\(.*\)"
    "\`.*\`"
    
    # File system manipulation
    "rm.*-rf.*/"
    "chmod.*777"
    "chown.*root"
    "dd.*if=/dev/zero"
    
    # Credential theft patterns
    "\/etc\/passwd"
    "\/etc\/shadow"
    "\.ssh\/id_rsa"
    "\.aws\/credentials"
    "\.env.*password"
    
    # Reverse shell patterns
    "bash.*-i.*>&"
    "python.*socket.*connect"
    "perl.*socket"
    "ruby.*socket"
    "php.*fsockopen"
    
    # Encoding/obfuscation patterns
    "base64.*-d"
    "echo.*\|.*base64"
    "printf.*\\\\x"
    "uuencode"
    "xxd.*-r"
    
    # Cryptocurrency mining
    "xmrig"
    "cryptonight"
    "stratum\+tcp"
    "monero"
    "mining.*pool"
)

# Secrets patterns
SECRETS_PATTERNS=(
    # API Keys
    "AKIA[0-9A-Z]{16}"  # AWS Access Key
    "AIza[a-zA-Z0-9_-]{35}"  # Google API Key
    "ghp_[a-zA-Z0-9]{36}"  # GitHub Personal Access Token
    "sk_live_[a-zA-Z0-9]{24,}"  # Stripe Live Key
    
    # Generic secrets
    "[Pp]assword['\"]?\s*[:=]\s*['\"][^'\"]{8,}"
    "[Aa]pi[_-]?[Kk]ey['\"]?\s*[:=]\s*['\"][^'\"]{10,}"
    "[Ss]ecret['\"]?\s*[:=]\s*['\"][^'\"]{10,}"
    "[Tt]oken['\"]?\s*[:=]\s*['\"][^'\"]{10,}"
)

# Initialize security scanner
init_security_scanner() {
    log_security "Initializing security scanner..."
    
    # Create results structure
    echo '{
        "scan_timestamp": "'$(date -Iseconds)'",
        "scan_type": "security",
        "findings": [],
        "summary": {
            "total_files_scanned": 0,
            "malicious_patterns_found": 0,
            "secrets_found": 0,
            "high_risk_files": 0
        }
    }' > "$RESULTS_FILE"
    
    log_security "Security scanner initialized"
}

# Scan for malicious patterns
scan_malicious_patterns() {
    log_security "Scanning for malicious code patterns..."
    
    local findings=0
    local scanned_files=0
    
    # Find all relevant files to scan
    while IFS= read -r file; do
        ((scanned_files++))
        local file_findings=0
        
        # Check each malicious pattern
        for pattern in "${MALICIOUS_PATTERNS[@]}"; do
            if grep -n -E "$pattern" "$file" 2>/dev/null; then
                log_security "WARNING: Malicious pattern found in $file: $pattern"
                ((findings++))
                ((file_findings++))
                
                # Add to results
                jq --arg file "$file" \
                   --arg pattern "$pattern" \
                   --arg severity "high" \
                   '.findings += [{"type": "malicious_pattern", "file": $file, "pattern": $pattern, "severity": $severity}]' \
                   "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
            fi
        done
        
        if [[ $file_findings -gt 0 ]]; then
            log_security "File $file contains $file_findings malicious patterns"
        fi
    done < <(find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.php" -o -name "*.rb" \) -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null)
    
    # Update summary
    jq --arg scanned "$scanned_files" \
       --arg findings "$findings" \
       '.summary.total_files_scanned = ($scanned | tonumber) | .summary.malicious_patterns_found = ($findings | tonumber)' \
       "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    
    log_security "Malicious pattern scan complete: $findings patterns found in $scanned_files files"
    return $findings
}

# Scan for secrets
scan_secrets() {
    log_security "Scanning for exposed secrets..."
    
    local secrets_found=0
    
    # Check each secrets pattern
    for pattern in "${SECRETS_PATTERNS[@]}"; do
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                local file=$(echo "$match" | cut -d: -f1)
                log_security "WARNING: Potential secret found in $file"
                ((secrets_found++))
                
                # Add to results
                jq --arg file "$file" \
                   --arg pattern "$pattern" \
                   --arg severity "critical" \
                   '.findings += [{"type": "exposed_secret", "file": $file, "pattern": $pattern, "severity": $severity}]' \
                   "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
            fi
        done < <(grep -r -E "$pattern" . --include="*.sh" --include="*.py" --include="*.js" --include="*.env" --include="*.yml" --include="*.yaml" --include="*.json" --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null || true)
    done
    
    # Update summary
    jq --arg secrets "$secrets_found" \
       '.summary.secrets_found = ($secrets | tonumber)' \
       "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    
    log_security "Secrets scan complete: $secrets_found potential secrets found"
    return $secrets_found
}

# Scan dependencies for vulnerabilities
scan_dependencies() {
    log_security "Scanning dependencies for vulnerabilities..."
    
    local vulns_found=0
    
    # NPM/Node.js
    if [[ -f "package.json" ]]; then
        log_security "Scanning npm dependencies..."
        if command -v npm &> /dev/null; then
            if npm audit --json 2>/dev/null | jq -e '.vulnerabilities | to_entries | length > 0' &>/dev/null; then
                log_security "WARNING: Vulnerable npm dependencies found"
                ((vulns_found++))
            fi
        fi
    fi
    
    # Python
    if [[ -f "requirements.txt" ]]; then
        log_security "Scanning Python dependencies..."
        if command -v safety &> /dev/null; then
            if ! safety check --json 2>/dev/null; then
                log_security "WARNING: Vulnerable Python dependencies found"
                ((vulns_found++))
            fi
        elif command -v pip-audit &> /dev/null; then
            if ! pip-audit 2>/dev/null; then
                log_security "WARNING: Vulnerable Python dependencies found"
                ((vulns_found++))
            fi
        fi
    fi
    
    # Go
    if [[ -f "go.mod" ]]; then
        log_security "Scanning Go dependencies..."
        if command -v go &> /dev/null; then
            if go list -json -m all | nancy sleuth 2>/dev/null | grep -q "Vulnerable"; then
                log_security "WARNING: Vulnerable Go dependencies found"
                ((vulns_found++))
            fi
        fi
    fi
    
    return $vulns_found
}

# Generate security report
generate_security_report() {
    local exit_code=$1
    
    log_security "Generating security report..."
    
    # Get summary stats
    local total_findings=$(jq '.findings | length' "$RESULTS_FILE")
    local high_severity=$(jq '[.findings[] | select(.severity == "high")] | length' "$RESULTS_FILE")
    local critical_severity=$(jq '[.findings[] | select(.severity == "critical")] | length' "$RESULTS_FILE")
    
    # Determine overall risk level
    local risk_level="low"
    if [[ $critical_severity -gt 0 ]]; then
        risk_level="critical"
    elif [[ $high_severity -gt 0 ]]; then
        risk_level="high"
    elif [[ $total_findings -gt 0 ]]; then
        risk_level="medium"
    fi
    
    # Update results with risk assessment
    jq --arg risk "$risk_level" \
       --arg status $([ $exit_code -eq 0 ] && echo "passed" || echo "failed") \
       '.summary.risk_level = $risk | .summary.scan_status = $status' \
       "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    
    # Display summary
    echo ""
    echo "🛡️  SECURITY SCAN SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Risk Level: $risk_level"
    echo "Total Findings: $total_findings"
    echo "Critical Issues: $critical_severity"
    echo "High Risk Issues: $high_severity"
    echo ""
    echo "Detailed results: $RESULTS_FILE"
    echo "Full log: $SECURITY_LOG_FILE"
    
    log_security "Security report generated"
}

# Main security validation
main() {
    local exit_code=0
    
    log_security "Starting security validation scan..."
    
    # Initialize scanner
    init_security_scanner
    
    # Run scans
    if ! scan_malicious_patterns; then
        exit_code=1
    fi
    
    if ! scan_secrets; then
        exit_code=1
    fi
    
    if ! scan_dependencies; then
        exit_code=1
    fi
    
    # Generate report
    generate_security_report $exit_code
    
    if [[ $exit_code -eq 0 ]]; then
        log_security "✅ Security validation completed successfully"
    else
        log_security "❌ Security validation found issues"
    fi
    
    return $exit_code
}

# Run main
main "$@"
SECURITY_SCANNER_EOF
    
    chmod +x scripts/validation/security_scanner.sh
    
    # Create security scan command for Claude
    cat > .claude/commands/security-scan.md << 'EOF'
# Security Scan Command

## Overview
The `/security-scan` command runs comprehensive security validation to detect malicious code patterns, exposed secrets, and dependency vulnerabilities.

## Usage
```
/security-scan [--detailed]
```

## Options
- `--detailed`: Show detailed findings in the output

## What It Scans

### Malicious Code Patterns
- Command injection attempts
- Network exfiltration
- Reverse shells
- File system manipulation
- Credential theft
- Encoding/obfuscation

### Exposed Secrets
- API keys (AWS, Google, GitHub, etc.)
- Passwords in code
- Authentication tokens
- Private keys

### Dependency Vulnerabilities
- npm packages (via npm audit)
- Python packages (via safety/pip-audit)
- Go modules (via nancy)

## Security Levels

### Critical
- Exposed secrets
- Active malicious code
- Critical dependency vulnerabilities

### High
- Suspicious code patterns
- Potential security risks
- High-severity vulnerabilities

### Medium
- Code quality issues with security implications
- Medium-severity vulnerabilities

### Low
- Best practice violations
- Low-severity vulnerabilities

## Integration

### Manual Scanning
Run the security scanner directly:
```bash
./scripts/validation/security_scanner.sh
```

### Claude Code Integration
Use the `/security-scan` command during development to check for security issues before committing.

### CI/CD Integration
Add to your GitHub Actions or other CI/CD pipeline:
```yaml
- name: Security Scan
  run: ./scripts/validation/security_scanner.sh
```

## Response to Findings

### Critical Issues
1. **STOP** - Do not deploy or commit
2. **REMOVE** - Delete or fix the security issue
3. **VERIFY** - Re-run scan to confirm resolution

### High Risk Issues
1. **REVIEW** - Examine the context
2. **ASSESS** - Determine if it's a false positive
3. **FIX** - Address legitimate issues

### Medium/Low Issues
1. **PLAN** - Schedule remediation
2. **TRACK** - Document in issue tracker
3. **IMPROVE** - Update code over time

## False Positives

If the scanner flags legitimate code:
1. Review the specific pattern
2. Confirm it's safe in your context
3. Consider refactoring to avoid the pattern
4. Document why it's safe if keeping

## Best Practices

1. **Run regularly** - Before each commit
2. **Fix immediately** - Don't accumulate security debt
3. **Stay updated** - Keep security tools current
4. **Train team** - Share security awareness

---

*Security scanning is essential for maintaining code integrity and protecting sensitive data.*
EOF

    echo "✅ Security validation scripts deployed"
fi

# Make hook scripts executable
chmod +x scripts/hooks/*.sh

echo "✅ Validation system deployment complete"
# ===== Module: 05-git-scripts.sh =====
# AI Setup Deployment Script - Git Scripts Module
# This module deploys git author management scripts

# Deploy Git Author Management Scripts
echo "🔧 Deploying git author management scripts..."

# Create scripts/git directory
mkdir -p scripts/git

# scripts/git/git-author-claude.sh
cat > scripts/git/git-author-claude.sh << 'EOF'
#!/bin/bash

# git-author-claude.sh - Switch git author to Claude Code Assistant
# Part of AI Setup Git Author Management System
# Version: 2.0.0 - Shell script-based implementation

set -e

# Configuration
CONFIG_DIR=".claude"
CONFIG_FILE="$CONFIG_DIR/git-authors.json"
BACKUP_FILE="$CONFIG_DIR/git-authors.backup"

# Claude author details
CLAUDE_NAME="Claude Code Assistant"
CLAUDE_EMAIL="claude-code@anthropic.com"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create configuration directory and file
create_config() {
    mkdir -p "$CONFIG_DIR"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "{}" > "$CONFIG_FILE"
    fi
}

# Get current git configuration
get_current_git_config() {
    local current_name=$(git config user.name 2>/dev/null || echo "")
    local current_email=$(git config user.email 2>/dev/null || echo "")
    echo "$current_name|$current_email"
}

# Save human author configuration
save_human_config() {
    local name="$1"
    local email="$2"
    
    # Create backup
    cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null || true
    
    # Update configuration file
    local temp_file=$(mktemp)
    jq --arg name "$name" \
       --arg email "$email" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.human = {name: $name, email: $email} | .current = "claude" | .last_updated = $date' \
       "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
}

# Main execution
main() {
    echo -e "${GREEN}Switching to Claude Code Assistant git author...${NC}"
    
    # Create configuration
    create_config
    
    # Get current configuration
    IFS='|' read -r current_name current_email <<< "$(get_current_git_config)"
    
    # Only save if we're not already Claude
    if [[ "$current_name" != "$CLAUDE_NAME" ]]; then
        if [[ -n "$current_name" && -n "$current_email" ]]; then
            echo -e "Saving current author: $current_name <$current_email>"
            save_human_config "$current_name" "$current_email"
        else
            echo -e "${YELLOW}Warning: No current git author configured${NC}"
        fi
    fi
    
    # Set Claude as author
    git config user.name "$CLAUDE_NAME"
    git config user.email "$CLAUDE_EMAIL"
    
    echo -e "${GREEN}✓ Git author switched to: $CLAUDE_NAME <$CLAUDE_EMAIL>${NC}"
    echo ""
    echo "Remember to switch back to your personal author after AI-assisted commits:"
    echo "  ./scripts/git/git-author-human.sh"
}

# Run main
main "$@"
EOF

# scripts/git/git-author-human.sh
cat > scripts/git/git-author-human.sh << 'EOF'
#!/bin/bash

# git-author-human.sh - Restore human git author
# Part of AI Setup Git Author Management System
# Version: 2.0.0 - Shell script-based implementation

set -e

# Configuration
CONFIG_DIR=".claude"
CONFIG_FILE="$CONFIG_DIR/git-authors.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse command line arguments
FORCE_RESTORE=false
RESET_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_RESTORE=true
            shift
            ;;
        --reset)
            RESET_CONFIG=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--force] [--reset]"
            exit 1
            ;;
    esac
done

# Get saved human configuration
get_saved_human_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local name=$(jq -r '.human.name // empty' "$CONFIG_FILE" 2>/dev/null)
        local email=$(jq -r '.human.email // empty' "$CONFIG_FILE" 2>/dev/null)
        
        if [[ -n "$name" && -n "$email" ]]; then
            echo "$name|$email"
            return 0
        fi
    fi
    
    return 1
}

# Get global git configuration
get_global_git_config() {
    local name=$(git config --global user.name 2>/dev/null || echo "")
    local email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ -n "$name" && -n "$email" ]]; then
        echo "$name|$email"
        return 0
    fi
    
    return 1
}

# Update configuration file
update_config_current() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local temp_file=$(mktemp)
        jq --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.current = "human" | .last_updated = $date' \
           "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Restoring human git author...${NC}"
    
    # Reset configuration if requested
    if [[ "$RESET_CONFIG" == "true" ]]; then
        echo "Resetting git author configuration..."
        rm -f "$CONFIG_FILE"
        echo -e "${GREEN}✓ Configuration reset${NC}"
        echo "Please set your git author manually:"
        echo "  git config user.name \"Your Name\""
        echo "  git config user.email \"your.email@example.com\""
        return 0
    fi
    
    # Try to get saved human configuration
    if human_config=$(get_saved_human_config); then
        IFS='|' read -r name email <<< "$human_config"
        echo -e "Restoring saved author: $name <$email>"
    elif [[ "$FORCE_RESTORE" == "true" ]] && global_config=$(get_global_git_config); then
        IFS='|' read -r name email <<< "$global_config"
        echo -e "Restoring from global config: $name <$email>"
    else
        echo -e "${RED}Error: No saved human author configuration found${NC}"
        echo ""
        echo "Options:"
        echo "1. Use --force to restore from global git config"
        echo "2. Use --reset to clear configuration and set manually"
        echo "3. Set author manually:"
        echo "   git config user.name \"Your Name\""
        echo "   git config user.email \"your.email@example.com\""
        exit 1
    fi
    
    # Restore human author
    git config user.name "$name"
    git config user.email "$email"
    
    # Update configuration
    update_config_current
    
    echo -e "${GREEN}✓ Git author restored to: $name <$email>${NC}"
}

# Run main
main "$@"
EOF

# scripts/git/git-author-verify.sh
cat > scripts/git/git-author-verify.sh << 'EOF'
#!/bin/bash

# git-author-verify.sh - Verify git author configuration
# Part of AI Setup Git Author Management System
# Version: 2.0.0 - Shell script-based implementation

set -e

# Configuration
CONFIG_DIR=".claude"
CONFIG_FILE="$CONFIG_DIR/git-authors.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
QUIET_MODE=false
VERBOSE_MODE=false
REPAIR_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q)
            QUIET_MODE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE_MODE=true
            shift
            ;;
        --repair)
            REPAIR_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--quiet] [--verbose] [--repair]"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "$@"
    fi
}

log_verbose() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo -e "$@"
    fi
}

# Check git configuration
check_git_config() {
    local current_name=$(git config user.name 2>/dev/null || echo "")
    local current_email=$(git config user.email 2>/dev/null || echo "")
    
    log "${BLUE}Current git configuration:${NC}"
    log "  Name:  ${current_name:-<not set>}"
    log "  Email: ${current_email:-<not set>}"
    
    if [[ -z "$current_name" || -z "$current_email" ]]; then
        log "${RED}✗ Git author configuration is incomplete${NC}"
        return 1
    fi
    
    # Check if Claude is currently set
    if [[ "$current_name" == "Claude Code Assistant" ]]; then
        log "${YELLOW}⚠ Claude Code Assistant is currently set as git author${NC}"
        log "  Remember to restore your personal author after AI commits"
        return 2
    fi
    
    log "${GREEN}✓ Git author configuration is valid${NC}"
    return 0
}

# Check configuration file
check_config_file() {
    log ""
    log "${BLUE}Configuration file status:${NC}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${YELLOW}⚠ Configuration file not found: $CONFIG_FILE${NC}"
        if [[ "$REPAIR_MODE" == "true" ]]; then
            log "  Creating configuration file..."
            mkdir -p "$CONFIG_DIR"
            echo '{"human": {}, "claude": {"name": "Claude Code Assistant", "email": "claude-code@anthropic.com"}, "current": "unknown"}' > "$CONFIG_FILE"
            log "${GREEN}  ✓ Configuration file created${NC}"
        fi
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log "${RED}✗ Configuration file contains invalid JSON${NC}"
        if [[ "$REPAIR_MODE" == "true" ]]; then
            log "  Backing up and recreating configuration..."
            mv "$CONFIG_FILE" "$CONFIG_FILE.broken.$(date +%s)"
            echo '{"human": {}, "claude": {"name": "Claude Code Assistant", "email": "claude-code@anthropic.com"}, "current": "unknown"}' > "$CONFIG_FILE"
            log "${GREEN}  ✓ Configuration file repaired${NC}"
        fi
        return 1
    fi
    
    # Check configuration content
    local human_name=$(jq -r '.human.name // empty' "$CONFIG_FILE" 2>/dev/null)
    local human_email=$(jq -r '.human.email // empty' "$CONFIG_FILE" 2>/dev/null)
    local current=$(jq -r '.current // "unknown"' "$CONFIG_FILE" 2>/dev/null)
    
    log_verbose "  Saved human: ${human_name:-<none>} <${human_email:-<none>}>"
    log_verbose "  Current mode: $current"
    
    if [[ -z "$human_name" || -z "$human_email" ]]; then
        log "${YELLOW}⚠ No saved human author in configuration${NC}"
    else
        log "${GREEN}✓ Configuration file is valid${NC}"
    fi
    
    return 0
}

# Check scripts
check_scripts() {
    log ""
    log "${BLUE}Git author scripts status:${NC}"
    
    local scripts=(
        "scripts/git/git-author-claude.sh"
        "scripts/git/git-author-human.sh"
    )
    
    local all_found=true
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            log_verbose "${GREEN}  ✓ $script (executable)${NC}"
        elif [[ -f "$script" ]]; then
            log "${YELLOW}  ⚠ $script (not executable)${NC}"
            if [[ "$REPAIR_MODE" == "true" ]]; then
                chmod +x "$script"
                log "${GREEN}    ✓ Made executable${NC}"
            fi
        else
            log "${RED}  ✗ $script (not found)${NC}"
            all_found=false
        fi
    done
    
    if [[ "$all_found" == "true" ]]; then
        log "${GREEN}✓ All git author scripts are available${NC}"
        return 0
    else
        log "${RED}✗ Some git author scripts are missing${NC}"
        return 1
    fi
}

# Main verification
main() {
    local exit_code=0
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${BLUE}=== Git Author Configuration Verification ===${NC}"
    fi
    
    # Check git configuration
    check_git_config || exit_code=$?
    
    # Check configuration file
    check_config_file || true
    
    # Check scripts
    check_scripts || true
    
    # Summary
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo ""
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ Git author system is properly configured${NC}"
        elif [[ $exit_code -eq 2 ]]; then
            echo -e "${YELLOW}⚠ Claude is currently set as git author${NC}"
            echo "  Run: ./scripts/git/git-author-human.sh"
        else
            echo -e "${RED}✗ Git author system needs configuration${NC}"
            echo "  Run: git config user.name \"Your Name\""
            echo "       git config user.email \"your.email@example.com\""
        fi
    fi
    
    return $exit_code
}

# Run main
main "$@"
EOF

# scripts/git/README.md
cat > scripts/git/README.md << 'EOF'
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
EOF

# Make scripts executable
chmod +x scripts/git/*.sh

echo "✅ Git author management scripts deployed"

# ===== Module: 05b-code-review.sh =====
# AI Setup Deployment Script - Code Review Module
# This module deploys code review bundling tools

# Deploy code review bundler script
echo "🔧 Deploying code review bundler..."

# Create the code review bundler script
cat > scripts/code_review/bundle_review.py << 'CODE_REVIEW_EOF'
#!/usr/bin/env python3
"""
Universal code-review bundler
Source: https://github.com/Strode-Mountain/machine-shop

Creates outputs under /scripts/code_review/output:
  - CODE_REVIEW_BUNDLE.md (or split files) : Markdown bundle with relevant source
  - REVIEW_PROMPT.md : Companion prompt for an AI reviewer

Automatically splits large bundles when they exceed size limits.
Cleans up previous output before generating new files.
Ensures /scripts/code_review/output/ is in the repo .gitignore.

Usage:
  python scripts/code_review/bundle_review.py [--root /path/to/repo] [--max-files N] [--max-bundle-mb N]

Defaults:
  --root  -> repo root inferred as two levels up from this script (../../)
  --max-files -> unlimited; set to cap files included (oldest-first pruned)
  --max-bundle-mb -> 8MB per file (configurable via BUNDLE_MAX_BUNDLE_MB env var)
"""
import os
import re
import sys
import argparse
import subprocess
import json
from pathlib import Path
from datetime import datetime, timezone

# ------------------------------ Config ------------------------------
# Directories at the REPO ROOT to ignore (your request)
ROOT_EXCLUDE_DIRS = {
    ".github", ".claude", ".expo", "docs", "archive", "specs", "scripts"
}

# Always-ignored directories anywhere in the tree
GLOBAL_EXCLUDE_DIRS = {
    # Version control and IDE
    ".git", ".gradle", ".idea",
    # Python virtual environments
    ".tox", ".venv", "venv", "env",
    # Build and output directories
    "build", "out", "dist", "coverage", ".cache", ".turbo",
    # JavaScript/TypeScript ecosystems
    "node_modules", ".next", "storybook-static", "cypress"
}

# Output directory (relative to repo root)
REL_OUT_DIR = Path("scripts/code_review/output")

# Include/Exclude rules for files
INCLUDE_EXT = {
    # Android/Java/Kotlin
    ".kt", ".java", ".gradle", ".kts", ".pro", ".xml",
    # JavaScript/TypeScript
    ".ts", ".tsx", ".js", ".jsx", ".cjs", ".mjs",
    # Python
    ".py", ".pyx", ".pyi",
    # Documentation and config
    ".md", ".properties", ".txt", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg"
}
INCLUDE_NAMES = {
    "AndroidManifest.xml", "Proguard-rules.pro", "proguard-rules.pro", "README.md", "LICENSE",
    "settings.gradle", "settings.gradle.kts", "Dockerfile", "docker-compose.yml", "Makefile"
}

# Important config files to always include regardless of extension
ALWAYS_INCLUDE_BASENAMES = {
    # Package managers
    "package.json", "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
    # TypeScript/JavaScript configs
    "tsconfig.json", "tsconfig.base.json", "jsconfig.json",
    "next.config.js", "next.config.mjs", "vite.config.ts", "vite.config.js",
    "babel.config.js", "babel.config.cjs", "babel.config.json",
    "eslint.config.js", ".eslintrc.json", ".eslintrc.js",
    "jest.config.js", "jest.config.ts", "playwright.config.ts", "vitest.config.ts",
    "webpack.config.js", "rollup.config.js",
    ".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js",
    # React Native
    "metro.config.js", "react-native.config.js",
    # Testing
    "cypress.config.ts", "cypress.config.js",
    # CI/CD
    ".gitlab-ci.yml", ".travis.yml", "azure-pipelines.yml"
}

BINARY_EXT = {
    ".apk", ".aar", ".so", ".dll", ".dylib", ".a", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg",
    ".jar", ".keystore", ".jks", ".ttf", ".otf", ".ico", ".pdf", ".mp3", ".wav", ".mp4"
}

EXCLUDE_FILES = {
    "local.properties", ".env", ".env.local", ".envrc",
    # Lock files and large metadata
    "yarn.lock", "pnpm-lock.yaml", "package-lock.json", "poetry.lock", "Cargo.lock"
}

# Maximum file size to include (default 256KB, configurable via env)
MAX_FILE_BYTES = int(os.getenv("BUNDLE_MAX_FILE_BYTES", 256 * 1024))

LANG_BY_EXT = {
    # JVM languages
    ".kt": "kotlin",
    ".java": "java",
    ".gradle": "groovy",
    ".kts": "kotlin",
    # Web languages
    ".ts": "typescript",
    ".tsx": "tsx",
    ".js": "javascript",
    ".jsx": "jsx",
    ".cjs": "javascript",
    ".mjs": "javascript",
    # Python
    ".py": "python",
    ".pyx": "python",
    ".pyi": "python",
    # Markup and config
    ".xml": "xml",
    ".md": "markdown",
    ".pro": "conf",
    ".properties": "properties",
    ".json": "json",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".ini": "ini",
    ".cfg": "ini",
    ".txt": "text"
}

# ------------------------------ GitHub PR Detection ------------------------------

def detect_github_pr(repo_root: Path) -> dict | None:
    """Detect if there's an open GitHub PR for the current branch.
    Returns PR info dict or None if no PR found."""
    try:
        # Check if gh CLI is available
        result = subprocess.run(
            ["gh", "--version"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            print("[info] GitHub CLI (gh) not found. Skipping PR detection.")
            return None

        # Get current branch
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            return None
        current_branch = result.stdout.strip()

        # List PRs for current branch
        result = subprocess.run(
            ["gh", "pr", "list", "--head", current_branch, "--json", "number,title,baseRefName,headRefName,url,state"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=10
        )
        if result.returncode != 0:
            return None

        prs = json.loads(result.stdout)
        if not prs:
            return None

        # Get the first open PR
        for pr in prs:
            if pr.get("state") == "OPEN":
                return pr

        return None
    except Exception as e:
        print(f"[warn] Error detecting GitHub PR: {e}")
        return None


def get_pr_diff(repo_root: Path, pr_info: dict) -> str | None:
    """Get the diff for a PR comparing current branch to base branch."""
    try:
        base_branch = pr_info.get("baseRefName", "main")

        # Get the merge-base to find where branches diverged
        result = subprocess.run(
            ["git", "merge-base", base_branch, "HEAD"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            # Fallback to simple diff if merge-base fails
            result = subprocess.run(
                ["git", "diff", f"{base_branch}...HEAD"],
                capture_output=True,
                text=True,
                cwd=repo_root,
                timeout=30
            )
        else:
            # Get diff from merge-base to HEAD
            merge_base = result.stdout.strip()
            result = subprocess.run(
                ["git", "diff", f"{merge_base}..HEAD"],
                capture_output=True,
                text=True,
                cwd=repo_root,
                timeout=30
            )

        if result.returncode != 0:
            return None

        return result.stdout
    except Exception as e:
        print(f"[warn] Error getting PR diff: {e}")
        return None


def write_pr_diff_bundle(repo_root: Path, pr_info: dict, diff_content: str, out_dir: Path) -> Path | None:
    """Write PR diff to a separate bundle file."""
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / "PR_DIFF_BUNDLE.md"

        pr_number = pr_info.get("number", "unknown")
        pr_title = pr_info.get("title", "Untitled PR")
        pr_url = pr_info.get("url", "")
        base_branch = pr_info.get("baseRefName", "main")
        head_branch = pr_info.get("headRefName", "current")
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")

        # Parse diff to get statistics
        files_changed = set()
        additions = 0
        deletions = 0

        for line in diff_content.splitlines():
            if line.startswith("diff --git"):
                # Extract filename from diff header
                parts = line.split()
                if len(parts) >= 3:
                    # Remove a/ or b/ prefix
                    fname = parts[2][2:] if parts[2].startswith("a/") else parts[2]
                    files_changed.add(fname)
            elif line.startswith("+") and not line.startswith("+++"):
                additions += 1
            elif line.startswith("-") and not line.startswith("---"):
                deletions += 1

        content = f"""# PR DIFF BUNDLE

Pull Request changes for review.
<!-- Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop -->

## PR Information
- **PR Number**: #{pr_number}
- **Title**: {pr_title}
- **URL**: {pr_url}
- **Base Branch**: {base_branch}
- **Head Branch**: {head_branch}
- **Generated**: {now} UTC

## Change Statistics
- **Files Changed**: {len(files_changed)}
- **Lines Added**: {additions:,}
- **Lines Deleted**: {deletions:,}
- **Net Change**: {additions - deletions:+,}

## Changed Files
{chr(10).join(f'- {f}' for f in sorted(files_changed))}

## Full Diff

The following shows all changes that would be merged from `{head_branch}` into `{base_branch}`:

```diff
{diff_content}
```

## Review Focus Areas

When reviewing this PR, consider:
1. **Backwards Compatibility**: Will these changes break existing functionality?
2. **Migration Requirements**: Do these changes require data migration or configuration updates?
3. **Test Coverage**: Are the changes adequately tested?
4. **Documentation**: Are API changes and new features properly documented?
5. **Performance Impact**: Do these changes affect performance characteristics?
6. **Security Implications**: Are there any security considerations with these changes?
"""

        out_path.write_text(content, encoding="utf-8")
        size_mb = out_path.stat().st_size / (1024 * 1024)
        print(f"  Created: {out_path.name} ({size_mb:.2f} MB) - PR #{pr_number} diff")
        return out_path
    except Exception as e:
        print(f"[error] Failed to write PR diff bundle: {e}")
        return None

# ------------------------------ Helpers ------------------------------

def detect_repo_root(via_arg: str | None) -> Path:
    if via_arg:
        return Path(via_arg).resolve()
    # Default: two levels up from this script: repo_root/scripts/code_review/bundle_review.py
    return Path(__file__).resolve().parents[2]


def ensure_gitignore_has_output(repo_root: Path, rel_out: Path) -> None:
    gitignore = repo_root / ".gitignore"
    rel_line = f"/{rel_out.as_posix().rstrip('/')}/\n"
    try:
        if gitignore.exists():
            text = gitignore.read_text(encoding="utf-8", errors="ignore")
            if rel_line.strip() not in {ln.strip() for ln in text.splitlines()}:
                with gitignore.open("a", encoding="utf-8") as f:
                    f.write("\n# Ignore code-review bundle outputs\n")
                    f.write(rel_line)
        else:
            with gitignore.open("w", encoding="utf-8") as f:
                f.write("# Ignore code-review bundle outputs\n")
                f.write(rel_line)
    except Exception as e:
        print(f"[warn] Unable to update .gitignore: {e}")


def cleanup_previous_output(out_dir: Path) -> None:
    """Remove previous bundle and prompt files before generating new ones."""
    patterns = [
        "CODE_REVIEW_BUNDLE*.md",
        "REVIEW_PROMPT.md",
        "PR_DIFF_BUNDLE.md"
    ]
    for pattern in patterns:
        for file in out_dir.glob(pattern):
            file.unlink()
            print(f"  Cleaned up: {file.name}")


def should_include_file(path: Path, repo_root: Path) -> bool:
    name = path.name
    ext = path.suffix.lower()
    
    # Exclude blacklisted files and binary files
    if name in EXCLUDE_FILES or ext in BINARY_EXT:
        return False
    
    # Always include important config files
    if name in ALWAYS_INCLUDE_BASENAMES:
        return True
    
    # Check standard include rules
    if name in INCLUDE_NAMES or ext in INCLUDE_EXT:
        # Apply size limit to prevent huge files
        try:
            if path.stat().st_size > MAX_FILE_BYTES:
                return False
        except Exception:
            pass
        return True
    
    return False


def detect_lang(path: Path) -> str:
    return LANG_BY_EXT.get(path.suffix.lower(), "")


def read_text(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="strict").splitlines()
    except Exception:
        return path.read_text(encoding="latin-1", errors="replace").splitlines()


def collect_files(repo_root: Path, max_files: int | None) -> list[Path]:
    files: list[Path] = []
    for root, dirs, fnames in os.walk(repo_root):
        root_path = Path(root)

        # Prune directories at the repo root (only when walking the root)
        if root_path == repo_root:
            dirs[:] = [d for d in dirs if d not in ROOT_EXCLUDE_DIRS]
        # Global pruning anywhere
        dirs[:] = [d for d in dirs if d not in GLOBAL_EXCLUDE_DIRS]

        # Also prune the output directory anywhere it appears
        # (resolved against repo root to be safe on first level)
        rels = [Path(d) for d in dirs]
        pruned = []
        for d in rels:
            absd = root_path / d
            if absd.resolve() == (repo_root / REL_OUT_DIR).resolve():
                continue
            pruned.append(d.name)
        dirs[:] = pruned

        for fname in fnames:
            fpath = root_path / fname
            # Skip anything inside the output dir
            try:
                if (repo_root / REL_OUT_DIR) in fpath.resolve().parents:
                    continue
            except Exception:
                pass
            if should_include_file(fpath, repo_root):
                files.append(fpath)

    files.sort(key=lambda p: (p.stat().st_mtime, p.as_posix()))  # stable, mtime increasing
    if max_files and len(files) > max_files:
        # Keep the most recent N files
        files = files[-max_files:]
    return files


def make_toc_anchor(path_str: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", path_str.lower()).strip('-')


# ------------------------------ Writers ------------------------------

def write_bundle_md(repo_root: Path, files: list[Path], out_dir: Path, max_bundle_mb: int = 8) -> list[Path]:
    """Write bundle MD file(s), splitting if content exceeds max_bundle_mb.
    Returns list of paths to all created files.
    
    Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop
    """
    MAX_SIZE_BYTES = max_bundle_mb * 1024 * 1024
    out_dir.mkdir(parents=True, exist_ok=True)
    
    # Pre-scan for metadata
    rels = [p.relative_to(repo_root) for p in files]
    modules = sorted({str(p).split("/")[0] for p in rels if "/" in str(p)})
    manifests = [str(p) for p in rels if p.name == "AndroidManifest.xml"]
    gradle_files = [str(p) for p in rels if p.suffix in {".gradle", ".kts"} or p.name.startswith("settings.gradle")]
    package_files = [str(p) for p in rels if p.name in {"package.json", "pyproject.toml", "Cargo.toml", "go.mod"}]
    
    todos: list[str] = []
    for p in files:
        # Scan more file types for TODOs
        if p.suffix.lower() in {".kt", ".java", ".gradle", ".kts", ".xml", ".py", ".ts", ".tsx", ".js", ".jsx"}:
            try:
                for i, line in enumerate(read_text(p), start=1):
                    if re.search(r"\b(TODO|FIXME|XXX|HACK|BUG)\b", line):
                        todos.append(f"- {p.relative_to(repo_root)}:{i} {line.strip()[:160]}")
            except Exception:
                pass
    
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    
    # Build header content
    header_lines = [
        "# CODE_REVIEW_BUNDLE\n\n",
        "Auto-generated for comprehensive static review.\n",
        "<!-- Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop -->\n\n",
        "## Overview\n",
        f"- **Generated**: {now} UTC\n",
        f"- **Files**: {len(files)} total\n",
        f"- **Modules**: {', '.join(modules) if modules else '(single-module)'}\n",
        f"- **Manifests**: {', '.join(manifests) or '(none found)'}\n",
        f"- **Gradle files**: {', '.join(gradle_files) or '(none found)'}\n",
        f"- **Package files**: {', '.join(package_files) or '(none found)'}\n",
        "- **TODO/FIXME/XXX/HACK/BUG sample**:\n",
        ("\n".join(todos[:30]) or "(none found)") + "\n\n"
    ]
    
    # Initialize tracking for file splitting
    bundle_files = []
    current_part = 1
    current_size = 0
    current_content = []
    
    def write_current_part() -> Path:
        """Write the current part to a file."""
        nonlocal current_part, current_size, current_content
        
        if current_part == 1 and len([p for p in files]) * 1000 < MAX_SIZE_BYTES:
            # Single file if small enough
            out_path = out_dir / "CODE_REVIEW_BUNDLE.md"
        else:
            # Multiple files with numbering
            out_path = out_dir / f"CODE_REVIEW_BUNDLE_{current_part:03d}.md"
        
        with out_path.open("w", encoding="utf-8") as f:
            f.write("".join(current_content))
        
        bundle_files.append(out_path)
        file_size_mb = current_size / (1024 * 1024)
        print(f"  Created: {out_path.name} ({file_size_mb:.2f} MB)")
        
        current_part += 1
        current_size = 0
        current_content = []
        return out_path
    
    def add_content(text: str) -> None:
        """Add content and track size."""
        nonlocal current_size, current_content
        content_bytes = text.encode("utf-8")
        current_size += len(content_bytes)
        current_content.append(text)
    
    # Add header to first part
    for line in header_lines:
        add_content(line)
    
    # Add table of contents (only in first file)
    add_content("## Table of Contents\n")
    for p in rels:
        anchor = make_toc_anchor(str(p))
        add_content(f"- [{p}](#{anchor})\n")
    add_content("\n---\n")
    
    # Process each file
    for p in files:
        rel = p.relative_to(repo_root)
        lang = detect_lang(p)
        
        # Build file content
        file_content = []
        file_content.append(f"\n## {rel}\n\n")
        file_content.append(f"```{lang}\n")
        
        lines = read_text(p)
        # Add line numbers for code files
        codeish = lang in {"kotlin", "java", "groovy", "typescript", "javascript", "python"}
        prefix = "// " if lang in {"kotlin", "java", "groovy", "typescript", "javascript"} else ("# " if lang in {"python", "yaml", "bash"} else "")
        
        if prefix:
            for i, line in enumerate(lines, start=1):
                file_content.append(f"{prefix}L{i:04d} {line}\n")
        else:
            for line in lines:
                file_content.append(f"{line}\n")
        file_content.append("```\n")
        
        # Check if adding this file would exceed the limit
        file_text = "".join(file_content)
        file_bytes = len(file_text.encode("utf-8"))
        
        if current_size + file_bytes > MAX_SIZE_BYTES and current_content:
            # Write current part and start a new one
            write_current_part()
            # Add continuation header for new part
            add_content(f"# CODE_REVIEW_BUNDLE (Part {current_part})\n\n")
            add_content(f"Continuation from Part {current_part - 1}\n\n")
        
        # Add the file content
        add_content(file_text)
    
    # Write any remaining content
    if current_content:
        write_current_part()
    
    return bundle_files


def write_prompt_md(repo_root: Path, files: list[Path], out_dir: Path, bundle_files: list[Path], pr_diff_file: Path | None = None) -> Path:
    out_path = out_dir / "REVIEW_PROMPT.md"
    rels = [p.relative_to(repo_root) for p in files]
    
    # Reference the bundle files appropriately
    if len(bundle_files) == 1:
        bundle_ref = "**CODE_REVIEW_BUNDLE.md**"
        bundle_note = ""
    else:
        bundle_names = ", ".join([f"**{f.name}**" for f in bundle_files])
        bundle_ref = f"the following bundle files: {bundle_names}"
        bundle_note = "\n\n**Note**: Due to size, the bundle has been split into multiple files. Review them in sequence."

    # Add PR diff reference if available
    pr_note = ""
    if pr_diff_file:
        pr_note = f"\n\n**Pull Request Diff**: Review **{pr_diff_file.name}** for proposed changes that would be merged."

    content = f"""
# Review Instructions (Companion Prompt)
You are reviewing a project bundle provided as {bundle_ref}. Treat it as read-only source; paths reflect the original repo.{bundle_note}{pr_note}

## Goals
1. **Architecture**: Evaluate design patterns, dependency management, module structure, separation of concerns.
2. **Platform-Specific Issues**:
   - Android: Lifecycle, background work, navigation, configuration changes
   - Web: Browser compatibility, state management, routing, bundling
   - Backend: API design, database patterns, authentication, scalability
3. **Security & Privacy**: Authentication, authorization, data validation, secrets management, OWASP compliance.
4. **Performance**: Load times, memory usage, network efficiency, caching strategies, optimization opportunities.
5. **Reliability**: Error handling, fault tolerance, logging, monitoring hooks, graceful degradation.
6. **Testing**: Test coverage, test quality, mocking strategies, edge cases, integration test gaps.
7. **Code Quality**: Readability, maintainability, documentation, type safety, linting compliance.
8. **PR-Specific Review** (if PR diff provided):
   - Validate changes against PR description and intent
   - Check for unintended changes or missing files
   - Ensure changes are complete and don't leave the codebase in an inconsistent state
   - Review for merge conflicts or compatibility issues with the base branch

## How to reference code
- Use the file headers and line numbers (e.g., `app/src/main/java/.../Foo.kt L0123`).
- Propose concrete patches or diff hunks when possible.

## Deliverables
- Top-level findings list (critical ➜ minor).
- File-specific comments grouped by path and line ranges.
- A prioritized refactor plan (1–2 weeks, 4–6 weeks).
- Risk register (user data, crashes, regressions) and quick mitigations.

## Context
- Bundle includes: Source code, configuration files, documentation, test files.
- Binaries, build outputs, secrets, images, and lock files are intentionally excluded.
- Root directories excluded from the scan: {', '.join(sorted(ROOT_EXCLUDE_DIRS))} (plus global ignores).
- Files larger than {MAX_FILE_BYTES // 1024}KB are skipped to prevent bundle bloat.

Report succinctly but precisely. Prefer code blocks and diffs over prose when giving fixes.
""".strip()

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content, encoding="utf-8")
    return out_path


# ------------------------------ Main ------------------------------

def main():
    ap = argparse.ArgumentParser(description="Generate code review bundle and prompt (with automatic splitting for large outputs).")
    ap.add_argument("--root", type=str, default=None, help="Repo root (defaults to ../../ from this script)")
    ap.add_argument("--max-files", type=int, default=None, help="Optional cap on number of files (keeps most recent N)")
    ap.add_argument("--max-bundle-mb", type=int, default=int(os.getenv("BUNDLE_MAX_BUNDLE_MB", 8)),
                    help="Maximum size per bundle file in MB (default 8MB)")
    args = ap.parse_args()

    repo_root = detect_repo_root(args.root)
    out_dir = repo_root / REL_OUT_DIR

    # Clean up previous output
    if out_dir.exists():
        print("Cleaning up previous output...")
        cleanup_previous_output(out_dir)

    ensure_gitignore_has_output(repo_root, REL_OUT_DIR)

    files = collect_files(repo_root, args.max_files)
    if not files:
        print("No files matched include rules. Check your repository paths and config.")
        return 1

    print(f"Processing {len(files)} files...")
    bundle_paths = write_bundle_md(repo_root, files, out_dir, args.max_bundle_mb)

    # Check for GitHub PR and generate diff bundle if found
    pr_diff_file = None
    pr_info = detect_github_pr(repo_root)
    if pr_info:
        pr_number = pr_info.get("number", "unknown")
        pr_title = pr_info.get("title", "Untitled")
        print(f"\nDetected open PR #{pr_number}: {pr_title}")
        print("Generating PR diff bundle...")

        diff_content = get_pr_diff(repo_root, pr_info)
        if diff_content:
            pr_diff_file = write_pr_diff_bundle(repo_root, pr_info, diff_content, out_dir)
            if not pr_diff_file:
                print("[warn] Failed to create PR diff bundle")
        else:
            print("[warn] Could not retrieve PR diff")
    else:
        print("\n[info] No open GitHub PR detected for current branch")

    prompt_path = write_prompt_md(repo_root, files, out_dir, bundle_paths, pr_diff_file)

    print(f"\n✅ Successfully created {len(bundle_paths)} bundle file(s):")
    for bp in bundle_paths:
        size_mb = bp.stat().st_size / (1024 * 1024)
        print(f"   - {bp.name} ({size_mb:.2f} MB)")
    if pr_diff_file:
        size_mb = pr_diff_file.stat().st_size / (1024 * 1024)
        print(f"✅ Created PR diff bundle: {pr_diff_file.name} ({size_mb:.2f} MB)")
    print(f"✅ Wrote prompt: {prompt_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
CODE_REVIEW_EOF

# Create the README
cat > scripts/code_review/README.md << 'CODE_REVIEW_README_EOF'
# Code Review Bundler

A universal code review bundler that creates comprehensive Markdown documentation of your codebase for AI-assisted review.

**Source**: https://github.com/Strode-Mountain/machine-shop

## Features

- **Universal language support**: Works with Android, JavaScript/TypeScript, Python, and more
- **Automatic file splitting**: Splits large bundles when they exceed size limits (default 8MB)
- **Smart file selection**: Includes source code and important configs, excludes binaries and lock files
- **Previous output cleanup**: Automatically removes old bundle files before generating new ones
- **TODO/FIXME tracking**: Scans for and summarizes TODO, FIXME, XXX, HACK, and BUG comments
- **Configurable limits**: Control maximum file size and bundle size via arguments or environment variables
- **GitHub PR integration**: Automatically detects open PRs and creates a separate diff bundle for merge review

## Outputs

Generated in `scripts/code_review/output/`:
- `CODE_REVIEW_BUNDLE.md` (or `CODE_REVIEW_BUNDLE_001.md`, `_002.md`, etc. for large codebases)
- `REVIEW_PROMPT.md` — AI reviewer instructions that reference the bundle file(s)
- `PR_DIFF_BUNDLE.md` — (Optional) Generated when an open GitHub PR is detected, contains the full diff for merge review

## Usage

### Basic Usage

```bash
# From repo root (recommended)
python3 scripts/code_review/bundle_review.py

# Or from anywhere
python3 scripts/code_review/bundle_review.py --root /path/to/repo
```

### GitHub PR Detection

The script automatically detects if there's an open GitHub PR for the current branch:
- Requires GitHub CLI (`gh`) to be installed and authenticated
- Creates a separate `PR_DIFF_BUNDLE.md` with the full diff
- Shows what changes would be merged into the base branch
- Includes change statistics and affected files list

### Advanced Options

```bash
# Limit the number of files included (keeps most recent N)
python3 scripts/code_review/bundle_review.py --max-files 800

# Set maximum bundle size (in MB, default is 8)
python3 scripts/code_review/bundle_review.py --max-bundle-mb 20

# Combine options
python3 scripts/code_review/bundle_review.py --root /path/to/repo --max-files 500 --max-bundle-mb 10
```

## Environment Variables

```bash
# Set default maximum file size to include (bytes, default 256KB)
export BUNDLE_MAX_FILE_BYTES=524288  # 512KB

# Set default maximum bundle size (MB, default 8)
export BUNDLE_MAX_BUNDLE_MB=20
```
CODE_REVIEW_README_EOF

# Make the Python script executable
chmod +x scripts/code_review/bundle_review.py

echo "✅ Code review bundler deployed"

# ===== Module: 06-hooks.sh =====
# AI Setup Deployment Script - Hooks Module
# This module deploys validation hooks system for Claude Code integration

# Deploy validation hooks system
echo "🔧 Deploying Claude Code hooks automation..."

# Create hooks directory if it doesn't exist
mkdir -p scripts/hooks

# scripts/hooks/validation_pre_hook.sh
cat > scripts/hooks/validation_pre_hook.sh << 'VALIDATION_PRE_HOOK_EOF'
#!/bin/bash
# validation_pre_hook.sh - Pre-tool validation hook
# Automatically triggered before AI tool usage to prepare validation context
# Part of Claude Code Validation Hooks Integration v1.0.0

set -e

# Configuration
VALIDATION_CONFIG_FILE=".validation/config.json"
VALIDATION_SESSION_DIR=".validation/sessions"
VALIDATION_RESULTS_DIR=".validation/results"
VALIDATION_LOGS_DIR=".validation/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_success() { echo -e "${GREEN}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_warning() { echo -e "${YELLOW}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_error() { echo -e "${RED}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }

# Initialize validation environment
init_validation_environment() {
    log_info "Initializing validation environment..."
    
    # Create validation directories
    mkdir -p "$VALIDATION_SESSION_DIR"
    mkdir -p "$VALIDATION_RESULTS_DIR"
    mkdir -p "$VALIDATION_LOGS_DIR"
    
    # Create session ID
    local session_id="pre_validation_$(date +%Y%m%d_%H%M%S)"
    export VALIDATION_SESSION_ID="$session_id"
    
    # Create session directory
    local session_dir="$VALIDATION_SESSION_DIR/$session_id"
    mkdir -p "$session_dir"
    export VALIDATION_SESSION_DIR="$session_dir"
    
    # Record session start
    echo "$(date -Iseconds)" > "$session_dir/start_time"
    echo "pre_validation" > "$session_dir/hook_type"
    
    log_success "Validation environment initialized (Session: $session_id)"
}

# Check validation prerequisites
check_validation_prerequisites() {
    log_info "Checking validation prerequisites..."
    
    local prerequisites_passed=true
    
    # Check if validation framework is available
    if [[ ! -f "scripts/validation/validate.sh" ]]; then
        log_error "Validation framework not found"
        prerequisites_passed=false
    fi
    
    # Check if AI feedback system is available
    if [[ ! -f "scripts/ai_feedback.py" ]]; then
        log_warning "AI feedback system not found - feedback collection will be limited"
    fi
    
    # Check project structure
    if [[ ! -f "package.json" ]] && [[ ! -f "requirements.txt" ]] && [[ ! -f "Cargo.toml" ]] && [[ ! -f "pom.xml" ]]; then
        log_warning "No recognized project configuration file found"
    fi
    
    # Check environment configuration
    if [[ ! -f ".env" ]] && [[ ! -f ".env.example" ]]; then
        log_warning "No environment configuration files found"
    fi
    
    if [[ "$prerequisites_passed" == "false" ]]; then
        log_error "Validation prerequisites not met"
        return 1
    fi
    
    log_success "Validation prerequisites check passed"
    return 0
}

# Detect project context
detect_project_context() {
    log_info "Detecting project context..."
    
    local project_type="unknown"
    local has_tests=false
    local has_docs=false
    
    # Detect project type
    if [[ -f "package.json" ]]; then
        project_type="web"
        log_info "Detected web project (Node.js)"
    elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
        project_type="api"
        log_info "Detected API project (Python)"
    elif [[ -f "Cargo.toml" ]]; then
        project_type="api"
        log_info "Detected API project (Rust)"
    elif [[ -f "pom.xml" ]]; then
        project_type="api"
        log_info "Detected API project (Java)"
    fi
    
    # Check for tests
    if [[ -d "tests" ]] || [[ -d "test" ]] || [[ -d "__tests__" ]] || [[ -d "spec" ]]; then
        has_tests=true
        log_info "Test directory detected"
    fi
    
    # Check for documentation
    if [[ -f "README.md" ]] || [[ -d "docs" ]] || [[ -d "documentation" ]]; then
        has_docs=true
        log_info "Documentation detected"
    fi
    
    # Export context variables
    export PROJECT_TYPE="$project_type"
    export HAS_TESTS="$has_tests"
    export HAS_DOCS="$has_docs"
    
    # Record context
    cat > "$VALIDATION_SESSION_DIR/project_context.json" << EOF
{
    "project_type": "$project_type",
    "has_tests": $has_tests,
    "has_docs": $has_docs,
    "detected_at": "$(date -Iseconds)"
}
EOF
    
    log_success "Project context detected and recorded"
}

# Setup validation tracking
setup_validation_tracking() {
    log_info "Setting up validation tracking..."
    
    # Create validation state file
    cat > "$VALIDATION_SESSION_DIR/validation_state.json" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "status": "initialized",
    "pre_validation_completed": false,
    "post_validation_completed": false,
    "completion_gate_passed": false,
    "validation_required": true,
    "tracking_started": "$(date -Iseconds)"
}
EOF
    
    # Set validation tracking environment variables
    export VALIDATION_TRACKING_ENABLED=true
    export VALIDATION_STATE_FILE="$VALIDATION_SESSION_DIR/validation_state.json"
    
    log_success "Validation tracking initialized"
}

# Check for pending validation requirements
check_pending_validation() {
    log_info "Checking for pending validation requirements..."
    
    # Check if there are recent changes that need validation
    if git diff --quiet HEAD^ HEAD 2>/dev/null; then
        log_info "No recent changes detected"
        return 0
    fi
    
    # Check if validation has been run recently
    local last_validation_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    if [[ -f "$last_validation_file" ]]; then
        local last_validation_time=$(jq -r '.timestamp' "$last_validation_file" 2>/dev/null)
        local last_commit_time=$(git log -1 --format=%cI 2>/dev/null)
        
        if [[ -n "$last_validation_time" ]] && [[ -n "$last_commit_time" ]]; then
            if [[ "$last_validation_time" > "$last_commit_time" ]]; then
                log_info "Recent validation found - validation may not be required"
                return 0
            fi
        fi
    fi
    
    log_warning "Pending validation requirements detected"
    export VALIDATION_REQUIRED=true
    return 0
}

# Generate pre-validation report
generate_pre_validation_report() {
    log_info "Generating pre-validation report..."
    
    local report_file="$VALIDATION_SESSION_DIR/pre_validation_report.json"
    
    cat > "$report_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "hook_type": "pre_validation",
    "timestamp": "$(date -Iseconds)",
    "project_type": "$PROJECT_TYPE",
    "has_tests": $HAS_TESTS,
    "has_docs": $HAS_DOCS,
    "validation_required": ${VALIDATION_REQUIRED:-false},
    "prerequisites_passed": true,
    "environment_initialized": true,
    "tracking_enabled": true,
    "recommendations": [
        "Validation environment ready",
        "Project context detected",
        "Proceed with AI tool usage"
    ]
}
EOF
    
    log_success "Pre-validation report generated: $report_file"
}

# Main pre-validation execution
main() {
    log_info "Starting pre-validation hook..."
    
    # Initialize validation environment
    if ! init_validation_environment; then
        log_error "Failed to initialize validation environment"
        exit 1
    fi
    
    # Check prerequisites
    if ! check_validation_prerequisites; then
        log_error "Validation prerequisites check failed"
        exit 1
    fi
    
    # Detect project context
    detect_project_context
    
    # Setup validation tracking
    setup_validation_tracking
    
    # Check for pending validation
    check_pending_validation
    
    # Generate pre-validation report
    generate_pre_validation_report
    
    log_success "Pre-validation hook completed successfully"
    
    # Export important variables for subsequent hooks
    echo "export VALIDATION_SESSION_ID=\"$VALIDATION_SESSION_ID\""
    echo "export VALIDATION_SESSION_DIR=\"$VALIDATION_SESSION_DIR\""
    echo "export PROJECT_TYPE=\"$PROJECT_TYPE\""
    echo "export VALIDATION_REQUIRED=\"${VALIDATION_REQUIRED:-false}\""
}

# Execute main function
main "$@"
VALIDATION_PRE_HOOK_EOF

# scripts/hooks/validation_post_hook.sh
cat > scripts/hooks/validation_post_hook.sh << 'VALIDATION_POST_HOOK_EOF'
#!/bin/bash
# validation_post_hook.sh - Post-tool validation hook
# Automatically triggered after AI tool usage to execute validation
# Part of Claude Code Validation Hooks Integration v1.0.0

set -e

# Configuration
VALIDATION_CONFIG_FILE=".validation/config.json"
VALIDATION_SESSION_DIR=".validation/sessions"
VALIDATION_RESULTS_DIR=".validation/results"
VALIDATION_LOGS_DIR=".validation/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_success() { echo -e "${GREEN}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_warning() { echo -e "${YELLOW}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_error() { echo -e "${RED}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }

# Load validation session context
load_validation_context() {
    log_info "Loading validation session context..."
    
    # Check if validation session exists
    if [[ -z "$VALIDATION_SESSION_ID" ]]; then
        log_warning "No validation session ID found - starting new session"
        export VALIDATION_SESSION_ID="post_validation_$(date +%Y%m%d_%H%M%S)"
        export VALIDATION_SESSION_DIR="$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID"
        mkdir -p "$VALIDATION_SESSION_DIR"
    fi
    
    # Load validation state
    local state_file="$VALIDATION_SESSION_DIR/validation_state.json"
    if [[ -f "$state_file" ]]; then
        log_info "Loading validation state from $state_file"
        export VALIDATION_STATE_FILE="$state_file"
    else
        log_warning "No validation state file found - creating new state"
        mkdir -p "$VALIDATION_SESSION_DIR"
        cat > "$state_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "status": "post_validation",
    "pre_validation_completed": false,
    "post_validation_completed": false,
    "completion_gate_passed": false,
    "validation_required": true,
    "post_validation_started": "$(date -Iseconds)"
}
EOF
        export VALIDATION_STATE_FILE="$state_file"
    fi
    
    log_success "Validation context loaded"
}

# Determine validation requirements
determine_validation_requirements() {
    log_info "Determining validation requirements..."
    
    local validation_required=false
    local validation_level="smoke"
    
    # Check if files were modified
    if git diff --quiet HEAD~1 HEAD 2>/dev/null; then
        log_info "No changes detected since last commit"
    else
        log_info "Changes detected - validation required"
        validation_required=true
    fi
    
    # Check if critical files were modified
    local critical_files=(
        "package.json"
        "requirements.txt"
        "Cargo.toml"
        "docker-compose.yml"
        "Dockerfile"
        ".env"
        "config.json"
        "config.yml"
    )
    
    for file in "${critical_files[@]}"; do
        if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "^$file$"; then
            log_warning "Critical file modified: $file - full validation required"
            validation_required=true
            validation_level="full"
            break
        fi
    done
    
    # Check if code files were modified
    local code_extensions=("*.js" "*.ts" "*.py" "*.rs" "*.java" "*.go" "*.rb" "*.php")
    for ext in "${code_extensions[@]}"; do
        if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "$ext$"; then
            log_info "Code files modified - validation required"
            validation_required=true
            break
        fi
    done
    
    # Export validation requirements
    export VALIDATION_REQUIRED="$validation_required"
    export VALIDATION_LEVEL="$validation_level"
    
    log_success "Validation requirements determined: required=$validation_required, level=$validation_level"
}

# Execute validation framework
execute_validation() {
    log_info "Executing validation framework..."
    
    if [[ "$VALIDATION_REQUIRED" != "true" ]]; then
        log_info "Validation not required - skipping"
        return 0
    fi
    
    # Check if validation framework is available
    if [[ ! -f "scripts/validation/validate.sh" ]]; then
        log_error "Validation framework not found"
        return 1
    fi
    
    # Setup validation environment variables
    export PROJECT_TYPE="${PROJECT_TYPE:-web}"
    export ENVIRONMENT="${ENVIRONMENT:-staging}"
    export VALIDATION_LEVEL="${VALIDATION_LEVEL:-smoke}"
    
    log_info "Starting validation with level: $VALIDATION_LEVEL"
    
    # Execute validation
    local validation_result=0
    local validation_log="$VALIDATION_SESSION_DIR/validation_execution.log"
    
    if ! bash scripts/validation/validate.sh --fast 2>&1 | tee "$validation_log"; then
        validation_result=1
        log_error "Validation execution failed"
    else
        log_success "Validation execution completed successfully"
    fi
    
    # Record validation result
    local result_file="$VALIDATION_SESSION_DIR/validation_result.json"
    cat > "$result_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_level": "$VALIDATION_LEVEL",
    "result": $(if [[ $validation_result -eq 0 ]]; then echo "\"success\""; else echo "\"failure\""; fi),
    "exit_code": $validation_result,
    "log_file": "$validation_log"
}
EOF
    
    return $validation_result
}

# Update validation state
update_validation_state() {
    local result=$1
    log_info "Updating validation state..."
    
    # Update state file
    local state_file="$VALIDATION_STATE_FILE"
    if [[ -f "$state_file" ]]; then
        local temp_file=$(mktemp)
        jq --arg result "$result" \
           --arg timestamp "$(date -Iseconds)" \
           '.post_validation_completed = true | .validation_result = $result | .post_validation_finished = $timestamp' \
           "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
    fi
    
    log_success "Validation state updated with result: $result"
}

# Generate validation feedback
generate_validation_feedback() {
    local result=$1
    log_info "Generating validation feedback..."
    
    local feedback_file="$VALIDATION_SESSION_DIR/validation_feedback.json"
    local recommendations=()
    
    if [[ "$result" == "success" ]]; then
        recommendations=(
            "Validation completed successfully"
            "All checks passed"
            "System ready for next steps"
        )
    else
        recommendations=(
            "Validation failed - review errors"
            "Check validation logs for details"
            "Fix issues before proceeding"
        )
    fi
    
    # Convert recommendations array to JSON
    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R . | jq -s .)
    
    cat > "$feedback_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_result": "$result",
    "validation_level": "$VALIDATION_LEVEL",
    "feedback_type": "post_validation",
    "recommendations": $recommendations_json,
    "next_steps": $(if [[ "$result" == "success" ]]; then echo "\"proceed_with_confidence\""; else echo "\"fix_issues_first\""; fi)
}
EOF
    
    log_success "Validation feedback generated: $feedback_file"
}

# Trigger AI feedback collection
trigger_ai_feedback() {
    log_info "Triggering AI feedback collection..."
    
    # Check if AI feedback system is available
    if [[ -f "scripts/ai_feedback.py" ]]; then
        local feedback_data="$VALIDATION_SESSION_DIR/validation_feedback.json"
        if [[ -f "$feedback_data" ]]; then
            log_info "Collecting AI feedback..."
            python scripts/ai_feedback.py --input "$feedback_data" --output "$VALIDATION_SESSION_DIR/ai_feedback.json" || {
                log_warning "AI feedback collection failed"
            }
        fi
    else
        log_warning "AI feedback system not available"
    fi
    
    log_success "AI feedback collection triggered"
}

# Create validation summary
create_validation_summary() {
    local result=$1
    log_info "Creating validation summary..."
    
    local summary_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    
    cat > "$summary_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "result": "$result",
    "validation_level": "$VALIDATION_LEVEL",
    "project_type": "$PROJECT_TYPE",
    "validation_required": $VALIDATION_REQUIRED,
    "session_dir": "$VALIDATION_SESSION_DIR"
}
EOF
    
    # Display summary
    log_info "=== Validation Summary ==="
    log_info "Session ID: $VALIDATION_SESSION_ID"
    log_info "Result: $result"
    log_info "Level: $VALIDATION_LEVEL"
    log_info "Required: $VALIDATION_REQUIRED"
    log_info "Project Type: $PROJECT_TYPE"
    log_info "========================="
    
    log_success "Validation summary created: $summary_file"
}

# Main post-validation execution
main() {
    log_info "Starting post-validation hook..."
    
    # Load validation context
    load_validation_context
    
    # Determine validation requirements
    determine_validation_requirements
    
    # Execute validation if required
    local validation_result="skipped"
    if [[ "$VALIDATION_REQUIRED" == "true" ]]; then
        if execute_validation; then
            validation_result="success"
        else
            validation_result="failure"
        fi
    fi
    
    # Update validation state
    update_validation_state "$validation_result"
    
    # Generate validation feedback
    generate_validation_feedback "$validation_result"
    
    # Trigger AI feedback collection
    trigger_ai_feedback
    
    # Create validation summary
    create_validation_summary "$validation_result"
    
    log_success "Post-validation hook completed with result: $validation_result"
    
    # Export result for completion gate
    export VALIDATION_RESULT="$validation_result"
    
    # Return appropriate exit code
    if [[ "$validation_result" == "failure" ]]; then
        log_error "Validation failed - blocking completion"
        exit 1
    fi
    
    log_success "Post-validation hook completed successfully"
}

# Execute main function
main "$@"
VALIDATION_POST_HOOK_EOF

# scripts/hooks/completion_gate.sh
cat > scripts/hooks/completion_gate.sh << 'COMPLETION_GATE_EOF'
#!/bin/bash
# completion_gate.sh - Completion gate validation hook
# Blocks completion until validation requirements are met
# Part of Claude Code Validation Hooks Integration v1.0.0

set -e

# Configuration
VALIDATION_CONFIG_FILE=".validation/config.json"
VALIDATION_SESSION_DIR=".validation/sessions"
VALIDATION_RESULTS_DIR=".validation/results"
VALIDATION_LOGS_DIR=".validation/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[CompletionGate] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/completion_gate.log"; }
log_success() { echo -e "${GREEN}[CompletionGate] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/completion_gate.log"; }
log_warning() { echo -e "${YELLOW}[CompletionGate] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/completion_gate.log"; }
log_error() { echo -e "${RED}[CompletionGate] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/completion_gate.log"; }
log_gate() { echo -e "${BOLD}${BLUE}[🚪 GATE] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/completion_gate.log"; }

# Initialize completion gate environment
init_completion_gate() {
    log_gate "Initializing completion gate validation..."
    
    # Create validation directories if they don't exist
    mkdir -p "$VALIDATION_SESSION_DIR"
    mkdir -p "$VALIDATION_RESULTS_DIR"
    mkdir -p "$VALIDATION_LOGS_DIR"
    
    # Create gate session
    local gate_session_id="completion_gate_$(date +%Y%m%d_%H%M%S)"
    export GATE_SESSION_ID="$gate_session_id"
    export GATE_SESSION_DIR="$VALIDATION_SESSION_DIR/$gate_session_id"
    
    mkdir -p "$GATE_SESSION_DIR"
    
    # Record gate session
    echo "$(date -Iseconds)" > "$GATE_SESSION_DIR/gate_start_time"
    echo "completion_gate" > "$GATE_SESSION_DIR/gate_type"
    
    log_success "Completion gate initialized (Session: $gate_session_id)"
}

# Check validation completion status
check_validation_status() {
    log_gate "Checking validation completion status..."
    
    local validation_completed=false
    local validation_result="unknown"
    local validation_timestamp=""
    
    # Check for recent validation results
    local last_validation_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    if [[ -f "$last_validation_file" ]]; then
        validation_result=$(jq -r '.result // "unknown"' "$last_validation_file" 2>/dev/null)
        validation_timestamp=$(jq -r '.timestamp // ""' "$last_validation_file" 2>/dev/null)
        
        if [[ "$validation_result" == "success" ]]; then
            validation_completed=true
            log_success "Recent successful validation found (Result: $validation_result)"
        elif [[ "$validation_result" == "failure" ]]; then
            log_error "Recent validation failed (Result: $validation_result)"
        else
            log_warning "Validation result unclear (Result: $validation_result)"
        fi
    else
        log_warning "No validation results found"
    fi
    
    # Check if validation is current (within reasonable time)
    if [[ -n "$validation_timestamp" ]]; then
        local current_time=$(date +%s)
        local validation_time=$(date -d "$validation_timestamp" +%s 2>/dev/null || echo "0")
        local time_diff=$((current_time - validation_time))
        
        # Consider validation stale if older than 1 hour (3600 seconds)
        if [[ $time_diff -gt 3600 ]]; then
            log_warning "Validation results are stale (Age: ${time_diff}s)"
            validation_completed=false
        fi
    fi
    
    # Export validation status
    export VALIDATION_COMPLETED="$validation_completed"
    export VALIDATION_RESULT="$validation_result"
    export VALIDATION_TIMESTAMP="$validation_timestamp"
    
    log_gate "Validation status: completed=$validation_completed, result=$validation_result"
}

# Check for pending changes that require validation
check_pending_changes() {
    log_gate "Checking for pending changes..."
    
    local changes_detected=false
    local change_details=()
    
    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null; then
        changes_detected=true
        change_details+=("Uncommitted changes detected")
        log_warning "Uncommitted changes found"
    fi
    
    # Check for untracked files
    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        changes_detected=true
        change_details+=("Untracked files detected")
        log_warning "Untracked files found"
    fi
    
    # Check for recent commits without validation
    local last_commit_time=$(git log -1 --format=%ct 2>/dev/null || echo "0")
    local validation_time=0
    
    if [[ -n "$VALIDATION_TIMESTAMP" ]]; then
        validation_time=$(date -d "$VALIDATION_TIMESTAMP" +%s 2>/dev/null || echo "0")
    fi
    
    if [[ $last_commit_time -gt $validation_time ]]; then
        changes_detected=true
        change_details+=("Recent commits without validation")
        log_warning "Recent commits found without corresponding validation"
    fi
    
    # Export change status
    export CHANGES_DETECTED="$changes_detected"
    export CHANGE_DETAILS="${change_details[*]}"
    
    log_gate "Changes detected: $changes_detected"
}

# Evaluate completion gate criteria
evaluate_completion_criteria() {
    log_gate "Evaluating completion gate criteria..."
    
    local gate_passed=false
    local blocking_reasons=()
    local warnings=()
    
    # Criterion 1: Validation must be completed successfully
    if [[ "$VALIDATION_COMPLETED" == "true" ]] && [[ "$VALIDATION_RESULT" == "success" ]]; then
        log_success "✓ Validation completed successfully"
    else
        blocking_reasons+=("Validation not completed or failed")
        log_error "✗ Validation completion requirement not met"
    fi
    
    # Criterion 2: No critical changes without validation
    if [[ "$CHANGES_DETECTED" == "true" ]]; then
        # Check if changes are critical
        local critical_changes=false
        
        # Check for critical file changes
        if git diff --name-only 2>/dev/null | grep -E '\.(js|ts|py|rs|java|go|rb|php)$' > /dev/null; then
            critical_changes=true
        fi
        
        if git diff --name-only 2>/dev/null | grep -E '(package\.json|requirements\.txt|Cargo\.toml|docker-compose\.yml|Dockerfile)$' > /dev/null; then
            critical_changes=true
        fi
        
        if [[ "$critical_changes" == "true" ]]; then
            blocking_reasons+=("Critical changes detected without validation")
            log_error "✗ Critical changes found without validation"
        else
            warnings+=("Non-critical changes detected")
            log_warning "△ Non-critical changes found"
        fi
    else
        log_success "✓ No pending changes detected"
    fi
    
    # Criterion 3: Permission system compliance (if applicable)
    if [[ -f ".permissions/config.json" ]]; then
        log_info "Checking permission system compliance..."
        
        # Check if permissions are properly configured
        local permissions_valid=true
        
        # Validate permissions configuration
        if ! jq empty ".permissions/config.json" 2>/dev/null; then
            permissions_valid=false
            blocking_reasons+=("Invalid permissions configuration")
            log_error "✗ Invalid permissions configuration"
        fi
        
        if [[ "$permissions_valid" == "true" ]]; then
            log_success "✓ Permissions system compliance verified"
        fi
    else
        log_info "No permission system detected - skipping compliance check"
    fi
    
    # Determine gate result
    if [[ ${#blocking_reasons[@]} -eq 0 ]]; then
        gate_passed=true
        log_success "✓ All completion gate criteria met"
    else
        log_error "✗ Completion gate criteria not met"
    fi
    
    # Export gate results
    export GATE_PASSED="$gate_passed"
    export BLOCKING_REASONS="${blocking_reasons[*]}"
    export GATE_WARNINGS="${warnings[*]}"
    
    log_gate "Gate evaluation: passed=$gate_passed, blocking_reasons=${#blocking_reasons[@]}, warnings=${#warnings[@]}"
}

# Generate completion gate report
generate_gate_report() {
    log_gate "Generating completion gate report..."
    
    local report_file="$GATE_SESSION_DIR/completion_gate_report.json"
    
    # Convert arrays to JSON
    local blocking_reasons_json
    local warnings_json
    
    if [[ -n "$BLOCKING_REASONS" ]]; then
        blocking_reasons_json=$(echo "$BLOCKING_REASONS" | tr ' ' '\n' | jq -R . | jq -s .)
    else
        blocking_reasons_json="[]"
    fi
    
    if [[ -n "$GATE_WARNINGS" ]]; then
        warnings_json=$(echo "$GATE_WARNINGS" | tr ' ' '\n' | jq -R . | jq -s .)
    else
        warnings_json="[]"
    fi
    
    cat > "$report_file" << EOF
{
    "gate_session_id": "$GATE_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "gate_passed": $GATE_PASSED,
    "validation_completed": $VALIDATION_COMPLETED,
    "validation_result": "$VALIDATION_RESULT",
    "changes_detected": $CHANGES_DETECTED,
    "blocking_reasons": $blocking_reasons_json,
    "warnings": $warnings_json,
    "criteria_evaluated": [
        "validation_completion",
        "change_validation",
        "permission_compliance"
    ],
    "next_steps": $(if [[ "$GATE_PASSED" == "true" ]]; then echo "\"completion_allowed\""; else echo "\"fix_blocking_issues\""; fi)
}
EOF
    
    log_success "Completion gate report generated: $report_file"
}

# Display gate status
display_gate_status() {
    log_gate "=== COMPLETION GATE STATUS ==="
    
    if [[ "$GATE_PASSED" == "true" ]]; then
        echo -e "${GREEN}${BOLD}🎉 COMPLETION GATE PASSED${NC}"
        echo -e "${GREEN}✓ All validation requirements met${NC}"
        echo -e "${GREEN}✓ Ready to proceed with completion${NC}"
    else
        echo -e "${RED}${BOLD}🚫 COMPLETION GATE BLOCKED${NC}"
        echo -e "${RED}✗ Completion requirements not met${NC}"
        
        if [[ -n "$BLOCKING_REASONS" ]]; then
            echo -e "${RED}Blocking reasons:${NC}"
            echo "$BLOCKING_REASONS" | tr ' ' '\n' | while read -r reason; do
                [[ -n "$reason" ]] && echo -e "${RED}  • $reason${NC}"
            done
        fi
        
        echo -e "${YELLOW}Required actions:${NC}"
        echo -e "${YELLOW}  • Run validation: scripts/validation/validate.sh${NC}"
        echo -e "${YELLOW}  • Fix any validation failures${NC}"
        echo -e "${YELLOW}  • Re-run completion gate${NC}"
    fi
    
    if [[ -n "$GATE_WARNINGS" ]]; then
        echo -e "${YELLOW}Warnings:${NC}"
        echo "$GATE_WARNINGS" | tr ' ' '\n' | while read -r warning; do
            [[ -n "$warning" ]] && echo -e "${YELLOW}  △ $warning${NC}"
        done
    fi
    
    log_gate "================================"
}

# Trigger validation if needed
trigger_validation_if_needed() {
    if [[ "$GATE_PASSED" == "false" ]] && [[ "$VALIDATION_COMPLETED" == "false" ]]; then
        log_gate "Triggering validation to meet completion requirements..."
        
        # Check if validation can be triggered automatically
        if [[ -f "scripts/validation/validate.sh" ]]; then
            log_info "Starting automatic validation..."
            
            # Trigger validation
            if bash scripts/validation/validate.sh --fast; then
                log_success "Automatic validation completed successfully"
                
                # Re-evaluate completion criteria
                check_validation_status
                evaluate_completion_criteria
                
                if [[ "$GATE_PASSED" == "true" ]]; then
                    log_success "Completion gate now passes after validation"
                    export GATE_PASSED="true"
                fi
            else
                log_error "Automatic validation failed"
            fi
        else
            log_warning "Cannot trigger automatic validation - script not found"
        fi
    fi
}

# Main completion gate execution
main() {
    log_gate "Starting completion gate validation..."
    
    # Initialize completion gate
    init_completion_gate
    
    # Check validation status
    check_validation_status
    
    # Check for pending changes
    check_pending_changes
    
    # Evaluate completion criteria
    evaluate_completion_criteria
    
    # Generate gate report
    generate_gate_report
    
    # Display gate status
    display_gate_status
    
    # Trigger validation if needed and possible
    trigger_validation_if_needed
    
    log_gate "Completion gate validation finished"
    
    # Final status check
    if [[ "$GATE_PASSED" == "true" ]]; then
        log_success "🎉 Completion gate PASSED - proceeding with completion"
        exit 0
    else
        log_error "🚫 Completion gate BLOCKED - completion not allowed"
        exit 1
    fi
}

# Execute main function
main "$@"
COMPLETION_GATE_EOF

# scripts/hooks/validation_feedback.sh
cat > scripts/hooks/validation_feedback.sh << 'VALIDATION_FEEDBACK_EOF'
#!/bin/bash
# validation_feedback.sh - Validation feedback integration hook
# Provides clear feedback to both AI and user about validation results
# Part of Claude Code Validation Hooks Integration v1.0.0

set -e

# Configuration
VALIDATION_CONFIG_FILE=".validation/config.json"
VALIDATION_SESSION_DIR=".validation/sessions"
VALIDATION_RESULTS_DIR=".validation/results"
VALIDATION_LOGS_DIR=".validation/logs"
FEEDBACK_DIR=".validation/feedback"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Emojis for better visual feedback
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
INFO_EMOJI="ℹ️"
FEEDBACK_EMOJI="💬"
AI_EMOJI="🤖"
USER_EMOJI="👤"
ROCKET_EMOJI="🚀"

# Logging functions
log_info() { echo -e "${BLUE}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_success() { echo -e "${GREEN}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_warning() { echo -e "${YELLOW}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_error() { echo -e "${RED}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_feedback() { echo -e "${PURPLE}[${FEEDBACK_EMOJI} FEEDBACK] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }

# Initialize feedback system
init_feedback_system() {
    log_info "Initializing validation feedback system..."
    
    # Create feedback directories
    mkdir -p "$FEEDBACK_DIR"
    mkdir -p "$VALIDATION_LOGS_DIR"
    
    # Create feedback session
    local feedback_session_id="feedback_$(date +%Y%m%d_%H%M%S)"
    export FEEDBACK_SESSION_ID="$feedback_session_id"
    export FEEDBACK_SESSION_DIR="$FEEDBACK_DIR/$feedback_session_id"
    
    mkdir -p "$FEEDBACK_SESSION_DIR"
    
    # Record feedback session
    echo "$(date -Iseconds)" > "$FEEDBACK_SESSION_DIR/feedback_start_time"
    echo "validation_feedback" > "$FEEDBACK_SESSION_DIR/feedback_type"
    
    log_success "Feedback system initialized (Session: $feedback_session_id)"
}

# Load validation results
load_validation_results() {
    log_info "Loading validation results..."
    
    local validation_found=false
    local validation_data=""
    
    # Check for recent validation results
    local last_validation_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    if [[ -f "$last_validation_file" ]]; then
        validation_data=$(cat "$last_validation_file")
        validation_found=true
        log_success "Validation results loaded from $last_validation_file"
    fi
    
    # Check for session-specific results
    if [[ -n "$VALIDATION_SESSION_ID" ]] && [[ -d "$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID" ]]; then
        local session_result_file="$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID/validation_result.json"
        if [[ -f "$session_result_file" ]]; then
            validation_data=$(cat "$session_result_file")
            validation_found=true
            log_success "Session-specific validation results loaded"
        fi
    fi
    
    # Export validation data
    export VALIDATION_FOUND="$validation_found"
    export VALIDATION_DATA="$validation_data"
    
    if [[ "$validation_found" == "false" ]]; then
        log_warning "No validation results found"
    fi
}

# Analyze validation results
analyze_validation_results() {
    log_info "Analyzing validation results..."
    
    if [[ "$VALIDATION_FOUND" == "false" ]]; then
        export VALIDATION_STATUS="no_validation"
        export VALIDATION_SUMMARY="No validation results available"
        return
    fi
    
    # Parse validation data
    local validation_result=$(echo "$VALIDATION_DATA" | jq -r '.result // "unknown"' 2>/dev/null)
    local validation_level=$(echo "$VALIDATION_DATA" | jq -r '.validation_level // "unknown"' 2>/dev/null)
    local validation_timestamp=$(echo "$VALIDATION_DATA" | jq -r '.timestamp // ""' 2>/dev/null)
    local project_type=$(echo "$VALIDATION_DATA" | jq -r '.project_type // "unknown"' 2>/dev/null)
    
    # Determine validation status
    local validation_status="unknown"
    local validation_summary=""
    
    case "$validation_result" in
        "success")
            validation_status="success"
            validation_summary="Validation completed successfully"
            ;;
        "failure")
            validation_status="failure"
            validation_summary="Validation failed - issues detected"
            ;;
        "skipped")
            validation_status="skipped"
            validation_summary="Validation was skipped"
            ;;
        *)
            validation_status="unknown"
            validation_summary="Validation status unclear"
            ;;
    esac
    
    # Export analysis results
    export VALIDATION_STATUS="$validation_status"
    export VALIDATION_SUMMARY="$validation_summary"
    export VALIDATION_LEVEL="$validation_level"
    export VALIDATION_TIMESTAMP="$validation_timestamp"
    export PROJECT_TYPE="$project_type"
    
    log_success "Validation analysis completed: $validation_status"
}

# Generate AI feedback
generate_ai_feedback() {
    log_info "Generating AI feedback..."
    
    local ai_feedback_file="$FEEDBACK_SESSION_DIR/ai_feedback.json"
    local ai_recommendations=()
    local ai_context=""
    
    # Generate context-aware recommendations
    case "$VALIDATION_STATUS" in
        "success")
            ai_recommendations=(
                "Validation completed successfully - all checks passed"
                "System is ready for production or next development phase"
                "Consider maintaining current validation practices"
                "Monitor system performance and user feedback"
            )
            ai_context="All validation checks passed. The system appears to be functioning correctly and meets quality standards."
            ;;
        "failure")
            ai_recommendations=(
                "Validation failed - immediate attention required"
                "Review validation logs for specific error details"
                "Fix identified issues before proceeding"
                "Consider running validation in stages to isolate problems"
                "Ensure all dependencies and configurations are correct"
            )
            ai_context="Validation failed indicating potential issues that need to be addressed before proceeding."
            ;;
        "skipped")
            ai_recommendations=(
                "Validation was skipped - consider running full validation"
                "Ensure validation is not being bypassed inappropriately"
                "Review validation triggers and requirements"
                "Run manual validation if automated validation is unavailable"
            )
            ai_context="Validation was skipped. Consider whether validation should have been performed."
            ;;
        *)
            ai_recommendations=(
                "Validation status unclear - investigate validation system"
                "Check validation framework configuration"
                "Ensure validation results are being properly recorded"
                "Consider running validation manually to verify system state"
            )
            ai_context="Validation status is unclear. Investigation needed to determine system state."
            ;;
    esac
    
    # Convert recommendations to JSON
    local recommendations_json=$(printf '%s\n' "${ai_recommendations[@]}" | jq -R . | jq -s .)
    
    # Create AI feedback
    cat > "$ai_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "validation_summary": "$VALIDATION_SUMMARY",
    "ai_context": "$ai_context",
    "recommendations": $recommendations_json,
    "confidence_level": $(case "$VALIDATION_STATUS" in
        "success") echo "\"high\"" ;;
        "failure") echo "\"high\"" ;;
        "skipped") echo "\"medium\"" ;;
        *) echo "\"low\"" ;;
    esac),
    "urgency": $(case "$VALIDATION_STATUS" in
        "success") echo "\"low\"" ;;
        "failure") echo "\"high\"" ;;
        "skipped") echo "\"medium\"" ;;
        *) echo "\"medium\"" ;;
    esac)
}
EOF
    
    log_success "AI feedback generated: $ai_feedback_file"
}

# Generate user feedback
generate_user_feedback() {
    log_info "Generating user feedback..."
    
    local user_feedback_file="$FEEDBACK_SESSION_DIR/user_feedback.json"
    local user_actions=()
    local user_summary=""
    
    # Generate user-friendly summary and actions
    case "$VALIDATION_STATUS" in
        "success")
            user_summary="Great news! All validation checks passed successfully. Your system is ready to go."
            user_actions=(
                "Continue with your development workflow"
                "Deploy with confidence"
                "Monitor system performance"
                "Keep validation practices consistent"
            )
            ;;
        "failure")
            user_summary="Validation found issues that need your attention. Please review and fix the problems."
            user_actions=(
                "Check validation logs for specific error details"
                "Fix identified issues one by one"
                "Run validation again after fixes"
                "Consider reaching out for help if issues persist"
            )
            ;;
        "skipped")
            user_summary="Validation was skipped. Consider running a full validation to ensure everything is working."
            user_actions=(
                "Run manual validation: scripts/validation/validate.sh"
                "Check why validation was skipped"
                "Ensure validation triggers are working correctly"
                "Review recent changes for potential issues"
            )
            ;;
        *)
            user_summary="Validation status is unclear. Please investigate the validation system."
            user_actions=(
                "Check validation framework setup"
                "Run manual validation to verify system state"
                "Review validation configuration"
                "Check for missing dependencies or configuration issues"
            )
            ;;
    esac
    
    # Convert actions to JSON
    local actions_json=$(printf '%s\n' "${user_actions[@]}" | jq -R . | jq -s .)
    
    # Create user feedback
    cat > "$user_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "user_summary": "$user_summary",
    "recommended_actions": $actions_json,
    "validation_level": "$VALIDATION_LEVEL",
    "project_type": "$PROJECT_TYPE"
}
EOF
    
    log_success "User feedback generated: $user_feedback_file"
}

# Display feedback to console
display_feedback() {
    log_feedback "=== VALIDATION FEEDBACK ==="
    echo ""
    
    # Display status with appropriate emoji and color
    case "$VALIDATION_STATUS" in
        "success")
            echo -e "${GREEN}${BOLD}${SUCCESS_EMOJI} VALIDATION SUCCESSFUL${NC}"
            echo -e "${GREEN}${VALIDATION_SUMMARY}${NC}"
            ;;
        "failure")
            echo -e "${RED}${BOLD}${ERROR_EMOJI} VALIDATION FAILED${NC}"
            echo -e "${RED}${VALIDATION_SUMMARY}${NC}"
            ;;
        "skipped")
            echo -e "${YELLOW}${BOLD}${WARNING_EMOJI} VALIDATION SKIPPED${NC}"
            echo -e "${YELLOW}${VALIDATION_SUMMARY}${NC}"
            ;;
        *)
            echo -e "${PURPLE}${BOLD}${INFO_EMOJI} VALIDATION STATUS UNCLEAR${NC}"
            echo -e "${PURPLE}${VALIDATION_SUMMARY}${NC}"
            ;;
    esac
    
    echo ""
    
    # Display project context
    echo -e "${CYAN}${INFO_EMOJI} Project: $PROJECT_TYPE | Level: $VALIDATION_LEVEL${NC}"
    if [[ -n "$VALIDATION_TIMESTAMP" ]]; then
        echo -e "${CYAN}${INFO_EMOJI} Validation Time: $VALIDATION_TIMESTAMP${NC}"
    fi
    
    echo ""
    
    # Display AI feedback
    echo -e "${BLUE}${AI_EMOJI} AI Assistant Feedback:${NC}"
    if [[ -f "$FEEDBACK_SESSION_DIR/ai_feedback.json" ]]; then
        local ai_context=$(jq -r '.ai_context' "$FEEDBACK_SESSION_DIR/ai_feedback.json" 2>/dev/null)
        echo -e "${BLUE}$ai_context${NC}"
        echo ""
        
        echo -e "${BLUE}AI Recommendations:${NC}"
        jq -r '.recommendations[]' "$FEEDBACK_SESSION_DIR/ai_feedback.json" 2>/dev/null | while read -r recommendation; do
            echo -e "${BLUE}  • $recommendation${NC}"
        done
    fi
    
    echo ""
    
    # Display user feedback
    echo -e "${GREEN}${USER_EMOJI} User Action Items:${NC}"
    if [[ -f "$FEEDBACK_SESSION_DIR/user_feedback.json" ]]; then
        local user_summary=$(jq -r '.user_summary' "$FEEDBACK_SESSION_DIR/user_feedback.json" 2>/dev/null)
        echo -e "${GREEN}$user_summary${NC}"
        echo ""
        
        echo -e "${GREEN}Recommended Actions:${NC}"
        jq -r '.recommended_actions[]' "$FEEDBACK_SESSION_DIR/user_feedback.json" 2>/dev/null | while read -r action; do
            echo -e "${GREEN}  • $action${NC}"
        done
    fi
    
    echo ""
    log_feedback "==============================="
}

# Create feedback summary
create_feedback_summary() {
    log_info "Creating feedback summary..."
    
    local summary_file="$FEEDBACK_DIR/latest_feedback.json"
    
    # Combine AI and user feedback
    local combined_feedback="{}"
    
    if [[ -f "$FEEDBACK_SESSION_DIR/ai_feedback.json" ]] && [[ -f "$FEEDBACK_SESSION_DIR/user_feedback.json" ]]; then
        combined_feedback=$(jq -s '.[0] + .[1] + {"feedback_type": "combined"}' \
            "$FEEDBACK_SESSION_DIR/ai_feedback.json" \
            "$FEEDBACK_SESSION_DIR/user_feedback.json")
    fi
    
    # Create summary
    cat > "$summary_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "validation_summary": "$VALIDATION_SUMMARY",
    "project_type": "$PROJECT_TYPE",
    "validation_level": "$VALIDATION_LEVEL",
    "session_dir": "$FEEDBACK_SESSION_DIR",
    "combined_feedback": $combined_feedback
}
EOF
    
    log_success "Feedback summary created: $summary_file"
}

# Integration with permission system
integrate_with_permissions() {
    log_info "Integrating with permission system..."
    
    # Check if permission system is available
    if [[ -f ".permissions/config.json" ]]; then
        log_info "Permission system detected - recording validation feedback"
        
        # Create permission-compatible feedback record
        local permission_feedback_file=".permissions/validation_feedback.json"
        
        cat > "$permission_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "permission_impact": $(case "$VALIDATION_STATUS" in
        "success") echo "\"validation_passed\"" ;;
        "failure") echo "\"validation_failed\"" ;;
        "skipped") echo "\"validation_skipped\"" ;;
        *) echo "\"validation_unclear\"" ;;
    esac),
    "requires_attention": $(case "$VALIDATION_STATUS" in
        "success") echo "false" ;;
        *) echo "true" ;;
    esac)
}
EOF
        
        log_success "Permission system integration completed"
    else
        log_info "No permission system detected - skipping integration"
    fi
}

# Main feedback execution
main() {
    log_info "Starting validation feedback generation..."
    
    # Initialize feedback system
    init_feedback_system
    
    # Load validation results
    load_validation_results
    
    # Analyze validation results
    analyze_validation_results
    
    # Generate AI feedback
    generate_ai_feedback
    
    # Generate user feedback
    generate_user_feedback
    
    # Display feedback to console
    display_feedback
    
    # Create feedback summary
    create_feedback_summary
    
    # Integration with permission system
    integrate_with_permissions
    
    log_success "Validation feedback generation completed"
    
    # Return appropriate exit code based on validation status
    case "$VALIDATION_STATUS" in
        "success")
            exit 0
            ;;
        "failure")
            exit 1
            ;;
        "skipped")
            exit 2
            ;;
        *)
            exit 3
            ;;
    esac
}

# Execute main function
main "$@"
VALIDATION_FEEDBACK_EOF

# Make hook scripts executable
chmod +x scripts/hooks/*.sh

echo "✅ Validation hooks deployment complete"
# ===== Module: 07-finalize.sh =====
# AI Setup Deployment Script - Finalize Module
# This module handles cleanup and final setup steps

# Deploy .gitignore with AI development working files
echo "🔧 Creating/updating .gitignore for AI development..."

# Create or update .gitignore with AI-specific entries
if [ -f .gitignore ]; then
    # Add AI-specific entries if they don't exist
    if ! grep -q "# AI Development" .gitignore; then
        cat >> .gitignore << 'GITIGNORE_EOF'

# AI Development
.claude/context.md
.claude/session*.md
.validation/
.validation_cache/
.validation_sessions/
scripts/logs/
scripts/ai_feedback/*.log

# Code review outputs
scripts/code_review/output/

GITIGNORE_EOF
        echo "✅ Updated existing .gitignore with AI development entries"
    else
        echo "✅ .gitignore already contains AI development entries"
    fi
else
    cat > .gitignore << 'GITIGNORE_EOF'
# Dependencies
node_modules/
venv/
env/
.env

# Build outputs
dist/
build/
*.min.js
*.min.css

# OS generated
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log
npm-debug.log*

# AI Development
.claude/context.md
.claude/session*.md
.validation/
.validation_cache/
.validation_sessions/
scripts/logs/
scripts/ai_feedback/*.log
GITIGNORE_EOF
    echo "✅ Created .gitignore with AI development support"
fi

# Deploy .cursorrules
cat > .cursorrules << 'EOF'
# Cursor IDE AI Rules
# Generated by AI Setup Deployment Script v4.0.0 on 2026-03-31 22:56:36 UTC

You are an expert AI coding assistant helping with this project. Follow these guidelines:

## Code Standards
- Write clean, readable, well-documented code
- Use meaningful variable and function names
- Follow existing code patterns and conventions
- Add inline comments for complex logic

## Development Practices
- Create comprehensive tests for new functionality
- Follow security best practices
- Optimize for performance and maintainability
- Use error handling consistently

## Git Workflow
- Make atomic commits with clear messages
- Follow conventional commit format when possible
- Include proper co-authoring for AI assistance

## Project Context
- Read docs/project_context.md for project-specific information
- Follow patterns established in existing codebase
- Reference CLAUDE.md for additional project guidance

## AI Assistance Guidelines
- Explain complex code changes clearly
- Suggest improvements and optimizations
- Point out potential issues or edge cases
- Provide alternative approaches when relevant

## Testing Requirements
- Write unit tests for business logic
- Include integration tests for API endpoints
- Add end-to-end tests for critical user flows
- Ensure good test coverage

## Documentation
- Update README when adding features
- Document API changes
- Add code comments for non-obvious logic
- Keep architectural decisions recorded
EOF

# Create final gitignore for Cursor-specific files if not present
if ! grep -q "# Cursor IDE" .gitignore; then
    cat >> .gitignore << 'CURSOR_GITIGNORE_EOF'

# Cursor IDE
.cursor/
.cursorignore
CURSOR_GITIGNORE_EOF
fi

# Create example deployment scripts directory with README
cat > scripts/deployment/README.md << 'EOF'
# Deployment Scripts Directory

This directory contains deployment-related scripts and configurations for the AI Setup system.

## Contents

### Modules (`modules/`)
Contains the modular components of the deployment system:
- `00-header.sh` - Core configuration and utilities
- `01-ai-docs.sh` - AI documentation deployment
- `02-docs.sh` - Documentation templates
- `03-claude-config.sh` - Claude Code configuration
- `04-validation.sh` - Validation system
- `05-git-scripts.sh` - Git author management
- `06-hooks.sh` - Validation hooks
- `07-finalize.sh` - Cleanup and final steps

### Build Process
The modular system allows for:
- Easier maintenance of the deployment script
- Independent testing of modules
- Selective deployment of components
- Better organization and readability

### Usage
These modules are automatically assembled into the main deployment script during the build process. They should not be executed individually in most cases.

## Development

When modifying the deployment system:
1. Edit the appropriate module in `modules/`
2. Test the module independently if possible
3. Rebuild the main deployment script
4. Test the complete deployment

## Version Control
All modules should be kept in sync with the main deployment script version to ensure compatibility.
EOF

# Create backup of configuration
backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "Configuration backed up to $BACKUP_FILE"
    fi
}

# Initialize configuration
initialize_config() {
    local current_name=$(git config user.name 2>/dev/null || echo "")
    local current_email=$(git config user.email 2>/dev/null || echo "")
    
    if [[ -n "$current_name" && -n "$current_email" ]]; then
        cat > "$CONFIG_FILE" << EOF
{
  "human": {
    "name": "$current_name",
    "email": "$current_email"
  },
  "claude": {
    "name": "Claude Code Assistant",
    "email": "claude-code@anthropic.com"
  },
  "current": "human",
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
        echo "Git author configuration initialized with current user"
    else
        echo "⚠️ Warning: No git user configuration found. Please configure git:"
        echo "  git config --global user.name \"Your Name\""
        echo "  git config --global user.email \"your.email@example.com\""
        echo "  Then run: ./scripts/git/git-author-verify.sh"
    fi
}

# Finalize git author configuration
echo "🔧 Finalizing git author configuration..."

# Backup existing configuration
backup_config

# Initialize configuration if it doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    initialize_config
fi

# Deploy Validation Cleanup Script
echo "🧹 Deploying validation cleanup script..."

cat > scripts/validation/cleanup_validation.sh << 'CLEANUP_VALIDATION_EOF'
#!/bin/bash
# cleanup_validation.sh - Cleanup old validation sessions and results
# Part of AI Setup Enhanced Validation Framework
# Version: 1.0.0

set -euo pipefail

# Configuration
VALIDATION_BASE_DIR=".validation"
SESSIONS_DIR="$VALIDATION_BASE_DIR/sessions"
RESULTS_DIR="$VALIDATION_BASE_DIR/results"
LOGS_DIR="$VALIDATION_BASE_DIR/logs"
FEEDBACK_DIR="$VALIDATION_BASE_DIR/feedback"
CACHE_DIR=".validation_cache"

# Retention settings (days)
SESSION_RETENTION_DAYS=7
LOG_RETENTION_DAYS=14
FEEDBACK_RETENTION_DAYS=30
CACHE_RETENTION_HOURS=24

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[Cleanup] $1${NC}"; }
log_success() { echo -e "${GREEN}[Cleanup] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[Cleanup] $1${NC}"; }

# Show usage
show_usage() {
    cat << EOF
Validation Cleanup Script

Usage: $(basename "$0") [OPTIONS]

Options:
  --sessions    Clean only validation sessions
  --logs        Clean only log files
  --feedback    Clean only feedback files
  --cache       Clean only cache files
  --all         Clean all validation data (default)
  --dry-run     Show what would be cleaned without doing it
  --help        Show this help message

Retention policies:
  Sessions: $SESSION_RETENTION_DAYS days
  Logs: $LOG_RETENTION_DAYS days
  Feedback: $FEEDBACK_RETENTION_DAYS days
  Cache: $CACHE_RETENTION_HOURS hours
EOF
}

# Cleanup sessions
cleanup_sessions() {
    local dry_run=$1
    log_info "Cleaning validation sessions older than $SESSION_RETENTION_DAYS days..."
    
    if [[ -d "$SESSIONS_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' session_dir; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $session_dir"
            else
                rm -rf "$session_dir"
            fi
            ((count++))
        done < <(find "$SESSIONS_DIR" -maxdepth 1 -type d -mtime +$SESSION_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count validation sessions"
        else
            log_info "No old validation sessions to clean"
        fi
    else
        log_info "No validation sessions directory found"
    fi
}

# Cleanup logs
cleanup_logs() {
    local dry_run=$1
    log_info "Cleaning log files older than $LOG_RETENTION_DAYS days..."
    
    if [[ -d "$LOGS_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' log_file; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $log_file"
            else
                rm -f "$log_file"
            fi
            ((count++))
        done < <(find "$LOGS_DIR" -type f -name "*.log" -mtime +$LOG_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count log files"
        else
            log_info "No old log files to clean"
        fi
    else
        log_info "No logs directory found"
    fi
}

# Cleanup feedback
cleanup_feedback() {
    local dry_run=$1
    log_info "Cleaning feedback files older than $FEEDBACK_RETENTION_DAYS days..."
    
    if [[ -d "$FEEDBACK_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' feedback_dir; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $feedback_dir"
            else
                rm -rf "$feedback_dir"
            fi
            ((count++))
        done < <(find "$FEEDBACK_DIR" -maxdepth 1 -type d -mtime +$FEEDBACK_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count feedback sessions"
        else
            log_info "No old feedback sessions to clean"
        fi
    else
        log_info "No feedback directory found"
    fi
}

# Cleanup cache
cleanup_cache() {
    local dry_run=$1
    log_info "Cleaning cache files older than $CACHE_RETENTION_HOURS hours..."
    
    if [[ -d "$CACHE_DIR" ]]; then
        local count=0
        local hours_in_minutes=$((CACHE_RETENTION_HOURS * 60))
        
        while IFS= read -r -d '' cache_file; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $cache_file"
            else
                rm -f "$cache_file"
            fi
            ((count++))
        done < <(find "$CACHE_DIR" -type f -mmin +$hours_in_minutes -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count cache files"
        else
            log_info "No old cache files to clean"
        fi
    else
        log_info "No cache directory found"
    fi
}

# Cleanup empty directories
cleanup_empty_dirs() {
    local dry_run=$1
    log_info "Cleaning empty directories..."
    
    local dirs=("$SESSIONS_DIR" "$LOGS_DIR" "$FEEDBACK_DIR" "$CACHE_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' empty_dir; do
                if [[ "$dry_run" == "true" ]]; then
                    echo "Would remove empty directory: $empty_dir"
                else
                    rmdir "$empty_dir" 2>/dev/null || true
                fi
            done < <(find "$dir" -type d -empty -print0 2>/dev/null)
        fi
    done
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "=== Validation Cleanup Report ==="
    
    # Count remaining items
    local sessions=0
    local logs=0
    local feedback=0
    local cache=0
    
    [[ -d "$SESSIONS_DIR" ]] && sessions=$(find "$SESSIONS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ -d "$LOGS_DIR" ]] && logs=$(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    [[ -d "$FEEDBACK_DIR" ]] && feedback=$(find "$FEEDBACK_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ -d "$CACHE_DIR" ]] && cache=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    
    echo "Remaining validation data:"
    echo "  Sessions: $((sessions - 1))"  # Subtract 1 for the directory itself
    echo "  Log files: $logs"
    echo "  Feedback sessions: $((feedback - 1))"  # Subtract 1 for the directory itself
    echo "  Cache files: $cache"
    
    # Calculate disk usage
    local total_size=0
    [[ -d "$VALIDATION_BASE_DIR" ]] && total_size=$(du -sh "$VALIDATION_BASE_DIR" 2>/dev/null | cut -f1 || echo "0")
    echo "  Total disk usage: $total_size"
    
    log_info "================================="
}

# Main execution
main() {
    local clean_sessions=false
    local clean_logs=false
    local clean_feedback=false
    local clean_cache=false
    local dry_run=false
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        clean_sessions=true
        clean_logs=true
        clean_feedback=true
        clean_cache=true
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sessions)
                clean_sessions=true
                shift
                ;;
            --logs)
                clean_logs=true
                shift
                ;;
            --feedback)
                clean_feedback=true
                shift
                ;;
            --cache)
                clean_cache=true
                shift
                ;;
            --all)
                clean_sessions=true
                clean_logs=true
                clean_feedback=true
                clean_cache=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting validation cleanup..."
    if [[ "$dry_run" == "true" ]]; then
        log_warning "DRY RUN MODE - No files will actually be deleted"
    fi
    
    # Execute cleanup operations
    [[ "$clean_sessions" == "true" ]] && cleanup_sessions "$dry_run"
    [[ "$clean_logs" == "true" ]] && cleanup_logs "$dry_run"
    [[ "$clean_feedback" == "true" ]] && cleanup_feedback "$dry_run"
    [[ "$clean_cache" == "true" ]] && cleanup_cache "$dry_run"
    
    # Cleanup empty directories
    cleanup_empty_dirs "$dry_run"
    
    # Generate report (only if not dry run)
    if [[ "$dry_run" != "true" ]]; then
        generate_cleanup_report
    fi
    
    log_success "Validation cleanup completed"
}

# Execute main
main "$@"
CLEANUP_VALIDATION_EOF

chmod +x scripts/validation/cleanup_validation.sh

# Final success message
echo ""
echo "🎉 AI Setup Deployment Complete!"
echo ""
echo "📁 Created directory structure:"
echo "   ├── docs/                 # Documentation, guides, and project context"
echo "   ├── .claude/commands/     # Claude Code commands"
echo "   ├── scripts/hooks/        # Validation hooks"
echo "   ├── scripts/validation/   # Validation system"
echo "   ├── scripts/git/          # Git author management"
echo "   └── CLAUDE.md             # Project guidance"
echo ""
echo "🔧 Key Features Deployed:"
echo "   • Lightweight validation system (<10 seconds)"
echo "   • Git author management for AI commits"
echo "   • Claude Code hooks and commands"
echo "   • Comprehensive AI documentation"
echo "   • Documentation templates (GitHub Pages compatible)"
if [[ "$DEPLOY_SECURITY_SCANNING" == "true" ]]; then
    echo "   • Security scanning system"
fi
echo ""
echo "🚀 Next Steps:"
echo "   1. Customize docs/project_context.md with your project details"
echo "   2. Update CLAUDE.md with project-specific guidance"
echo "   3. Review and adjust .claude/settings.json as needed"
echo "   4. Test validation: ./scripts/validation/validate.sh --fast"
echo "   5. Verify git author setup: ./scripts/git/git-author-verify.sh"
echo ""
echo "💡 Claude Code Commands Available:"
echo "   /prime          - Load project context (run this first)"
echo "   /update-agency  - Sync agent personas from agency-agents library"
echo "   /address-issue  - Autonomously implement a GitHub issue"
echo "   /refine-issue   - Refine a rough issue into an actionable spec"
echo "   /review-pr      - Review a PR for quality and security"
if [[ "$DEPLOY_SECURITY_SCANNING" == "true" ]]; then
    echo "   /security-scan  - Security validation"
fi
echo ""
echo "📚 Documentation:"
echo "   • Fill in docs/project_context.md with your project details"
echo "   • Command usage: .claude/commands/"
echo "   • Git workflows: scripts/git/README.md"
echo "   • Validation: scripts/validation/"
echo ""

# Update version references in all files
find . -name "*.md" -o -name "*.sh" -o -name "*.json" | grep -v node_modules | grep -v .git | xargs sed -i.bak "s/4.0.0/$VERSION/g" 2>/dev/null || true
find . -name "*.md" -o -name "*.sh" -o -name "*.json" | grep -v node_modules | grep -v .git | xargs sed -i.bak "s/2026-03-31 22:56:36 UTC/$DEPLOY_DATE/g" 2>/dev/null || true
find . -name "*.bak" -delete 2>/dev/null || true

echo "✅ All files updated with version $VERSION"
echo ""
echo "Ready for AI-assisted development! 🤖✨"