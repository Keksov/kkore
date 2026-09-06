#!/bin/bash
# NumericGuards — kk.isInt / kk.isNum (kcl review 2026-09-06, decision D1).
#
# X-INJ (findings G1-02, G3-04, TSH-01, TCA-05, M4, tregex T2, G6-06, G8-06):
# ~40 places across kcl push a user-supplied index or count straight into
# `(( ))` or `${!x}`, so `L.Get 'x[$(touch pwn)]'` EXECUTES the command and
# `L.Get abc` silently reads element 0. Leading-zero fields — the normal output
# of `IFS=- read y m d <<< 2011-08-09` — are read as octal and blow up
# (`encodeDate 2011 08 09`, G3-01).
#
# D1: one shared guard in kkore validates and normalises every numeric argument,
# rc 1 and no output on violation. This file is its contract.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "NumericGuards" "$SCRIPT_DIR" "$@"

KKORE_DIR="$SCRIPT_DIR/.."
source "$KKORE_DIR/klib.sh"

OUTF="$(kt_fixture_tmpdir)/guard.out"

# --- kk.isInt: accepted, with the normalised value ---------------------------
# "input|expected __KK_INT"
INT_OK=(
    "0|0"            "7|7"              "-3|-3"            "+3|3"
    "08|8"           "09|9"             "007|7"            "000|0"
    "-08|-8"         "-0|0"             "+0|0"             "0000000012|12"
    "2147483648|2147483648"             "-2147483648|-2147483648"
    "9223372036854775807|9223372036854775807"
    "-9223372036854775808|-9223372036854775808"
)
for spec in "${INT_OK[@]}"; do
    in="${spec%%|*}"; want="${spec#*|}"
    kt_test_start "kk.isInt '$in' -> rc 0, __KK_INT=$want [D1]"
    __KK_INT="<unset>"
    kk.isInt "$in" >"$OUTF" 2>&1; rc=$?
    extra="$(<"$OUTF")"
    if [[ $rc -eq 0 && "$__KK_INT" == "$want" && -z "$extra" ]]; then
        kt_test_pass "rc=0 __KK_INT=$__KK_INT"
    else
        kt_test_fail "rc=$rc __KK_INT='$__KK_INT' output='$extra'"
    fi
done

# --- kk.isInt: rejected -------------------------------------------------------
# The injection shapes come straight from the review's repro (repro/g8/inj.sh).
INT_BAD=(
    ''  ' '  '  '  'abc'  '1.5'  '1,5'  '1 2'  ' 7'  '7 '  '0x10'  '1e3'
    '--'  '-'  '+'  '++1'  '1-'  'a1'  '1a'  '10#8'  '1+1'  'inf'  'nan'  'NaN'
    'x[$(touch pwn)]'  '0[$(touch pwn)]'  '$((1+1))'
    '9223372036854775808'  '-9223372036854775809'  '99999999999999999999'
    '1;id'  'true'
)
INT_BAD+=( $'1\n2' )
for in in "${INT_BAD[@]}"; do
    kt_test_start "kk.isInt '${in//$'\n'/<nl>}' -> rc 1, silent [D1]"
    kk.isInt "$in" >"$OUTF" 2>&1; rc=$?
    extra="$(<"$OUTF")"
    if [[ $rc -eq 1 && -z "$extra" ]]; then
        kt_test_pass "rejected silently"
    else
        kt_test_fail "rc=$rc output='$extra'"
    fi
done

# --- kk.isInt must not execute anything --------------------------------------
kt_test_start "kk.isInt never evaluates its argument [X-INJ]"
canary="$(kt_fixture_tmpdir)/pwned"
rm -f "$canary"
kk.isInt "x[\$(touch '$canary')]" >/dev/null 2>&1
kk.isInt "\$(touch '$canary')" >/dev/null 2>&1
kk.isInt "0\$(touch '$canary')" >/dev/null 2>&1
[[ ! -e "$canary" ]] && kt_test_pass "no side effect" || kt_test_fail "argument was evaluated"

# --- kk.isInt: optional output variable ---------------------------------------
kt_test_start "kk.isInt VALUE OUTVAR assigns the normalised value [D1]"
idx="<unset>"
kk.isInt 007 idx; rc=$?
[[ $rc -eq 0 && "$idx" == "7" ]] && kt_test_pass "idx=7" || kt_test_fail "rc=$rc idx='$idx'"

kt_test_start "kk.isInt leaves OUTVAR untouched when the value is rejected [D1]"
idx="keep"
kk.isInt abc idx; rc=$?
[[ $rc -eq 1 && "$idx" == "keep" ]] && kt_test_pass "untouched" || kt_test_fail "rc=$rc idx='$idx'"

kt_test_start "kk.isInt rejects an OUTVAR that is not a plain identifier [X-INJ]"
canary2="$(kt_fixture_tmpdir)/pwned2"
rm -f "$canary2"
kk.isInt 5 "a[\$(touch '$canary2')]" >/dev/null 2>&1; rc=$?
if [[ $rc -ne 0 && ! -e "$canary2" ]]; then
    kt_test_pass "rc=$rc, no side effect"
else
    kt_test_fail "rc=$rc canary=$([[ -e "$canary2" ]] && echo created || echo absent)"
fi

# bash scopes locals dynamically, so an OUTVAR that happens to match one of the
# guard's OWN locals resolves to that local: the caller's variable is never
# written and the guard still reports success. The locals therefore carry the
# framework's reserved __kk_ prefix, and that prefix is refused as an OUTVAR.
kt_test_start "kk.isInt refuses an OUTVAR in the reserved __kk_ / __KK_ space [D1]"
bad_outvars=(__v __sign __zeros __n __mant __ip __fp __e __kk_v __kk_anything __KK_INT __KK_NUM)
failed=""
for name in "${bad_outvars[@]}"; do
    unset "$name" 2>/dev/null || true
    kk.isInt 42 "$name" 2>/dev/null; rc=$?
    # Either the name is refused (rc 2), or — for a name outside the reserved
    # space — it really did reach the caller. Silently doing neither is the bug.
    if [[ $rc -eq 2 ]]; then
        continue
    fi
    if [[ "${!name:-}" != "42" ]]; then
        failed+="$name(rc=$rc,value='${!name:-}') "
    fi
done
[[ -z "$failed" ]] && kt_test_pass "no OUTVAR silently swallowed" \
    || kt_test_fail "silently swallowed: $failed"

kt_test_start "kk.isNum refuses an OUTVAR in the reserved __kk_ / __KK_ space [D1]"
failed=""
for name in "${bad_outvars[@]}"; do
    unset "$name" 2>/dev/null || true
    kk.isNum 4.5 "$name" 2>/dev/null; rc=$?
    if [[ $rc -eq 2 ]]; then
        continue
    fi
    if [[ "${!name:-}" != "4.5" ]]; then
        failed+="$name(rc=$rc,value='${!name:-}') "
    fi
done
[[ -z "$failed" ]] && kt_test_pass "no OUTVAR silently swallowed" \
    || kt_test_fail "silently swallowed: $failed"

kt_test_start "kk.isInt / kk.isNum with NO argument reject cleanly under set -u [D1, D7]"
errf="$(kt_fixture_tmpdir)/noarg.err"
out="$(bash -c "set -u
source '$KKORE_DIR/klib.sh'
kk.isInt || printf 'int-rejected,'
kk.isNum || printf 'num-rejected'" 2>"$errf")"
err="$(<"$errf")"
if [[ "$out" == "int-rejected,num-rejected" && -z "$err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "out='$out' stderr='$err'"
fi

kt_test_start "the normalised value is safe in arithmetic [G3-01]"
if kk.isInt 09; then
    n=$(( __KK_INT + 1 ))
    [[ "$n" == "10" ]] && kt_test_pass "09 + 1 = 10" || kt_test_fail "got $n"
else
    kt_test_fail "kk.isInt rejected 09"
fi

# --- kk.isNum: accepted -------------------------------------------------------
# "input" or "input|expected __KK_NUM" when normalisation changes it.
NUM_OK=( '0' '7' '-3' '+3|3' '1.5' '-1.5' '+1.5|1.5' '.5' '-.5' '1.' '08' '0.0'
         '1e3' '1E3' '1e-3' '1e+3' '-2.5E-10' '3.14159265358979'
         '9999999999999999999999' '0.000000001' )
for spec in "${NUM_OK[@]}"; do
    in="${spec%%|*}"
    if [[ "$spec" == *"|"* ]]; then want="${spec#*|}"; else want="$in"; fi
    kt_test_start "kk.isNum '$in' -> rc 0, __KK_NUM=$want [D1]"
    __KK_NUM="<unset>"
    kk.isNum "$in" >"$OUTF" 2>&1; rc=$?
    extra="$(<"$OUTF")"
    if [[ $rc -eq 0 && "$__KK_NUM" == "$want" && -z "$extra" ]]; then
        kt_test_pass "rc=0 __KK_NUM=$__KK_NUM"
    else
        kt_test_fail "rc=$rc __KK_NUM='$__KK_NUM' output='$extra'"
    fi
done

# --- kk.isNum: rejected -------------------------------------------------------
# `inf`/`nan` are rejected here on purpose: they are float-engine tokens, and
# the math unit normalises them itself (R11) before or after this guard.
NUM_BAD=( '' ' ' 'abc' '.' '-.' '1.2.3' '1e' '1e+' 'e3' '1e3.5' '0x1p3' '1 2'
          '--1' '1-' 'inf' '-inf' 'nan' '1,5' '$((1))' '1[$(touch pwn)]' ' 1' '1 ' )
for in in "${NUM_BAD[@]}"; do
    kt_test_start "kk.isNum '$in' -> rc 1, silent [D1]"
    kk.isNum "$in" >"$OUTF" 2>&1; rc=$?
    extra="$(<"$OUTF")"
    if [[ $rc -eq 1 && -z "$extra" ]]; then
        kt_test_pass "rejected silently"
    else
        kt_test_fail "rc=$rc output='$extra'"
    fi
done

kt_test_start "kk.isNum VALUE OUTVAR assigns the value [D1]"
val="<unset>"
kk.isNum "+2.5" val; rc=$?
[[ $rc -eq 0 && "$val" == "2.5" ]] && kt_test_pass "val=2.5" || kt_test_fail "rc=$rc val='$val'"

# --- both guards are fork-free (they sit in every hot path) -------------------
kt_test_start "kk.isInt and kk.isNum run without forking [perf contract]"
before="$BASHPID"
kk.isInt 42; a="$BASHPID"
kk.isNum 4.2; b="$BASHPID"
if [[ "$a" == "$before" && "$b" == "$before" ]]; then
    kt_test_pass "same shell (pid $before)"
else
    kt_test_fail "forked: $before -> $a / $b"
fi

kt_test_start "1000 kk.isInt calls cost under 1 s [perf contract]"
start="${EPOCHREALTIME/./}"
for ((i = 0; i < 1000; i++)); do kk.isInt "0000$i" || true; done
end="${EPOCHREALTIME/./}"
elapsed_ms=$(( (10#$end - 10#$start) / 1000 ))
if (( elapsed_ms < 1000 )); then
    kt_test_pass "${elapsed_ms} ms / 1000 calls"
else
    kt_test_fail "${elapsed_ms} ms / 1000 calls"
fi

# --- the guards themselves must be set -u clean (D7) --------------------------
kt_test_start "kk.isInt / kk.isNum work under set -u [D7]"
errf="$(kt_fixture_tmpdir)/guard.err"
out="$(bash -c "set -u
source '$KKORE_DIR/klib.sh'
kk.isInt 08 && printf '%s,' \"\$__KK_INT\"
kk.isNum -1.5 && printf '%s' \"\$__KK_NUM\"
kk.isInt zzz || printf ',rejected'" 2>"$errf")"
err="$(<"$errf")"
if [[ "$out" == "8,-1.5,rejected" && -z "$err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "out='$out' stderr='$err'"
fi

kt_test_log "006_NumericGuards.sh completed"
