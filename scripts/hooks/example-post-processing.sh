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
