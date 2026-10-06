#!/bin/bash
# kkore/kuse.sh — the unit loader: kk.unit, kk.uses, kk.defined.
# Design: kklass/USES_PLAN.md (decisions U1-U37, §7 amendments, header shapes §7.4).
#
# A UNIT is a file whose first lines — after an optional shebang, blank lines and
# `#` comment lines, all within its first 512 characters — are the two header
# lines (§7.4):
#
#     [[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tlist.sh}../../kbool.sh" || return
#     kk.unit tlist || return $__kk_unit_rc
#
# (a unit outside the kbool tree uses `source "${KBOOL_HOME-}/kbool.sh" || return 2`
# on line 1). Line 1 bootstraps kbool.sh when it is not loaded yet; line 2
# registers the unit, so a repeated plain `source` of the same file is a no-op.
#
#   kk.unit NAME            the header. rc 0 = load the unit now (registered,
#                           KK_UNIT_DIR = its folder); rc 1 = already loaded, skip;
#                           rc 2 = error (printed). $__kk_unit_rc is 0 on a skip and
#                           2 on an error, so `|| return $__kk_unit_rc` makes the
#                           source return 0 or 2.
#   kk.unit --forget NAME   drop a unit's registration (and its classes, through the
#                           kk._unit_forget_class hook kklass defines) so the next
#                           source loads it again. rc 0 / 1 not registered / 2 error
#                           (no name, a system unit kbool.sh loaded, a unit loading now).
#   kk.uses ARG...          load units once. ARG with `/`, `\` or ending in `.sh` is a
#                           PATH (relative = relative to the calling file); anything
#                           else is a unit NAME, ALWAYS resolved — the calling file's
#                           folder, then the project paths (U1b), then the system paths
#                           (kkore, kklass, kcl/*) — and compared with the unit of that
#                           name already loaded: the same file is a no-op, another file
#                           is an error (owner 2026-10-06). Only files carrying the
#                           header count for a NAME lookup; other files are reachable
#                           by path only. A name no lookup finds but that is loaded
#                           (the system units until they carry headers) is a no-op.
#                           rc 0 = all loaded (or already loaded); rc != 0 = the first
#                           failure (rc 2 for a loader error, else the unit's own rc).
#   kk.defined NAME         rc 0 when NAME is a project define (U1b), 1 when not,
#                           2 without a name.
#
# Identity of a unit = its NAME (the file stem, U33) + `[[ -ef ]]` against the
# registered file (U18'): the same name from another file is an error. A cycle
# (A uses B uses A while A loads) is an error naming the chain; it is detected from
# the bottom-relative index of the unit's `source` frame (C12), no RETURN trap.
#
# Completion (U34). kk.uses knows a unit's rc: a failed load is forgotten, so a
# retry loads it again. A PLAIN `source unit.sh` returns its rc to the caller
# only, so a plain-sourced unit counts as complete once its source frame has
# returned — unless a STRUCTURAL loader error happened inside its load (a header
# error, a cycle, a unit-name/identity clash, a use of an incomplete unit): then
# it is marked incomplete and a later kk.uses of it is an error until
# `kk.unit --forget NAME`. A dependency that is merely not found or fails with
# its own rc does NOT mark it — the unit may handle that (`kk.uses opt || ...`).
# A plain-sourced unit that fails by its own `return N` cannot be told from a
# complete one. A file WITHOUT the header loaded by `kk.uses PATH` is remembered
# by its lexically normalised path (and never by name).
#
# Messages: errors and the argument WARNING go to stderr as `kbool: ...` lines,
# silenced only by VERBOSE_KKLASS=quiet (a loader error is a compile error, not a
# member's rc-1 miss — kcl/README.md 1.2 does not apply to it).
#
# Everything here is fork-free. All locals carry the reserved __kk_ prefix: bash
# scopes dynamically, and a unit loaded by kk.uses runs inside kk.uses, so its
# file-scope code would otherwise see (and clobber) the loader's variables (C11).

# kuse.sh cannot carry the unit header (kk.unit is defined here): kbool.sh sources
# it plainly and registers it as the unit `kuse`. It has NO re-source guard
# variable — an inherited or exported guard (a parent's `set -a`) made a child
# skip its tables, and `__KK_UNITS=()` then created an INDEXED array (critic C2).
# Sourcing it again redefines the functions and repairs the tables.

# The tables. __KK_UNITS is also the loader guard (`${__KK_UNITS[@]@a} == A*`):
# non-empty exactly while kbool.sh is loaded (kbool.sh puts the sentinel [kbool]
# in it; kk.unit and kk.uses refuse to work without it).
#   __KK_UNITS         name -> absolute file, as spelled when registered
#   __KK_UNIT_SRC      name -> the BASH_SOURCE spelling of its source frame
#   __KK_UNIT_BOT      name -> bottom-relative index of that frame (-1: registered by kbool.sh)
#   __KK_UNIT_DONE     name -> 1 once completely loaded
#   __KK_UNIT_FAIL     name -> 1 when a structural load error happened inside its load (U34)
#   __KK_UNIT_SYS      name -> 1 for the units kbool.sh itself loaded (never forgotten)
#   __KK_UNIT_CLASSES  name -> space-separated classes the unit declared (fed by kklass, U2)
#   __KK_UNIT_FILES    normalised path -> 1: header-less files loaded by kk.uses PATH
#   __KK_UNIT_CAND     stem -> newline-terminated candidate files <stem>.sh, in search order
#   __KK_UNIT_IDX      name -> the first HEADERED candidate ('' = none)
#   __KK_UNIT_RES      callerdir<US>name -> what the name resolves to from there ('' = nothing)
#   __KK_UNIT_HIT      callerfile<US>name -> the registered file it matched (kk.uses fast path)
#   __KK_DEFINES       project defines (U1b, U31)
#   __KK_UNIT_PROJPATH / __KK_UNIT_SYSPATH  search path entries; `dir/*` = every subfolder
#   __KK_LOADED        [on]=1, set by kbool.sh: THIS shell owns the tables (R14). Checked as
#                      `${__KK_LOADED[@]@a} == A` by every entry point before any table
#                      is subscripted by a non-literal key (on a non-assoc table the key
#                      would be evaluated as arithmetic: `d[$(cmd)]` runs cmd)
declare -g __KK_SEP=$'\x1f'
kk._unit_tables() {
    local -
    local __kk_t
    set +u
    for __kk_t in __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_FAIL \
                  __KK_UNIT_SYS __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_CAND __KK_UNIT_IDX \
                  __KK_UNIT_RES __KK_UNIT_HIT __KK_DEFINES; do
        # keep an ASSIGNED assoc; replace anything else (unset, declared-but-
        # unassigned — whose `${R[@]@a}` reads "A" —, a scalar, an indexed array)
        if [[ ${!__kk_t@a} != *A* ]]; then
            unset "$__kk_t"
            declare -gA "$__kk_t"
            eval "$__kk_t=()"
        fi
    done
    for __kk_t in __KK_UNIT_PROJPATH __KK_UNIT_SYSPATH; do
        if [[ ${!__kk_t@a} != *a* ]]; then
            unset "$__kk_t"
            declare -ga "$__kk_t"
            eval "$__kk_t=()"
        fi
    done
    if [[ ${__KK_UNIT_IDX_OK-} != [01] ]]; then __KK_UNIT_IDX_OK=0; fi
    __kk_unit_rc=0          # the header's `return $__kk_unit_rc`: 0 skip, 2 error
    return 0
}
kk._unit_tables

# ---------------------------------------------------------------------------
# Messages
kk._unit_err() {
    if [[ "${VERBOSE_KKLASS:-}" != quiet ]]; then
        printf 'kbool: error: %s\n' "$*" >&2
    fi
    return 0
}

kk._unit_warn() {
    if [[ "${VERBOSE_KKLASS:-}" != quiet ]]; then
        printf 'kbool: WARNING: %s\n' "$*" >&2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Paths (lexical only — no cd, no fork)

# kk._unit_lexnorm PATH -> __kk_n: absolute, `/`-separated, `.`, `..` and `//`
# folded; `C:\x` and `C:/x` become `/c/x`. Lexical, so it does not resolve
# symlinks: used for messages, KBOOL_HOME (validated with -ef) and the keys of
# header-less files, never as a unit's identity (U18').
kk._unit_lexnorm() {
    local __kk_p="${1//\\//}" __kk_s __kk_o=""
    if [[ $__kk_p == [A-Za-z]:* ]]; then
        __kk_s=${__kk_p:0:1}
        __kk_p="/${__kk_s,}/${__kk_p:2}"
    fi
    if [[ $__kk_p != /* ]]; then
        __kk_p="$PWD/$__kk_p"
    fi
    __kk_p+=/
    while [[ -n $__kk_p ]]; do
        __kk_s=${__kk_p%%/*}
        __kk_p=${__kk_p#*/}
        case $__kk_s in
            ''|.) ;;
            ..) __kk_o=${__kk_o%/*} ;;
            *) __kk_o+=/$__kk_s ;;
        esac
    done
    __kk_n=${__kk_o:-/}
}

# kk._unit_dir FILE -> __kk_d: the folder of FILE as spelled, made absolute
# against PWD (a no-slash `tlist.sh` -> $PWD).
kk._unit_dir() {
    case $1 in
        */*|*\\*)
            __kk_d=${1%[/\\]*}
            if [[ -z $__kk_d ]]; then __kk_d=/; fi
            ;;
        *) __kk_d=. ;;
    esac
    if [[ $__kk_d == . ]]; then
        __kk_d=$PWD
    elif [[ $__kk_d != /* && $__kk_d != [A-Za-z]:* ]]; then
        __kk_d=$PWD/$__kk_d
    fi
}

# kk._unit_has_header FILE STEM — rc 0 when FILE carries the unit header for STEM:
# within its first 512 characters, skipping blank lines and `#` lines (a shebang,
# a comment block), the first or second remaining line is `kk.unit STEM` followed
# by nothing, a blank or `;|&` (leading blanks and a CR ignored; a line cut by the
# 512-character limit does not count). A missing/unreadable FILE is rc 1.
# ONE `read -N` per file, no fork: a line-by-line `read` costs ~2.5x as much on
# MSYS (it reads in small chunks and seeks back) — P5 measurement in the ledger.
kk._unit_has_header() {
    local __kk_h="" __kk_l __kk_i=0
    IFS= read -r -N 512 __kk_h 2>/dev/null <"$1" || :     # rc 1 at EOF (a short file) is normal
    [[ $__kk_h == *"kk.unit $2"* ]] || return 1    # one scan rejects most non-units
    if (( ${#__kk_h} >= 512 )); then
        [[ $__kk_h == *$'\n'* ]] || return 1
        __kk_h=${__kk_h%$'\n'*}$'\n'               # drop the cut last line
    fi
    while [[ -n $__kk_h ]]; do
        __kk_l=${__kk_h%%$'\n'*}
        if [[ $__kk_h == *$'\n'* ]]; then __kk_h=${__kk_h#*$'\n'}; else __kk_h=""; fi
        __kk_l=${__kk_l%$'\r'}
        __kk_l=${__kk_l#"${__kk_l%%[![:space:]]*}"}
        [[ -z $__kk_l || $__kk_l == '#'* ]] && continue
        if [[ $__kk_l == "kk.unit $2" || $__kk_l == "kk.unit $2"[[:space:]\;\|\&]* ]]; then
            return 0
        fi
        (( ++__kk_i < 2 )) || return 1
    done
    return 1
}

# ---------------------------------------------------------------------------
# Registry state

# kk._unit_check NAME MIN — the state of a REGISTERED unit not marked done.
# MIN is the lowest frame index, in THIS function's view, that counts as an outer
# load (kk.unit passes 3: 0 = here, 1 = kk.unit, 2 = the header's own file;
# kk._uses passes 3: 0 = here, 1 = kk._uses, 2 = kk.uses, 3 = the calling file,
# which counts — a unit using itself is a cycle).
#   rc 0: the unit's source frame has returned and no error was seen while it
#         loaded -> it is complete (a plain-sourced unit is marked done lazily, here);
#   rc 2: its frame is still on the stack (cycle) or it was tainted (U34); printed.
kk._unit_check() {
    local __kk_b=${__KK_UNIT_BOT[$1]--1} __kk_n=${#BASH_SOURCE[@]} __kk_k __kk_j __kk_s __kk_c=""
    if (( __kk_b >= 0 )); then
        __kk_k=$(( __kk_n - 1 - __kk_b ))
        if (( __kk_k >= $2 && __kk_k < __kk_n )) \
           && [[ ${FUNCNAME[__kk_k]-} == source && ${BASH_SOURCE[__kk_k]-} == "${__KK_UNIT_SRC[$1]-}" ]]; then
            for (( __kk_j = __kk_k; __kk_j >= $2; __kk_j-- )); do
                if [[ ${FUNCNAME[__kk_j]-} == source ]]; then
                    __kk_s=${BASH_SOURCE[__kk_j]##*[/\\]}
                    __kk_s=${__kk_s%.sh}
                    if [[ -n $__kk_s && -n ${__KK_UNITS[$__kk_s]+x} ]]; then
                        __kk_c+="$__kk_s -> "
                    fi
                fi
            done
            kk._unit_err "circular unit reference: ${__kk_c}$1"
            return 2
        fi
    fi
    if [[ -n ${__KK_UNIT_FAIL[$1]+x} ]]; then
        kk._unit_err "unit '$1' is not completely loaded: an error stopped its earlier load (kk.unit --forget $1 loads it again)"
        return 2
    fi
    __KK_UNIT_DONE[$1]=1
    return 0
}

# kk._unit_taint MIN — a STRUCTURAL load error happened (a header error, a cycle,
# a unit-name/identity clash, a use of an incomplete unit): mark the innermost
# unit still being loaded (a `source` frame at index >= MIN in this function's
# view whose registration matches it) as not completely loaded (U34). Never
# called for a dependency that is not found or fails with its own rc — the unit
# may handle that (R1). A unit loaded by kk.uses is forgotten by kk.uses anyway;
# this is what catches a PLAIN-sourced one.
kk._unit_taint() {
    local __kk_j __kk_s __kk_n=${#BASH_SOURCE[@]}
    for (( __kk_j = $1; __kk_j < __kk_n; __kk_j++ )); do
        [[ ${FUNCNAME[__kk_j]-} == source ]] || continue
        __kk_s=${BASH_SOURCE[__kk_j]##*[/\\]}
        __kk_s=${__kk_s%.sh}
        if [[ -n $__kk_s && -n ${__KK_UNITS[$__kk_s]+x} && -z ${__KK_UNIT_DONE[$__kk_s]+x} \
              && ${__KK_UNIT_SRC[$__kk_s]-} == "${BASH_SOURCE[__kk_j]}" \
              && ${__KK_UNIT_BOT[$__kk_s]--1} == $(( __kk_n - 1 - __kk_j )) ]]; then
            __KK_UNIT_FAIL[$__kk_s]=1
            return 0
        fi
    done
    return 0
}

# kk._unit_current -> RESULT: the name of the innermost unit being loaded right
# now (rc 0), or '' (rc 1). The hook kklass uses to file a class under its unit (U2).
kk._unit_current() {
    RESULT=""
    [[ ${__KK_LOADED[@]@a} == A ]] || return 1     # no registry of this shell (R14)
    local __kk_j __kk_s __kk_n=${#BASH_SOURCE[@]}
    for (( __kk_j = 1; __kk_j < __kk_n; __kk_j++ )); do
        [[ ${FUNCNAME[__kk_j]-} == source ]] || continue
        __kk_s=${BASH_SOURCE[__kk_j]##*[/\\]}
        __kk_s=${__kk_s%.sh}
        if [[ -n $__kk_s && -n ${__KK_UNITS[$__kk_s]+x} && -z ${__KK_UNIT_DONE[$__kk_s]+x} \
              && ${__KK_UNIT_SRC[$__kk_s]-} == "${BASH_SOURCE[__kk_j]}" \
              && ${__KK_UNIT_BOT[$__kk_s]--1} == $(( __kk_n - 1 - __kk_j )) ]]; then
            RESULT=$__kk_s
            return 0
        fi
    done
    RESULT=""
    return 1
}

# kk._unit_register NAME FILE — register NAME as completely loaded from FILE
# (kbool.sh, for the system units it sources plainly).
kk._unit_register() {
    if [[ -z ${__KK_UNITS[$1]+x} ]]; then
        __KK_UNITS[$1]=$2
        __KK_UNIT_SRC[$1]=$2
        __KK_UNIT_BOT[$1]=-1
    fi
    __KK_UNIT_DONE[$1]=1
    __KK_UNIT_SYS[$1]=1
    unset "__KK_UNIT_FAIL[$1]"
}

# kk._unit_drop NAME — forget a unit: its classes first (the kklass hook), then
# every registry entry. No checks.
kk._unit_drop() {
    local __kk_l="${__KK_UNIT_CLASSES[$1]-} " __kk_c
    if [[ $__kk_l != " " ]] && declare -F kk._unit_forget_class >/dev/null; then
        while [[ -n ${__kk_l// /} ]]; do
            __kk_c=${__kk_l%% *}
            __kk_l=${__kk_l#* }
            if [[ -n $__kk_c ]]; then kk._unit_forget_class "$__kk_c"; fi
        done
    fi
    unset "__KK_UNITS[$1]" "__KK_UNIT_SRC[$1]" "__KK_UNIT_BOT[$1]" "__KK_UNIT_DONE[$1]" \
          "__KK_UNIT_FAIL[$1]" "__KK_UNIT_CLASSES[$1]"
}

# kk._unit_reset — empty every registry table (kbool.sh: a fresh start, and the
# cleanup of a failed start): unset + a fresh declaration, so a table that is
# not an assoc any more (an inherited scalar, an indexed array) cannot survive.
# Defines and search paths go too.
kk._unit_reset() {
    unset __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_FAIL __KK_UNIT_SYS \
          __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_CAND __KK_UNIT_IDX __KK_UNIT_RES \
          __KK_UNIT_HIT __KK_DEFINES __KK_UNIT_PROJPATH __KK_UNIT_SYSPATH __KK_UNIT_IDX_OK \
          __KK_LOADED
    kk._unit_tables
}

# ---------------------------------------------------------------------------
# The unit -> classes registry (P4). kklass (U2) files every class it builds
# under kk._unit_current and defines kk._unit_forget_class CLASS, which
# `kk.unit --forget` calls for each of them.

# kk._unit_add_class UNIT CLASS — rc 0 (a repeat is a no-op), rc 2 on an empty argument.
kk._unit_add_class() {
    [[ -n ${1-} && -n ${2-} ]] || return 2
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2     # no registry of this shell (R14)
    case " ${__KK_UNIT_CLASSES[$1]-} " in
        *" $2 "*) return 0 ;;
    esac
    __KK_UNIT_CLASSES[$1]+="${__KK_UNIT_CLASSES[$1]:+ }$2"
    return 0
}

# kk._unit_classes UNIT -> RESULT: the space-separated classes of UNIT ('' when none).
kk._unit_classes() {
    RESULT=""
    [[ ${__KK_LOADED[@]@a} == A ]] || return 0     # no registry of this shell (R14)
    RESULT="${__KK_UNIT_CLASSES[${1:-.}]-}"
    return 0
}

# ---------------------------------------------------------------------------
# The name index (U13', U16, P5/P6), lazy at two levels:
#  * the CANDIDATE map (stem -> files named <stem>.sh, in search order) is built
#    by one glob per path entry at the first name not found in the caller's
#    folder — never in kbool.sh; project paths first, then the system paths; an
#    entry ending in `/*` means every subfolder of it;
#  * a file's header is read only when its stem is looked up, and the answer is
#    cached per name in __KK_UNIT_IDX (a miss as ''), for the shell session (U16).
# The result equals a full index of HEADERED files with first-match-wins (U13',
# U15), but the first lookup costs one glob + one file read instead of reading
# every candidate (kcl/*: 48 files, 29 of them units — P5, see the U1a ledger).
# kk.project (U1b) sets __KK_UNIT_IDX_OK=0; the next lookup rebuilds both maps.
kk._unit_index_build() {
    local __kk_e __kk_f __kk_s __kk_nf=0 __kk_fg=0 __kk_ng=0
    local -a __kk_g
    local GLOBIGNORE        # a caller's GLOBIGNORE='*' would empty the index (C10);
    unset GLOBIGNORE        # the caller's value comes back when this function returns
    __KK_UNIT_IDX=()
    __KK_UNIT_CAND=()
    __KK_UNIT_RES=()        # resolutions depend on the search path: start over
    __KK_UNIT_HIT=()
    if [[ $- == *f* ]]; then __kk_nf=1; set +f; fi
    if [[ :$BASHOPTS: == *:failglob:* ]]; then __kk_fg=1; shopt -u failglob; fi
    if [[ :$BASHOPTS: != *:nullglob:* ]]; then __kk_ng=1; shopt -s nullglob; fi
    for __kk_e in "${__KK_UNIT_PROJPATH[@]}" "${__KK_UNIT_SYSPATH[@]}"; do
        if [[ $__kk_e == */\* ]]; then
            __kk_g=("${__kk_e%/\*}"/*/*.sh)
        else
            __kk_g=("$__kk_e"/*.sh)
        fi
        for __kk_f in "${__kk_g[@]}"; do
            __kk_s=${__kk_f##*/}
            __kk_s=${__kk_s%.sh}
            __KK_UNIT_CAND[$__kk_s]+="$__kk_f"$'\n'
        done
    done
    if (( __kk_ng )); then shopt -u nullglob; fi
    if (( __kk_fg )); then shopt -s failglob; fi
    if (( __kk_nf )); then set -f; fi
    __KK_UNIT_IDX_OK=1
    return 0
}

# kk._unit_find NAME DIR -> __kk_found: DIR/NAME.sh when it carries the header,
# else the first HEADERED candidate named NAME.sh on the search path. rc 1 when
# NAME is not a unit anywhere.
kk._unit_find() {
    local __kk_l __kk_f
    if kk._unit_has_header "$2/$1.sh" "$1"; then
        __kk_found=$2/$1.sh
        return 0
    fi
    if (( ! __KK_UNIT_IDX_OK )); then kk._unit_index_build; fi
    if [[ -z ${__KK_UNIT_IDX[$1]+x} ]]; then
        __KK_UNIT_IDX[$1]=""
        __kk_l=${__KK_UNIT_CAND[$1]-}
        while [[ -n $__kk_l ]]; do
            __kk_f=${__kk_l%%$'\n'*}
            __kk_l=${__kk_l#*$'\n'}
            if kk._unit_has_header "$__kk_f" "$1"; then
                __KK_UNIT_IDX[$1]=$__kk_f
                break
            fi
        done
    fi
    __kk_found=${__KK_UNIT_IDX[$1]}
    [[ -n $__kk_found ]]
}

# ---------------------------------------------------------------------------
# kk.unit NAME | kk.unit --forget NAME
kk.unit() {
    # Fast path — the no-op re-source of a loaded unit by the spelling it was
    # registered with (absolute), sourced without arguments: one test, no locals.
    # Ownership first (R14): no table is subscripted unless it is this shell's.
    if [[ $# == 1 && ${__KK_LOADED[@]@a} == A && -n ${__KK_UNIT_DONE[${1:-.}]+x} && ${FUNCNAME[1]-} == source \
          && ${BASH_SOURCE[1]-} == "${__KK_UNITS[$1]}" \
          && ${BASH_ARGC[0]-} == 1 && ${BASH_ARGV[0]-} == "${BASH_SOURCE[1]}" ]]; then
        __kk_unit_rc=0
        return 1
    fi
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        __kk_unit_rc=2
        printf 'kbool: error: kk.unit %s: kbool.sh is not loaded (line 1 of a unit header loads it)\n' "$*" >&2
        return 2
    fi
    if [[ ${1-} == --forget ]]; then
        kk._unit_forget "${2-}"
        return
    fi
    local __kk_name=${1-} __kk_src=${BASH_SOURCE[1]-} __kk_stem __kk_a __kk_p __kk_d __kk_n __kk_m \
          __kk_ai=0 __kk_vo=0
    __kk_unit_rc=2
    if [[ ${FUNCNAME[1]-} != source || -z $__kk_src ]]; then
        kk._unit_err "kk.unit ${__kk_name}: not the header of a unit file (it must be loaded by source or kk.uses)"
        return 2
    fi
    if (( $# != 1 )) || [[ -z $__kk_name ]]; then
        kk._unit_err "kk.unit: usage 'kk.unit NAME || return \$__kk_unit_rc' (in '$__kk_src')"
        kk._unit_taint 3
        return 2
    fi
    __kk_stem=${__kk_src##*[/\\]}
    __kk_stem=${__kk_stem%.sh}
    if [[ $__kk_name != "$__kk_stem" ]]; then
        kk._unit_err "unit header 'kk.unit $__kk_name' does not match the file name '${__kk_src##*[/\\]}' (a unit's name is its file stem)"
        kk._unit_taint 3
        return 2
    fi
    # P8: units take no arguments. A `source FILE` without arguments pushes FILE on
    # BASH_ARGV with BASH_ARGC 1 (evalfile.c). With arguments the top entry is never
    # that: bash pushes the arguments (at top level they even stay on BASH_ARGV
    # afterwards) or nothing. Under extdebug kk.unit's own frame comes first. The
    # one false negative: `source FILE FILE` (one argument equal to the file's path).
    if [[ $BASHOPTS == *extdebug* ]]; then
        __kk_ai=1
        __kk_vo=${BASH_ARGC[0]-0}
    fi
    if [[ ${BASH_ARGC[__kk_ai]-} != 1 || ${BASH_ARGV[__kk_vo]-} != "$__kk_src" ]]; then
        kk._unit_warn "unit '$__kk_name' called with arguments; units take none ($__kk_src)"
    fi
    if [[ $__kk_src == /* || $__kk_src == [A-Za-z]:* ]]; then
        __kk_a=$__kk_src
    else
        __kk_a=$PWD/$__kk_src
    fi
    if [[ -n ${__KK_UNITS[$__kk_name]+x} ]]; then
        __kk_p=${__KK_UNITS[$__kk_name]}
        if [[ $__kk_p != "$__kk_a" && ! $__kk_p -ef $__kk_a ]]; then
            kk._unit_lexnorm "$__kk_p"
            __kk_m=$__kk_n
            kk._unit_lexnorm "$__kk_a"
            kk._unit_err "unit '$__kk_name' is already loaded from '$__kk_m'; refusing '$__kk_n' (unit names are unique)"
            kk._unit_taint 3
            return 2
        fi
        if [[ -z ${__KK_UNIT_DONE[$__kk_name]+x} ]] && ! kk._unit_check "$__kk_name" 3; then
            kk._unit_taint 3
            return 2
        fi
        __kk_unit_rc=0
        return 1
    fi
    __KK_UNITS[$__kk_name]=$__kk_a
    __KK_UNIT_SRC[$__kk_name]=$__kk_src
    __KK_UNIT_BOT[$__kk_name]=$(( ${#BASH_SOURCE[@]} - 2 ))
    unset "__KK_UNIT_DONE[$__kk_name]" "__KK_UNIT_FAIL[$__kk_name]"
    kk._unit_dir "$__kk_src"
    KK_UNIT_DIR=$__kk_d
    __kk_unit_rc=0
    return 0
}

# kk._unit_forget NAME — `kk.unit --forget NAME` (U24', P4).
kk._unit_forget() {
    local __kk_b __kk_k __kk_n=${#BASH_SOURCE[@]}
    if [[ -z $1 ]]; then
        kk._unit_err "kk.unit --forget: no unit named"
        return 2
    fi
    [[ -n ${__KK_UNITS[$1]+x} ]] || return 1
    if [[ -n ${__KK_UNIT_SYS[$1]+x} ]]; then
        kk._unit_err "kk.unit --forget $1: a system unit loaded by kbool.sh cannot be forgotten"
        return 2
    fi
    if [[ -z ${__KK_UNIT_DONE[$1]+x} ]]; then
        __kk_b=${__KK_UNIT_BOT[$1]--1}
        __kk_k=$(( __kk_n - 1 - __kk_b ))
        if (( __kk_b >= 0 && __kk_k >= 1 && __kk_k < __kk_n )) \
           && [[ ${FUNCNAME[__kk_k]-} == source && ${BASH_SOURCE[__kk_k]-} == "${__KK_UNIT_SRC[$1]-}" ]]; then
            kk._unit_err "kk.unit --forget $1: the unit is being loaded right now"
            return 2
        fi
    fi
    kk._unit_drop "$1"
    return 0
}

# ---------------------------------------------------------------------------
# kk.uses ARG...
kk.uses() {
    # Fast path (C8): every argument is a NAME this calling file already resolved
    # to the unit now registered and complete — one assoc test per argument, no
    # `set --`, no caller-dir work. OWNERSHIP FIRST (R14): only when the registry
    # is this shell's assoc tables is any table subscripted by a non-literal key.
    if [[ ${__KK_LOADED[@]@a} == A && ${BASH_SOURCE[1]-} == /* ]]; then
        if (( $# == 1 )) && [[ -n ${__KK_UNIT_DONE[${1:-.}]+x} \
              && ${__KK_UNIT_HIT[${BASH_SOURCE[1]}$__KK_SEP$1]-} == "${__KK_UNITS[$1]}" ]]; then
            return 0
        fi
        if (( $# > 1 )); then
            local __kk_q
            for __kk_q; do
                [[ -n ${__KK_UNIT_DONE[${__kk_q:-.}]+x} \
                   && ${__KK_UNIT_HIT[${BASH_SOURCE[1]}$__KK_SEP$__kk_q]-} == "${__KK_UNITS[$__kk_q]}" ]] || break
                __kk_q=$__KK_SEP     # marks "all passed" when the loop ends here
            done
            [[ $__kk_q != "$__KK_SEP" ]] || return 0
        fi
    elif [[ ${__KK_LOADED[@]@a} != A ]]; then
        # a child bash that inherited kk.uses (exported functions) but not the
        # registry (arrays are never exported): kbool.sh from KBOOL_HOME first (C7)
        [[ -z ${KBOOL_HOME-} || ! -f ${KBOOL_HOME-}/kbool.sh ]] || source "$KBOOL_HOME/kbool.sh" || return
        [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.uses %s: kbool.sh is not loaded\n' "$*" >&2; return 2; }
    fi
    # bash copies a function's whole body on every call (execute_function), so the
    # work lives in kk._uses and this wrapper stays small (C8: copying the old
    # one-piece kk.uses was ~70 us of its ~85 us already-loaded cost).
    kk._uses "${BASH_SOURCE[1]-}" "$@"
}

# kk._uses CALLER ARG... — kk.uses' body. CALLER = the calling file (BASH_SOURCE[1]
# of kk.uses, '' at a prompt). Frame indices seen from here are one deeper than
# from kk.uses: the caller's frame is 3 for kk._unit_check / kk._unit_taint.
kk._uses() {
    # an exported kk._uses called on its own in a registry-less child (R14)
    [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.uses: kbool.sh is not loaded\n' >&2; return 2; }
    local __kk_caller=$1
    shift
    local -a __kk_args=("$@")
    local __kk_a __kk_f __kk_nm __kk_cdir __kk_d __kk_n __kk_k __kk_rc __kk_sv __kk_svset __kk_hl \
          __kk_found __kk_m __kk_p __kk_key
    set --
    if (( ${#__kk_args[@]} == 0 )); then
        kk._unit_err "kk.uses: no unit named"
        return 2
    fi
    # the calling file's folder: relative paths and the first lookup place (U12, U14)
    if [[ -n $__kk_caller ]]; then
        kk._unit_dir "$__kk_caller"
        __kk_cdir=$__kk_d
    else
        __kk_cdir=$PWD
    fi
    for __kk_a in "${__kk_args[@]}"; do
        __kk_hl=0
        if [[ $__kk_a == */* || $__kk_a == *\\* || $__kk_a == *.sh ]]; then
            # a PATH
            if [[ $__kk_a == /* || $__kk_a == [A-Za-z]:* ]]; then
                __kk_f=$__kk_a
            else
                __kk_f=$__kk_cdir/$__kk_a
            fi
            if [[ ! -f $__kk_f ]]; then
                kk._unit_err "kk.uses: unit file '$__kk_a' not found (relative to '$__kk_cdir')"
                return 2
            fi
            __kk_nm=${__kk_f##*[/\\]}
            __kk_nm=${__kk_nm%.sh}
            if kk._unit_has_header "$__kk_f" "$__kk_nm"; then
                if [[ -n ${__KK_UNITS[$__kk_nm]+x} ]]; then
                    if [[ ${__KK_UNITS[$__kk_nm]} == "$__kk_f" || ${__KK_UNITS[$__kk_nm]} -ef $__kk_f ]]; then
                        if [[ -n ${__KK_UNIT_DONE[$__kk_nm]+x} ]] || kk._unit_check "$__kk_nm" 3; then
                            continue
                        fi
                        kk._unit_taint 3
                        return 2
                    fi
                    kk._unit_lexnorm "${__KK_UNITS[$__kk_nm]}"
                    __kk_m=$__kk_n
                    kk._unit_lexnorm "$__kk_f"
                    kk._unit_err "unit '$__kk_nm' is already loaded from '$__kk_m'; refusing '$__kk_n' (unit names are unique)"
                    kk._unit_taint 3
                    return 2
                fi
            else
                # a file without the header: tracked by its normalised path
                __kk_hl=1
                kk._unit_lexnorm "$__kk_f"
                __kk_k=$__kk_n
                if [[ -n ${__KK_UNIT_FILES[$__kk_k]+x} ]]; then
                    continue
                fi
            fi
        else
            # a unit NAME: always resolved from this caller, then compared with the
            # unit of that name already loaded (owner 2026-10-06, "найти и сравнить")
            if [[ -z $__kk_a || $__kk_a == *[[:space:]*?\[]* ]]; then
                kk._unit_err "kk.uses: '$__kk_a' is not a unit name"
                return 2
            fi
            __kk_key=$__kk_cdir$__KK_SEP$__kk_a
            if [[ -z ${__KK_UNIT_RES[$__kk_key]+x} ]]; then
                if kk._unit_find "$__kk_a" "$__kk_cdir"; then
                    __KK_UNIT_RES[$__kk_key]=$__kk_found
                else
                    __KK_UNIT_RES[$__kk_key]=""
                fi
            fi
            __kk_f=${__KK_UNIT_RES[$__kk_key]}
            if [[ -n ${__KK_UNITS[$__kk_a]+x} ]]; then
                __kk_p=${__KK_UNITS[$__kk_a]}
                if [[ -n $__kk_f && $__kk_f != "$__kk_p" && ! $__kk_f -ef $__kk_p ]]; then
                    kk._unit_lexnorm "$__kk_p"
                    __kk_m=$__kk_n
                    kk._unit_lexnorm "$__kk_f"
                    kk._unit_err "unit '$__kk_a' is already loaded from '$__kk_m'; here it resolves to '$__kk_n' (unit names are unique)"
                    kk._unit_taint 3
                    return 2
                fi
                # the same file — or a loaded unit no lookup finds (the system
                # units until they carry headers, U3)
                if [[ -n ${__KK_UNIT_DONE[$__kk_a]+x} ]] || kk._unit_check "$__kk_a" 3; then
                    if [[ $__kk_caller == /* ]]; then
                        __KK_UNIT_HIT[$__kk_caller$__KK_SEP$__kk_a]=$__kk_p
                    fi
                    continue
                fi
                kk._unit_taint 3
                return 2
            fi
            if [[ -z $__kk_f ]]; then
                kk._unit_err "kk.uses: unit '$__kk_a' not found (searched '$__kk_cdir', the project and the system paths; a file without the header 'kk.unit $__kk_a' is loaded by path only)"
                return 2
            fi
            __kk_nm=$__kk_a
        fi
        # load it: no arguments (C10), plain `source` (C11), KK_UNIT_DIR kept (C19)
        __kk_svset=${KK_UNIT_DIR+1}
        __kk_sv=${KK_UNIT_DIR-}
        source "$__kk_f"
        __kk_rc=$?
        if [[ -n $__kk_svset ]]; then
            KK_UNIT_DIR=$__kk_sv
        else
            unset KK_UNIT_DIR
        fi
        __kk_unit_rc=0
        if (( __kk_rc != 0 )); then
            # forget a failed load, so a retry loads it again (C12). The CALLER is
            # not marked incomplete: it may handle the failure (R1/C1); a structural
            # error inside the failed unit has marked it already (kk.unit).
            if [[ ${__KK_UNITS[$__kk_nm]-} == "$__kk_f" && -z ${__KK_UNIT_DONE[$__kk_nm]+x} ]]; then
                kk._unit_drop "$__kk_nm"
            fi
            kk._unit_err "kk.uses: loading unit '$__kk_nm' failed (rc=$__kk_rc)"
            return "$__kk_rc"
        fi
        if [[ ${__KK_UNITS[$__kk_nm]-} == "$__kk_f" ]]; then
            __KK_UNIT_DONE[$__kk_nm]=1
            unset "__KK_UNIT_FAIL[$__kk_nm]"
            if [[ $__kk_hl == 0 && $__kk_a != *[/\\]* && $__kk_a != *.sh && $__kk_caller == /* ]]; then
                __KK_UNIT_HIT[$__kk_caller$__KK_SEP$__kk_a]=$__kk_f
            fi
        elif (( __kk_hl )); then
            __KK_UNIT_FILES[$__kk_k]=1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# kk.defined NAME — a project define (U31): rc 0 defined, 1 not, 2 no name.
kk.defined() {
    [[ -n ${1-} ]] || return 2
    [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.defined %s: kbool.sh is not loaded\n' "$1" >&2; return 2; }
    [[ -n ${__KK_DEFINES[$1]+x} ]]
}
