#!/bin/bash

# Prevent multiple sourcing
if [[ -n "$__KLIB_SOURCED" ]]; then
    return
fi
declare -g __KLIB_SOURCED=1

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
