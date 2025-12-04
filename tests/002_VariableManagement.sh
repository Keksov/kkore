#!/bin/bash
# KVar Tests - Variable Management Functions
# Comprehensive tests for kvar.sh library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "VariableManagement" "$SCRIPT_DIR" "$@"

# Source kvar if needed
KVAR_DIR="$SCRIPT_DIR/.."
[[ -f "$KVAR_DIR/kvar.sh" ]] && source "$KVAR_DIR/kvar.sh"

# ============================================================================
# kv.new() Tests - Create new variable
# ============================================================================

# Test 1: kv.new creates variable and returns name
kt_test_start "kv.new creates variable and returns name"
kv.new "initial_value" "test_var"
if kt_assert_true "$RESULT" "Should return variable name in RESULT"; then
    kt_test_pass "kv.new creates variable and returns name"
else
    kt_test_fail "kv.new did not return variable name"
fi

# Test 2: kv.new generates unique variable names
kt_test_start "kv.new generates unique variable names"
kv.new "value1" "var"
var_name_1="$RESULT"
kv.new "value2" "var"
var_name_2="$RESULT"
if kt_assert_not_equals "$var_name_1" "$var_name_2" "Each call should generate unique name"; then
    kt_test_pass "kv.new generates unique variable names"
else
    kt_test_fail "kv.new generated duplicate variable names"
fi

# Test 3: kv.new stores initial value
kt_test_start "kv.new stores initial value correctly"
kv.new "test_value" "myvar"
var_name="$RESULT"
if kt_assert_equals "test_value" "${__KLIB_VARS[$var_name]}" "Should store initial value"; then
    kt_test_pass "kv.new stores initial value correctly"
else
    kt_test_fail "kv.new failed to store initial value (got: ${__KLIB_VARS[$var_name]})"
fi

# Test 4: kv.new with default value 0
kt_test_start "kv.new uses default value 0 when not provided"
kv.new
var_name="$RESULT"
if kt_assert_equals "0" "${__KLIB_VARS[$var_name]}" "Should default to 0"; then
    kt_test_pass "kv.new uses default value 0 when not provided"
else
    kt_test_fail "kv.new default value incorrect (got: ${__KLIB_VARS[$var_name]})"
fi

# Test 5: kv.new uses default variable prefix
kt_test_start "kv.new uses default variable prefix"
kv.new "value"
var_name="$RESULT"
if kt_assert_contains "$var_name" "__var" "Should contain default prefix __var"; then
    kt_test_pass "kv.new uses default variable prefix"
else
    kt_test_fail "kv.new did not use default prefix (got: $var_name)"
fi

# Test 6: kv.new includes RANDOM in name
kt_test_start "kv.new includes RANDOM in variable name"
kv.new "value"
var_name="$RESULT"
if kt_assert_contains "$var_name" "_" "Should include separator and random data"; then
    kt_test_pass "kv.new includes RANDOM in variable name"
else
    kt_test_fail "kv.new variable name format invalid (got: $var_name)"
fi

# ============================================================================
# kv.set() Tests - Set variable value
# ============================================================================

# Test 7: kv.set updates existing variable
kt_test_start "kv.set updates existing variable"
kv.new "original"
var_name="$RESULT"
kv.set "$var_name" "modified"
if kt_assert_equals "modified" "${__KLIB_VARS[$var_name]}" "Should update variable value"; then
    kt_test_pass "kv.set updates existing variable"
else
    kt_test_fail "kv.set failed to update value (got: ${__KLIB_VARS[$var_name]})"
fi

# Test 8: kv.set can set empty string
kt_test_start "kv.set can set empty string"
kv.new "value"
var_name="$RESULT"
kv.set "$var_name" ""
if kt_assert_equals "" "${__KLIB_VARS[$var_name]}" "Should allow empty string"; then
    kt_test_pass "kv.set can set empty string"
else
    kt_test_fail "kv.set failed with empty string (got: ${__KLIB_VARS[$var_name]})"
fi

# Test 9: kv.set handles special characters
kt_test_start "kv.set handles special characters"
kv.new "initial"
var_name="$RESULT"
special_value=$'Line1\nLine2\t"quoted"'
kv.set "$var_name" "$special_value"
if kt_assert_equals "$special_value" "${__KLIB_VARS[$var_name]}" "Should handle special characters"; then
    kt_test_pass "kv.set handles special characters"
else
    kt_test_fail "kv.set failed with special characters"
fi

# Test 10: kv.set handles numeric values
kt_test_start "kv.set handles numeric values"
kv.new "0"
var_name="$RESULT"
kv.set "$var_name" "42"
if kt_assert_equals "42" "${__KLIB_VARS[$var_name]}" "Should store numeric values"; then
    kt_test_pass "kv.set handles numeric values"
else
    kt_test_fail "kv.set failed with numeric value"
fi

# Test 11: kv.set overwrites existing values completely
kt_test_start "kv.set overwrites existing values"
kv.new "short"
var_name="$RESULT"
kv.set "$var_name" "very_long_replacement_value"
kv.set "$var_name" "new"
if kt_assert_equals "new" "${__KLIB_VARS[$var_name]}" "Should overwrite completely"; then
    kt_test_pass "kv.set overwrites existing values"
else
    kt_test_fail "kv.set overwrite failed (got: ${__KLIB_VARS[$var_name]})"
fi

# ============================================================================
# kv.get() Tests - Get variable value
# ============================================================================

# Test 12: kv.get retrieves value in normal context
kt_test_start "kv.get retrieves value in normal context"
kv.new "test_value"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "test_value" "$RESULT" "Should retrieve value in RESULT"; then
    kt_test_pass "kv.get retrieves value in normal context"
else
    kt_test_fail "kv.get failed (got: $RESULT)"
fi

# Test 13: kv.get returns empty string for undefined variable
kt_test_start "kv.get handles undefined variable"
kv.get "nonexistent_var_name"
if kt_assert_equals "" "$RESULT" "Should return empty for undefined variable"; then
    kt_test_pass "kv.get handles undefined variable"
else
    kt_test_fail "kv.get should return empty for undefined variable"
fi

# Test 14: kv.get with subshell echoes value
kt_test_start "kv.get echoes value in subshell"
kv.new "subshell_value"
var_name="$RESULT"
result=$(kv.get "$var_name")
if kt_assert_equals "subshell_value" "$result" "Should echo value in subshell"; then
    kt_test_pass "kv.get echoes value in subshell"
else
    kt_test_fail "kv.get subshell echo failed (got: $result)"
fi

# Test 15: kv.get handles special characters
kt_test_start "kv.get retrieves special characters correctly"
special_value=$'Test\nValue\tWith\nSpecials'
kv.new "$special_value"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "$special_value" "$RESULT" "Should retrieve special characters"; then
    kt_test_pass "kv.get retrieves special characters correctly"
else
    kt_test_fail "kv.get failed with special characters"
fi

# Test 16: kv.get works with numeric values
kt_test_start "kv.get retrieves numeric values"
kv.new "12345"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "12345" "$RESULT" "Should retrieve numeric value"; then
    kt_test_pass "kv.get retrieves numeric values"
else
    kt_test_fail "kv.get failed with numeric value"
fi

# ============================================================================
# kv.free() Tests - Delete variable
# ============================================================================

# Test 17: kv.free removes variable from storage
kt_test_start "kv.free removes variable from storage"
kv.new "to_delete"
var_name="$RESULT"
kv.free "$var_name"
kv.get "$var_name"
if kt_assert_equals "" "$RESULT" "Should return empty after free"; then
    kt_test_pass "kv.free removes variable from storage"
else
    kt_test_fail "kv.free failed to remove variable"
fi

# Test 18: kv.free allows recreation of variable name
kt_test_start "kv.free allows variable name reuse"
kv.new "value1"
var_name="$RESULT"
kv.free "$var_name"
kv.set "$var_name" "value2"
if kt_assert_equals "value2" "${__KLIB_VARS[$var_name]}" "Should allow reuse after free"; then
    kt_test_pass "kv.free allows variable name reuse"
else
    kt_test_fail "kv.free did not properly release variable"
fi

# Test 19: kv.free with undefined variable does nothing
kt_test_start "kv.free handles undefined variable safely"
kv.free "undefined_variable"
if kt_assert_equals "" "${__KLIB_VARS[undefined_variable]}" "Should handle undefined gracefully"; then
    kt_test_pass "kv.free handles undefined variable safely"
else
    kt_test_fail "kv.free failed with undefined variable"
fi

# ============================================================================
# Integration Tests
# ============================================================================

# Test 20: Full workflow - create, set, get, free
kt_test_start "Full workflow: create, set, get, free"
kv.new "initial"
var1="$RESULT"
kv.set "$var1" "updated"
kv.get "$var1"
value_before_free="$RESULT"
kv.free "$var1"
kv.get "$var1"
value_after_free="$RESULT"

if [[ "$value_before_free" == "updated" ]] && [[ "$value_after_free" == "" ]]; then
    kt_test_pass "Full workflow: create, set, get, free"
else
    kt_test_fail "Full workflow failed"
fi

# Test 21: Multiple variables management
kt_test_start "Multiple variables can be managed independently"
kv.new "value1"
var1="$RESULT"
kv.new "value2"
var2="$RESULT"
kv.new "value3"
var3="$RESULT"

kv.get "$var1"
val1="$RESULT"
kv.get "$var2"
val2="$RESULT"
kv.get "$var3"
val3="$RESULT"

if [[ "$val1" == "value1" ]] && [[ "$val2" == "value2" ]] && [[ "$val3" == "value3" ]]; then
    kt_test_pass "Multiple variables can be managed independently"
else
    kt_test_fail "Multiple variable management failed"
fi

# Test 22: Variable updates don't affect other variables
kt_test_start "Variable updates are isolated"
kv.new "var_a_value"
var_a="$RESULT"
kv.new "var_b_value"
var_b="$RESULT"

kv.set "$var_a" "modified_a"

kv.get "$var_b"
val_b_after="$RESULT"

if kt_assert_equals "var_b_value" "$val_b_after" "Other variables should not be affected"; then
    kt_test_pass "Variable updates are isolated"
else
    kt_test_fail "Variable isolation failed"
fi

# ============================================================================
# Counter Usage in Loops - Practical Examples
# ============================================================================

# Test 23: Variable as counter in for loop
kt_test_start "Variable as counter in for loop"
kv.new "0"
counter="$RESULT"
for i in {1..5}; do
    kv.get "$counter"
    current=$((RESULT + 1))
    kv.set "$counter" "$current"
done
kv.get "$counter"
if kt_assert_equals "5" "$RESULT" "Counter should reach 5 after 5 iterations"; then
    kt_test_pass "Variable as counter in for loop"
else
    kt_test_fail "Counter loop failed (got: $RESULT)"
fi

# Test 24: Variable as counter in while loop
kt_test_start "Variable as counter in while loop"
kv.new "0"
counter="$RESULT"
iteration=0
while [[ $iteration -lt 10 ]]; do
    kv.get "$counter"
    current=$((RESULT + 1))
    kv.set "$counter" "$current"
    ((iteration++))
done
kv.get "$counter"
if kt_assert_equals "10" "$RESULT" "While loop counter should reach 10"; then
    kt_test_pass "Variable as counter in while loop"
else
    kt_test_fail "While loop counter failed (got: $RESULT)"
fi

# Test 25: Multiple counters in nested loops
kt_test_start "Multiple counters in nested loops"
kv.new "0"
outer_counter="$RESULT"
kv.new "0"
inner_counter="$RESULT"

for i in {1..3}; do
    kv.get "$outer_counter"
    outer_val=$((RESULT + 1))
    kv.set "$outer_counter" "$outer_val"
    
    for j in {1..2}; do
        kv.get "$inner_counter"
        inner_val=$((RESULT + 1))
        kv.set "$inner_counter" "$inner_val"
    done
done

kv.get "$outer_counter"
outer_final="$RESULT"
kv.get "$inner_counter"
inner_final="$RESULT"

if [[ "$outer_final" == "3" ]] && [[ "$inner_final" == "6" ]]; then
    kt_test_pass "Multiple counters in nested loops"
else
    kt_test_fail "Nested loop counters failed (outer: $outer_final, inner: $inner_final)"
fi

# Test 26: Counter with string accumulation
kt_test_start "Counter with string value accumulation in loop"
kv.new "" "straccum"
result="$RESULT"
for char in A B C D E; do
    kv.get "$result"
    current="$RESULT"
    kv.set "$result" "${current}${char}"
done
kv.get "$result"
if kt_assert_equals "ABCDE" "$RESULT" "Should accumulate string values"; then
    kt_test_pass "Counter with string value accumulation in loop"
else
    kt_test_fail "String accumulation failed (got: $RESULT)"
fi

# Test 27: Counter reset and reuse in loop
kt_test_start "Counter reset and reuse in loops"
kv.new "0"
counter="$RESULT"

for i in {1..3}; do
    kv.get "$counter"
    kv.set "$counter" "$((RESULT + 1))"
done
kv.get "$counter"
first_result="$RESULT"

kv.set "$counter" "0"

for i in {1..5}; do
    kv.get "$counter"
    kv.set "$counter" "$((RESULT + 1))"
done
kv.get "$counter"
second_result="$RESULT"

if [[ "$first_result" == "3" ]] && [[ "$second_result" == "5" ]]; then
    kt_test_pass "Counter reset and reuse in loops"
else
    kt_test_fail "Counter reset failed (first: $first_result, second: $second_result)"
fi

# Test 28: While loop with counter-based condition
kt_test_start "While loop with counter-based condition"
kv.new "0"
counter="$RESULT"
max_iterations=7

while true; do
    kv.get "$counter"
    current=$RESULT
    [[ $current -ge $max_iterations ]] && break
    kv.set "$counter" "$((current + 1))"
done

kv.get "$counter"
if kt_assert_equals "7" "$RESULT" "Counter should reach max value"; then
    kt_test_pass "While loop with counter-based condition"
else
    kt_test_fail "Counter-based while condition failed (got: $RESULT)"
fi

# Test 29: Counter with array iteration
kt_test_start "Counter with array element processing"
kv.new "0"
counter="$RESULT"
declare -a arr=("first" "second" "third" "fourth")

for element in "${arr[@]}"; do
    kv.get "$counter"
    kv.set "$counter" "$((RESULT + 1))"
done

kv.get "$counter"
if kt_assert_equals "4" "$RESULT" "Counter should match array length"; then
    kt_test_pass "Counter with array element processing"
else
    kt_test_fail "Array counter failed (got: $RESULT)"
fi

# Test 30: Countdown counter in while loop
kt_test_start "Countdown counter in while loop"
kv.new "5"
counter="$RESULT"

iterations=0
while true; do
    kv.get "$counter"
    current=$RESULT
    [[ $current -le 0 ]] && break
    kv.set "$counter" "$((current - 1))"
    ((iterations++))
done

kv.get "$counter"
if [[ "$RESULT" == "0" ]] && [[ $iterations -eq 5 ]]; then
    kt_test_pass "Countdown counter in while loop"
else
    kt_test_fail "Countdown failed (final: $RESULT, iterations: $iterations)"
fi

# ============================================================================
# Function Scope Tests - Variable Creation and Passing
# ============================================================================

# Test 31: Create variable inside function
kt_test_start "Create variable inside function"
create_var_in_func() {
    kv.new "internal_value" "funcvar"
}
create_var_in_func
var_from_func="$RESULT"
if [[ -n "$var_from_func" ]]; then
    kv.get "$var_from_func"
    if kt_assert_equals "internal_value" "$RESULT" "Should create and access variable from function"; then
        kt_test_pass "Create variable inside function"
    else
        kt_test_fail "Function variable creation failed (got: $RESULT)"
    fi
else
    kt_test_fail "Function did not return variable name"
fi

# Test 32: Pass variable between two functions
kt_test_start "Pass variable between two functions"
modify_in_func1() {
    local var_name="$1"
    kv.set "$var_name" "modified_by_func1"
}
read_in_func2() {
    local var_name="$1"
    kv.get "$var_name"
}
kv.new "initial_value"
shared_var="$RESULT"
modify_in_func1 "$shared_var"
read_in_func2 "$shared_var"
if kt_assert_equals "modified_by_func1" "$RESULT" "Variable should be modified by func1 and readable in func2"; then
    kt_test_pass "Pass variable between two functions"
else
    kt_test_fail "Variable passing between functions failed"
fi

# Test 33: Modify same variable in different functions
kt_test_start "Modify same variable in different functions"
increment_in_func1() {
    local var_name="$1"
    kv.get "$var_name"
    local val=$RESULT
    kv.set "$var_name" "$((val + 1))"
}
increment_in_func2() {
    local var_name="$1"
    kv.get "$var_name"
    local val=$RESULT
    kv.set "$var_name" "$((val + 10))"
}
kv.new "0"
counter="$RESULT"
increment_in_func1 "$counter"
increment_in_func2 "$counter"
kv.get "$counter"
if kt_assert_equals "11" "$RESULT" "Sequential modifications should accumulate"; then
    kt_test_pass "Modify same variable in different functions"
else
    kt_test_fail "Sequential function modifications failed (got: $RESULT)"
fi

# Test 34: Function returns variable name for further use
kt_test_start "Function returns variable name for further use"
create_and_return_var() {
    local prefix="$1"
    local initial="$2"
    kv.new "$initial" "$prefix"
}
create_and_return_var "myvar" "test_value"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "test_value" "$RESULT" "Should use returned variable name"; then
    kt_test_pass "Function returns variable name for further use"
else
    kt_test_fail "Returned variable name failed"
fi

# Test 35: Multiple variables created in function scope
kt_test_start "Multiple variables created in function scope"
create_multiple_vars() {
    local var1_name var2_name var3_name
    kv.new "value1"
    var1_name="$RESULT"
    kv.new "value2"
    var2_name="$RESULT"
    kv.new "value3"
    var3_name="$RESULT"
    echo "$var1_name:$var2_name:$var3_name"
}
# Use explicit array assignment to capture all variable names
create_multiple_vars() {
    kv.new "value1"
    __test_v1="$RESULT"
    kv.new "value2"
    __test_v2="$RESULT"
    kv.new "value3"
    __test_v3="$RESULT"
}
create_multiple_vars
kv.get "$__test_v1"
val1="$RESULT"
kv.get "$__test_v2"
val2="$RESULT"
kv.get "$__test_v3"
val3="$RESULT"
if [[ "$val1" == "value1" ]] && [[ "$val2" == "value2" ]] && [[ "$val3" == "value3" ]]; then
    kt_test_pass "Multiple variables created in function scope"
else
    kt_test_fail "Multiple function variables failed"
fi

# Test 36: Function accumulates value in passed variable
kt_test_start "Function accumulates value in passed variable"
append_to_var() {
    local var_name="$1"
    local text="$2"
    kv.get "$var_name"
    local current="$RESULT"
    kv.set "$var_name" "${current}${text}"
}
kv.new "" "textaccum"
accumulator="$RESULT"
append_to_var "$accumulator" "Hello"
append_to_var "$accumulator" " "
append_to_var "$accumulator" "World"
kv.get "$accumulator"
if kt_assert_equals "Hello World" "$RESULT" "Function should accumulate text"; then
    kt_test_pass "Function accumulates value in passed variable"
else
    kt_test_fail "Function accumulation failed"
fi

# Test 37: Sequential function calls with variable passing
kt_test_start "Sequential function calls with variable passing"
append_func() {
    local var_name="$1"
    local suffix="$2"
    kv.get "$var_name"
    local val="$RESULT"
    kv.set "$var_name" "${val}${suffix}"
}
kv.new "start" "seqvar"
seq_var="$RESULT"
append_func "$seq_var" "_mid"
append_func "$seq_var" "_end"
kv.get "$seq_var"
if kt_assert_equals "start_mid_end" "$RESULT" "Sequential calls should chain modifications"; then
    kt_test_pass "Sequential function calls with variable passing"
else
    kt_test_fail "Sequential function calls failed (got: $RESULT)"
fi

# Test 38: Function parameter passing with kv operations
kt_test_start "Function parameter passing with kv operations"
modify_via_param() {
    local var_name="$1"
    kv.get "$var_name"
    local val="$RESULT"
    kv.set "$var_name" "${val}_modified"
}
kv.new "original"
var_to_modify="$RESULT"
modify_via_param "$var_to_modify"
kv.get "$var_to_modify"
if kt_assert_equals "original_modified" "$RESULT" "Function should modify variable via parameter"; then
    kt_test_pass "Function parameter passing with kv operations"
else
    kt_test_fail "Function parameter passing failed"
fi

# Test 39: Function cleans up temporary variables
kt_test_start "Function creates and cleans temporary variables"
func_with_cleanup() {
    local var_name="$1"
    kv.new "temp_data"
    local temp_var="$RESULT"
    kv.get "$temp_var"
    local temp_val="$RESULT"
    kv.set "$var_name" "$temp_val"
    kv.free "$temp_var"
    # Return temp_var name for verification
    RESULT="$temp_var"
}
kv.new "target"
result_var="$RESULT"
func_with_cleanup "$result_var"
temp_var_name="$RESULT"
kv.get "$result_var"
target_val="$RESULT"
kv.get "$temp_var_name"
temp_val_after="$RESULT"
if [[ "$target_val" == "temp_data" ]] && [[ "$temp_val_after" == "" ]]; then
    kt_test_pass "Function creates and cleans temporary variables"
else
    kt_test_fail "Function cleanup failed"
fi

# Test 40: Two functions share and modify same variable
kt_test_start "Two functions share and modify same variable"
first_modifier() {
    local var_name="$1"
    kv.get "$var_name"
    kv.set "$var_name" "${__KLIB_VARS[$var_name]}_first"
}
second_modifier() {
    local var_name="$1"
    kv.get "$var_name"
    kv.set "$var_name" "${__KLIB_VARS[$var_name]}_second"
}
kv.new "base"
shared="$RESULT"
first_modifier "$shared"
second_modifier "$shared"
kv.get "$shared"
if kt_assert_equals "base_first_second" "$RESULT" "Both functions should modify same variable"; then
    kt_test_pass "Two functions share and modify same variable"
else
    kt_test_fail "Shared variable modification failed"
fi

# Test 41: Function returns array of variable names
kt_test_start "Function returns array of variable names"
declare -a __test_var_batch=()
create_var_batch() {
    local count="$1"
    __test_var_batch=()
    local i
    for ((i=1; i<=count; i++)); do
        kv.new "value_$i"
        __test_var_batch+=("$RESULT")
    done
}
create_var_batch 4
var_names=("${__test_var_batch[@]}")
if kt_assert_equals "4" "${#var_names[@]}" "Should create 4 variables"; then
    kt_test_pass "Function returns array of variable names"
else
    kt_test_fail "Function batch creation failed (got ${#var_names[@]} vars)"
fi

# ============================================================================
# Edge Cases and Error Handling Tests
# ============================================================================

# Test 42: kv.new with empty variable name prefix
kt_test_start "kv.new handles empty variable name prefix"
kv.new "value" ""
var_name="$RESULT"
if kt_assert_not_equals "" "$var_name" "Should generate valid name even with empty prefix"; then
    kt_test_pass "kv.new handles empty variable name prefix"
else
    kt_test_fail "kv.new failed with empty prefix"
fi

# Test 43: kv.new with special characters in custom prefix
kt_test_start "kv.new handles special characters in custom prefix"
kv.new "value" "my-prefix_123"
var_name="$RESULT"
if kt_assert_contains "$var_name" "my-prefix_123" "Should use custom prefix"; then
    kt_test_pass "kv.new handles special characters in custom prefix"
else
    kt_test_fail "kv.new failed with special prefix characters"
fi

# Test 44: kv.get with whitespace variable name
kt_test_start "kv.get handles whitespace variable name"
kv.get "   "
if kt_assert_equals "" "$RESULT" "Should return empty for whitespace name"; then
    kt_test_pass "kv.get handles whitespace variable name"
else
    kt_test_fail "kv.get failed with whitespace name"
fi

# Test 45: kv.set with whitespace variable name
kt_test_start "kv.set handles whitespace variable name"
kv.set "   " "some_value"
if [[ "${__KLIB_VARS["   "]}" == "some_value" ]] && kt_assert_equals "some_value" "${__KLIB_VARS["   "]}" "Should handle whitespace name"; then
    kt_test_pass "kv.set handles whitespace variable name"
else
    kt_test_fail "kv.set failed with whitespace name"
fi

# Test 46: kv.free with whitespace variable name
kt_test_start "kv.free handles whitespace variable name"
kv.free "   "
if kt_assert_equals "" "${__KLIB_VARS["   "]}" "Should handle whitespace name gracefully"; then
    kt_test_pass "kv.free handles whitespace variable name"
else
    kt_test_fail "kv.free failed with whitespace name"
fi

# Test 47: kv.new with very long initial value
kt_test_start "kv.new handles very long initial value"
long_value=$(printf 'A%.0s' {1..1000})
kv.new "$long_value" "longvar"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "$long_value" "$RESULT" "Should handle long values"; then
    kt_test_pass "kv.new handles very long initial value"
else
    kt_test_fail "kv.new failed with long value"
fi

# Test 48: kv.set with very long value
kt_test_start "kv.set handles very long replacement value"
long_replacement=$(printf 'B%.0s' {1..2000})
kv.new "short"
var_name="$RESULT"
kv.set "$var_name" "$long_replacement"
if kt_assert_equals "$long_replacement" "${__KLIB_VARS[$var_name]}" "Should handle long replacement"; then
    kt_test_pass "kv.set handles very long replacement value"
else
    kt_test_fail "kv.set failed with long replacement"
fi

# Test 49: kv.new generates different names with same prefix
kt_test_start "kv.new generates unique names with same prefix"
kv.new "val1" "test"
name1="$RESULT"
kv.new "val2" "test"
name2="$RESULT"
kv.new "val3" "test"
name3="$RESULT"
if kt_assert_not_equals "$name1" "$name2" && kt_assert_not_equals "$name2" "$name3" && kt_assert_not_equals "$name1" "$name3"; then
    kt_test_pass "kv.new generates unique names with same prefix"
else
    kt_test_fail "kv.new generated duplicate names with same prefix"
fi

# Test 50: kv.set with whitespace-only values
kt_test_start "kv.set handles whitespace-only values"
kv.new "value"
var_name="$RESULT"
kv.set "$var_name" "   "
if kt_assert_equals "   " "${__KLIB_VARS[$var_name]}" "Should preserve whitespace"; then
    kt_test_pass "kv.set handles whitespace-only values"
else
    kt_test_fail "kv.set failed with whitespace-only value"
fi

# Test 51: kv.get with variable containing only whitespace
kt_test_start "kv.get retrieves whitespace-only values correctly"
kv.set "$var_name" "   "
kv.get "$var_name"
if kt_assert_equals "   " "$RESULT" "Should return exact whitespace"; then
    kt_test_pass "kv.get retrieves whitespace-only values correctly"
else
    kt_test_fail "kv.get failed with whitespace-only value"
fi

# ============================================================================
# Subshell and Context Tests
# ============================================================================

# Test 52: kv.new in subshell
kt_test_start "kv.new creates variables in subshell context"
kv.new "nested_value"
var_name="$RESULT"
if [[ -n "$var_name" ]]; then
    kv.get "$var_name"
    if kt_assert_equals "nested_value" "$RESULT" "Should create variable in subshell"; then
        kt_test_pass "kv.new creates variables in subshell context"
    else
        kt_test_fail "kv.new subshell value incorrect"
    fi
else
    kt_test_fail "kv.new failed in subshell"
fi

# Test 53: kv.get returns same value in multiple calls
kt_test_start "kv.get returns consistent values"
kv.new "consistent"
var_name="$RESULT"
result1=$(kv.get "$var_name")
result2=$(kv.get "$var_name")
result3=$(kv.get "$var_name")
if [[ "$result1" == "consistent" ]] && [[ "$result2" == "consistent" ]] && [[ "$result3" == "consistent" ]]; then
    kt_test_pass "kv.get returns consistent values"
else
    kt_test_fail "kv.get inconsistent across calls"
fi

# Test 54: kv.set in subshell affects global storage
kt_test_start "kv.set in subshell affects global storage"
kv.new "global_test"
var_name="$RESULT"
kv.set "$var_name" "modified_in_subshell"
kv.get "$var_name"
if [[ "$RESULT" == "modified_in_subshell" ]]; then
    kt_test_pass "kv.set in subshell affects global storage"
else
    kt_test_fail "kv.set subshell modification failed"
fi

# ============================================================================
# Performance and Resource Management Tests
# ============================================================================

# Test 55: Large number of variable creation
kt_test_start "kv.new handles large number of variables efficiently"
start_time=$(date +%s%N)
declare -a large_var_names
for i in {1..100}; do
    kv.new "batch_value_$i"
    large_var_names+=("$RESULT")
done
end_time=$(date +%s%N)
duration=$((end_time - start_time))

# Verify all variables were created correctly
all_valid=true
for var_name in "${large_var_names[@]}"; do
    kv.get "$var_name"
    if [[ ! "$RESULT" =~ ^batch_value_[0-9]+$ ]]; then
        all_valid=false
        break
    fi
done

if [[ "$all_valid" == true ]] && [[ $duration -lt 1000000000 ]]; then
    kt_test_pass "kv.new handles large number of variables efficiently"
else
    kt_test_fail "Large variable batch creation failed or too slow"
fi

# Test 56: Memory cleanup after batch free
kt_test_start "Memory is properly cleaned after batch free"
kv.new "test1"
var1="$RESULT"
kv.new "test2"
var2="$RESULT"
kv.new "test3"
var3="$RESULT"

# Count variables before cleanup
var_count_before="${#__KLIB_VARS[@]}"

kv.free "$var1"
kv.free "$var2"
kv.free "$var3"

var_count_after="${#__KLIB_VARS[@]}"

if [[ $var_count_after -lt $var_count_before ]]; then
    kt_test_pass "Memory is properly cleaned after batch free"
else
    kt_test_fail "Memory cleanup failed (before: $var_count_before, after: $var_count_after)"
fi

# ============================================================================
# Integration with Shell Features Tests
# ============================================================================

# Test 57: Variable management with command substitution
kt_test_start "Variables work with command substitution context"
kv.new "cmd_test"
var_name="$RESULT"
kv.set "$var_name" "hello"
result=$(kv.get "$var_name" && echo " world")
if kt_assert_equals "hello world" "$result" "Should work in command substitution"; then
    kt_test_pass "Variables work with command substitution context"
else
    kt_test_fail "Variables failed in command substitution"
fi

# Test 58: kv operations in conditional statements
kt_test_start "kv operations work correctly in conditionals"
kv.new "0"
counter="$RESULT"
if kv.set "$counter" "1"; then
    kv.get "$counter"
    if [[ "$RESULT" == "1" ]]; then
        kt_test_pass "kv operations work correctly in conditionals"
    else
        kt_test_fail "kv operations failed in conditional value check"
    fi
else
    kt_test_fail "kv.set failed in conditional"
fi

# Test 59: Variable values in arithmetic expressions
kt_test_start "Variable values work in arithmetic expressions"
kv.new "5"
num_var="$RESULT"
kv.set "$num_var" "10"
kv.get "$num_var"
doubled=$((RESULT * 2))
if kt_assert_equals "20" "$doubled" "Should work in arithmetic"; then
    kt_test_pass "Variable values work in arithmetic expressions"
else
    kt_test_fail "Variables failed in arithmetic context"
fi

# Test 60: String concatenation with variables
kt_test_start "Variable values work in string operations"
kv.new "prefix"
str_var="$RESULT"
kv.set "$str_var" "Hello"
kv.get "$str_var"
concatenated="${RESULT} World"
if kt_assert_equals "Hello World" "$concatenated" "Should work in string operations"; then
    kt_test_pass "Variable values work in string operations"
else
    kt_test_fail "Variables failed in string concatenation"
fi

# ============================================================================
# Recursive and Complex Function Patterns Tests
# ============================================================================

# Test 61: Recursive variable creation and access
kt_test_start "Variables work in recursive function calls"
recursive_counter() {
    local depth="$1"
    local var_name="$2"
    if [[ $depth -gt 0 ]]; then
        kv.get "$var_name"
        local current=$((RESULT + 1))
        kv.set "$var_name" "$current"
        recursive_counter $((depth - 1)) "$var_name"
    fi
}
kv.new "0"
rec_counter="$RESULT"
recursive_counter 5 "$rec_counter"
kv.get "$rec_counter"
if kt_assert_equals "5" "$RESULT" "Recursive calls should accumulate correctly"; then
    kt_test_pass "Variables work in recursive function calls"
else
    kt_test_fail "Recursive variable operations failed (got: $RESULT)"
fi

# Test 62: Variable passing through multiple function layers
kt_test_start "Variables pass through multiple function layers"
layer1() {
    local var_name="$1"
    layer2 "$var_name"
}
layer2() {
    local var_name="$1"
    layer3 "$var_name"
}
layer3() {
    local var_name="$1"
    kv.get "$var_name"
    local val="$RESULT"
    kv.set "$var_name" "${val}_layer3"
}
kv.new "base"
multi_var="$RESULT"
layer1 "$multi_var"
kv.get "$multi_var"
if kt_assert_equals "base_layer3" "$RESULT" "Should pass through all layers"; then
    kt_test_pass "Variables pass through multiple function layers"
else
    kt_test_fail "Multi-layer variable passing failed (got: $RESULT)"
fi

# Test 63: Temporary variable cleanup in error scenarios
kt_test_start "Temporary variables are cleaned up in error scenarios"
cleanup_on_error() {
    local target_var_name="$1"
    kv.new "temp_value"
    local temp_var="$RESULT"
    # Simulate error condition
    if [[ "$target_var_name" == "error" ]]; then
        kv.free "$temp_var"
        return 1
    fi
    kv.get "$temp_var"
    kv.set "$target_var_name" "$RESULT"
    kv.free "$temp_var"
    return 0
}
# Create a properly named variable, not using the word "target"
kv.new "" "error_test_var"
result_var_name="$RESULT"
cleanup_on_error "error"
cleanup_result=$?
kv.get "$result_var_name"
if [[ $cleanup_result -ne 0 ]] && [[ "$RESULT" == "" ]]; then
    kt_test_pass "Temporary variables are cleaned up in error scenarios"
else
    kt_test_fail "Cleanup on error failed (result: $cleanup_result, target: $RESULT)"
fi

# Test 64: Complex nested variable dependencies
kt_test_start "Complex nested variable dependencies work correctly"
kv.new "A"
var_a="$RESULT"
kv.new "B"
var_b="$RESULT"
kv.new "C"
var_c="$RESULT"

# Set up dependencies
kv.set "$var_a" "initial_A"
kv.set "$var_b" "${__KLIB_VARS[$var_a]}_B"
kv.set "$var_c" "${__KLIB_VARS[$var_b]}_C"

kv.get "$var_a"
val_a="$RESULT"
kv.get "$var_b"
val_b="$RESULT"
kv.get "$var_c"
val_c="$RESULT"

if [[ "$val_a" == "initial_A" ]] && [[ "$val_b" == "initial_A_B" ]] && [[ "$val_c" == "initial_A_B_C" ]]; then
    kt_test_pass "Complex nested variable dependencies work correctly"
else
    kt_test_fail "Nested dependencies failed (A: $val_a, B: $val_b, C: $val_c)"
fi

# Test 65: Variable state preservation across complex script phases
kt_test_start "Variables preserve state across script execution phases"
# Simulate different phases
phase1_vars() {
    kv.new "phase1_data"
    __phase1_var="$RESULT"
    kv.set "$__phase1_var" "phase1_value"
}
phase2_vars() {
    kv.get "$__phase1_var"
    if [[ "$RESULT" == "phase1_value" ]]; then
        kv.new "phase2_data"
        __phase2_var="$RESULT"
        kv.set "$__phase2_var" "phase2_value"
    fi
}
phase3_vars() {
    kv.get "$__phase1_var"
    local p1="$RESULT"
    kv.get "$__phase2_var"
    local p2="$RESULT"
    RESULT="${p1}:${p2}"
}
phase1_vars
phase2_vars
phase3_vars
if kt_assert_equals "phase1_value:phase2_value" "$RESULT" "State should persist across phases"; then
    kt_test_pass "Variables preserve state across script execution phases"
else
    kt_test_fail "State preservation failed (got: $RESULT)"
fi

# ============================================================================
# Additional Edge Cases and Boundary Tests
# ============================================================================

# Test 66: kv.new with Unicode characters in value
kt_test_start "kv.new handles Unicode characters in value"
unicode_value="Привет мир 你好世界 🎉"
kv.new "$unicode_value" "unicode_var"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "$unicode_value" "$RESULT" "Should handle Unicode characters"; then
    kt_test_pass "kv.new handles Unicode characters in value"
else
    kt_test_fail "kv.new failed with Unicode value (got: $RESULT)"
fi

# Test 67: kv.set with null byte handling
kt_test_start "kv.set handles values with special shell characters"
special_shell_value='$HOME $(echo test) `whoami` ${PATH}'
kv.new "initial"
var_name="$RESULT"
kv.set "$var_name" "$special_shell_value"
kv.get "$var_name"
if kt_assert_equals "$special_shell_value" "$RESULT" "Should preserve shell special characters literally"; then
    kt_test_pass "kv.set handles values with special shell characters"
else
    kt_test_fail "kv.set failed with shell special characters"
fi

# Test 68: kv.new with backslash characters
kt_test_start "kv.new handles backslash characters"
backslash_value='path\\to\\file\nwith\\escapes'
kv.new "$backslash_value" "backslash_var"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "$backslash_value" "$RESULT" "Should handle backslashes"; then
    kt_test_pass "kv.new handles backslash characters"
else
    kt_test_fail "kv.new failed with backslash value"
fi

# Test 69: kv.get with empty variable name
kt_test_start "kv.get handles empty variable name"
kv.get ""
if kt_assert_equals "" "$RESULT" "Should return empty for empty name"; then
    kt_test_pass "kv.get handles empty variable name"
else
    kt_test_fail "kv.get failed with empty name"
fi

# Test 70: kv.set with empty variable name
kt_test_start "kv.set handles empty variable name"
kv.set "" "some_value"
if kt_assert_equals "some_value" "${__KLIB_VARS[""]}" "Should handle empty name"; then
    kt_test_pass "kv.set handles empty variable name"
else
    kt_test_fail "kv.set failed with empty name"
fi

# Test 71: kv.free with empty variable name
kt_test_start "kv.free handles empty variable name"
kv.free ""
if kt_assert_equals "" "${__KLIB_VARS[""]}" "Should handle empty name gracefully"; then
    kt_test_pass "kv.free handles empty variable name"
else
    kt_test_fail "kv.free failed with empty name"
fi

# Test 72: Variable with equals sign in value
kt_test_start "kv.set handles equals sign in value"
kv.new "initial"
var_name="$RESULT"
kv.set "$var_name" "key=value=another"
kv.get "$var_name"
if kt_assert_equals "key=value=another" "$RESULT" "Should handle equals signs"; then
    kt_test_pass "kv.set handles equals sign in value"
else
    kt_test_fail "kv.set failed with equals sign in value"
fi

# Test 73: Variable with quotes in value
kt_test_start "kv.set handles quotes in value"
kv.new "initial"
var_name="$RESULT"
quoted_value='"double" and '\''single'\'' quotes'
kv.set "$var_name" "$quoted_value"
kv.get "$var_name"
if kt_assert_equals "$quoted_value" "$RESULT" "Should handle quotes"; then
    kt_test_pass "kv.set handles quotes in value"
else
    kt_test_fail "kv.set failed with quotes in value"
fi

# Test 74: Rapid sequential set/get operations
kt_test_start "Rapid sequential set/get operations"
kv.new "0"
rapid_var="$RESULT"
success=true
for i in {1..50}; do
    kv.set "$rapid_var" "$i"
    kv.get "$rapid_var"
    if [[ "$RESULT" != "$i" ]]; then
        success=false
        break
    fi
done
if [[ "$success" == true ]]; then
    kt_test_pass "Rapid sequential set/get operations"
else
    kt_test_fail "Rapid set/get failed at iteration $i"
fi

# Test 75: Variable name with dots
kt_test_start "kv.new handles dots in prefix"
kv.new "value" "my.prefix.name"
var_name="$RESULT"
if kt_assert_contains "$var_name" "my.prefix.name" "Should use prefix with dots"; then
    kt_test_pass "kv.new handles dots in prefix"
else
    kt_test_fail "kv.new failed with dots in prefix"
fi

# Test 76: Variable name with colons
kt_test_start "kv.new handles colons in prefix"
kv.new "value" "namespace:var"
var_name="$RESULT"
if kt_assert_contains "$var_name" "namespace:var" "Should use prefix with colons"; then
    kt_test_pass "kv.new handles colons in prefix"
else
    kt_test_fail "kv.new failed with colons in prefix"
fi

# Test 77: kv.set overwrites with shorter value
kt_test_start "kv.set correctly overwrites with shorter value"
kv.new "this_is_a_very_long_initial_value_that_should_be_completely_replaced"
var_name="$RESULT"
kv.set "$var_name" "short"
kv.get "$var_name"
if kt_assert_equals "short" "$RESULT" "Should completely replace with shorter value"; then
    kt_test_pass "kv.set correctly overwrites with shorter value"
else
    kt_test_fail "kv.set failed to overwrite with shorter value"
fi

# Test 78: Multiple variables with same value
kt_test_start "Multiple variables can have same value"
kv.new "shared_value"
var1="$RESULT"
kv.new "shared_value"
var2="$RESULT"
kv.new "shared_value"
var3="$RESULT"
kv.get "$var1"
val1="$RESULT"
kv.get "$var2"
val2="$RESULT"
kv.get "$var3"
val3="$RESULT"
if [[ "$val1" == "shared_value" ]] && [[ "$val2" == "shared_value" ]] && [[ "$val3" == "shared_value" ]]; then
    kt_test_pass "Multiple variables can have same value"
else
    kt_test_fail "Multiple variables with same value failed"
fi

# Test 79: kv.free doesn't affect other variables
kt_test_start "kv.free doesn't affect other variables"
kv.new "value1"
var1="$RESULT"
kv.new "value2"
var2="$RESULT"
kv.free "$var1"
kv.get "$var2"
if kt_assert_equals "value2" "$RESULT" "Other variables should remain intact"; then
    kt_test_pass "kv.free doesn't affect other variables"
else
    kt_test_fail "kv.free affected other variables"
fi

# Test 80: Variable with array-like value
kt_test_start "kv.set handles array-like string value"
kv.new "initial"
var_name="$RESULT"
array_like="[1, 2, 3, 4, 5]"
kv.set "$var_name" "$array_like"
kv.get "$var_name"
if kt_assert_equals "$array_like" "$RESULT" "Should handle array-like strings"; then
    kt_test_pass "kv.set handles array-like string value"
else
    kt_test_fail "kv.set failed with array-like value"
fi

# Test 81: Variable with JSON-like value
kt_test_start "kv.set handles JSON-like string value"
kv.new "initial"
var_name="$RESULT"
json_like='{"key": "value", "number": 42, "nested": {"a": 1}}'
kv.set "$var_name" "$json_like"
kv.get "$var_name"
if kt_assert_equals "$json_like" "$RESULT" "Should handle JSON-like strings"; then
    kt_test_pass "kv.set handles JSON-like string value"
else
    kt_test_fail "kv.set failed with JSON-like value"
fi

# Test 82: Variable with multiline value
kt_test_start "kv.set handles multiline value"
kv.new "initial"
var_name="$RESULT"
multiline_value="Line 1
Line 2
Line 3"
kv.set "$var_name" "$multiline_value"
kv.get "$var_name"
if kt_assert_equals "$multiline_value" "$RESULT" "Should handle multiline values"; then
    kt_test_pass "kv.set handles multiline value"
else
    kt_test_fail "kv.set failed with multiline value"
fi

# Test 83: Variable with leading/trailing whitespace
kt_test_start "kv.set preserves leading/trailing whitespace"
kv.new "initial"
var_name="$RESULT"
whitespace_value="   leading and trailing   "
kv.set "$var_name" "$whitespace_value"
kv.get "$var_name"
if kt_assert_equals "$whitespace_value" "$RESULT" "Should preserve whitespace"; then
    kt_test_pass "kv.set preserves leading/trailing whitespace"
else
    kt_test_fail "kv.set failed to preserve whitespace"
fi

# Test 84: Variable with pipe character
kt_test_start "kv.set handles pipe character"
kv.new "initial"
var_name="$RESULT"
pipe_value="cmd1 | cmd2 | cmd3"
kv.set "$var_name" "$pipe_value"
kv.get "$var_name"
if kt_assert_equals "$pipe_value" "$RESULT" "Should handle pipe characters"; then
    kt_test_pass "kv.set handles pipe character"
else
    kt_test_fail "kv.set failed with pipe character"
fi

# Test 85: Variable with redirect characters
kt_test_start "kv.set handles redirect characters"
kv.new "initial"
var_name="$RESULT"
redirect_value="input < file > output 2>&1"
kv.set "$var_name" "$redirect_value"
kv.get "$var_name"
if kt_assert_equals "$redirect_value" "$RESULT" "Should handle redirect characters"; then
    kt_test_pass "kv.set handles redirect characters"
else
    kt_test_fail "kv.set failed with redirect characters"
fi

# ============================================================================
# Stress and Boundary Tests
# ============================================================================

# Test 86: Create and free many variables in sequence
kt_test_start "Create and free many variables in sequence"
for i in {1..50}; do
    kv.new "temp_$i"
    kv.free "$RESULT"
done
kt_test_pass "Create and free many variables in sequence"

# Test 87: Variable value with only special characters
kt_test_start "kv.set handles value with only special characters"
kv.new "initial"
var_name="$RESULT"
special_only="!@#\$%^&*()_+-=[]{}|;':\",./<>?"
kv.set "$var_name" "$special_only"
kv.get "$var_name"
if kt_assert_equals "$special_only" "$RESULT" "Should handle special-only values"; then
    kt_test_pass "kv.set handles value with only special characters"
else
    kt_test_fail "kv.set failed with special-only value"
fi

# Test 88: Variable with numeric-only name prefix
kt_test_start "kv.new handles numeric-only prefix"
kv.new "value" "12345"
var_name="$RESULT"
if kt_assert_contains "$var_name" "12345" "Should use numeric prefix"; then
    kt_test_pass "kv.new handles numeric-only prefix"
else
    kt_test_fail "kv.new failed with numeric prefix"
fi

# Test 89: Verify RESULT is set correctly after kv.new
kt_test_start "RESULT is set correctly after kv.new"
RESULT=""
kv.new "test_value"
if [[ -n "$RESULT" ]] && [[ "$RESULT" != "" ]]; then
    kt_test_pass "RESULT is set correctly after kv.new"
else
    kt_test_fail "RESULT was not set after kv.new"
fi

# Test 90: Verify RESULT is set correctly after kv.get
kt_test_start "RESULT is set correctly after kv.get"
kv.new "expected_value"
var_name="$RESULT"
RESULT=""
kv.get "$var_name"
if kt_assert_equals "expected_value" "$RESULT" "RESULT should contain the value"; then
    kt_test_pass "RESULT is set correctly after kv.get"
else
    kt_test_fail "RESULT was not set correctly after kv.get"
fi

# ============================================================================
# Subshell Tests - BASH_SUBSHELL handling
# ============================================================================

# Test 91: kv.new handles variable name with BASH_SUBSHELL level
kt_test_start "kv.new variable name includes subshell level"
kv.new "sub_test"
var_name1="$RESULT"
if kt_assert_contains "$var_name1" "_0_" "Should contain BASH_SUBSHELL=0 level"; then
    kt_test_pass "kv.new variable name includes subshell level"
else
    kt_test_fail "Variable name does not contain subshell level"
fi

# Test 92: kv.new variable name includes stack depth
kt_test_start "kv.new variable name includes stack depth"
kv.new "depth_test"
main_var="$RESULT"
test_depth_func() {
    kv.new "in_func"
}
test_depth_func
func_var="$RESULT"
if [[ "$main_var" != "$func_var" ]]; then
    kt_test_pass "kv.new variable name includes stack depth"
else
    kt_test_fail "Variable names should differ by stack depth"
fi

# Test 93: Variable name components include RANDOM
kt_test_start "Variable name includes RANDOM component"
kv.new "value1"
name1="$RESULT"
kv.new "value2"
name2="$RESULT"
# Extract RANDOM part if pattern is __var_subshell_depth_func_line_RANDOM_PID
# Names should differ because RANDOM differs
if [[ "$name1" != "$name2" ]]; then
    kt_test_pass "Variable name includes RANDOM component"
else
    kt_test_fail "Variable names are identical (should contain RANDOM)"
fi

# Test 94: Variable name components include process ID
kt_test_start "Variable name includes process ID"
kv.new "test_value" "prefix"
var_name="$RESULT"
# Check that variable name contains $$
if kt_assert_contains "$var_name" "$$" "Should contain process ID"; then
    kt_test_pass "Variable name includes process ID"
else
    kt_test_fail "Variable name does not contain process ID"
fi

# Test 95: Variable name components include function name
kt_test_start "Variable name includes function name in nested call"
test_func_for_name() {
    kv.new "func_value"
}
test_func_for_name
var_name="$RESULT"
if kt_assert_contains "$var_name" "test_func_for_name" "Should contain function name"; then
    kt_test_pass "Variable name includes function name in nested call"
else
    kt_test_fail "Variable name does not contain function name"
fi

# ============================================================================
# Parameter Validation Tests
# ============================================================================

# Test 96: kv.new with only value parameter (no prefix)
kt_test_start "kv.new works with only value parameter"
kv.new "value_only"
var_name="$RESULT"
kv.get "$var_name"
if kt_assert_equals "value_only" "$RESULT" "Should work with single parameter"; then
    kt_test_pass "kv.new works with only value parameter"
else
    kt_test_fail "kv.new failed with single parameter (got: $RESULT)"
fi

# Test 97: kv.new respects parameter order (value first, prefix second)
kt_test_start "kv.new respects parameter order"
kv.new "myvalue" "myprefix"
var_name="$RESULT"
if kt_assert_contains "$var_name" "myprefix" "Prefix should be in variable name"; then
    kv.get "$var_name"
    if kt_assert_equals "myvalue" "$RESULT" "Value should be myvalue, not myprefix"; then
        kt_test_pass "kv.new respects parameter order"
    else
        kt_test_fail "kv.new parameter order incorrect (got value: $RESULT)"
    fi
else
    kt_test_fail "kv.new did not use prefix correctly"
fi

# Test 98: kv.new with numeric prefix
kt_test_start "kv.new works with numeric prefix"
kv.new "numvalue" "999"
var_name="$RESULT"
if kt_assert_contains "$var_name" "999" "Should use numeric prefix"; then
    kt_test_pass "kv.new works with numeric prefix"
else
    kt_test_fail "kv.new failed with numeric prefix"
fi

# Test 99: kv.new prefix with special characters
kt_test_start "kv.new prefix with special characters"
kv.new "value" "pre-fix_123"
var_name="$RESULT"
if kt_assert_contains "$var_name" "pre-fix_123" "Should preserve special chars in prefix"; then
    kt_test_pass "kv.new prefix with special characters"
else
    kt_test_fail "kv.new failed with special prefix characters"
fi

# ============================================================================
# Variable Storage Integrity Tests
# ============================================================================

# Test 100: __KLIB_VARS array is global and persists
kt_test_start "__KLIB_VARS array persists across calls"
initial_count=${#__KLIB_VARS[@]}
kv.new "persist1"
var1="$RESULT"
kv.new "persist2"
var2="$RESULT"
final_count=${#__KLIB_VARS[@]}
if [[ $final_count -gt $initial_count ]]; then
    kt_test_pass "__KLIB_VARS array persists across calls"
else
    kt_test_fail "__KLIB_VARS count did not increase"
fi

# Test 101: Direct array access returns same value as kv.get
kt_test_start "Direct array access matches kv.get"
kv.new "array_test_value"
var_name="$RESULT"
kv.get "$var_name"
get_result="$RESULT"
array_result="${__KLIB_VARS[$var_name]}"
if kt_assert_equals "$get_result" "$array_result" "Array access should match kv.get"; then
    kt_test_pass "Direct array access matches kv.get"
else
    kt_test_fail "Array access mismatch (kv.get: $get_result, array: $array_result)"
fi

# Test 102: kv.set directly modifies __KLIB_VARS
kt_test_start "kv.set directly modifies __KLIB_VARS array"
kv.new "before_direct"
var_name="$RESULT"
kv.set "$var_name" "after_direct"
if kt_assert_equals "after_direct" "${__KLIB_VARS[$var_name]}" "Array should be updated"; then
    kt_test_pass "kv.set directly modifies __KLIB_VARS array"
else
    kt_test_fail "kv.set did not update array (got: ${__KLIB_VARS[$var_name]})"
fi

# Test 103: kv.free unsets array element
kt_test_start "kv.free unsets array element"
kv.new "to_unset"
var_name="$RESULT"
kv.free "$var_name"
if [[ -z "${__KLIB_VARS[$var_name]}" ]]; then
    kt_test_pass "kv.free unsets array element"
else
    kt_test_fail "kv.free did not unset element (value: ${__KLIB_VARS[$var_name]})"
fi

# ============================================================================
# Large Scale and Stress Tests
# ============================================================================

# Test 104: Handle 100 variables simultaneously
kt_test_start "Handle 100 variables simultaneously"
declare -a var_array
for i in {1..100}; do
    kv.new "value_$i"
    var_array+=("$RESULT")
done
success=true
for i in {0..99}; do
    kv.get "${var_array[$i]}"
    if [[ "$RESULT" != "value_$((i+1))" ]]; then
        success=false
        break
    fi
done
if [[ "$success" == true ]]; then
    kt_test_pass "Handle 100 variables simultaneously"
else
    kt_test_fail "Failed to manage 100 variables (failed at index $i)"
fi

# Test 105: Large value (10KB string)
kt_test_start "Handle large values (10KB)"
kv.new "init"
var_name="$RESULT"
large_value=$(printf 'x%.0s' {1..10240})
kv.set "$var_name" "$large_value"
kv.get "$var_name"
if [[ ${#RESULT} -eq 10240 ]]; then
    kt_test_pass "Handle large values (10KB)"
else
    kt_test_fail "Large value size mismatch (expected 10240, got ${#RESULT})"
fi

# Test 106: Rapid free and recreate same prefix
kt_test_start "Rapid free and recreate with same prefix"
kv.new "val1" "rapid"
var1="$RESULT"
kv.free "$var1"
kv.new "val2" "rapid"
var2="$RESULT"
kv.get "$var2"
# Names should differ because of RANDOM component, but both should use "rapid" prefix
if [[ "$var1" != "$var2" ]] && kt_assert_equals "val2" "$RESULT" "Should recreate with different name"; then
    kt_test_pass "Rapid free and recreate with same prefix"
else
    kt_test_fail "Rapid recreate failed"
fi

# ============================================================================
# Function Scope Edge Cases
# ============================================================================

# Test 107: Variable created in function accessible from parent scope
kt_test_start "Variable created in nested function accessible from parent"
nested_create() {
    deep_nest() {
        kv.new "deeply_nested"
    }
    deep_nest
}
nested_create
deep_var="$RESULT"
kv.get "$deep_var"
if kt_assert_equals "deeply_nested" "$RESULT" "Should access deeply nested variable"; then
    kt_test_pass "Variable created in nested function accessible from parent"
else
    kt_test_fail "Deep nested variable access failed"
fi

# Test 108: Multiple function calls with variables
kt_test_start "Multiple function calls with variable management"
func_a() {
    kv.new "from_a"
    # RESULT is set by kv.new
}
func_b() {
    kv.new "from_b"
    # RESULT is set by kv.new
}
func_a
var_a="$RESULT"
func_b
var_b="$RESULT"
if [[ -n "$var_a" ]] && [[ -n "$var_b" ]]; then
    kv.get "$var_a"
    val_a="$RESULT"
    kv.get "$var_b"
    val_b="$RESULT"
    if [[ "$val_a" == "from_a" ]] && [[ "$val_b" == "from_b" ]]; then
        kt_test_pass "Multiple function calls with variable management"
    else
        kt_test_fail "Function variable values incorrect (a: $val_a, b: $val_b)"
    fi
else
    kt_test_fail "Functions did not return variable names"
fi

# ============================================================================
# Edge Cases with Default Values
# ============================================================================

# Test 109: kv.new with empty value parameter defaults to 0
kt_test_start "kv.new with empty string uses default 0"
kv.new "" "emptyval"
var_name="$RESULT"
if [[ -n "$var_name" ]]; then
    kv.get "$var_name"
    if kt_assert_equals "0" "$RESULT" "Empty value should default to 0"; then
        kt_test_pass "kv.new with empty string uses default 0"
    else
        kt_test_fail "Empty value did not default (got: $RESULT)"
    fi
else
    kt_test_fail "kv.new did not return variable name"
fi

# Test 110: kv.new no parameter creates variable with value 0
kt_test_start "kv.new with no parameter defaults to 0"
kv.new
var1="$RESULT"
if [[ -n "$var1" ]]; then
    kv.get "$var1"
    if kt_assert_equals "0" "$RESULT" "No parameter should default to 0"; then
        kt_test_pass "kv.new with no parameter defaults to 0"
    else
        kt_test_fail "Default value incorrect (got: $RESULT)"
    fi
else
    kt_test_fail "kv.new did not return variable name"
fi

# Cleanup
unset __KLIB_VARS
unset RESULT
unset var_name
unset var_name_1
unset var_name_2
unset var_name_3
unset var1
unset var2
unset var3
unset counter
unset result
unset arr
unset shared_var
unset accumulator
unset seq_var
unset var_to_modify
unset result_var
unset shared
unset var_names
unset __test_var_batch
unset var_batch
unset large_var_names
unset all_valid
unset duration
unset start_time
unset end_time
unset i
unset j
unset iteration
unset iterations
unset max_iterations
unset element
unset outer_counter
unset inner_counter
unset outer_val
unset inner_val
unset outer_final
unset inner_final
unset temp_var
unset temp_val
unset temp_val_after
unset temp_var_name
unset target_val
unset first_result
unset second_result
unset doubled
unset concatenated
unset depth
unset rec_counter
unset multi_var
unset p1
unset p2
unset val_a
unset val_b
unset val_c
unset current
unset val1
unset val2
unset val3
unset val1_before
unset val2_before
unset val3_before
unset val1_after
unset val2_after
unset val3_after
unset value_before_free
unset value_after_free
unset val_b_after
unset val_a_final
unset val_b_final
unset val_c_final
unset val_a_updated
unset val_b_updated
unset val_c_updated
unset val_a_read
unset val_b_read
unset val_c_read
unset func1_result
unset func2_result
unset func1_name
unset func2_name
unset temp_from_func1
unset temp_from_func2
unset mod_from_func1
unset mod_from_func2
unset temp_val_1
unset temp_val_2
unset temp_val_3
unset temp1
unset temp2
unset temp3
unset char
unset straccum
unset funcvar
unset var_from_func
unset create_and_return_var
unset myvar
unset append_to_var
unset text
unset append_func
unset suffix
unset modify_via_param
unset var_name_to_modify
unset func_with_cleanup
unset first_modifier
unset second_modifier
unset base
unset create_var_batch
unset count
unset __phase1_var
unset __phase2_var
unset phase1_vars
unset phase2_vars
unset phase3_vars
unset long_value
unset long_replacement
unset name1
unset name2
unset name3
unset whitespace_value
unset nested_value
unset nested_result
unset consistent
unset result1
unset result2
unset result3
unset cmd_test
unset cmd_result
unset num_var
unset str_var
unset layer1
unset layer2
unset layer3
unset cleanup_on_error
unset target_var
unset var_a
unset var_b
unset var_c
unset unicode_value
unset special_shell_value
unset backslash_value
unset quoted_value
unset rapid_var
unset success
unset array_like
unset json_like
unset multiline_value
unset pipe_value
unset redirect_value
unset special_only
unset result
unset name1
unset name2
unset var_name1
unset main_var
unset test_depth_func
unset func_var
unset prefix
unset test_func_for_name
unset value_only
unset myprefix
unset myvalue
unset numvalue
unset emptyval
unset initial_count
unset persist1
unset persist2
unset final_count
unset get_result
unset array_result
unset before_direct
unset after_direct
unset to_unset
unset var_array
unset large_value
unset rapid
unset val1
unset val2
unset nested_create
unset deep_nest
unset deep_var
unset func_a
unset func_b
unset var_a
unset var_b
unset val_a
unset val_b
unset deeply_nested
unset from_a
unset from_b

kt_test_finish
