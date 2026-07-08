#!/bin/bash
# Hardening regression tests for kkore
# Guards the fixes from the optimization effort:
#   P0.1 kv.new deterministic uniqueness (was a ~14% $RANDOM collision)
#   P2.4 kv.set/get/free signal non-zero on empty name
#   P2.5 kc.iasAlias fork-free nameref detection
#   P2.3 kk.getScriptDir sets RESULT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "HardeningRegression" "$SCRIPT_DIR" "$@"

KKORE_DIR="$SCRIPT_DIR/.."
[[ -f "$KKORE_DIR/klib.sh" ]] && source "$KKORE_DIR/klib.sh"
[[ -f "$KKORE_DIR/kerr.sh" ]] && source "$KKORE_DIR/kerr.sh"
[[ -f "$KKORE_DIR/kvar.sh" ]] && source "$KKORE_DIR/kvar.sh"
[[ -f "$KKORE_DIR/kcfg.sh" ]] && source "$KKORE_DIR/kcfg.sh"
[[ -f "$KKORE_DIR/kuse.sh" ]] && source "$KKORE_DIR/kuse.sh"

# P0.1: kv.new must produce unique names even when called from the same line in
# a tight loop (the old $RANDOM key collided ~14% of the time over 100 draws).
kt_test_start "kv.new produces unique names in a 1000-iteration tight loop"
declare -A _seen=()
_dup_name=""
for ((i = 0; i < 1000; i++)); do
    kv.new "val_$i"
    _n="$RESULT"
    if [[ -n "${_seen[$_n]:-}" ]]; then
        _dup_name="$_n"
        break
    fi
    _seen[$_n]=1
done
if [[ -z "$_dup_name" && ${#_seen[@]} -eq 1000 ]]; then
    kt_test_pass "kv.new produces unique names in a 1000-iteration tight loop"
else
    kt_test_fail "kv.new collision: duplicate '$_dup_name' (unique=${#_seen[@]}/1000)"
fi

# P2.4: empty variable name must return non-zero (was a bare 'return' ~= 0).
kt_test_start "kv.set returns non-zero on empty variable name"
kv.set "" "value" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    kt_test_pass "kv.set returns non-zero on empty variable name"
else
    kt_test_fail "kv.set returned 0 for empty name"
fi

kt_test_start "kv.get returns non-zero on empty variable name"
kv.get "" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    kt_test_pass "kv.get returns non-zero on empty variable name"
else
    kt_test_fail "kv.get returned 0 for empty name"
fi

kt_test_start "kv.free returns non-zero on empty variable name"
kv.free "" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    kt_test_pass "kv.free returns non-zero on empty variable name"
else
    kt_test_fail "kv.free returned 0 for empty name"
fi

# P2.5: kc.iasAlias must detect a nameref and reject a non-nameref, fork-free.
kt_test_start "kc.iasAlias detects a config alias nameref"
kc.set "feature_x" "true"
kc.alias "feature_x"
if kc.iasAlias "kc_feature_x"; then
    kt_test_pass "kc.iasAlias detects a config alias nameref"
else
    kt_test_fail "kc.iasAlias failed to detect nameref kc_feature_x"
fi

kt_test_start "kc.iasAlias returns false for a plain variable"
if ! kc.iasAlias "PATH"; then
    kt_test_pass "kc.iasAlias returns false for a plain variable"
else
    kt_test_fail "kc.iasAlias wrongly reported PATH as a nameref"
fi

# P1.6: kc.alias must reject an invalid (non-identifier) key rather than corrupt
# the declare.
kt_test_start "kc.alias rejects an invalid key"
kc.alias 'bad]=x; echo hi' >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    kt_test_pass "kc.alias rejects an invalid key"
else
    kt_test_fail "kc.alias accepted an invalid key"
fi

# P2.3: kk.getScriptDir must set RESULT (so callers can avoid a $(...) fork).
kt_test_start "kk.getScriptDir sets RESULT"
RESULT=""
kk.getScriptDir "$SCRIPT_DIR/005_HardeningRegression.sh" >/dev/null
if [[ -n "$RESULT" && -d "$RESULT" ]]; then
    kt_test_pass "kk.getScriptDir sets RESULT"
else
    kt_test_fail "kk.getScriptDir did not set RESULT (got '$RESULT')"
fi
