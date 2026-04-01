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
