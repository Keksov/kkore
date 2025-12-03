#!/bin/bash

#
declare -A __KLIB_VARS

# Generate unique variable name with random ID
kv.new() {
    local var_name="${2:-__var}_${RANDOM}_$$"
    local initial_value="${1-0}"
    __KLIB_VARS["$var_name"]="$initial_value"
    if [[ $BASH_SUBSHELL -gt 0 ]]; then
        # In subshell: echo the value
        echo -n "$var_name"
        return
    fi
    RESULT="$var_name"
}

# Set variable value in global storage
kv.set() {
    local var_name="$1"
    local value="$2"
    __KLIB_VARS["$var_name"]="$value"
}

# Get variable value from global storage
kv.get() {
    local var_name="$1"
    if [[ $BASH_SUBSHELL -gt 0 ]]; then
        # In subshell: echo the value
        echo -n "${__KLIB_VARS[$var_name]}"
        return
    fi
    RESULT="${__KLIB_VARS[$var_name]}"
}

# Delete variable (cleanup)
kv.free() {
    local var_name="$1"
    unset __KLIB_VARS["$var_name"]
}
