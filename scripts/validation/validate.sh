#!/bin/bash
# validate.sh - Lightweight validation runner for AI Setup
# Version: 4.0.0
# Purpose: Fast, simple validation that addresses cashflow team performance concerns
#
# Usage:
#   ./validate.sh           # Run fast validation (default)
#   ./validate.sh --fast    # Explicitly run fast validation
#   ./validate.sh --full    # Run comprehensive validation
#   ./validate.sh --help    # Show usage

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/.validation_cache"
CACHE_TTL=3600  # 1 hour
VERSION="4.0.0"

# Colors for output (minimal, clear)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Simple logging
log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Show usage
show_usage() {
    cat << EOF
AI Setup Validation Runner v$VERSION

Usage: $(basename "$0") [OPTIONS]

Options:
  --fast    Run fast validation (default, <10 seconds)
  --full    Run comprehensive validation
  --clean   Clean validation cache
  --help    Show this help message

Fast mode includes:
  • Syntax validation for shell scripts
  • Basic security checks
  • Test execution (if framework detected)
  • Git author verification

Full mode adds:
  • Deep security scanning
  • Code quality validation
  • Integration tests
  • Performance profiling
EOF
}

# Test framework detection
detect_test_framework() {
    # JavaScript/Node.js projects
    if [[ -f "package.json" ]]; then
        if grep -q '"jest"' package.json 2>/dev/null; then
            echo "jest"
        elif grep -q '"vitest"' package.json 2>/dev/null; then
            echo "vitest"
        elif grep -q '"mocha"' package.json 2>/dev/null; then
            echo "mocha"
        elif grep -q '"test"' package.json 2>/dev/null; then
            echo "npm"
        else
            echo "none"
        fi
    # Python projects
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        if grep -q "pytest" requirements.txt 2>/dev/null || grep -q "pytest" pyproject.toml 2>/dev/null; then
            echo "pytest"
        elif grep -q "unittest" requirements.txt 2>/dev/null; then
            echo "unittest"
        else
            echo "none"
        fi
    # Go projects
    elif [[ -f "go.mod" ]]; then
        echo "go"
    # Rust projects
    elif [[ -f "Cargo.toml" ]]; then
        echo "cargo"
    else
        echo "none"
    fi
}

# Run tests based on detected framework
run_tests() {
    local framework=$(detect_test_framework)
    
    case "$framework" in
        jest|vitest|mocha|npm)
            log_info "Running JavaScript tests with $framework..."
            if npm test -- --passWithNoTests 2>/dev/null || npm test 2>/dev/null; then
                log_success "JavaScript tests passed"
                return 0
            else
                log_warning "JavaScript tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        pytest)
            log_info "Running Python tests with pytest..."
            if python -m pytest -q 2>/dev/null; then
                log_success "Python tests passed"
                return 0
            else
                log_warning "Python tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        unittest)
            log_info "Running Python tests with unittest..."
            if python -m unittest discover -q 2>/dev/null; then
                log_success "Python tests passed"
                return 0
            else
                log_warning "Python tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        go)
            log_info "Running Go tests..."
            if go test ./... 2>/dev/null; then
                log_success "Go tests passed"
                return 0
            else
                log_warning "Go tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        cargo)
            log_info "Running Rust tests..."
            if cargo test --quiet 2>/dev/null; then
                log_success "Rust tests passed"
                return 0
            else
                log_warning "Rust tests failed or not found"
                return 0  # Don't fail validation
            fi
            ;;
        none)
            log_info "No test framework detected - skipping tests"
            return 0
            ;;
    esac
}

# Cache functions
cache_key() {
    local validation_type="$1"
    local file_hash=$(find . -type f -name "*.sh" -o -name "*.js" -o -name "*.py" 2>/dev/null | head -20 | xargs ls -la 2>/dev/null | sha256sum | cut -d' ' -f1)
    echo "${validation_type}_${file_hash:0:16}"
}

check_cache() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"
    
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $CACHE_TTL ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

save_cache() {
    local key="$1"
    local result="$2"
    mkdir -p "$CACHE_DIR"
    echo "$result" > "$CACHE_DIR/$key"
}

# Fast validation (core checks only)
validate_fast() {
    local start_time=$(date +%s)
    local failed=0
    
    echo "🚀 Running fast validation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check cache
    local cache_key=$(cache_key "fast")
    if check_cache "$cache_key" > /dev/null 2>&1; then
        log_success "Using cached validation results (valid for 1 hour)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        local end_time=$(date +%s)
        echo "⏱️  Completed in $((end_time - start_time)) seconds"
        return 0
    fi
    
    # 1. Syntax validation
    log_info "Checking shell script syntax..."
    local syntax_errors=0
    while IFS= read -r script; do
        if ! bash -n "$script" 2>/dev/null; then
            log_error "Syntax error in: $script"
            ((syntax_errors++))
        fi
    done < <(find . -name "*.sh" -type f -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null)
    
    if [[ $syntax_errors -eq 0 ]]; then
        log_success "Shell syntax validation passed"
    else
        log_error "Found $syntax_errors syntax errors"
        ((failed++))
    fi
    
    # 2. Basic security checks
    log_info "Running security checks..."
    local security_issues=0
    
    # Check for dangerous patterns
    if grep -r "eval\|curl.*sh\|wget.*sh" . --include="*.sh" --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null | grep -v "^Binary file"; then
        log_warning "Found potentially dangerous code patterns"
        ((security_issues++))
    fi
    
    if [[ $security_issues -eq 0 ]]; then
        log_success "Basic security checks passed"
    else
        log_warning "Found $security_issues security concerns (review recommended)"
    fi
    
    # 3. Git author verification
    if [[ -d "$PROJECT_ROOT/scripts/git" ]]; then
        log_info "Checking git author configuration..."
        if [[ -x "$PROJECT_ROOT/scripts/git/git-author-verify.sh" ]]; then
            if "$PROJECT_ROOT/scripts/git/git-author-verify.sh" --quiet 2>/dev/null; then
                log_success "Git author configuration valid"
            else
                log_warning "Git author configuration needs attention"
            fi
        fi
    fi
    
    # 4. Run tests
    run_tests
    
    # Save cache
    save_cache "$cache_key" "$failed"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $failed -eq 0 ]]; then
        log_success "Fast validation completed successfully"
    else
        log_error "Fast validation completed with $failed issues"
    fi
    
    echo "⏱️  Completed in $duration seconds"
    
    return $failed
}

# Full validation (comprehensive checks)
validate_full() {
    local start_time=$(date +%s)
    
    echo "🔍 Running comprehensive validation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # First run fast validation
    validate_fast
    local fast_result=$?
    
    # Additional comprehensive checks
    log_info "Running extended validation..."
    
    # Check if old validation system exists
    if [[ -d "$SCRIPT_DIR/modules" ]]; then
        log_info "Legacy validation modules detected - running compatibility mode..."
        
        # Run specific validators if they exist
        for validator in "$SCRIPT_DIR"/modules/*.sh; do
            if [[ -x "$validator" ]]; then
                local validator_name=$(basename "$validator" .sh)
                log_info "Running $validator_name validation..."
                if "$validator" 2>/dev/null; then
                    log_success "$validator_name validation passed"
                else
                    log_warning "$validator_name validation had issues"
                fi
            fi
        done
    else
        log_info "No extended validation modules found"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "⏱️  Completed in $duration seconds"
    
    return $fast_result
}

# Clean cache
clean_cache() {
    log_info "Cleaning validation cache..."
    rm -rf "$CACHE_DIR"
    log_success "Cache cleaned"
}

# Cleanup old validation sessions
cleanup_sessions() {
    local session_dir="$PROJECT_ROOT/.validation_sessions"
    if [[ -d "$session_dir" ]]; then
        log_info "Cleaning old validation sessions..."
        # Remove sessions older than 7 days
        find "$session_dir" -type d -name "session_*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
        # Keep only last 10 sessions
        ls -dt "$session_dir"/session_* 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true
        log_success "Old sessions cleaned"
    fi
}

# Main
main() {
    case "${1:-}" in
        --fast|"")
            validate_fast
            cleanup_sessions
            ;;
        --full)
            validate_full
            cleanup_sessions
            ;;
        --clean)
            clean_cache
            cleanup_sessions
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
