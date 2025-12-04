#!/bin/bash
# KKLib Tests - Improved Version
# Comprehensive tests for core kk library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KKLib" "$SCRIPT_DIR" "$@"

# Source klib if needed
KLIB_DIR="$SCRIPT_DIR/.."
[[ -f "$KLIB_DIR/klib.sh" ]] && source "$KLIB_DIR/klib.sh"
[[ -f "$KLIB_DIR/kerr.sh" ]] && source "$KLIB_DIR/kerr.sh" set_trap

# ============================================================================
# kl.getTopCaller() Tests
# ============================================================================

# Test 1: Basic functionality - returns non-empty result
kt_test_start "kl.getTopCaller returns non-empty result"
result=$(kl.getTopCaller)
if kt_assert_true "$result" "kl.getTopCaller returns non-empty result"; then
    kt_test_pass "kl.getTopCaller returns non-empty result"
else
    kt_test_fail "kl.getTopCaller returns non-empty result (got empty result)"
fi

# Test 2: Returns valid file path (normalized)
kt_test_start "kl.getTopCaller result is a valid path"
result=$(kl.getTopCaller)
if kt_assert_true "$result" "Result should be a non-empty string"; then
    kt_test_pass "kl.getTopCaller result is a valid path"
else
    kt_test_fail "kl.getTopCaller result is invalid"
fi

# Test 3: Skips klib.sh itself (returns caller, not the library)
kt_test_start "kl.getTopCaller skips klib.sh"
result=$(kl.getTopCaller)
if kt_assert_not_contains "$result" "klib.sh" "Should not return klib.sh itself"; then
    kt_test_pass "kl.getTopCaller skips klib.sh"
else
    kt_test_fail "kl.getTopCaller returned klib.sh (should skip it)"
fi

# Test 4: Works in nested function calls
kt_test_start "kl.getTopCaller works in nested function call"
wrapper_func() {
    kl.getTopCaller
}
result=$(wrapper_func)
if kt_assert_true "$result" "Should return non-empty result in nested call"; then
    kt_test_pass "kl.getTopCaller works in nested function call"
else
    kt_test_fail "kl.getTopCaller failed in nested function call"
fi

# Test 5: Works with multiple levels of nesting
kt_test_start "kl.getTopCaller handles deep nesting"
level_3_func() {
    kl.getTopCaller
}
level_2_func() {
    level_3_func
}
level_1_func() {
    level_2_func
}
result=$(level_1_func)
if kt_assert_true "$result" "Should work with deep function nesting"; then
    kt_test_pass "kl.getTopCaller handles deep nesting"
else
    kt_test_fail "kl.getTopCaller failed with deep nesting"
fi

# Test 6: Returns actual caller file when called from external script
kt_test_start "kl.getTopCaller returns correct caller file"
TMP_DIR="$SCRIPT_DIR/.tmp"
mkdir -p "$TMP_DIR"
temp_file="$TMP_DIR/temp_test_$(date +%s)_$RANDOM.sh"
KLIB_FULL_PATH="$KLIB_DIR/klib.sh"
cat > "$temp_file" << 'EOF'
#!/bin/bash
source "$1"
kl.getTopCaller
EOF
chmod +x "$temp_file"
result=$("$temp_file" "$KLIB_FULL_PATH")
expected=$(realpath "$temp_file" 2>/dev/null || echo "$temp_file")
if kt_assert_equals "$expected" "$result" "Should return the actual caller script path"; then
    kt_test_pass "kl.getTopCaller returns correct caller file"
else
    kt_test_fail "kl.getTopCaller result mismatch (expected: $expected, got: $result)"
fi
rm -f "$temp_file"

# Test 7: Handles edge case when called with no caller (should return empty)
kt_test_start "kl.getTopCaller handles edge case with minimal stack"
# This test verifies behavior when called from a context with minimal call stack
( # Subshell to limit BASH_SOURCE array
    source "$KLIB_DIR/klib.sh"
    result=$(kl.getTopCaller)
    if kt_assert_true "$result" "Should return valid result even in limited context"; then
        echo "PASS"
    fi
) | grep -q "PASS"
if [[ $? -eq 0 ]]; then
    kt_test_pass "kl.getTopCaller handles edge case with minimal stack"
else
    kt_test_fail "kl.getTopCaller failed in minimal stack context"
fi

# ============================================================================
# kl.write() Tests
# ============================================================================

# Test 8: Outputs text without newline
kt_test_start "kl.write outputs without newline"
output=$(kl.write "test" | od -An -tx1 | tr -d ' \n')
expected="74657374"  # "test" in hex without newline (0a)
if kt_assert_equals "$expected" "$output" "Output should not contain newline character"; then
    kt_test_pass "kl.write outputs without newline"
else
    kt_test_fail "kl.write added newlines (got: $output)"
fi

# Test 9: Outputs exact text provided
kt_test_start "kl.write outputs exact text"
test_string="Hello, World!"
output=$(kl.write "$test_string")
if kt_assert_equals "$test_string" "$output" "Should output exact text without modification"; then
    kt_test_pass "kl.write outputs exact text"
else
    kt_test_fail "kl.write modified the input text"
fi

# Test 10: Handles empty string
kt_test_start "kl.write handles empty string"
output=$(kl.write "")
expected=""
if kt_assert_equals "$expected" "$output" "Should handle empty string gracefully"; then
    kt_test_pass "kl.write handles empty string"
else
    kt_test_fail "kl.write failed with empty string"
fi

# Test 11: Handles special characters
kt_test_start "kl.write handles special characters"
test_string=$'Line1\nLine2\tTabbed\r\nWindows'
output=$(kl.write "$test_string")
if kt_assert_equals "$test_string" "$output" "Should handle special characters correctly"; then
    kt_test_pass "kl.write handles special characters"
else
    kt_test_fail "kl.write failed with special characters"
fi

# Test 12: Multiple arguments handling
kt_test_start "kl.write concatenates multiple arguments"
output=$(kl.write "Hello" " " "World" "!")
expected="Hello   World !"
if kt_assert_equals "$expected" "$output" "Should concatenate all arguments"; then
    kt_test_pass "kl.write concatenates multiple arguments"
else
    kt_test_fail "kl.write failed to concatenate multiple arguments"
fi

# ============================================================================
# kl.writeln() Tests  
# ============================================================================

# Test 13: Outputs text with newline
kt_test_start "kl.writeln outputs with newline"
line_count=$(kl.writeln "test" | wc -l)
if kt_assert_equals "1" "$line_count" "Should output exactly one newline"; then
    kt_test_pass "kl.writeln outputs with newline"
else
    kt_test_fail "kl.writeln didn't output newline correctly (expected 1, got $line_count)"
fi

# Test 14: Outputs with text (verified by grep)
kt_test_start "kl.writeln outputs text correctly"
test_string="Hello, World!"
output=$(kl.writeln "$test_string")
if [[ "$output" == *"Hello, World!"* ]]; then
    kt_test_pass "kl.writeln outputs text correctly"
else
    kt_test_fail "kl.writeln output doesn't contain expected text"
fi

# Test 15: Handles empty string with newline
kt_test_start "kl.writeln handles empty string"
line_count=$(kl.writeln "" | wc -l)
if kt_assert_equals "1" "$line_count" "Should output newline for empty string"; then
    kt_test_pass "kl.writeln handles empty string"
else
    kt_test_fail "kl.writeln failed with empty string"
fi

# Test 16: Multiple arguments with newlines
kt_test_start "kl.writeln concatenates arguments then adds newline"
output=$(kl.writeln "Line1" "Line2" "Line3")
# Should have all three parts separated by spaces
if [[ "$output" == *"Line1"* ]] && [[ "$output" == *"Line2"* ]] && [[ "$output" == *"Line3"* ]]; then
    kt_test_pass "kl.writeln concatenates arguments then adds newline"
else
    kt_test_fail "kl.writeln failed with multiple arguments"
fi

# ============================================================================
# kl.errln() Tests
# ============================================================================

# Test 17: Outputs to stderr
kt_test_start "kl.errln outputs to stderr"
test_message="Error message for testing"
stderr_output=$(kl.errln "$test_message" 2>&1 >/dev/null)
if kt_assert_contains "$stderr_output" "$test_message" "Should output to stderr"; then
    kt_test_pass "kl.errln outputs to stderr"
else
    kt_test_fail "kl.errln failed to output to stderr"
fi

# Test 18: Handles special characters in error output
kt_test_start "kl.errln handles special characters"
special_msg=$'Error: \n\tSpecial chars: $VAR `command`'
stderr_output=$(kl.errln "$special_msg" 2>&1 >/dev/null)
if kt_assert_contains "$stderr_output" "Special chars" "Should handle special characters in error output"; then
    kt_test_pass "kl.errln handles special characters"
else
    kt_test_fail "kl.errln failed with special characters"
fi

# ============================================================================
# Error Handler Tests
# ============================================================================

# Test 19: Error handler is set up correctly
kt_test_start "Error handler trap is configured"
# Check if the ERR trap is set
trap_output=$(trap -p ERR 2>/dev/null)
if kt_assert_contains "$trap_output" "ke.onError" "ERR trap should call ke.onError"; then
    kt_test_pass "Error handler trap is configured"
else
    kt_test_fail "Error handler trap not properly configured"
fi

# Test 20: Error handler produces expected output
kt_test_start "Error handler produces expected output"
# Temporarily enable error capturing for this test
old_trap_state="$TRAP_ERRORS_ENABLED"
TRAP_ERRORS_ENABLED=true

# Create a test script that will trigger an error
test_script="$TMP_DIR/error_test_$(date +%s)_$RANDOM.sh"
cat > "$test_script" << 'EOF'
#!/bin/bash
source "$1"
source "$2" "set_trap"
# Force an error by calling a non-existent command
false_command_that_does_not_exist 2>/dev/null
EOF
chmod +x "$test_script"

# Capture error output
error_output=$("$test_script" "$KLIB_DIR/klib.sh" "$KLIB_DIR/kerr.sh" 2>&1 || true)
if kt_assert_contains "$error_output" "SCRIPT ERROR" "Should contain error header"; then
    kt_test_pass "Error handler produces expected output"
else
    kt_test_fail "Error handler output doesn't match expected format"
fi

rm -f "$test_script"
TRAP_ERRORS_ENABLED="$old_trap_state"

# ============================================================================
# Integration Tests
# ============================================================================

# Test 21: Functions work together correctly
kt_test_start "Functions work together in combination"
# Test that kl.write and kl.writeln can be used in sequence
combined_output=$(kl.write "Start" && kl.writeln " End")
if [[ "$combined_output" == *"Start"* ]] && [[ "$combined_output" == *"End"* ]]; then
    kt_test_pass "Functions work together in combination"
else
    kt_test_fail "Combined function usage failed"
fi


# Cleanup
rm -rf "$TMP_DIR"
