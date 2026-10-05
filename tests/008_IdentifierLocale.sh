#!/bin/bash
# IdentifierLocale — kk._is_ident, kk._outName and kc.alias are locale-exact
# (kklass round 4 / P12, findings L1 + L2, decision DR13).
#
# ONE identifier helper, kk._is_ident NAME (rc 0 = a plain ASCII bash
# identifier [A-Za-z_][A-Za-z0-9_]*, rc 1 otherwise), lives here in klib.sh;
# kklass (which sources klib.sh first) uses it for every class/member/instance
# name, kk._outName and kc.alias use it for theirs. No locale switch: the range
# glob plus a `*[![:ascii:]]*` guard, and under `shopt -s nocasematch` the core
# runs with nocasematch OFF (restored before returning). Before P12:
#   L1  kk._outName's range glob accepted ı İ Ａ (and é Ä ß with
#       globasciiranges off) under en_US.UTF-8, İ under nocasematch in
#       C.UTF-8 — the caller's `local -n` then printed a bash diagnostic;
#       kc.alias (`=~`) let ı/İ through under nocasematch and clobbered
#       BASH_REMATCH on EVERY call; under nocasematch kk._outName also refused
#       `result`, `Result`, `This`, `STATE`, `ifs`, `reply` (the reserved set
#       is case-SENSITIVE: bash names are).
#   L2  kklass's kk._is_ident switched `local LC_ALL=C` — ≈4.5× slower under
#       a UTF-8 caller locale (kk.derivesFrom 70 -> 213 us).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IdentifierLocale" "$SCRIPT_DIR" "$@"

KKORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$KKORE_DIR/klib.sh"
source "$KKORE_DIR/kcfg.sh"

TMPD="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMPD/err"

# ============================================================================
# The helper's home and shape
# ============================================================================
kt_test_start "kk._is_ident is defined by klib.sh alone, and by kcfg.sh alone (it sources klib.sh) [DR13]"
o1="$(bash -c 'source "$1/klib.sh"; kk._is_ident ok_1 && ! kk._is_ident "a b" && echo yes' _ "$KKORE_DIR" 2>&1)"
o2="$(bash -c 'set -u; source "$1/kcfg.sh"; kk._is_ident ok_1 && ! kk._is_ident 1a && kc.alias feat && echo yes' _ "$KKORE_DIR" 2>&1)"
o3="$(bash -c 'set -u; source "$1/klib.sh"; source "$1/kcfg.sh"; source "$1/kcfg.sh"; kk._is_ident ok && echo yes' _ "$KKORE_DIR" 2>&1)"
if [[ "$o1|$o2|$o3" == "yes|yes|yes" ]]; then kt_test_pass "klib / kcfg / klib+kcfg twice"; else kt_test_fail "klib='$o1' kcfg='$o2' both='$o3'"; fi

# kc.alias calls the helper; kk._outName (hot: every kcl output-array member)
# carries an INLINE copy of its rule — the extra call cost +20 us per call on
# bash 5.2 / msys. The copy's verdicts are pinned against the same expected
# table as kk._is_ident below (all names × 12 combinations).
kt_test_start "kc.alias calls kk._is_ident, kk._outName and kk._setOut carry its inline rule (incl. the [![:ascii:]] guard); no =~ and no locale switch left [DR13]"
bad=""
for fn in kk._outName kc.alias; do
    b="$(declare -f "$fn")" || { bad+=" $fn-missing"; continue; }
    [[ "$b" != *"=~"* ]] || bad+=" $fn-regex"
    [[ "$b" != *LC_ALL* && "$b" != *LANG* ]] || bad+=" $fn-switches-locale"
done
[[ "$(declare -f kc.alias)" == *kk._is_ident* ]] || bad+=" kc.alias-no-helper"
[[ "$(declare -f kk._outName)" == *"[![:ascii:]]"* ]] || bad+=" kk._outName-no-ascii-guard"
[[ "$(declare -f kk._setOut)" == *"[![:ascii:]]"* ]] || bad+=" kk._setOut-no-ascii-guard"
[[ "$(declare -f kk._setOut)" != *LC_ALL* ]] || bad+=" kk._setOut-switches-locale"
b="$(declare -f kk._is_ident)" || bad+=" ident-missing"
[[ "$b" != *LC_ALL* && "$b" != *LANG* ]] || bad+=" ident-switches-locale"
case "$b" in *'$('*|*'`'*|*' | '*|*'<('*) bad+=" ident-forks" ;; esac
if [[ -z "$bad" ]]; then kt_test_pass "one helper"; else kt_test_fail "$bad"; fi

kt_test_start "kk._is_ident / kk._outName / kc.alias leave BASH_REMATCH alone, also on a VALID name [L1]"
bad=""
for cmd in "kk._is_ident abc" "kk._is_ident 'a b'" "kk._outName out" "kk._outName 1bad" "kc.alias feat_ok" "kc.alias 'a b'"; do
    [[ "keep-me" =~ (keep)-(me) ]]
    eval "$cmd" >/dev/null 2>&1
    [[ "${BASH_REMATCH[*]}" == "keep-me keep me" ]] || bad+=" [$cmd] BASH_REMATCH=(${BASH_REMATCH[*]});"
done
if [[ -z "$bad" ]]; then kt_test_pass "untouched"; else kt_test_fail "$bad"; fi

kt_test_start "kk._is_ident / kk._outName do not fork, also under nocasematch [perf contract]"
before="$BASHPID"
kk._is_ident abc; a="$BASHPID"
shopt -s nocasematch
kk._is_ident abc; b="$BASHPID"
kk._outName out __x_; c="$BASHPID"
shopt -u nocasematch
if [[ "$a:$b:$c" == "$before:$before:$before" ]]; then kt_test_pass "same shell"; else kt_test_fail "forked: $before -> $a/$b/$c"; fi

# ============================================================================
# Every locale × globasciiranges × nocasematch combination, in a child shell.
# A non-identifier that slips through to an indirect expansion / nameref can
# ABORT the whole top-level command, so the child counts the names it got
# through. The expected verdicts are computed HERE with an explicit-letter
# list (character equality, no ranges, nocasematch off): exact by construction.
# ============================================================================
L='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
expect() {   # NAME -> 0 identifier / 1 not
    local n="$1"
    shopt -u nocasematch
    [[ -n "$n" && "$n" != [!${L}_]* && "$n" != *[!${L}0123456789_]* ]] && return 0
    return 1
}
names=(abc A_1 _x _ _9 Z9 a_ x0123456789 "$L" i I k K s S
       "" 9a 1a a-b "a b" a. 'a[0]' '$(touch pwn)' $'a\nb' $'a\n'
       $'\xc4\xb1' $'\xc4\xb0' $'\xef\xbc\xa1' $'\xc3\xa9' $'\xc3\x84' $'\xc3\x9f' $'a\xc4\xb1b'
       $'\xc5\xbf' $'\xe2\x84\xaa' $'\xc2\xb2' $'x\xd9\xa3' $'\xef\xbc\x91a' $'a\xc3\xa9' $'\xc4\xb1\xc4\xb0'
       $'\xff' $'a\x80' $'\xc3' $'\xc3a')
for (( i = 32; i <= 126; i++ )); do
    printf -v c "\\x$(printf %x "$i")"
    names+=("$c" "a$c")
done
: > "$TMPD/names"
for nm in "${names[@]}"; do expect "$nm"; printf '%s\0%s\0' "$nm" "$?" >> "$TMPD/names"; done
NNAMES=${#names[@]}

cat > "$TMPD/combo.sh" <<'EOF'
source "$1/klib.sh"; source "$1/kcfg.sh"
loc="$2" asc="$3" ncm="$4" ef="$5" nf="$6" total="$7"
# the names are read BEFORE the locale switch: bash 5.2's read -d '' in a UTF-8
# locale swallows the NUL after an incomplete multibyte sequence (\xc3)
mapfile -d '' -t NV < "$nf"
export LC_ALL="$loc"
if [[ $asc == on ]]; then shopt -s globasciiranges; else shopt -u globasciiranges; fi
if [[ $ncm == on ]]; then shopt -s nocasematch; else shopt -u nocasematch; fi
state() { REPLY="${LC_ALL-UNSET}|$BASHOPTS"; }
state; want_state="$REPLY"
bind() { local -n __b="$1"; : "${__b-}"; }
# kk._setOut / kk.isInt OUTVAR write the caller's variable: the name is made
# LOCAL here first (silently refused when it is no identifier), so an accepted
# one-letter name cannot clobber this script's own n, k, r, M ...
setchk() { local -- "$1" 2>/dev/null; kk._setOut "$1" v; }
isintchk() { local -- "$1" 2>/dev/null; kk.isInt 5 "$1"; }
o_id="" o_out="" o_res="" o_kc="" o_st="" o_set="" n=0
# §1 identifier verdicts (kk._is_ident, kk._outName; a nameref on an accepted name binds silently)
for (( k = 0; k < ${#NV[@]}; k += 2 )); do
    nm="${NV[k]}" want="${NV[k+1]}"
    M=0; { kk._is_ident "$nm"; r=$?; M=1; } 2>"$ef"
    [[ $M == 1 && $r == "$want" && ! -s $ef ]] || o_id+=" [$(printf %q "$nm")]=M$M:$r/want$want"
    state; [[ "$REPLY" == "$want_state" ]] || o_st+=" ident[$(printf %q "$nm")]:$REPLY"
    wo=0; (( want )) && wo=2
    M=0; { kk._outName "$nm"; r=$?; M=1; } 2>"$ef"
    [[ $M == 1 && $r == "$wo" && ! -s $ef ]] || o_out+=" [$(printf %q "$nm")]=M$M:$r/want$wo"
    if (( r == 0 )); then
        { bind "$nm"; } 2>"$ef"; [[ -s $ef ]] && o_out+=" DIAG[$(printf %q "$nm")]:$(<"$ef")"
    fi
    state; [[ "$REPLY" == "$want_state" ]] || o_st+=" outName[$(printf %q "$nm")]:$REPLY"
    M=0; { setchk "$nm"; r=$?; M=1; } 2>"$ef"
    [[ $M == 1 && $r == "$wo" && ! -s $ef ]] || o_set+=" setOut[$(printf %q "$nm")]=M$M:$r/want$wo:$(<"$ef")"
    wi=$wo; [[ -z $nm ]] && wi=0   # an EMPTY OUTVAR means "no OUTVAR" (kk.isInt contract)
    M=0; { isintchk "$nm"; r=$?; M=1; } 2>"$ef"
    [[ $M == 1 && $r == "$wi" && ! -s $ef ]] || o_set+=" isInt[$(printf %q "$nm")]=M$M:$r/want$wi:$(<"$ef")"
    state; [[ "$REPLY" == "$want_state" ]] || o_st+=" setOut[$(printf %q "$nm")]:$REPLY"
    n=$((n + 1))
done
[[ $n == "$total" ]] || o_id+=" ABORTED-after-$n-of-$total"
# §2 the reserved set is case-SENSITIVE (bash names are) in every combination
for nm in result Result This STATE ifs reply Reply Ifs __Kk_x Inst; do
    kk._outName "$nm"; r=$?; [[ $r == 0 ]] || o_res+=" $nm=$r(want0)"
done
for nm in RESULT REPLY IFS this state __inst__ __class__ __kk_x __KK_x; do
    kk._outName "$nm"; r=$?; [[ $r == 2 ]] || o_res+=" $nm=$r(want2)"
done
kk._outName __TQS_a __tqs_; r=$?; [[ $r == 0 ]] || o_res+=" prefix-case=$r(want0)"
kk._outName __tqs_a __tqs_; r=$?; [[ $r == 2 ]] || o_res+=" prefix=$r(want2)"
__inst__=foo
kk._outName FOO_data; r=$?; [[ $r == 0 ]] || o_res+=" FOO_data=$r(want0)"
kk._outName foo_data; r=$?; [[ $r == 2 ]] || o_res+=" foo_data=$r(want2)"
__inst__=""
state; [[ "$REPLY" == "$want_state" ]] || o_st+=" reserved:$REPLY"
# §3 kc.alias: own message, no bash diagnostic; valid name binds, BASH_REMATCH kept
for nm in $'\xc4\xb1' $'\xc4\xb0' $'\xef\xbc\xa1' $'\xc3\xa9' $'\xc3\x9f' $'a\xc4\xb1' 'a b' 1a; do
    M=0; { kc.alias "$nm"; r=$?; M=1; } 2>"$ef"
    e="$(<"$ef")"
    [[ $M == 1 && $r == 1 && "$e" == "kc.alias: invalid key '$nm' (must be a valid identifier)" ]] \
        || o_kc+=" [$(printf %q "$nm")]=M$M:$r:'$e'"
done
kc.set feat_ok on
[[ "keep-me" =~ (keep)-(me) ]]
kc.alias feat_ok 2>"$ef"; r=$?
[[ $r == 0 && ! -s $ef && "${kc_feat_ok:-}" == on ]] || o_kc+=" valid=$r:'$(<"$ef")':'${kc_feat_ok:-}'"
[[ "${BASH_REMATCH[*]}" == "keep-me keep me" ]] || o_kc+=" BASH_REMATCH=(${BASH_REMATCH[*]})"
state; [[ "$REPLY" == "$want_state" ]] || o_st+=" kc.alias:$REPLY"
# §4 kk._setOut's reserved space is case-sensitive too
setchk __Kk_x; r=$?; [[ $r == 0 ]] || o_set+=" __Kk_x=$r(want0)"
setchk __kk_x; r=$?; [[ $r == 2 ]] || o_set+=" __kk_x=$r(want2)"
setchk __KK_x; r=$?; [[ $r == 2 ]] || o_set+=" __KK_x=$r(want2)"
state; [[ "$REPLY" == "$want_state" ]] || o_st+=" setOut-reserved:$REPLY"
printf '%s<<S>>%s<<S>>%s<<S>>%s<<S>>%s<<S>>%s|END' "$o_id" "$o_out" "$o_res" "$o_kc" "$o_set" "$o_st"
EOF

declare -A sect=([1]="" [2]="" [3]="" [4]="" [5]="" [6]="")
for loc in C C.UTF-8 en_US.UTF-8; do
    for asc in on off; do
        for ncm in off on; do
            o="$("$BASH" "$TMPD/combo.sh" "$KKORE_DIR" "$loc" "$asc" "$ncm" "$ERRF" "$TMPD/names" "$NNAMES" 2>&1)"
            if [[ "$o" != *"|END" ]]; then
                sect[1]+=" {$loc/$asc/$ncm: no END: ${o:0:300}}"
                continue
            fi
            o="${o%|END}"
            for k in 1 2 3 4 5; do
                s="${o%%<<S>>*}"; o="${o#*<<S>>}"
                [[ -z "$s" ]] || sect[$k]+=" {$loc/$asc/$ncm:$s}"
            done
            [[ -z "$o" ]] || sect[6]+=" {$loc/$asc/$ncm:$o}"
        done
    done
done

kt_test_start "kk._is_ident: $NNAMES names (ı İ Ａ é Ä ß ſ K ² ٣ １, invalid UTF-8 bytes, every printable ASCII char alone and after 'a') × 12 combos → exact, silent, never an abort [L1, L2]"
if [[ -z "${sect[1]}" ]]; then kt_test_pass "exact"; else kt_test_fail "${sect[1]}"; fi

kt_test_start "kk._outName: the same names × 12 combos → rc 2 for every non-identifier, an accepted name binds a nameref with no bash diagnostic [L1]"
if [[ -z "${sect[2]}" ]]; then kt_test_pass "exact"; else kt_test_fail "${sect[2]}"; fi

kt_test_start "kk._outName: the reserved set and the prefixes are case-sensitive in every combo (nocasematch: result/Result/This/STATE/ifs/reply rc 0, RESULT/this/state rc 2) [L1]"
if [[ -z "${sect[3]}" ]]; then kt_test_pass "case-sensitive"; else kt_test_fail "${sect[3]}"; fi

kt_test_start "kc.alias: ı İ Ａ é ß 'a b' 1a × 12 combos → rc 1 with its OWN message only (no bash diagnostic); a valid key binds, BASH_REMATCH kept [L1]"
if [[ -z "${sect[4]}" ]]; then kt_test_pass "own message"; else kt_test_fail "${sect[4]}"; fi

kt_test_start "kk._setOut (kk.isInt OUTVAR): the same names × 12 combos → rc 2 for every non-identifier with NOTHING printed (no printf diagnostic), rc 0 for identifiers; __kk_/__KK_ refused case-sensitively [P12 review R1]"
if [[ -z "${sect[5]}" ]]; then kt_test_pass "exact, silent"; else kt_test_fail "${sect[5]}"; fi

kt_test_start "LC_ALL, nocasematch and globasciiranges are the caller's after every call, in every combo [DR13]"
if [[ -z "${sect[6]}" ]]; then kt_test_pass "restored"; else kt_test_fail "${sect[6]}"; fi

kt_test_log "008_IdentifierLocale.sh completed"
