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
