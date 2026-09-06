#!/bin/bash

# Prevent multiple sourcing
if [[ -n "${__KLIB_VARS_SOURCED:-}" ]]; then
    return
fi
declare -g __KLIB_VARS_SOURCED=1

declare -gA __KLIB_VARS
# Frame stack: three parallel INDEXED arrays keyed by frame depth. The frame id
# IS the integer depth index. This replaces the previous scheme where the id was
# a long $RANDOM-built string used as an associative-array key — that generated a
# fresh random key on every method call (hot path) for no benefit. Strict
# push/pop keeps these dense (0..depth-1). __KLIB_FRAME_STACK tracks depth.
declare -ga __KLIB_FRAME_STACK=()
declare -ga __KLIB_FRAME_INSTANCE=()
declare -ga __KLIB_FRAME_CLASS=()

# Monotonic per-process counter for collision-free unique names. Combined with
# BASHPID (distinct in every subshell) it guarantees uniqueness process-wide,
# unlike the previous $RANDOM scheme which collided ~14% of the time in tight
# same-line loops (0-32767 range, birthday paradox).
declare -gi __KLIB_UID=0

kv._set_result() {
    local value="$1"
    local allow_echo="${2:-true}"

    RESULT="$value"
    if [[ $BASH_SUBSHELL -gt 0 && "$allow_echo" == "true" ]]; then
        echo -n "$value"
        return
    fi
}

# Generate unique variable name with random ID
kv.new() {
    #local caller_func="${FUNCNAME[1]:-main}"
    #local stack_depth=${#FUNCNAME[@]}
    #local subshell_level=$BASH_SUBSHELL
    #local var_name="${2:-__var}_${caller_func}_${stack_depth}_${subshell_level}_${RANDOM}_$$"

    local var_name="${2:-__var}_${BASH_SUBSHELL}_${#FUNCNAME[@]}_${FUNCNAME[1]:-main}_${BASH_LINENO[0]}_$((++__KLIB_UID))_${BASHPID}"
    local initial_value="${1-0}"

    __KLIB_VARS["$var_name"]="$initial_value"
    kv._set_result "$var_name"
}

kv.framePush() {
    local instance_name="$1"
    local class_name="$2"

    if [[ -z "$instance_name" || -z "$class_name" ]]; then
        ke.reportError "frame push requires instance and class"
        return 1
    fi

    local frame_id=${#__KLIB_FRAME_STACK[@]}
    __KLIB_FRAME_STACK[frame_id]=$frame_id
    __KLIB_FRAME_INSTANCE[frame_id]="$instance_name"
    __KLIB_FRAME_CLASS[frame_id]="$class_name"

    kv._set_result "$frame_id" false
}

kv.frameCurrent() {
    local frame_count=${#__KLIB_FRAME_STACK[@]}
    if (( frame_count == 0 )); then
        kv._set_result "" false
        return 1
    fi

    kv._set_result "${__KLIB_FRAME_STACK[$((frame_count - 1))]}" false
}

kv.frameInstance() {
    local frame_id="$1"
    if [[ -z "$frame_id" ]]; then
        ke.reportError "frame id cannot be empty"
        return 1
    fi

    kv._set_result "${__KLIB_FRAME_INSTANCE[$frame_id]}" false
}

kv.frameClass() {
    local frame_id="$1"
    if [[ -z "$frame_id" ]]; then
        ke.reportError "frame id cannot be empty"
        return 1
    fi

    kv._set_result "${__KLIB_FRAME_CLASS[$frame_id]}" false
}

kv.framePop() {
    local frame_count=${#__KLIB_FRAME_STACK[@]}
    if (( frame_count == 0 )); then
        kv._set_result "" false
        return 1
    fi

    local frame_id=$((frame_count - 1))
    unset '__KLIB_FRAME_STACK[frame_id]'
    unset '__KLIB_FRAME_INSTANCE[frame_id]'
    unset '__KLIB_FRAME_CLASS[frame_id]'

    kv._set_result "$frame_id" false
}

# Set variable value in global storage
kv.set() {
    local var_name="$1"
    local value="$2"
    if [[ -z "$var_name" ]]; then
        ke.reportError "variable name cannot be empty"
        return 1
    fi
    __KLIB_VARS["$var_name"]="$value"
}

# Get variable value from global storage
kv.get() {
    local var_name="$1"
    if [[ -z "$var_name" ]]; then
        ke.reportError "variable name cannot be empty"
        return 1
    fi
    # Route through the shared convention (sets RESULT, echoes in a subshell)
    # instead of duplicating the BASH_SUBSHELL branch.
    kv._set_result "${__KLIB_VARS[$var_name]}"
}

# Delete variable (cleanup)
kv.free() {
    local var_name="$1"
    if [[ -z "$var_name" ]]; then
        ke.reportError "variable name cannot be empty"
        return 1
    fi
    unset __KLIB_VARS["$var_name"]
}
