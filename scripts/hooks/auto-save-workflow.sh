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
