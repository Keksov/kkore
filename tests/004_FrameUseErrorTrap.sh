#!/bin/bash
# Core Tests - Frame stack (kvar), error-trap exit toggle (kerr) and kk.use (kuse)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FrameUseErrorTrap" "$SCRIPT_DIR" "$@"

KKORE_DIR="$SCRIPT_DIR/.."
source "$KKORE_DIR/kvar.sh"
source "$KKORE_DIR/kerr.sh"
source "$KKORE_DIR/kuse.sh"

# ============================================================================
# kv frame stack tests
# ============================================================================

# Test 1: framePush stores frame and returns id
kt_test_start "kv.framePush returns a frame id"
__KLIB_FRAME_STACK=()
kv.framePush "inst1" "ClassA"
frame1="$RESULT"
if kt_assert_not_equals "" "$frame1" "framePush should return a non-empty frame id"; then
    kt_test_pass "kv.framePush returns a frame id"
else
    kt_test_fail "kv.framePush did not return a frame id"
fi

# Test 2: frameCurrent returns the top frame
kt_test_start "kv.frameCurrent returns the most recent frame"
kv.frameCurrent
if kt_assert_equals "$frame1" "$RESULT" "frameCurrent should match last pushed id"; then
    kt_test_pass "kv.frameCurrent returns the most recent frame"
else
    kt_test_fail "kv.frameCurrent mismatch (got: $RESULT)"
fi

# Test 3: frameInstance / frameClass resolve metadata
kt_test_start "kv.frameInstance and kv.frameClass resolve frame metadata"
kv.frameInstance "$frame1"
inst_val="$RESULT"
kv.frameClass "$frame1"
class_val="$RESULT"
if [[ "$inst_val" == "inst1" && "$class_val" == "ClassA" ]]; then
    kt_test_pass "kv.frameInstance and kv.frameClass resolve frame metadata"
else
    kt_test_fail "frame metadata mismatch (instance: '$inst_val', class: '$class_val')"
fi

# Test 4: nested frames - current follows the top of stack
kt_test_start "Nested frames track the top of the stack"
kv.framePush "inst2" "ClassB"
frame2="$RESULT"
kv.frameCurrent
top_after_push="$RESULT"
kv.framePop
popped="$RESULT"
kv.frameCurrent
top_after_pop="$RESULT"
if [[ "$top_after_push" == "$frame2" && "$popped" == "$frame2" && "$top_after_pop" == "$frame1" ]]; then
    kt_test_pass "Nested frames track the top of the stack"
else
    kt_test_fail "Nested frame tracking failed (push: '$top_after_push', pop: '$popped', after: '$top_after_pop')"
fi

# Test 5: framePop on empty stack returns failure
kt_test_start "kv.framePop on empty stack reports failure"
kv.framePop  # removes frame1, stack now empty
if kv.framePop; then
    kt_test_fail "framePop on empty stack should fail"
else
    kt_test_pass "kv.framePop on empty stack reports failure"
fi

# Test 6: framePush validates arguments
kt_test_start "kv.framePush requires instance and class"
ke.errorsReportingOff
if kv.framePush "" "ClassX"; then
    kt_test_fail "framePush should fail with empty instance"
else
    kt_test_pass "kv.framePush requires instance and class"
fi

# ============================================================================
# kerr exit-on-error toggle tests
# ============================================================================

# Test 7: exit-on-error toggle functions set the flag
kt_test_start "ke.exitOnErrorOn/Off toggle EXIT_ON_ERROR_ENABLED"
ke.exitOnErrorOn
on_val="$EXIT_ON_ERROR_ENABLED"
ke.exitOnErrorOff
off_val="$EXIT_ON_ERROR_ENABLED"
if [[ "$on_val" == "true" && "$off_val" == "false" ]]; then
    kt_test_pass "ke.exitOnErrorOn/Off toggle EXIT_ON_ERROR_ENABLED"
else
    kt_test_fail "exit-on-error toggle failed (on: '$on_val', off: '$off_val')"
fi

# Test 8: default trap does not exit the shell (returns instead)
kt_test_start "ERR trap returns instead of exiting when exit-on-error is off"
trap_out=$(
    source "$KKORE_DIR/kerr.sh"
    ke.exitOnErrorOff
    ke.errorsReportingOff
    ke.setTrap
    false
    echo "REACHED"
)
if kt_assert_contains "$trap_out" "REACHED" "Execution should continue after a failing command"; then
    kt_test_pass "ERR trap returns instead of exiting when exit-on-error is off"
else
    kt_test_fail "ERR trap exited the shell when it should have returned (out: '$trap_out')"
fi

# Test 9: trap exits the shell when exit-on-error is on
kt_test_start "ERR trap exits the shell when exit-on-error is on"
trap_out_exit=$(
    source "$KKORE_DIR/kerr.sh"
    ke.exitOnErrorOn
    ke.errorsReportingOff
    ke.setTrap
    false
    echo "REACHED"
)
if kt_assert_not_contains "$trap_out_exit" "REACHED" "Shell should exit before reaching the echo"; then
    kt_test_pass "ERR trap exits the shell when exit-on-error is on"
else
    kt_test_fail "ERR trap did not exit when exit-on-error is on (out: '$trap_out_exit')"
fi

# ============================================================================
# kk.use tests (caller-relative resolution)
# ============================================================================

USE_TMP="$SCRIPT_DIR/.tmp/usecase"

# Test 10: kk.use resolves files relative to the caller, not kuse.sh
kt_test_start "kk.use resolves relative to the calling script"
rm -rf "$USE_TMP"
mkdir -p "$USE_TMP"
echo '__USE_TARGET_LOADED=1' > "$USE_TMP/use_target.sh"
cat > "$USE_TMP/use_helper.sh" <<'HELPER'
__USE_HELPER_RESULT="$(kk.use "use_target.sh")"
__USE_HELPER_STATUS=$?
HELPER

kk.clearUseCache
source "$USE_TMP/use_helper.sh"
expected_path="$USE_TMP/use_target.sh"
if [[ "$__USE_HELPER_STATUS" -eq 0 && "$__USE_HELPER_RESULT" == "$expected_path" ]]; then
    kt_test_pass "kk.use resolves relative to the calling script"
else
    kt_test_fail "kk.use resolution failed (status: $__USE_HELPER_STATUS, path: '$__USE_HELPER_RESULT', expected: '$expected_path')"
fi

# Test 11: kk.use returns 1 (already loaded) on second call
kt_test_start "kk.use skips already-loaded files"
cat > "$USE_TMP/use_helper2.sh" <<'HELPER'
kk.use "use_target.sh" >/dev/null
kk.use "use_target.sh" >/dev/null
__USE_HELPER2_STATUS=$?
HELPER
kk.clearUseCache
source "$USE_TMP/use_helper2.sh"
if [[ "$__USE_HELPER2_STATUS" -eq 1 ]]; then
    kt_test_pass "kk.use skips already-loaded files"
else
    kt_test_fail "kk.use should return 1 for already-loaded file (got: $__USE_HELPER2_STATUS)"
fi

# Test 12: kk.use reports an error for a missing file
kt_test_start "kk.use fails for a missing file"
cat > "$USE_TMP/use_helper3.sh" <<'HELPER'
kk.use "does_not_exist.sh" >/dev/null 2>&1
__USE_HELPER3_STATUS=$?
HELPER
source "$USE_TMP/use_helper3.sh"
if [[ "$__USE_HELPER3_STATUS" -eq 2 ]]; then
    kt_test_pass "kk.use fails for a missing file"
else
    kt_test_fail "kk.use should return 2 for a missing file (got: $__USE_HELPER3_STATUS)"
fi

rm -rf "$USE_TMP"
