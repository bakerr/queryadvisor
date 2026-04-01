#!/bin/bash
# cleanup_validation.sh - Cleanup old validation sessions and results
# Part of AI Setup Enhanced Validation Framework
# Version: 1.0.0

set -euo pipefail

# Configuration
VALIDATION_BASE_DIR=".validation"
SESSIONS_DIR="$VALIDATION_BASE_DIR/sessions"
RESULTS_DIR="$VALIDATION_BASE_DIR/results"
LOGS_DIR="$VALIDATION_BASE_DIR/logs"
FEEDBACK_DIR="$VALIDATION_BASE_DIR/feedback"
CACHE_DIR=".validation_cache"

# Retention settings (days)
SESSION_RETENTION_DAYS=7
LOG_RETENTION_DAYS=14
FEEDBACK_RETENTION_DAYS=30
CACHE_RETENTION_HOURS=24

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[Cleanup] $1${NC}"; }
log_success() { echo -e "${GREEN}[Cleanup] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[Cleanup] $1${NC}"; }

# Show usage
show_usage() {
    cat << EOF
Validation Cleanup Script

Usage: $(basename "$0") [OPTIONS]

Options:
  --sessions    Clean only validation sessions
  --logs        Clean only log files
  --feedback    Clean only feedback files
  --cache       Clean only cache files
  --all         Clean all validation data (default)
  --dry-run     Show what would be cleaned without doing it
  --help        Show this help message

Retention policies:
  Sessions: $SESSION_RETENTION_DAYS days
  Logs: $LOG_RETENTION_DAYS days
  Feedback: $FEEDBACK_RETENTION_DAYS days
  Cache: $CACHE_RETENTION_HOURS hours
EOF
}

# Cleanup sessions
cleanup_sessions() {
    local dry_run=$1
    log_info "Cleaning validation sessions older than $SESSION_RETENTION_DAYS days..."
    
    if [[ -d "$SESSIONS_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' session_dir; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $session_dir"
            else
                rm -rf "$session_dir"
            fi
            ((count++))
        done < <(find "$SESSIONS_DIR" -maxdepth 1 -type d -mtime +$SESSION_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count validation sessions"
        else
            log_info "No old validation sessions to clean"
        fi
    else
        log_info "No validation sessions directory found"
    fi
}

# Cleanup logs
cleanup_logs() {
    local dry_run=$1
    log_info "Cleaning log files older than $LOG_RETENTION_DAYS days..."
    
    if [[ -d "$LOGS_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' log_file; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $log_file"
            else
                rm -f "$log_file"
            fi
            ((count++))
        done < <(find "$LOGS_DIR" -type f -name "*.log" -mtime +$LOG_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count log files"
        else
            log_info "No old log files to clean"
        fi
    else
        log_info "No logs directory found"
    fi
}

# Cleanup feedback
cleanup_feedback() {
    local dry_run=$1
    log_info "Cleaning feedback files older than $FEEDBACK_RETENTION_DAYS days..."
    
    if [[ -d "$FEEDBACK_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' feedback_dir; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $feedback_dir"
            else
                rm -rf "$feedback_dir"
            fi
            ((count++))
        done < <(find "$FEEDBACK_DIR" -maxdepth 1 -type d -mtime +$FEEDBACK_RETENTION_DAYS -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count feedback sessions"
        else
            log_info "No old feedback sessions to clean"
        fi
    else
        log_info "No feedback directory found"
    fi
}

# Cleanup cache
cleanup_cache() {
    local dry_run=$1
    log_info "Cleaning cache files older than $CACHE_RETENTION_HOURS hours..."
    
    if [[ -d "$CACHE_DIR" ]]; then
        local count=0
        local hours_in_minutes=$((CACHE_RETENTION_HOURS * 60))
        
        while IFS= read -r -d '' cache_file; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would remove: $cache_file"
            else
                rm -f "$cache_file"
            fi
            ((count++))
        done < <(find "$CACHE_DIR" -type f -mmin +$hours_in_minutes -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            log_success "Cleaned $count cache files"
        else
            log_info "No old cache files to clean"
        fi
    else
        log_info "No cache directory found"
    fi
}

# Cleanup empty directories
cleanup_empty_dirs() {
    local dry_run=$1
    log_info "Cleaning empty directories..."
    
    local dirs=("$SESSIONS_DIR" "$LOGS_DIR" "$FEEDBACK_DIR" "$CACHE_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' empty_dir; do
                if [[ "$dry_run" == "true" ]]; then
                    echo "Would remove empty directory: $empty_dir"
                else
                    rmdir "$empty_dir" 2>/dev/null || true
                fi
            done < <(find "$dir" -type d -empty -print0 2>/dev/null)
        fi
    done
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "=== Validation Cleanup Report ==="
    
    # Count remaining items
    local sessions=0
    local logs=0
    local feedback=0
    local cache=0
    
    [[ -d "$SESSIONS_DIR" ]] && sessions=$(find "$SESSIONS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ -d "$LOGS_DIR" ]] && logs=$(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    [[ -d "$FEEDBACK_DIR" ]] && feedback=$(find "$FEEDBACK_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ -d "$CACHE_DIR" ]] && cache=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    
    echo "Remaining validation data:"
    echo "  Sessions: $((sessions - 1))"  # Subtract 1 for the directory itself
    echo "  Log files: $logs"
    echo "  Feedback sessions: $((feedback - 1))"  # Subtract 1 for the directory itself
    echo "  Cache files: $cache"
    
    # Calculate disk usage
    local total_size=0
    [[ -d "$VALIDATION_BASE_DIR" ]] && total_size=$(du -sh "$VALIDATION_BASE_DIR" 2>/dev/null | cut -f1 || echo "0")
    echo "  Total disk usage: $total_size"
    
    log_info "================================="
}

# Main execution
main() {
    local clean_sessions=false
    local clean_logs=false
    local clean_feedback=false
    local clean_cache=false
    local dry_run=false
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        clean_sessions=true
        clean_logs=true
        clean_feedback=true
        clean_cache=true
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sessions)
                clean_sessions=true
                shift
                ;;
            --logs)
                clean_logs=true
                shift
                ;;
            --feedback)
                clean_feedback=true
                shift
                ;;
            --cache)
                clean_cache=true
                shift
                ;;
            --all)
                clean_sessions=true
                clean_logs=true
                clean_feedback=true
                clean_cache=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting validation cleanup..."
    if [[ "$dry_run" == "true" ]]; then
        log_warning "DRY RUN MODE - No files will actually be deleted"
    fi
    
    # Execute cleanup operations
    [[ "$clean_sessions" == "true" ]] && cleanup_sessions "$dry_run"
    [[ "$clean_logs" == "true" ]] && cleanup_logs "$dry_run"
    [[ "$clean_feedback" == "true" ]] && cleanup_feedback "$dry_run"
    [[ "$clean_cache" == "true" ]] && cleanup_cache "$dry_run"
    
    # Cleanup empty directories
    cleanup_empty_dirs "$dry_run"
    
    # Generate report (only if not dry run)
    if [[ "$dry_run" != "true" ]]; then
        generate_cleanup_report
    fi
    
    log_success "Validation cleanup completed"
}

# Execute main
main "$@"
