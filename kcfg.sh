#!/bin/bash

# Prevent multiple sourcing
if [[ -n "${__KLIB_CFG_SOURCED:-}" ]]; then
    return
fi
declare -g __KLIB_CFG_SOURCED=1

declare -gA __KLIB_CONFIG

# Set config value
kc.set() {
    local key="$1"
    local value="$2"
    __KLIB_CONFIG["$key"]="$value"
}

# Get config value
kc.get() {
    local key="$1"
    if [[ $BASH_SUBSHELL -gt 0 ]]; then
        echo -n "${__KLIB_CONFIG[$key]}"
        return
    fi
    RESULT="${__KLIB_CONFIG[$key]}"
}

# Check if config key exists
kc.exists() {
    local key="$1"
    [[ -v __KLIB_CONFIG["$key"] ]]
}

# Delete config value
kc.delete() {
    local key="$1"
    unset __KLIB_CONFIG["$key"]
}

# Get all config keys
kc.keys() {
    if [[ $BASH_SUBSHELL -gt 0 ]]; then
        echo "${!__KLIB_CONFIG[@]}"
        return
    fi
    RESULT="${!__KLIB_CONFIG[@]}"
}

# Clear all config
kc.clear() {
    __KLIB_CONFIG=()
}

# Set config value to true
kc.setTrue() {
    local key="$1"
    __KLIB_CONFIG["$key"]="true"
}

# Set config value to false
kc.setFalse() {
    local key="$1"
    __KLIB_CONFIG["$key"]="false"
}

# Check if config value is true
kc.isTrue() {
    [[ "${__KLIB_CONFIG[$1]}" == "true" ]]
}

# Check if config value is false
kc.isFalse() {
    [[ "${__KLIB_CONFIG[$1]}" == "false" ]]
}


# Create dynamic variable alias for config value (optimized for tight loops)
# Usage: kc.alias "feature" creates nameref: kc_feature -> __KLIB_CONFIG[feature]
# Alias automatically reflects current value in __KLIB_CONFIG[feature]
kc.alias() {
    local key="$1"
    # SECURITY: the key is interpolated into both a variable name (kc_$key) and a
    # nameref target subscript. A key like 'x]=...; cmd' would corrupt the declare.
    # Restrict to a plain identifier (which is also all a valid nameref name allows).
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "kc.alias: invalid key '$key' (must be a valid identifier)" >&2
        return 1
    fi
    declare -ng "kc_${key}=__KLIB_CONFIG[$key]"
}

# Check if nameref variable exists
# Usage: kc.iasAlias "kc_feature"
kc.iasAlias() {
    # -R is a fork-free nameref test (bash 4.3+); the old form forked a subshell
    # to grep `declare -p` output on every call.
    [[ -R "$1" ]]
}
