#!/bin/bash

# Prevent multiple sourcing
if [[ -n "$__KLIB_ERR_SOURCED" ]]; then
    if [[ "$1" == "set_trap" ]]; then
        ke.setTrap
    fi
    return
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/klib.sh"

declare -g __KLIB_ERR_SOURCED=1

# KLib Error Handler - Error handling and trapping
# Provides comprehensive error reporting with stack traces and code context

# Control flag for error trap (allow code to suppress intentional errors)
declare -g TRAP_ERRORS_ENABLED=true
declare -g REPORT_ERRORS_ENABLED=true
declare -g __KLIB_HAS_ERRROR=false

ke.errorsReportingOff() {
    REPORT_ERRORS_ENABLED=false
}

ke.enableErrorReport() {
    REPORT_ERRORS_ENABLED=true
}

ke.setError() {
    __KLIB_HAS_ERRROR=true
}

ke.hasError() {
    echo -n "$__KLIB_HAS_ERRROR"
    __KLIB_HAS_ERRROR=false
}

# Report error with detailed information
# Usage: ke.reportError "error message" "script" "function" "line" "exit_code" "command"
ke.reportError() {
    ke.setError

    if [[ "$REPORT_ERRORS_ENABLED" == "false" ]]; then
        ke.enableErrorReport
        return
    fi

    local message="$1"
    local script="${2:-${BASH_SOURCE[1]:-$0}}"
    local func_name="${3:-${FUNCNAME[1]:-main}}"
    local line_number="${4:-${BASH_LINENO[0]}}"
    local exit_code="${5:-1}"
    local last_command="$6"
    
    kl.errln "============================================"
    kl.errln "SCRIPT ERROR"
    kl.errln "============================================"
    kl.errln "Script:        $script"
    kl.errln "Function:      $func_name"
    kl.errln "Line:          $line_number"
    kl.errln "Error code:    $exit_code"
    if [[ -n "$last_command" ]]; then
        kl.errln "Command:       $last_command"
    fi
    if [[ -n "$message" ]]; then
        kl.errln "Message:       $message"
    fi
    kl.errln "============================================"
    
    # Display call stack
    if [ ${#FUNCNAME[@]} -gt 2 ]; then
        kl.errln "Call stack:"
        local frame=0
        while caller $frame >&2; do
            ((frame++))
        done
        kl.errln "============================================"
    fi
    
    # Display code context (3 lines before and after error)
    if [ -f "$script" ]; then
        kl.errln "Code context:"
        local start=$((line_number - 3))
        local end=$((line_number + 3))
        [ $start -lt 1 ] && start=1
        
        awk -v start=$start -v end=$end -v err=$line_number '
            NR >= start && NR <= end {
                prefix = (NR == err) ? ">>> " : "    "
                printf "%s%4d: %s\n", prefix, NR, $0
            }
        ' "$script"
        kl.errln "============================================"
    fi

}

# Error handling function
ke.onError() {
    local exit_code=$?
    
    # Skip error output if disabled, but return the error code
    if [[ "$TRAP_ERRORS_ENABLED" == "false" ]]; then
        TRAP_ERRORS_ENABLED=true
        return $exit_code
    fi
    local line_number=$1
    local bash_lineno=$2
    local last_command="${BASH_COMMAND}"
    local func_name="${FUNCNAME[1]:-main}"
    
    ke.reportError "" "${BASH_SOURCE[1]:-$0}" "$func_name" "$line_number" "$exit_code" "$last_command"
    
    exit $exit_code
    #return 0
}

ke.setTrap() {
    trap 'ke.onError ${LINENO} ${BASH_LINENO}' ERR
}

# Set trap if requested via argument
if [[ "$1" == "set_trap" ]]; then
    ke.setTrap
fi