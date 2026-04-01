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
