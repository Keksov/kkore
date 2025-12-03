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

# Cleanup
unset __KLIB_VARS
unset RESULT
unset RESULT
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
