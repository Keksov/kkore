#!/bin/bash

# Prevent multiple sourcing
if [[ -n "${__KLIB_SOURCED:-}" ]]; then
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

# ============================================================================
# Numeric argument guards (kcl decision D1, 2026-09-06)
# ============================================================================
# Every kcl member that takes an index, a count or a number validates it here
# BEFORE the value reaches `(( ))`, `${!x}` or an external tool. Without a guard
# `L.Get 'x[$(touch pwn)]'` executes the command substitution inside arithmetic,
# `L.Get abc` silently resolves to element 0, and `encodeDate 2011 08 09` dies
# on an octal parse (review 2026-09-06: X-INJ, G3-01).
#
# Contract, identical for both:
#   kk.isInt VALUE [OUTVAR]     rc 0 = accepted, rc 1 = rejected, rc 2 = bad OUTVAR
#   kk.isNum VALUE [OUTVAR]
#   * NOTHING is ever printed, on either path — callers own the error reporting.
#   * On acceptance the NORMALISED value lands in __KK_INT / __KK_NUM and, when
#     OUTVAR is given, in that variable too. OUTVAR must be a plain identifier
#     outside the framework's reserved __kk_/__KK_ space; assignment goes through
#     `printf -v`, never eval.
#   * On rejection OUTVAR and the normalised globals are left untouched.
#   * Pure bash: no fork, no subshell, no external command, and the input is
#     never expanded or evaluated — only pattern-matched.
#
# On the OUTVAR name: bash scopes locals DYNAMICALLY, so `printf -v NAME` inside
# these functions resolves to one of their own locals whenever the names collide
# — the caller's variable is never written and the guard still reports success.
# Hence both belts: every local here carries the reserved __kk_ prefix, and
# kk._setOut refuses that prefix as an OUTVAR (rc 2, loud by status).
#
# kk.isInt normalises away a leading `+` and leading zeros (the `10#` problem)
# so the result is safe in arithmetic, and rejects anything outside int64, which
# `(( ))` would otherwise wrap silently. kk.isNum accepts an optional fraction
# and exponent, strips only a leading `+`, and leaves the digits verbatim for
# the float engine; `inf`/`nan` are NOT numbers here — the math unit handles
# those tokens itself.
declare -g __KK_INT=""
declare -g __KK_NUM=""

# Assign VALUE to the variable named NAME, refusing anything that is not a
# plain identifier (`a[$(cmd)]` is an arithmetic-evaluated subscript in printf -v)
# and anything in the reserved __kk_/__KK_ space (see the note above).
kk._setOut() {   # NAME VALUE
    case "${1:-}" in
        ""|*[!A-Za-z0-9_]*|[0-9]*|__kk_*|__KK_*) return 2 ;;
    esac
    printf -v "$1" '%s' "${2:-}"
}

kk.isInt() {   # VALUE [OUTVAR]
    local __kk_v="${1:-}" __kk_sign=""
    case "$__kk_v" in
        -*) __kk_sign="-"; __kk_v="${__kk_v#-}" ;;
        +*) __kk_v="${__kk_v#+}" ;;
    esac
    # Non-empty and digits only. This also rejects whitespace, `1 2`, `0x10`,
    # `1e3` and every injection shape, since none of them are pure digits.
    [[ -n "$__kk_v" && "$__kk_v" != *[!0-9]* ]] || return 1

    # Strip the leading run of zeros in one expansion pair (`008` -> `8`).
    local __kk_zeros="${__kk_v%%[!0]*}"
    __kk_v="${__kk_v#"$__kk_zeros"}"
    [[ -n "$__kk_v" ]] || { __kk_v=0; __kk_sign=""; }

    # int64 range: `(( ))` wraps silently past it, FPC's StrToInt raises.
    local __kk_n=${#__kk_v}
    if (( __kk_n > 19 )); then
        return 1
    elif (( __kk_n == 19 )); then
        if [[ -z "$__kk_sign" ]]; then
            [[ "$__kk_v" > "9223372036854775807" ]] && return 1
        else
            [[ "$__kk_v" > "9223372036854775808" ]] && return 1
        fi
    fi

    if [[ -n "${2:-}" ]]; then
        kk._setOut "$2" "${__kk_sign}${__kk_v}" || return 2
    fi
    __KK_INT="${__kk_sign}${__kk_v}"
    return 0
}

kk.isNum() {   # VALUE [OUTVAR]
    local __kk_v="${1:-}" __kk_sign="" __kk_mant __kk_ip __kk_fp
    case "$__kk_v" in
        -*) __kk_sign="-"; __kk_v="${__kk_v#-}" ;;
        +*) __kk_v="${__kk_v#+}" ;;
    esac

    # Split off the exponent. `1e5e6` keeps `1e5` as the mantissa and fails below.
    if [[ "$__kk_v" == *[eE]* ]]; then
        local __kk_e="${__kk_v##*[eE]}"
        __kk_mant="${__kk_v%[eE]*}"
        case "$__kk_e" in -*|+*) __kk_e="${__kk_e:1}" ;; esac
        [[ -n "$__kk_e" && "$__kk_e" != *[!0-9]* ]] || return 1
    else
        __kk_mant="$__kk_v"
    fi

    if [[ "$__kk_mant" == *.* ]]; then
        __kk_ip="${__kk_mant%%.*}"
        __kk_fp="${__kk_mant#*.}"
        [[ "$__kk_fp" == *.* ]] && return 1          # a second dot
    else
        __kk_ip="$__kk_mant"
        __kk_fp=""
    fi
    [[ -n "$__kk_ip$__kk_fp" ]] || return 1             # `.`, `e3`, empty
    [[ "$__kk_ip" != *[!0-9]* ]] || return 1
    [[ "$__kk_fp" != *[!0-9]* ]] || return 1

    if [[ -n "${2:-}" ]]; then
        kk._setOut "$2" "${__kk_sign}${__kk_v}" || return 2
    fi
    __KK_NUM="${__kk_sign}${__kk_v}"
    return 0
}

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
