#!/bin/bash
# validation_pre_hook.sh - Pre-tool validation hook
# Automatically triggered before AI tool usage to prepare validation context
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
log_info() { echo -e "${BLUE}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_success() { echo -e "${GREEN}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_warning() { echo -e "${YELLOW}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }
log_error() { echo -e "${RED}[PreValidation] $1${NC}" | tee -a "$VALIDATION_LOGS_DIR/pre_hook.log"; }

# Initialize validation environment
init_validation_environment() {
    log_info "Initializing validation environment..."
    
    # Create validation directories
    mkdir -p "$VALIDATION_SESSION_DIR"
    mkdir -p "$VALIDATION_RESULTS_DIR"
    mkdir -p "$VALIDATION_LOGS_DIR"
    
    # Create session ID
    local session_id="pre_validation_$(date +%Y%m%d_%H%M%S)"
    export VALIDATION_SESSION_ID="$session_id"
    
    # Create session directory
    local session_dir="$VALIDATION_SESSION_DIR/$session_id"
    mkdir -p "$session_dir"
    export VALIDATION_SESSION_DIR="$session_dir"
    
    # Record session start
    echo "$(date -Iseconds)" > "$session_dir/start_time"
    echo "pre_validation" > "$session_dir/hook_type"
    
    log_success "Validation environment initialized (Session: $session_id)"
}

# Check validation prerequisites
check_validation_prerequisites() {
    log_info "Checking validation prerequisites..."
    
    local prerequisites_passed=true
    
    # Check if validation framework is available
    if [[ ! -f "scripts/validation/validate.sh" ]]; then
        log_error "Validation framework not found"
        prerequisites_passed=false
    fi
    
    # Check if AI feedback system is available
    if [[ ! -f "scripts/ai_feedback.py" ]]; then
        log_warning "AI feedback system not found - feedback collection will be limited"
    fi
    
    # Check project structure
    if [[ ! -f "package.json" ]] && [[ ! -f "requirements.txt" ]] && [[ ! -f "Cargo.toml" ]] && [[ ! -f "pom.xml" ]]; then
        log_warning "No recognized project configuration file found"
    fi
    
    # Check environment configuration
    if [[ ! -f ".env" ]] && [[ ! -f ".env.example" ]]; then
        log_warning "No environment configuration files found"
    fi
    
    if [[ "$prerequisites_passed" == "false" ]]; then
        log_error "Validation prerequisites not met"
        return 1
    fi
    
    log_success "Validation prerequisites check passed"
    return 0
}

# Detect project context
detect_project_context() {
    log_info "Detecting project context..."
    
    local project_type="unknown"
    local has_tests=false
    local has_docs=false
    
    # Detect project type
    if [[ -f "package.json" ]]; then
        project_type="web"
        log_info "Detected web project (Node.js)"
    elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
        project_type="api"
        log_info "Detected API project (Python)"
    elif [[ -f "Cargo.toml" ]]; then
        project_type="api"
        log_info "Detected API project (Rust)"
    elif [[ -f "pom.xml" ]]; then
        project_type="api"
        log_info "Detected API project (Java)"
    fi
    
    # Check for tests
    if [[ -d "tests" ]] || [[ -d "test" ]] || [[ -d "__tests__" ]] || [[ -d "spec" ]]; then
        has_tests=true
        log_info "Test directory detected"
    fi
    
    # Check for documentation
    if [[ -f "README.md" ]] || [[ -d "docs" ]] || [[ -d "documentation" ]]; then
        has_docs=true
        log_info "Documentation detected"
    fi
    
    # Export context variables
    export PROJECT_TYPE="$project_type"
    export HAS_TESTS="$has_tests"
    export HAS_DOCS="$has_docs"
    
    # Record context
    cat > "$VALIDATION_SESSION_DIR/project_context.json" << EOF
{
    "project_type": "$project_type",
    "has_tests": $has_tests,
    "has_docs": $has_docs,
    "detected_at": "$(date -Iseconds)"
}
EOF
    
    log_success "Project context detected and recorded"
}

# Setup validation tracking
setup_validation_tracking() {
    log_info "Setting up validation tracking..."
    
    # Create validation state file
    cat > "$VALIDATION_SESSION_DIR/validation_state.json" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "status": "initialized",
    "pre_validation_completed": false,
    "post_validation_completed": false,
    "completion_gate_passed": false,
    "validation_required": true,
    "tracking_started": "$(date -Iseconds)"
}
EOF
    
    # Set validation tracking environment variables
    export VALIDATION_TRACKING_ENABLED=true
    export VALIDATION_STATE_FILE="$VALIDATION_SESSION_DIR/validation_state.json"
    
    log_success "Validation tracking initialized"
}

# Check for pending validation requirements
check_pending_validation() {
    log_info "Checking for pending validation requirements..."
    
    # Check if there are recent changes that need validation
    if git diff --quiet HEAD^ HEAD 2>/dev/null; then
        log_info "No recent changes detected"
        return 0
    fi
    
    # Check if validation has been run recently
    local last_validation_file="$VALIDATION_RESULTS_DIR/last_validation.json"
    if [[ -f "$last_validation_file" ]]; then
        local last_validation_time=$(jq -r '.timestamp' "$last_validation_file" 2>/dev/null)
        local last_commit_time=$(git log -1 --format=%cI 2>/dev/null)
        
        if [[ -n "$last_validation_time" ]] && [[ -n "$last_commit_time" ]]; then
            if [[ "$last_validation_time" > "$last_commit_time" ]]; then
                log_info "Recent validation found - validation may not be required"
                return 0
            fi
        fi
    fi
    
    log_warning "Pending validation requirements detected"
    export VALIDATION_REQUIRED=true
    return 0
}

# Generate pre-validation report
generate_pre_validation_report() {
    log_info "Generating pre-validation report..."
    
    local report_file="$VALIDATION_SESSION_DIR/pre_validation_report.json"
    
    cat > "$report_file" << EOF
{
    "session_id": "$VALIDATION_SESSION_ID",
    "hook_type": "pre_validation",
    "timestamp": "$(date -Iseconds)",
    "project_type": "$PROJECT_TYPE",
    "has_tests": $HAS_TESTS,
    "has_docs": $HAS_DOCS,
    "validation_required": ${VALIDATION_REQUIRED:-false},
    "prerequisites_passed": true,
    "environment_initialized": true,
    "tracking_enabled": true,
    "recommendations": [
        "Validation environment ready",
        "Project context detected",
        "Proceed with AI tool usage"
    ]
}
EOF
    
    log_success "Pre-validation report generated: $report_file"
}

# Main pre-validation execution
main() {
    log_info "Starting pre-validation hook..."
    
    # Initialize validation environment
    if ! init_validation_environment; then
        log_error "Failed to initialize validation environment"
        exit 1
    fi
    
    # Check prerequisites
    if ! check_validation_prerequisites; then
        log_error "Validation prerequisites check failed"
        exit 1
    fi
    
    # Detect project context
    detect_project_context
    
    # Setup validation tracking
    setup_validation_tracking
    
    # Check for pending validation
    check_pending_validation
    
    # Generate pre-validation report
    generate_pre_validation_report
    
    log_success "Pre-validation hook completed successfully"
    
    # Export important variables for subsequent hooks
    echo "export VALIDATION_SESSION_ID=\"$VALIDATION_SESSION_ID\""
    echo "export VALIDATION_SESSION_DIR=\"$VALIDATION_SESSION_DIR\""
    echo "export PROJECT_TYPE=\"$PROJECT_TYPE\""
    echo "export VALIDATION_REQUIRED=\"${VALIDATION_REQUIRED:-false}\""
}

# Execute main function
main "$@"
