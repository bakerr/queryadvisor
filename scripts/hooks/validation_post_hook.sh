#!/bin/bash
# validation_post_hook.sh - Post-tool validation hook
# Automatically triggered after AI tool usage to execute validation
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
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_success() { echo -e "${GREEN}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_warning() { echo -e "${YELLOW}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }
log_error() { echo -e "${RED}[PostValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/post_hook.log"; }

# Load validation session context
load_validation_context() {
    log_info "Loading validation session context..."
    
    # Check if validation session exists
    if [[ -z "$VALIDATION_SESSION_ID" ]]; then
        log_warning "No validation session ID found - starting new session"
        export VALIDATION_SESSION_ID="post_validation_$(date +%Y%m%d_%H%M%S)"
        export VALIDATION_SESSION_DIR="$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID"
        mkdir -p "$VALIDATION_SESSION_DIR"
    fi
    
    # Load validation state
    local state_file="$VALIDATION_SESSION_DIR/validation_state.json"
    if [[ -f "$state_file" ]]; then
        log_info "Loading validation state from $state_file"
        export VALIDATION_STATE_FILE="$state_file"
    else
        log_warning "No validation state file found - creating new state"
        mkdir -p "$VALIDATION_SESSION_DIR"
        cat > "$state_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "status": "post_validation",
    "pre_validation_completed": false,
    "post_validation_completed": false,
    "completion_gate_passed": false,
    "validation_required": true,
    "post_validation_started": "$(date -Iseconds)"
}
EOF
        export VALIDATION_STATE_FILE="$state_file"
    fi
    
    log_success "Validation context loaded"
}

# Determine validation requirements
determine_validation_requirements() {
    log_info "Determining validation requirements..."
    
    local validation_required=false
    local validation_level="smoke"
    
    # Check if files were modified
    if git diff --quiet HEAD~1 HEAD 2>/dev/null; then
        log_info "No changes detected since last commit"
    else
        log_info "Changes detected - validation required"
        validation_required=true
    fi
    
    # Check if critical files were modified
    local critical_files=(
        "package.json"
        "requirements.txt"
        "Cargo.toml"
        "docker-compose.yml"
        "Dockerfile"
        ".env"
        "config.json"
        "config.yml"
    )
    
    for file in "${critical_files[@]}"; do
        if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "^$file$"; then
            log_warning "Critical file modified: $file - full validation required"
            validation_required=true
            validation_level="full"
            break
        fi
    done
    
    # Check if code files were modified
    local code_extensions=("*.js" "*.ts" "*.py" "*.rs" "*.java" "*.go" "*.rb" "*.php")
    for ext in "${code_extensions[@]}"; do
        if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "$ext$"; then
            log_info "Code files modified - validation required"
            validation_required=true
            break
        fi
    done
    
    # Export validation requirements
    export VALIDATION_REQUIRED="$validation_required"
    export VALIDATION_LEVEL="$validation_level"
    
    log_success "Validation requirements determined: required=$validation_required, level=$validation_level"
}

# Execute validation framework
execute_validation() {
    log_info "Executing validation framework..."
    
    if [[ "$VALIDATION_REQUIRED" != "true" ]]; then
        log_info "Validation not required - skipping"
        return 0
    fi
    
    # Check if validation framework is available
    if [[ ! -f "scripts/validation/validate.sh" ]]; then
        log_error "Validation framework not found"
        return 1
    fi
    
    # Setup validation environment variables
    export PROJECT_TYPE="${PROJECT_TYPE:-web}"
    export ENVIRONMENT="${ENVIRONMENT:-staging}"
    export VALIDATION_LEVEL="${VALIDATION_LEVEL:-smoke}"
    
    log_info "Starting validation with level: $VALIDATION_LEVEL"
    
    # Execute validation
    local validation_result=0
    local validation_log="$VALIDATION_SESSION_DIR/validation_execution.log"
    
    if ! bash scripts/validation/validate.sh --fast 2>&1 | tee "$validation_log"; then
        validation_result=1
        log_error "Validation execution failed"
    else
        log_success "Validation execution completed successfully"
    fi
    
    # Record validation result
    local result_file="$VALIDATION_SESSION_DIR/validation_result.json"
    cat > "$result_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_level": "$VALIDATION_LEVEL",
    "result": $(if [[ $validation_result -eq 0 ]]; then echo "\"success\""; else echo "\"failure\""; fi),
    "exit_code": $validation_result,
    "log_file": "$validation_log"
}
EOF
    
    return $validation_result
}

# Update validation state
update_validation_state() {
    local result=$1
    log_info "Updating validation state..."
    
    # Update state file
    local state_file="$VALIDATION_STATE_FILE"
    if [[ -f "$state_file" ]]; then
        local temp_file=$(mktemp)
        jq --arg result "$result" \
           --arg timestamp "$(date -Iseconds)" \
           '.post_validation_completed = true | .validation_result = $result | .post_validation_finished = $timestamp' \
           "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
    fi
    
    log_success "Validation state updated with result: $result"
}

# Generate validation feedback
generate_validation_feedback() {
    local result=$1
    log_info "Generating validation feedback..."
    
    local feedback_file="$VALIDATION_SESSION_DIR/validation_feedback.json"
    local recommendations=()
    
    if [[ "$result" == "success" ]]; then
        recommendations=(
            "Validation completed successfully"
            "All checks passed"
            "System ready for next steps"
        )
    else
        recommendations=(
            "Validation failed - review errors"
            "Check validation logs for details"
            "Fix issues before proceeding"
        )
    fi
    
    # Convert recommendations array to JSON
    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R . | jq -s .)
    
    cat > "$feedback_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_result": "$result",
    "validation_level": "$VALIDATION_LEVEL",
    "feedback_type": "post_validation",
    "recommendations": $recommendations_json,
    "next_steps": $(if [[ "$result" == "success" ]]; then echo "\"proceed_with_confidence\""; else echo "\"fix_issues_first\""; fi)
}
EOF
    
    log_success "Validation feedback generated: $feedback_file"
}

# Trigger AI feedback collection
trigger_ai_feedback() {
    log_info "Triggering AI feedback collection..."
    
    # Check if AI feedback system is available
    if [[ -f "scripts/ai_feedback.py" ]]; then
        local feedback_data="$VALIDATION_SESSION_DIR/validation_feedback.json"
        if [[ -f "$feedback_data" ]]; then
            log_info "Collecting AI feedback..."
            python scripts/ai_feedback.py --input "$feedback_data" --output "$VALIDATION_SESSION_DIR/ai_feedback.json" || {
                log_warning "AI feedback collection failed"
            }
        fi
    else
        log_warning "AI feedback system not available"
    fi
    
    log_success "AI feedback collection triggered"
}

# Create validation summary
create_validation_summary() {
    local result=$1
    log_info "Creating validation summary..."
    
    local summary_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    
    cat > "$summary_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "result": "$result",
    "validation_level": "$VALIDATION_LEVEL",
    "project_type": "$PROJECT_TYPE",
    "validation_required": $VALIDATION_REQUIRED,
    "session_dir": "$VALIDATION_SESSION_DIR"
}
EOF
    
    # Display summary
    log_info "=== Validation Summary ==="
    log_info "Session ID: $VALIDATION_SESSION_ID"
    log_info "Result: $result"
    log_info "Level: $VALIDATION_LEVEL"
    log_info "Required: $VALIDATION_REQUIRED"
    log_info "Project Type: $PROJECT_TYPE"
    log_info "========================="
    
    log_success "Validation summary created: $summary_file"
}

# Main post-validation execution
main() {
    log_info "Starting post-validation hook..."
    
    # Load validation context
    load_validation_context
    
    # Determine validation requirements
    determine_validation_requirements
    
    # Execute validation if required
    local validation_result="skipped"
    if [[ "$VALIDATION_REQUIRED" == "true" ]]; then
        if execute_validation; then
            validation_result="success"
        else
            validation_result="failure"
        fi
    fi
    
    # Update validation state
    update_validation_state "$validation_result"
    
    # Generate validation feedback
    generate_validation_feedback "$validation_result"
    
    # Trigger AI feedback collection
    trigger_ai_feedback
    
    # Create validation summary
    create_validation_summary "$validation_result"
    
    log_success "Post-validation hook completed with result: $validation_result"
    
    # Export result for completion gate
    export VALIDATION_RESULT="$validation_result"
    
    # Return appropriate exit code
    if [[ "$validation_result" == "failure" ]]; then
        log_error "Validation failed - blocking completion"
        exit 1
    fi
    
    log_success "Post-validation hook completed successfully"
}

# Execute main function
main "$@"
