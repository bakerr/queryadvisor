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
