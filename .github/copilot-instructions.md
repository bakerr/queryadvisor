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
