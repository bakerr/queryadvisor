#!/bin/bash
# validation_feedback.sh - Validation feedback integration hook
# Provides clear feedback to both AI and user about validation results
# Part of Claude Code Validation Hooks Integration v1.0.0

set -e

# Configuration
VALIDATION_CONFIG_FILE=".validation/config.json"
VALIDATION_SESSION_DIR=".validation/sessions"
VALIDATION_RESULTS_DIR=".validation/results"
VALIDATION_LOGS_DIR=".validation/logs"
FEEDBACK_DIR=".validation/feedback"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Emojis for better visual feedback
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
INFO_EMOJI="ℹ️"
FEEDBACK_EMOJI="💬"
AI_EMOJI="🤖"
USER_EMOJI="👤"
ROCKET_EMOJI="🚀"

# Logging functions
log_info() { echo -e "${BLUE}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_success() { echo -e "${GREEN}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_warning() { echo -e "${YELLOW}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_error() { echo -e "${RED}[ValidationFeedback] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }
log_feedback() { echo -e "${PURPLE}[${FEEDBACK_EMOJI} FEEDBACK] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/feedback.log"; }

# Initialize feedback system
init_feedback_system() {
    log_info "Initializing validation feedback system..."
    
    # Create feedback directories
    mkdir -p "$FEEDBACK_DIR"
    mkdir -p "$VALIDATION_LOGS_DIR"
    
    # Create feedback session
    local feedback_session_id="feedback_$(date +%Y%m%d_%H%M%S)"
    export FEEDBACK_SESSION_ID="$feedback_session_id"
    export FEEDBACK_SESSION_DIR="$FEEDBACK_DIR/$feedback_session_id"
    
    mkdir -p "$FEEDBACK_SESSION_DIR"
    
    # Record feedback session
    echo "$(date -Iseconds)" > "$FEEDBACK_SESSION_DIR/feedback_start_time"
    echo "validation_feedback" > "$FEEDBACK_SESSION_DIR/feedback_type"
    
    log_success "Feedback system initialized (Session: $feedback_session_id)"
}

# Load validation results
load_validation_results() {
    log_info "Loading validation results..."
    
    local validation_found=false
    local validation_data=""
    
    # Check for recent validation results
    local last_validation_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    if [[ -f "$last_validation_file" ]]; then
        validation_data=$(cat "$last_validation_file")
        validation_found=true
        log_success "Validation results loaded from $last_validation_file"
    fi
    
    # Check for session-specific results
    if [[ -n "$VALIDATION_SESSION_ID" ]] && [[ -d "$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID" ]]; then
        local session_result_file="$VALIDATION_SESSION_DIR/$VALIDATION_SESSION_ID/validation_result.json"
        if [[ -f "$session_result_file" ]]; then
            validation_data=$(cat "$session_result_file")
            validation_found=true
            log_success "Session-specific validation results loaded"
        fi
    fi
    
    # Export validation data
    export VALIDATION_FOUND="$validation_found"
    export VALIDATION_DATA="$validation_data"
    
    if [[ "$validation_found" == "false" ]]; then
        log_warning "No validation results found"
    fi
}

# Analyze validation results
analyze_validation_results() {
    log_info "Analyzing validation results..."
    
    if [[ "$VALIDATION_FOUND" == "false" ]]; then
        export VALIDATION_STATUS="no_validation"
        export VALIDATION_SUMMARY="No validation results available"
        return
    fi
    
    # Parse validation data
    local validation_result=$(echo "$VALIDATION_DATA" | jq -r '.result // "unknown"' 2>/dev/null)
    local validation_level=$(echo "$VALIDATION_DATA" | jq -r '.validation_level // "unknown"' 2>/dev/null)
    local validation_timestamp=$(echo "$VALIDATION_DATA" | jq -r '.timestamp // ""' 2>/dev/null)
    local project_type=$(echo "$VALIDATION_DATA" | jq -r '.project_type // "unknown"' 2>/dev/null)
    
    # Determine validation status
    local validation_status="unknown"
    local validation_summary=""
    
    case "$validation_result" in
        "success")
            validation_status="success"
            validation_summary="Validation completed successfully"
            ;;
        "failure")
            validation_status="failure"
            validation_summary="Validation failed - issues detected"
            ;;
        "skipped")
            validation_status="skipped"
            validation_summary="Validation was skipped"
            ;;
        *)
            validation_status="unknown"
            validation_summary="Validation status unclear"
            ;;
    esac
    
    # Export analysis results
    export VALIDATION_STATUS="$validation_status"
    export VALIDATION_SUMMARY="$validation_summary"
    export VALIDATION_LEVEL="$validation_level"
    export VALIDATION_TIMESTAMP="$validation_timestamp"
    export PROJECT_TYPE="$project_type"
    
    log_success "Validation analysis completed: $validation_status"
}

# Generate AI feedback
generate_ai_feedback() {
    log_info "Generating AI feedback..."
    
    local ai_feedback_file="$FEEDBACK_SESSION_DIR/ai_feedback.json"
    local ai_recommendations=()
    local ai_context=""
    
    # Generate context-aware recommendations
    case "$VALIDATION_STATUS" in
        "success")
            ai_recommendations=(
                "Validation completed successfully - all checks passed"
                "System is ready for production or next development phase"
                "Consider maintaining current validation practices"
                "Monitor system performance and user feedback"
            )
            ai_context="All validation checks passed. The system appears to be functioning correctly and meets quality standards."
            ;;
        "failure")
            ai_recommendations=(
                "Validation failed - immediate attention required"
                "Review validation logs for specific error details"
                "Fix identified issues before proceeding"
                "Consider running validation in stages to isolate problems"
                "Ensure all dependencies and configurations are correct"
            )
            ai_context="Validation failed indicating potential issues that need to be addressed before proceeding."
            ;;
        "skipped")
            ai_recommendations=(
                "Validation was skipped - consider running full validation"
                "Ensure validation is not being bypassed inappropriately"
                "Review validation triggers and requirements"
                "Run manual validation if automated validation is unavailable"
            )
            ai_context="Validation was skipped. Consider whether validation should have been performed."
            ;;
        *)
            ai_recommendations=(
                "Validation status unclear - investigate validation system"
                "Check validation framework configuration"
                "Ensure validation results are being properly recorded"
                "Consider running validation manually to verify system state"
            )
            ai_context="Validation status is unclear. Investigation needed to determine system state."
            ;;
    esac
    
    # Convert recommendations to JSON
    local recommendations_json=$(printf '%s\n' "${ai_recommendations[@]}" | jq -R . | jq -s .)
    
    # Create AI feedback
    cat > "$ai_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "validation_summary": "$VALIDATION_SUMMARY",
    "ai_context": "$ai_context",
    "recommendations": $recommendations_json,
    "confidence_level": $(case "$VALIDATION_STATUS" in
        "success") echo "\"high\"" ;;
        "failure") echo "\"high\"" ;;
        "skipped") echo "\"medium\"" ;;
        *) echo "\"low\"" ;;
    esac),
    "urgency": $(case "$VALIDATION_STATUS" in
        "success") echo "\"low\"" ;;
        "failure") echo "\"high\"" ;;
        "skipped") echo "\"medium\"" ;;
        *) echo "\"medium\"" ;;
    esac)
}
EOF
    
    log_success "AI feedback generated: $ai_feedback_file"
}

# Generate user feedback
generate_user_feedback() {
    log_info "Generating user feedback..."
    
    local user_feedback_file="$FEEDBACK_SESSION_DIR/user_feedback.json"
    local user_actions=()
    local user_summary=""
    
    # Generate user-friendly summary and actions
    case "$VALIDATION_STATUS" in
        "success")
            user_summary="Great news! All validation checks passed successfully. Your system is ready to go."
            user_actions=(
                "Continue with your development workflow"
                "Deploy with confidence"
                "Monitor system performance"
                "Keep validation practices consistent"
            )
            ;;
        "failure")
            user_summary="Validation found issues that need your attention. Please review and fix the problems."
            user_actions=(
                "Check validation logs for specific error details"
                "Fix identified issues one by one"
                "Run validation again after fixes"
                "Consider reaching out for help if issues persist"
            )
            ;;
        "skipped")
            user_summary="Validation was skipped. Consider running a full validation to ensure everything is working."
            user_actions=(
                "Run manual validation: scripts/validation/validate.sh"
                "Check why validation was skipped"
                "Ensure validation triggers are working correctly"
                "Review recent changes for potential issues"
            )
            ;;
        *)
            user_summary="Validation status is unclear. Please investigate the validation system."
            user_actions=(
                "Check validation framework setup"
                "Run manual validation to verify system state"
                "Review validation configuration"
                "Check for missing dependencies or configuration issues"
            )
            ;;
    esac
    
    # Convert actions to JSON
    local actions_json=$(printf '%s\n' "${user_actions[@]}" | jq -R . | jq -s .)
    
    # Create user feedback
    cat > "$user_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "user_summary": "$user_summary",
    "recommended_actions": $actions_json,
    "validation_level": "$VALIDATION_LEVEL",
    "project_type": "$PROJECT_TYPE"
}
EOF
    
    log_success "User feedback generated: $user_feedback_file"
}

# Display feedback to console
display_feedback() {
    log_feedback "=== VALIDATION FEEDBACK ==="
    echo ""
    
    # Display status with appropriate emoji and color
    case "$VALIDATION_STATUS" in
        "success")
            echo -e "${GREEN}${BOLD}${SUCCESS_EMOJI} VALIDATION SUCCESSFUL${NC}"
            echo -e "${GREEN}${VALIDATION_SUMMARY}${NC}"
            ;;
        "failure")
            echo -e "${RED}${BOLD}${ERROR_EMOJI} VALIDATION FAILED${NC}"
            echo -e "${RED}${VALIDATION_SUMMARY}${NC}"
            ;;
        "skipped")
            echo -e "${YELLOW}${BOLD}${WARNING_EMOJI} VALIDATION SKIPPED${NC}"
            echo -e "${YELLOW}${VALIDATION_SUMMARY}${NC}"
            ;;
        *)
            echo -e "${PURPLE}${BOLD}${INFO_EMOJI} VALIDATION STATUS UNCLEAR${NC}"
            echo -e "${PURPLE}${VALIDATION_SUMMARY}${NC}"
            ;;
    esac
    
    echo ""
    
    # Display project context
    echo -e "${CYAN}${INFO_EMOJI} Project: $PROJECT_TYPE | Level: $VALIDATION_LEVEL${NC}"
    if [[ -n "$VALIDATION_TIMESTAMP" ]]; then
        echo -e "${CYAN}${INFO_EMOJI} Validation Time: $VALIDATION_TIMESTAMP${NC}"
    fi
    
    echo ""
    
    # Display AI feedback
    echo -e "${BLUE}${AI_EMOJI} AI Assistant Feedback:${NC}"
    if [[ -f "$FEEDBACK_SESSION_DIR/ai_feedback.json" ]]; then
        local ai_context=$(jq -r '.ai_context' "$FEEDBACK_SESSION_DIR/ai_feedback.json" 2>/dev/null)
        echo -e "${BLUE}$ai_context${NC}"
        echo ""
        
        echo -e "${BLUE}AI Recommendations:${NC}"
        jq -r '.recommendations[]' "$FEEDBACK_SESSION_DIR/ai_feedback.json" 2>/dev/null | while read -r recommendation; do
            echo -e "${BLUE}  • $recommendation${NC}"
        done
    fi
    
    echo ""
    
    # Display user feedback
    echo -e "${GREEN}${USER_EMOJI} User Action Items:${NC}"
    if [[ -f "$FEEDBACK_SESSION_DIR/user_feedback.json" ]]; then
        local user_summary=$(jq -r '.user_summary' "$FEEDBACK_SESSION_DIR/user_feedback.json" 2>/dev/null)
        echo -e "${GREEN}$user_summary${NC}"
        echo ""
        
        echo -e "${GREEN}Recommended Actions:${NC}"
        jq -r '.recommended_actions[]' "$FEEDBACK_SESSION_DIR/user_feedback.json" 2>/dev/null | while read -r action; do
            echo -e "${GREEN}  • $action${NC}"
        done
    fi
    
    echo ""
    log_feedback "==============================="
}

# Create feedback summary
create_feedback_summary() {
    log_info "Creating feedback summary..."
    
    local summary_file="$FEEDBACK_DIR/latest_feedback.json"
    
    # Combine AI and user feedback
    local combined_feedback="{}"
    
    if [[ -f "$FEEDBACK_SESSION_DIR/ai_feedback.json" ]] && [[ -f "$FEEDBACK_SESSION_DIR/user_feedback.json" ]]; then
        combined_feedback=$(jq -s '.[0] + .[1] + {"feedback_type": "combined"}' \
            "$FEEDBACK_SESSION_DIR/ai_feedback.json" \
            "$FEEDBACK_SESSION_DIR/user_feedback.json")
    fi
    
    # Create summary
    cat > "$summary_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "validation_summary": "$VALIDATION_SUMMARY",
    "project_type": "$PROJECT_TYPE",
    "validation_level": "$VALIDATION_LEVEL",
    "session_dir": "$FEEDBACK_SESSION_DIR",
    "combined_feedback": $combined_feedback
}
EOF
    
    log_success "Feedback summary created: $summary_file"
}

# Integration with permission system
integrate_with_permissions() {
    log_info "Integrating with permission system..."
    
    # Check if permission system is available
    if [[ -f ".permissions/config.json" ]]; then
        log_info "Permission system detected - recording validation feedback"
        
        # Create permission-compatible feedback record
        local permission_feedback_file=".permissions/validation_feedback.json"
        
        cat > "$permission_feedback_file" << EOF
{
    "feedback_session_id": "$FEEDBACK_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "validation_status": "$VALIDATION_STATUS",
    "permission_impact": $(case "$VALIDATION_STATUS" in
        "success") echo "\"validation_passed\"" ;;
        "failure") echo "\"validation_failed\"" ;;
        "skipped") echo "\"validation_skipped\"" ;;
        *) echo "\"validation_unclear\"" ;;
    esac),
    "requires_attention": $(case "$VALIDATION_STATUS" in
        "success") echo "false" ;;
        *) echo "true" ;;
    esac)
}
EOF
        
        log_success "Permission system integration completed"
    else
        log_info "No permission system detected - skipping integration"
    fi
}

# Main feedback execution
main() {
    log_info "Starting validation feedback generation..."
    
    # Initialize feedback system
    init_feedback_system
    
    # Load validation results
    load_validation_results
    
    # Analyze validation results
    analyze_validation_results
    
    # Generate AI feedback
    generate_ai_feedback
    
    # Generate user feedback
    generate_user_feedback
    
    # Display feedback to console
    display_feedback
    
    # Create feedback summary
    create_feedback_summary
    
    # Integration with permission system
    integrate_with_permissions
    
    log_success "Validation feedback generation completed"
    
    # Return appropriate exit code based on validation status
    case "$VALIDATION_STATUS" in
        "success")
            exit 0
            ;;
        "failure")
            exit 1
            ;;
        "skipped")
            exit 2
            ;;
        *)
            exit 3
            ;;
    esac
}

# Execute main function
main "$@"
