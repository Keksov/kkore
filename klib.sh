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
#
# The identifier check is an INLINE copy of kk._is_ident's rule (below; kklass
# round 4 / P12 review R1): the bare range glob that stood here accepted ı İ Ａ
# under en_US.UTF-8 (é Ä ß with globasciiranges off, İ / KELVIN SIGN under
# nocasematch), and `printf -v` then printed a bash diagnostic — breaking the
# "nothing is ever printed" contract of kk.isInt / kk.isNum. Inline, not a
# call: kk.isInt/kk.isNum are hot in kcl, and on bash 5.2 / msys the call cost
# +17 us per OUTVAR vs +4.5 us inline. THIS COPY MUST STAY EQUIVALENT TO
# kk._is_ident — kkore test 008 runs one name table through both in all 12
# locale × globasciiranges × nocasematch combinations. Under nocasematch the
# check runs with it switched off (restored), so __kk_/__KK_ are case-sensitive.
kk._setOut() {   # NAME VALUE
    if [[ a == A && $BASHOPTS == *nocasematch* ]]; then
        shopt -u nocasematch
        kk._setOut "$@"
        local __kk_rc=$?
        shopt -s nocasematch
        return "$__kk_rc"
    fi
    case "${1:-}" in
        ""|*[!A-Za-z0-9_]*|*[![:ascii:]]*|[0-9]*|__kk_*|__KK_*) return 2 ;;   # = kk._is_ident
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


# ============================================================================
# kk.debug MSG...   — the kcl debug channel (decision D2, plan P9)
# ============================================================================
# kcl's error contract is "rc 1 + RESULT='' + nothing printed"; a diagnostic
# goes to stderr ONLY under `VERBOSE_KKLASS=debug`. Eleven units wrote that out
# by hand ~80 times, in three spellings:
#
#   [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "..."   >&2
#   [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && printf ... "..." >&2
#   unit._debug() { if [[ ... ]]; then printf '%s\n' "$1" >&2; fi; }
#
# All three are one idiom, and the `&&` spelling has a trap: with the switch OFF
# the list evaluates to FALSE, so a member that ends on it returns 1 by accident
# and aborts a `set -e` caller (kcl/README.md 1.4). kk.debug is the same idiom
# with one spelling and an UNCONDITIONAL rc 0.
#
#   * rc 0 always, on both branches — safe as the last statement of a function.
#   * Nothing ever reaches stdout; the message is stderr-only and appears only
#     under the switch.
#   * The message is DATA: `printf '%s\n' "$*"`, so `-e`, `-n`, `%s` and
#     backslashes survive verbatim (`echo` would eat the first two).
#   * No fork, no subshell, no external command; `set -eu` clean with or
#     without an argument.
kk.debug() {   # MSG...
    if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
        printf '%s\n' "$*" >&2
    fi
    return 0
}


# ============================================================================
# kk.warn MSG...   — the kcl warning channel (D6 final Q6, tpipe P3)
# ============================================================================
# `VERBOSE_KKLASS` has THREE levels, and this helper is the middle one:
#
#   quiet     nothing at all reaches stderr — neither errors nor warnings;
#   unset     (the default) warnings are printed, errors are not;
#   debug     both are printed.
#
# An ERROR (kk.debug) explains an answer the caller already has: rc 1 with
# RESULT='' or rc 2 for a malformed call. The unit did nothing, so a caller who
# wants the reason turns the switch on.
#
# A WARNING (kk.warn) is the opposite case: the call WORKED — its rc and RESULT
# are exactly what the contract promises — but it very likely did not do what
# the caller meant, and nothing in the rc or the value can say so. The first
# case is a sink running inside a subshell (tpipe D6 final): every record is
# delivered and the count is right, while the object the callback mutated dies
# with the subshell. A caller who never sees that line loses state in silence,
# which is why the default is ON.
#
# A unit that warns owes the caller two things, both in its README: the line
# VERBATIM, and the per-call way to silence it (tpipe: the `-s` flag or
# `KK_SUBSHELL_OK=1`). `VERBOSE_KKLASS=quiet` is the corpus-wide off switch and
# silences every warning of every unit at once.
#
#   * rc 0 always, on both branches — safe as the last statement of a function.
#   * Nothing ever reaches stdout; the message is stderr-only.
#   * The message is DATA: `printf '%s\n' "$*"`, so `-e`, `-n`, `%s` and
#     backslashes survive verbatim (`echo` would eat the first two).
#   * It changes neither RESULT nor the caller's rc; no fork, no subshell,
#     `set -eu` clean with or without an argument.
kk.warn() {   # MSG...
    if [[ "${VERBOSE_KKLASS:-}" != "quiet" ]]; then
        printf '%s\n' "$*" >&2
    fi
    return 0
}

# ============================================================================
# kk._is_ident NAME   — the ONE plain-identifier check (kklass round 4, DR13)
# ============================================================================
# rc 0 when NAME is a plain ASCII bash identifier ([A-Za-z_][A-Za-z0-9_]*),
# rc 1 otherwise. Silent, fork-free, the argument is only pattern-matched,
# BASH_REMATCH is left alone (no =~). Used by kk._outName and kc.alias here
# and — kklass.sh sources this file first — by every kklass entry path
# (kk.isAbstract, kk.derivesFrom, kk.decl._validate_ident, the generated
# CLASS.new under nocasematch, loadObjects).
#
# Locale-exact WITHOUT a locale switch. A bare range glob is not exact: under
# en_US.UTF-8 on bash 5.2 `[A-Za-z]` matches ı İ Ａ, and with globasciiranges
# off also é Ä ß. Every such character is non-ASCII, so the `*[![:ascii:]]*`
# guard refuses them all, and on ASCII the ranges are exact in every locale.
# The other hole is `shopt -s nocasematch` (case folding lets İ / ı match i / I
# and the KELVIN SIGN match k): the core then runs with nocasematch OFF and the
# caller's setting is restored before returning. Round 3 (kklass P11) used a
# function-local `LC_ALL=C` instead — exact as well, but ≈4.5× slower under a
# UTF-8 caller locale (kk.derivesFrom 70 -> 213 us, finding L2). Exactness is
# pinned by kkore test 008 (every printable ASCII character, ı İ Ａ é Ä ß ſ K
# ² ٣ １ … × 12 locale × globasciiranges × nocasematch combinations).
kk._is_ident() {   # NAME
    if [[ a == A && $BASHOPTS == *nocasematch* ]]; then   # see kk._outName on the probe
        shopt -u nocasematch
        kk._is_ident "$@"
        local __kk_rc=$?
        shopt -s nocasematch
        return "$__kk_rc"
    fi
    [[ -n "${1:-}" && "$1" != [!A-Za-z_]* && "$1" != *[!A-Za-z0-9_]* && "$1" != *[![:ascii:]]* ]]
}

# ============================================================================
# kk._outName NAME [RESERVED_PREFIX...]   — the §1.7 output-name rule (P8-F1)
# ============================================================================
# A member that fills a caller array takes the array's NAME and binds a nameref
# to it (kcl/README.md 1.7). The name must be validated BEFORE the binding,
# because `local -n out="$1"` on a bad name prints a bash diagnostic and leaves
# rc 0, and on a RESERVED name it aliases something the member itself owns:
#
#   h.ToArray __ts_it     -> the fill loop appended the set's storage to itself
#   d.KeysToArray __td_items -> `ref=()` WIPED the dictionary, rc 0 (G2-02)
#   I.ReadSections dirty  -> the output bound the instance's own state (T13)
#   TRegEx.matches x 1bad -> bash diagnostic, rc 0, RESULT=1 (T8)
#
# bash scopes locals DYNAMICALLY, which is why a unit's own local-variable
# prefix has to be refused as well: the caller passes RESERVED_PREFIX for each
# prefix the calling unit uses (`__tqs_`, `__tif_`, `__tre_`, …).
#
#   rc 0 = usable, rc 2 = malformed call (kcl/README.md 1.2 reserves rc 2 for
#   exactly this), silent on both paths, fork-free, and the argument is only
#   PATTERN-MATCHED — never expanded, never evaluated, never assigned to, so a
#   name is not created as a side effect of checking it.
#
# Refused: anything that is not a plain identifier; the kklass reserved set
# `this __inst__ __class__ RESULT REPLY IFS state` and the `__kk_`/`__KK_` space
# (`state` is in it because kk._run_frame_body binds it as a nameref onto
# `${inst}_data` in EVERY member frame, so an output array called `state` can
# never reach the caller from inside an instance member — a framework fact, not
# a per-unit convention); each
# RESERVED_PREFIX given (an empty one is ignored, so `"$prefix"` from an unset
# variable cannot refuse every name); and, when `__inst__` is non-empty — i.e.
# inside an instance member body — that instance's own `_data`, `_class` and
# `_items` arrays. A unit with MORE per-instance arrays than those three
# (tqueuestack's `_qhead`/`_nhook`, tinifile's twelve) checks the extra ones
# itself and calls this for the shared core.
#
# The identifier check is kk._is_ident's rule (kklass round 4, DR13: locale-
# exact; the bare range glob that stood here accepted ı İ Ａ under en_US.UTF-8,
# and the caller's `local -n` then printed a bash diagnostic), as an INLINE
# copy: kcl units call kk._outName on every output-array member, and on bash
# 5.2 / msys the extra function call doubled its cost (26.6 -> 47 us).
# THIS COPY MUST STAY EQUIVALENT TO kk._is_ident — kkore test 008 runs one
# name table through both in all 12 locale × globasciiranges × nocasematch
# combinations. Every comparison runs with nocasematch OFF (restored on
# return): the reserved set and the prefixes are case-SENSITIVE, as bash names
# are — under nocasematch `result`, `This`, `STATE`, `ifs` used to be refused
# as if they were RESULT, this, state, IFS.
# The nocasematch probe is `[[ a == A ]]` — true only under nocasematch and
# cheaper than matching $BASHOPTS (≈1.5 us per call on bash 5.2 / msys);
# $BASHOPTS then confirms it before anything is switched.
kk._outName() {   # NAME [RESERVED_PREFIX...]
    if [[ a == A && $BASHOPTS == *nocasematch* ]]; then
        shopt -u nocasematch
        kk._outName "$@"
        local __kk_rc=$?
        shopt -s nocasematch
        return "$__kk_rc"
    fi
    local __kk_n="${1:-}" __kk_p
    case "$__kk_n" in
        ""|*[!A-Za-z0-9_]*|*[![:ascii:]]*|[0-9]*)  return 2 ;;   # = kk._is_ident
        this|__inst__|__class__|RESULT|REPLY|IFS|state) return 2 ;;
        __kk_*|__KK_*)                             return 2 ;;
    esac
    if [[ -n "${__inst__:-}" ]]; then
        case "$__kk_n" in
            "${__inst__}_data"|"${__inst__}_class"|"${__inst__}_items") return 2 ;;
        esac
    fi
    shift || return 2
    for __kk_p in "$@"; do
        if [[ -n "$__kk_p" && "$__kk_n" == "$__kk_p"* ]]; then
            return 2
        fi
    done
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
