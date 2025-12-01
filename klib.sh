#!/bin/bash

kl.write() {
    echo -en "$*"
}

kl.writeln() {
    echo -e "$*"
}

kl.errln() {
    echo -e "$@" >&2
}

#set -eo pipefail

kl.getTopCaller() {
    for ((i=1; i<${#BASH_SOURCE[@]}; i++)); do
        local caller_file="${BASH_SOURCE[i]}"
        if [[ -n "$caller_file" && "$caller_file" != "${BASH_SOURCE[0]}" ]]; then
            if [[ -f "$caller_file" ]]; then
                realpath "$caller_file" 2>/dev/null || kl.write "$caller_file"
            else
                kl.write "$caller_file"
            fi
            return 0
        fi
    done
    echo ""
}

# Control flag for error trap (allow code to suppress intentional errors)
TRAP_ERRORS_ENABLED=true

# Error handling function
kl.errorHandler() {
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
    
    kl.errln "============================================"
    kl.errln "SCRIPT ERROR"
    kl.errln "============================================"
    kl.errln "Script:        ${BASH_SOURCE[1]:-$0}"
    kl.errln "Function:      $func_name"
    kl.errln "Line:          $line_number"
    kl.errln "Error code:    $exit_code"
    kl.errln "Command:       $last_command"
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
    if [ -f "${BASH_SOURCE[1]}" ]; then
        kl.errln "Code context:"
        local start=$((line_number - 3))
        local end=$((line_number + 3))
        [ $start -lt 1 ] && start=1
        
        awk -v start=$start -v end=$end -v err=$line_number '
            NR >= start && NR <= end {
                prefix = (NR == err) ? ">>> " : "    "
                printf "%s%4d: %s\n", prefix, NR, $0
            }
        ' "${BASH_SOURCE[1]}"
        kl.errln "============================================"
    fi
    
    # Display environment variables (optional)
    # echo "Environment variables:" >&2
    # env | sort >&2
    
    exit $exit_code
    #return 0
}

trap 'kl.errorHandler ${LINENO} ${BASH_LINENO}' ERR