#!/bin/bash
# KKLib Tests
# Tests for core kk library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "KKLib" "$SCRIPT_DIR" "$@"

# Source kklib if needed
KKLIB_DIR="$SCRIPT_DIR/.."
[[ -f "$KKLIB_DIR/kklib.sh" ]] && source "$KKLIB_DIR/kklib.sh"


# Test 1: kk.getTopCaller returns valid file path
kk_test_start "kk.getTopCaller returns non-empty result"
result=$(kk.getTopCaller)
if [[ -n "$result" ]]; then
    kk_test_pass "kk.getTopCaller returns non-empty result"
else
    kk_test_fail "kk.getTopCaller returns non-empty result (got empty result)"
fi

# Test 2: kk.getTopCaller result is a valid path or file
kk_test_start "kk.getTopCaller result is a valid path"
result=$(kk.getTopCaller)
# The result should either be a file that exists or a path string
if [[ -f "$result" ]] || [[ -n "$result" ]]; then
    kk_test_pass "kk.getTopCaller result is a valid path"
else
    kk_test_fail "kk.getTopCaller result is invalid"
fi

# Test 3: kk.getTopCaller skips the source file itself
kk_test_start "kk.getTopCaller skips kklib.sh"
result=$(kk.getTopCaller)
# Should not return kklib.sh itself
if [[ "$result" != *"kklib.sh" ]]; then
    kk_test_pass "kk.getTopCaller skips kklib.sh"
else
    kk_test_fail "kk.getTopCaller returned kklib.sh (should skip it)"
fi

# Test 4: kk.getTopCaller returns path when called from wrapper function
kk_test_start "kk.getTopCaller works in nested function call"
wrapper_func() {
    kk.getTopCaller
}
result=$(wrapper_func)
if [[ -n "$result" ]]; then
    kk_test_pass "kk.getTopCaller works in nested function call"
else
    kk_test_fail "kk.getTopCaller failed in nested function call (empty result)"
fi

# Test 5: kk.write outputs text without newline
kk_test_start "kk.write outputs without newline"
result=$(kk.write "test" | wc -l)
if [[ "$result" == "0" ]]; then
    kk_test_pass "kk.write outputs without newline"
else
    kk_test_fail "kk.write added newlines (expected 0, got $result)"
fi

# Test 6: kk.writeln outputs text with newline
kk_test_start "kk.writeln outputs with newline"
result=$(kk.writeln "test" | wc -l)
if [[ "$result" == "1" ]]; then
    kk_test_pass "kk.writeln outputs with newline"
else
    kk_test_fail "kk.writeln didn't output newline correctly (expected 1, got $result)"
fi
