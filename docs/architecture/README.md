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
