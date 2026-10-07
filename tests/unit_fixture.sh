#!/bin/bash
# Shared fixture for the unit-loader tests (009_UnitsAndUses.sh, 010_KboolLoader.sh).
# Not a test file: the runner only picks up NNN_*.sh.
#
# uf_build DIR   builds a throw-away kbool tree:
#                  DIR/kbool.sh, DIR/kkore/*.sh       copies of the real loader + system units
#                  DIR/kcl/<unit>/<unit>.sh           fixture units with the two header lines
#                  DIR/proj/...                       a "user project" outside the tree
# uf_run SNIPPET runs SNIPPET in a fresh "$BASH" -c with FX=DIR in the environment;
#                sets UF_OUT (stdout+stderr) and UF_RC.

UF_REAL="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"     # the real kbool root

# uf_unit DIR NAME BODY...  — a kcl-shaped unit (relative first line, U19'/§7.4)
uf_unit() {
    local dir="$1/kcl/$2" name="$2"; shift 2
    mkdir -p "$dir"
    {
        printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$name"'.sh}../../kbool.sh" || return'
        printf '%s\n' "kk.unit $name || return \$__kk_unit_rc"
        printf '%s\n' "$@"
    } > "$dir/$name.sh"
}

# uf_user FILE NAME BODY...  — a user unit outside the tree (KBOOL_HOME first line, P1;
#                              `|| return 2`, never `${KBOOL_HOME:?}`, which exits the shell)
uf_user() {
    local file="$1" name="$2"; shift 2
    mkdir -p "${file%/*}"
    {
        printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2'
        printf '%s\n' "kk.unit $name || return \$__kk_unit_rc"
        printf '%s\n' "$@"
    } > "$file"
}

uf_build() {
    local fx="$1"
    rm -rf "$fx"
    mkdir -p "$fx/kkore" "$fx/kcl" "$fx/kklass"
    cp "$UF_REAL/kbool.sh" "$fx/kbool.sh" || { echo "uf_build: cannot copy $UF_REAL/kbool.sh" >&2; return 1; }
    cp "$UF_REAL"/kkore/*.sh "$fx/kkore/" || { echo "uf_build: cannot copy kkore" >&2; return 1; }

    uf_unit "$fx" a \
        'A_LOADS=$(( ${A_LOADS:-0} + 1 )); A_DIR="${KK_UNIT_DIR-}"' \
        'kk._unit_current || :; A_CUR="${RESULT-}"' \
        'if (( ${UF_CYC:-0} )); then kk.uses b || return; fi' \
        'A_DIR_AFTER="${KK_UNIT_DIR-}"' \
        'a.hello() { echo a; }'
    uf_unit "$fx" b \
        'B_LOADS=$(( ${B_LOADS:-0} + 1 ))' \
        'if (( ${UF_CYC:-0} == 1 )); then kk.uses a || return; fi' \
        'if (( ${UF_CYC:-0} == 2 )); then source "${BASH_SOURCE%b.sh}../a/a.sh" || return; fi' \
        'b.hello() { echo b; }'
    uf_unit "$fx" fail \
        'FAIL_LOADS=$(( ${FAIL_LOADS:-0} + 1 ))' \
        'if (( ${UF_FAIL:-0} == 1 )); then return 3; fi' \
        'fail.hello() { echo fail; }'
    # a STRUCTURAL error inside its load (it plain-sources a unit with a header
    # error) marks a plain-sourced dep incomplete (U34)
    uf_unit "$fx" dep \
        'DEP_LOADS=$(( ${DEP_LOADS:-0} + 1 ))' \
        'if (( ${UF_FAIL:-0} )); then source "${KK_UNIT_DIR}/../bad/bad.sh" || return; fi' \
        'dep.hello() { echo dep; }'
    # an OPTIONAL dependency the unit handles: never marks it incomplete (R1)
    uf_unit "$fx" opt \
        'kk.uses nosuchopt 2>/dev/null || OPT_FALLBACK=1' \
        'kk.uses fail 2>/dev/null || OPT_FALLBACK2=1' \
        'OPT_LOADS=$(( ${OPT_LOADS:-0} + 1 ))'
    # a kcl unit that needs THE kcl unit `a` (R3: a name is resolved, then compared)
    uf_unit "$fx" needa \
        'kk.uses a || return' \
        'NEEDA_LOADS=$(( ${NEEDA_LOADS:-0} + 1 ))'
    # header placement (R4): shebang + blank line; shebang + comment block; CRLF
    mkdir -p "$fx/kcl/shb" "$fx/kcl/cmt" "$fx/kcl/crlf"
    printf '%s\n' '#!/bin/bash' '' \
        '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%shb.sh}../../kbool.sh" || return' \
        'kk.unit shb || return $__kk_unit_rc' 'SHB_LOADS=$(( ${SHB_LOADS:-0} + 1 ))' > "$fx/kcl/shb/shb.sh"
    printf '%s\n' '#!/bin/bash' '' '# cmt.sh — a unit with a comment block' '#' \
        '#   (c) someone, licence text, a few lines of description' '' \
        '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%cmt.sh}../../kbool.sh" || return' \
        'kk.unit cmt || return $__kk_unit_rc' 'CMT_LOADS=$(( ${CMT_LOADS:-0} + 1 ))' > "$fx/kcl/cmt/cmt.sh"
    printf '%s\r\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%crlf.sh}../../kbool.sh" || return' \
        'kk.unit crlf || return $__kk_unit_rc' 'CRLF_LOADS=1' > "$fx/kcl/crlf/crlf.sh"
    # R14: a calling file in a folder whose NAME is a command substitution — a
    # registry key built from it must never be evaluated (arithmetic subscript)
    mkdir -p "$fx/inj/d[\$(touch PWN)]" "$fx/cwd"
    printf '%s\n' 'kk.uses a b; echo "inj rc=$? A=${A_LOADS:-0} B=${B_LOADS:-0}"' \
        'kk.uses a b; echo "inj again rc=$?"' > "$fx/inj/d[\$(touch PWN)]/caller.sh"
    # the header after more than two code lines is not a header
    mkdir -p "$fx/kcl/late"
    printf '%s\n' '#!/bin/bash' 'LATE_X=1' 'LATE_Y=2' 'kk.unit late || return $__kk_unit_rc' > "$fx/kcl/late/late.sh"
    uf_unit "$fx" args \
        'ARGS_LOADS=$(( ${ARGS_LOADS:-0} + 1 )); ARGS_N=$#; ARGS_1="${1-}"'
    uf_unit "$fx" kdir \
        'KDIR_TOP="${KK_UNIT_DIR-}"' \
        'kk.uses b || return' \
        'KDIR_AFTER="${KK_UNIT_DIR-}"'
    # a function defined IN the unit re-sources it at the depth of the first load:
    # its frame has the unit's BASH_SOURCE but is not a `source` frame (no false cycle)
    uf_unit "$fx" fnu \
        'FNU_LOADS=$(( ${FNU_LOADS:-0} + 1 ))' \
        'fnu.reuse() { source "$FX/kcl/fnu/fnu.sh"; }'
    # U33: the header names another unit than the file stem
    uf_unit "$fx" bad 'BAD_LOADS=1'
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%bad.sh}../../kbool.sh" || return' \
        'kk.unit wrongname || return $__kk_unit_rc' 'BAD_LOADS=1' > "$fx/kcl/bad/bad.sh"
    # a second unit named `a` in another folder (same name, different file)
    mkdir -p "$fx/kcl/zdup"
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%a.sh}../../kbool.sh" || return' \
        'kk.unit a || return $__kk_unit_rc' 'DUP_LOADS=1' > "$fx/kcl/zdup/a.sh"
    # header-less files: a bench script next to a unit, a helper (U13')
    printf '%s\n' 'BENCH_LOADS=$(( ${BENCH_LOADS:-0} + 1 ))' > "$fx/kcl/a/bench.sh"
    printf '%s\n' 'HELPER_LOADS=$(( ${HELPER_LOADS:-0} + 1 ))' > "$fx/kcl/a/helper.sh"

    # a user project outside the kbool tree (caller dir first, U14; KBOOL_HOME shape, P1)
    uf_user "$fx/proj/a.sh" a 'PROJ_A_LOADS=$(( ${PROJ_A_LOADS:-0} + 1 ))'
    uf_user "$fx/proj/lib/user.sh" user 'USER_LOADS=$(( ${USER_LOADS:-0} + 1 ))'
    printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.uses a || exit 8' \
        'echo "proj=${PROJ_A_LOADS:-0} kcl=${A_LOADS:-0}"' > "$fx/proj/main.sh"
    # R3, both directions: the project's `a` first, then a kcl unit needing the kcl `a` ...
    printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.uses a; kk.uses needa' \
        'echo "rc=$? proj=${PROJ_A_LOADS:-0} kcl=${A_LOADS:-0} needa=${NEEDA_LOADS:-0}"' > "$fx/proj/main1.sh"
    # ... and the kcl `a` first (through needa), then the project's `a` by name
    printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.uses needa; kk.uses a' \
        'echo "rc=$? proj=${PROJ_A_LOADS:-0} kcl=${A_LOADS:-0} needa=${NEEDA_LOADS:-0}"' > "$fx/proj/main2.sh"
    # a user unit named like a system unit, in the caller's folder
    uf_user "$fx/proj3/klib.sh" klib 'USERKLIB=1'
    printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.uses klib' \
        'echo "rc=$? userklib=${USERKLIB:-0}"' > "$fx/proj3/main.sh"
}

uf_run() {
    # hermetic (C5, U1b): none of the caller's loader variables reach the child,
    # and every config lookup points into the fixture — HOME is a fixture folder,
    # USERPROFILE / ProgramData (and the never-read PROGRAMDATA) are unset, and
    # the system folder /etc/kbool is replaced by __KK_CFG_ETC (kuse.sh's test
    # hook). A snippet exports its own values to test a level.
    UF_OUT="$(env -u KBOOL_HOME -u KBOOL_CONFIG -u VERBOSE_KKLASS -u KK_UNIT_DIR -u __KK_LOADED \
        -u USERPROFILE -u ProgramData -u PROGRAMDATA \
        HOME="$UF_FX/home" __KK_CFG_ETC="$UF_FX/etc/kbool" FX="$UF_FX" "$BASH" -c "$1" 2>&1)"
    UF_RC=$?
}

# uf_win /c/x/y -> UF_WIN='C:\x\y' (lexical; only for a /<drive>/ path)
uf_win() {
    local __d=${1:1:1} __r=${1:2}
    [[ $1 == /[A-Za-z]/* ]] || { echo "uf_win: not a /<drive>/ path: $1" >&2; return 1; }
    UF_WIN="${__d^^}:${__r//\//\\}"
}

# uf_cfg FILE LINE...  — write a config file (LF line ends)
uf_cfg() {
    local f="$1"; shift
    mkdir -p "${f%/*}"
    printf '%s\n' "$@" > "$f"
}

# uf_check TITLE COND-RESULT DETAIL — pass/fail on a [[ ]] already evaluated by the caller
uf_check() {
    local title="$1" ok="$2"
    kt_test_start "$title"
    if [[ "$ok" == 0 ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title — rc=$UF_RC out='${UF_OUT//$'\n'/ | }'"
    fi
}
