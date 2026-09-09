#!/bin/bash
# DebugAndOutName — kk.debug / kk._outName (kcl plan P9, finding P8-F1).
#
# Two idioms are repeated across the kcl corpus and were deferred to P9:
#
#   1. `[[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "..." >&2` — the D2 error
#      channel, written out ~80 times in 11 units, in three spellings (echo /
#      printf / a unit-local `_debug` wrapper), each of which returns rc 1 when
#      the switch is off. `kk.debug MSG...` is that idiom with one spelling and
#      an unconditional rc 0, so it is also safe as the last statement of a
#      function under `set -e`.
#
#   2. The §1.7 output-array name check (`kcl/README.md`): a plain identifier,
#      not a kklass reserved name, not in the unit's own local-variable prefix
#      space, not one of the receiving instance's own arrays. Seven units carry
#      a hand-written copy (P8-F1); `kk._outName NAME [PREFIX...]` is the shared
#      core they can delegate to.
#
# Contract (both): silent on every path, fork-free, `set -eu` clean, the
# argument is never expanded or evaluated.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "DebugAndOutName" "$SCRIPT_DIR" "$@"

KKORE_DIR="$SCRIPT_DIR/.."
source "$KKORE_DIR/klib.sh"

TMPD="$(kt_fixture_tmpdir)"
OUTF="$TMPD/out"
ERRF="$TMPD/err"

# ============================================================================
# kk.debug
# ============================================================================

kt_test_start "kk.debug is defined [P9]"
if declare -F kk.debug >/dev/null 2>&1; then
    kt_test_pass "defined"
else
    kt_test_fail "kk.debug does not exist"
fi

# --- off by default: nothing anywhere, rc 0 ----------------------------------
for sw in "<unset>" "" "info" "verbose" "DEBUG" "debug " " debug"; do
    kt_test_start "kk.debug is silent when VERBOSE_KKLASS='$sw' [D2]"
    if [[ "$sw" == "<unset>" ]]; then unset VERBOSE_KKLASS; else VERBOSE_KKLASS="$sw"; fi
    kk.debug "must not appear" >"$OUTF" 2>"$ERRF"; rc=$?
    out="$(<"$OUTF")"; err="$(<"$ERRF")"
    if [[ $rc -eq 0 && -z "$out" && -z "$err" ]]; then
        kt_test_pass "rc=0, silent"
    else
        kt_test_fail "rc=$rc stdout='$out' stderr='$err'"
    fi
done
unset VERBOSE_KKLASS

# --- on: exactly the message, on stderr, with one trailing newline -----------
kt_test_start "kk.debug prints MSG to stderr under VERBOSE_KKLASS=debug [D2]"
VERBOSE_KKLASS=debug
kk.debug "Error: TList.Get: index out of bounds" >"$OUTF" 2>"$ERRF"; rc=$?
out="$(<"$OUTF")"
err="$(cat "$ERRF")"
bytes=$(wc -c <"$ERRF")
if [[ $rc -eq 0 && -z "$out" && "$err" == "Error: TList.Get: index out of bounds" \
      && "$bytes" -eq 38 ]]; then
    kt_test_pass "rc=0, stderr exact, $bytes bytes"
else
    kt_test_fail "rc=$rc stdout='$out' stderr='$err' bytes=$bytes"
fi
unset VERBOSE_KKLASS

# --- the message is DATA: no echo-option eating, no % expansion, no escapes ---
# `echo "-e"` swallows the argument and `printf "$msg"` would read `%s` as a
# format — the two ways the corpus's hand-written spellings can lose a message.
VERBOSE_KKLASS=debug
DATA_MSGS=( '-e' '-n' '-neE' '100%% done' 'a%sb' 'back\slash' 'tab\there' '--' )
for msg in "${DATA_MSGS[@]}"; do
    kt_test_start "kk.debug emits '$msg' verbatim [contract: values are data]"
    kk.debug "$msg" 2>"$ERRF"
    err="$(cat "$ERRF")"
    if [[ "$err" == "$msg" ]]; then
        kt_test_pass "verbatim"
    else
        kt_test_fail "got '$err'"
    fi
done
unset VERBOSE_KKLASS

kt_test_start "kk.debug joins its arguments with a single space [P9]"
VERBOSE_KKLASS=debug
kk.debug Error: TDictionary.Add: duplicate 2>"$ERRF"
err="$(cat "$ERRF")"
[[ "$err" == "Error: TDictionary.Add: duplicate" ]] && kt_test_pass "$err" \
    || kt_test_fail "got '$err'"
unset VERBOSE_KKLASS

kt_test_start "kk.debug with NO argument is rc 0 and prints an empty line [P9]"
VERBOSE_KKLASS=debug
kk.debug 2>"$ERRF"; rc=$?
bytes=$(wc -c <"$ERRF")
[[ $rc -eq 0 && "$bytes" -eq 1 ]] && kt_test_pass "rc=0, $bytes byte" \
    || kt_test_fail "rc=$rc bytes=$bytes"
unset VERBOSE_KKLASS

# --- rc 0 ALWAYS: this is the whole point of the helper ----------------------
# The `[[ … ]] && echo` spelling returns 1 with the switch off, so a member that
# ends on it returns 1 by accident and aborts an `set -e` caller.
kt_test_start "kk.debug returns 0 as the LAST statement of a function under set -e [D7]"
out="$(bash -c "set -e
source '$KKORE_DIR/klib.sh'
f() { kk.debug 'note'; }
g() { VERBOSE_KKLASS=debug kk.debug 'note'; }
f 2>/dev/null; printf 'off:%s,' \$?
g 2>/dev/null; printf 'on:%s' \$?" 2>"$ERRF")"
err="$(<"$ERRF")"
if [[ "$out" == "off:0,on:0" && -z "$err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "out='$out' stderr='$err'"
fi

kt_test_start "kk.debug is set -u clean with and without an argument [D7]"
out="$(bash -c "set -eu
source '$KKORE_DIR/klib.sh'
kk.debug
kk.debug 'x'
VERBOSE_KKLASS=debug
kk.debug
kk.debug 'y'
printf 'survived'" 2>"$ERRF" >"$OUTF"; printf '%s' "$(<"$OUTF")")"
err="$(<"$ERRF")"
if [[ "$out" == "survived" && "$err" == $'\ny' ]]; then
    kt_test_pass "survived, stderr='<nl>y'"
else
    kt_test_fail "out='$out' stderr='${err//$'\n'/<nl>}'"
fi

kt_test_start "kk.debug does not fork [perf contract]"
before="$BASHPID"
kk.debug "x" 2>/dev/null; a="$BASHPID"
VERBOSE_KKLASS=debug kk.debug "x" 2>/dev/null; b="$BASHPID"
unset VERBOSE_KKLASS
if [[ "$a" == "$before" && "$b" == "$before" ]]; then
    kt_test_pass "same shell ($before)"
else
    kt_test_fail "forked: $before -> $a / $b"
fi

kt_test_start "kk.debug leaves RESULT and REPLY alone [contract]"
RESULT="keep-r"; REPLY="keep-y"
VERBOSE_KKLASS=debug kk.debug "noise" 2>/dev/null
unset VERBOSE_KKLASS
[[ "$RESULT" == "keep-r" && "$REPLY" == "keep-y" ]] \
    && kt_test_pass "untouched" || kt_test_fail "RESULT='$RESULT' REPLY='$REPLY'"

# ============================================================================
# kk._outName  (finding P8-F1)
# ============================================================================

kt_test_start "kk._outName is defined [P8-F1]"
if declare -F kk._outName >/dev/null 2>&1; then
    kt_test_pass "defined"
else
    kt_test_fail "kk._outName does not exist"
fi

# --- accepted: plain identifiers ---------------------------------------------
unset __inst__ 2>/dev/null || true
OK_NAMES=( out parts _x _ A1 a_b_c OUT lines2 x9 items data class matches
           tlist_items myRESULT RESULTS __t __ts __tsx )
for name in "${OK_NAMES[@]}"; do
    kt_test_start "kk._outName '$name' -> rc 0 [P8-F1]"
    kk._outName "$name" >"$OUTF" 2>"$ERRF"; rc=$?
    out="$(<"$OUTF")"; err="$(<"$ERRF")"
    if [[ $rc -eq 0 && -z "$out$err" ]]; then
        kt_test_pass "rc=0, silent"
    else
        kt_test_fail "rc=$rc stdout='$out' stderr='$err'"
    fi
done

# --- rejected: not a plain identifier ----------------------------------------
BAD_SHAPE=( '' ' ' 'a b' '1bad' '0' 'a-b' 'a.b' 'a[0]' 'a[$(touch pwn)]' '$x'
            'a;id' 'a/b' 'a+b' 'x*' '-e' '--' 'a\b' )
BAD_SHAPE+=( $'a\nb' )
for name in "${BAD_SHAPE[@]}"; do
    kt_test_start "kk._outName '${name//$'\n'/<nl>}' -> rc 2, silent [P8-F1]"
    kk._outName "$name" >"$OUTF" 2>"$ERRF"; rc=$?
    out="$(<"$OUTF")"; err="$(<"$ERRF")"
    if [[ $rc -eq 2 && -z "$out$err" ]]; then
        kt_test_pass "rc=2, silent"
    else
        kt_test_fail "rc=$rc stdout='$out' stderr='$err'"
    fi
done

# --- rejected: the kklass reserved set (kcl/README.md §1.7) ------------------
# `state` is in the list because kklass binds it as a nameref onto
# `${inst}_data` in EVERY member frame (kklass.sh:359), so an output array named
# `state` can never reach the caller from inside an instance member — it is a
# framework fact, not a per-unit convention (owner decision, kcl P9).
RESERVED=( this __inst__ __class__ RESULT REPLY IFS state
           __kk_ __kk_v __kk_anything __KK_INT __KK_NUM __KK_ )
for name in "${RESERVED[@]}"; do
    kt_test_start "kk._outName refuses the reserved name '$name' [P8-F1, §1.7]"
    kk._outName "$name" >"$OUTF" 2>"$ERRF"; rc=$?
    out="$(<"$OUTF")"; err="$(<"$ERRF")"
    if [[ $rc -eq 2 && -z "$out$err" ]]; then
        kt_test_pass "rc=2, silent"
    else
        kt_test_fail "rc=$rc stdout='$out' stderr='$err'"
    fi
done

# --- rejected: the caller's own reserved prefixes ----------------------------
# Every unit names its locals with one prefix precisely because bash scopes
# locals DYNAMICALLY: an output name equal to one of them binds the nameref to
# the unit's own scratch (G2-02, T8, TSH-16).
PREFIXES=( __tqs_ __ts_ __td_ __tif_ __tre_ __trx_ __tsh_ __ta_ __tol_ __tca_ )
for p in "${PREFIXES[@]}"; do
    kt_test_start "kk._outName '${p}items' with prefix '$p' -> rc 2 [P8-F1]"
    kk._outName "${p}items" "$p" >"$OUTF" 2>"$ERRF"; rc=$?
    out="$(<"$OUTF")"; err="$(<"$ERRF")"
    if [[ $rc -eq 2 && -z "$out$err" ]]; then
        kt_test_pass "rc=2, silent"
    else
        kt_test_fail "rc=$rc stdout='$out' stderr='$err'"
    fi
done

kt_test_start "kk._outName refuses 'state' but not names merely containing it [P9, §1.7]"
# The refusal must be the exact name: `states`, `my_state` and `state2` are
# ordinary caller arrays and must keep working.
kk._outName state 2>/dev/null; rc_state=$?
bad=""
for n in states my_state state2 stateful _state; do
    kk._outName "$n" 2>/dev/null || bad+="$n "
done
if [[ $rc_state -eq 2 && -z "$bad" ]]; then
    kt_test_pass "state -> rc 2, neighbours accepted"
else
    kt_test_fail "state rc=$rc_state, wrongly refused: $bad"
fi

kt_test_start "kk._outName accepts a name that only RESEMBLES a reserved prefix [P8-F1]"
fails=""
for spec in "tqs_items|__tqs_" "x__tqs_a|__tqs_" "_tqs_x|__tqs_" "__tq_x|__tqs_"; do
    n="${spec%%|*}"; p="${spec#*|}"
    kk._outName "$n" "$p" 2>/dev/null || fails+="$n "
done
[[ -z "$fails" ]] && kt_test_pass "all accepted" || kt_test_fail "wrongly refused: $fails"

kt_test_start "kk._outName checks EVERY prefix it is given [P8-F1]"
kk._outName "__trx_g" __tre_ __trx_ 2>/dev/null; rc1=$?
kk._outName "__tre_g" __tre_ __trx_ 2>/dev/null; rc2=$?
kk._outName "out"     __tre_ __trx_ 2>/dev/null; rc3=$?
if [[ $rc1 -eq 2 && $rc2 -eq 2 && $rc3 -eq 0 ]]; then
    kt_test_pass "2/2/0"
else
    kt_test_fail "rc=$rc1/$rc2/$rc3"
fi

kt_test_start "kk._outName ignores an EMPTY prefix argument [P8-F1]"
# An empty prefix would otherwise match every name and refuse the lot.
kk._outName "out" "" 2>/dev/null; rc=$?
[[ $rc -eq 0 ]] && kt_test_pass "rc=0" || kt_test_fail "rc=$rc"

# --- rejected: the receiving instance's own storage --------------------------
# Inside a kklass member body `__inst__` is the instance name; `<inst>_data`,
# `<inst>_class` and `<inst>_items` are its own arrays, and binding an output
# nameref to one of them wipes the object and reports success (G2-02).
kt_test_start "kk._outName refuses the instance's own arrays when __inst__ is set [P8-F1, §1.7]"
__inst__="obj7"
fails=""
for n in obj7_data obj7_class obj7_items; do
    kk._outName "$n" 2>/dev/null && fails+="$n "
done
unset __inst__
[[ -z "$fails" ]] && kt_test_pass "all refused" || kt_test_fail "accepted: $fails"

kt_test_start "kk._outName accepts another instance's arrays and unrelated <inst>_* names [P8-F1]"
__inst__="obj7"
fails=""
for n in obj8_data obj7_other obj7 obj7_datax xobj7_data; do
    kk._outName "$n" 2>/dev/null || fails+="$n "
done
unset __inst__
[[ -z "$fails" ]] && kt_test_pass "all accepted" || kt_test_fail "refused: $fails"

kt_test_start "kk._outName does not invent an instance when __inst__ is empty/unset [P8-F1]"
unset __inst__ 2>/dev/null || true
kk._outName "_data" 2>/dev/null; rc1=$?
__inst__=""
kk._outName "_data" 2>/dev/null; rc2=$?
kk._outName "_class" 2>/dev/null; rc3=$?
unset __inst__
if [[ $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 ]]; then
    kt_test_pass "0/0/0"
else
    kt_test_fail "rc=$rc1/$rc2/$rc3"
fi

# --- it must never EXECUTE the name it is handed ------------------------------
kt_test_start "kk._outName never evaluates its argument [X-INJ]"
canary="$TMPD/pwned"
rm -f "$canary"
kk._outName "a[\$(touch '$canary')]" >/dev/null 2>&1
kk._outName "\$(touch '$canary')" >/dev/null 2>&1
kk._outName "out" "\$(touch '$canary')" >/dev/null 2>&1
[[ ! -e "$canary" ]] && kt_test_pass "no side effect" || kt_test_fail "argument was evaluated"

kt_test_start "kk._outName does not create or modify the variable it validates [P8-F1]"
unset probe_var 2>/dev/null || true
kk._outName probe_var 2>/dev/null
if [[ -z "${probe_var+set}" ]]; then
    kt_test_pass "still unset"
else
    kt_test_fail "probe_var now '${probe_var}'"
fi

kt_test_start "kk._outName is set -eu clean [D7]"
out="$(bash -c "set -eu
source '$KKORE_DIR/klib.sh'
kk._outName out    && printf 'ok,'
kk._outName '1bad' || printf 'rc=%s,' \$?
kk._outName        || printf 'noarg=%s,' \$?
kk._outName x __p_ && printf 'pfx-ok'" 2>"$ERRF")"
err="$(<"$ERRF")"
if [[ "$out" == "ok,rc=2,noarg=2,pfx-ok" && -z "$err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "out='$out' stderr='$err'"
fi

kt_test_start "kk._outName does not fork [perf contract]"
before="$BASHPID"
kk._outName out; a="$BASHPID"
kk._outName "1bad" 2>/dev/null; b="$BASHPID"
kk._outName out __x_ __y_; c="$BASHPID"
if [[ "$a" == "$before" && "$b" == "$before" && "$c" == "$before" ]]; then
    kt_test_pass "same shell ($before)"
else
    kt_test_fail "forked: $before -> $a / $b / $c"
fi

kt_test_start "kk._outName leaves RESULT and REPLY alone [contract]"
RESULT="keep-r"; REPLY="keep-y"
kk._outName out
kk._outName "" 2>/dev/null
[[ "$RESULT" == "keep-r" && "$REPLY" == "keep-y" ]] \
    && kt_test_pass "untouched" || kt_test_fail "RESULT='$RESULT' REPLY='$REPLY'"

kt_test_start "2000 kk._outName calls cost under 1 s [perf contract]"
start="${EPOCHREALTIME/./}"
for ((i = 0; i < 2000; i++)); do kk._outName "out$i" __p_ __q_ || true; done
end="${EPOCHREALTIME/./}"
elapsed_ms=$(( (10#$end - 10#$start) / 1000 ))
if (( elapsed_ms < 1000 )); then
    kt_test_pass "${elapsed_ms} ms / 2000 calls"
else
    kt_test_fail "${elapsed_ms} ms / 2000 calls"
fi

kt_test_log "007_DebugAndOutName.sh completed"
