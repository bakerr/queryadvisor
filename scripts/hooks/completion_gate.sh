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
