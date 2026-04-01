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
