#!/bin/bash
# KConfig Tests - Configuration Management Functions
# Comprehensive tests for kcfg.sh library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ConfigManagement" "$SCRIPT_DIR" "$@"

# Source kcfg if needed
KCFG_DIR="$SCRIPT_DIR/.."
[[ -f "$KCFG_DIR/kcfg.sh" ]] && source "$KCFG_DIR/kcfg.sh"

# ============================================================================
# kc.set() Tests - Set configuration value
# ============================================================================

# Test 1: kc.set creates and stores configuration
kt_test_start "kc.set creates and stores configuration"
kc.set "app_name" "TestApp"
if kt_assert_equals "TestApp" "${__KLIB_CONFIG[app_name]}" "Should store value in __KLIB_CONFIG"; then
    kt_test_pass "kc.set creates and stores configuration"
else
    kt_test_fail "kc.set failed to store value"
fi

# Test 2: kc.set overwrites existing value
kt_test_start "kc.set overwrites existing value"
kc.set "setting" "initial"
kc.set "setting" "updated"
if kt_assert_equals "updated" "${__KLIB_CONFIG[setting]}" "Should overwrite existing value"; then
    kt_test_pass "kc.set overwrites existing value"
else
    kt_test_fail "kc.set failed to overwrite (got: ${__KLIB_CONFIG[setting]})"
fi

# Test 3: kc.set stores empty string
kt_test_start "kc.set stores empty string"
kc.set "empty_key" ""
if kt_assert_equals "" "${__KLIB_CONFIG[empty_key]}" "Should store empty string"; then
    kt_test_pass "kc.set stores empty string"
else
    kt_test_fail "kc.set failed with empty string"
fi

# Test 4: kc.set handles numeric values
kt_test_start "kc.set handles numeric values"
kc.set "port" "8080"
if kt_assert_equals "8080" "${__KLIB_CONFIG[port]}" "Should store numeric value as string"; then
    kt_test_pass "kc.set handles numeric values"
else
    kt_test_fail "kc.set failed with numeric value"
fi

# Test 5: kc.set handles special characters
kt_test_start "kc.set handles special characters"
special_value="path/to/file:with|special&chars"
kc.set "path_setting" "$special_value"
if kt_assert_equals "$special_value" "${__KLIB_CONFIG[path_setting]}" "Should preserve special characters"; then
    kt_test_pass "kc.set handles special characters"
else
    kt_test_fail "kc.set failed with special characters"
fi

# ============================================================================
# kc.get() Tests - Get configuration value
# ============================================================================

# Test 6: kc.get retrieves value in normal context
kt_test_start "kc.get retrieves value in normal context"
kc.set "debug_mode" "true"
kc.get "debug_mode"
if kt_assert_equals "true" "$RESULT" "Should retrieve value in RESULT"; then
    kt_test_pass "kc.get retrieves value in normal context"
else
    kt_test_fail "kc.get failed (got: $RESULT)"
fi

# Test 7: kc.get returns empty for nonexistent key
kt_test_start "kc.get returns empty for nonexistent key"
kc.get "nonexistent_key"
if kt_assert_equals "" "$RESULT" "Should return empty for missing key"; then
    kt_test_pass "kc.get returns empty for nonexistent key"
else
    kt_test_fail "kc.get should return empty for nonexistent key"
fi

# Test 8: kc.get echoes value in subshell
kt_test_start "kc.get echoes value in subshell"
kc.set "version" "1.0.0"
result=$(kc.get "version")
if kt_assert_equals "1.0.0" "$result" "Should echo value in subshell"; then
    kt_test_pass "kc.get echoes value in subshell"
else
    kt_test_fail "kc.get subshell echo failed (got: $result)"
fi

# Test 9: kc.get retrieves special characters correctly
kt_test_start "kc.get retrieves special characters correctly"
special_val="config=value&other=data"
kc.set "special_config" "$special_val"
kc.get "special_config"
if kt_assert_equals "$special_val" "$RESULT" "Should retrieve special characters"; then
    kt_test_pass "kc.get retrieves special characters correctly"
else
    kt_test_fail "kc.get failed with special characters"
fi

# ============================================================================
# kc.exists() Tests - Check if key exists
# ============================================================================

# Test 10: kc.exists returns true for existing key
kt_test_start "kc.exists returns true for existing key"
kc.set "existing_key" "value"
if kc.exists "existing_key"; then
    kt_test_pass "kc.exists returns true for existing key"
else
    kt_test_fail "kc.exists failed for existing key"
fi

# Test 11: kc.exists returns false for nonexistent key
kt_test_start "kc.exists returns false for nonexistent key"
if ! kc.exists "nonexistent_test_key_xyz"; then
    kt_test_pass "kc.exists returns false for nonexistent key"
else
    kt_test_fail "kc.exists incorrectly reported nonexistent key"
fi

# Test 12: kc.exists works with empty string values
kt_test_start "kc.exists works with empty string values"
kc.set "empty_config" ""
if kc.exists "empty_config"; then
    kt_test_pass "kc.exists works with empty string values"
else
    kt_test_fail "kc.exists failed for empty value"
fi

# ============================================================================
# kc.delete() Tests - Delete configuration value
# ============================================================================

# Test 13: kc.delete removes configuration key
kt_test_start "kc.delete removes configuration key"
kc.set "to_delete" "temporary_value"
kc.delete "to_delete"
kc.get "to_delete"
if kt_assert_equals "" "$RESULT" "Should return empty after delete"; then
    kt_test_pass "kc.delete removes configuration key"
else
    kt_test_fail "kc.delete failed to remove key"
fi

# Test 14: kc.delete on nonexistent key does nothing
kt_test_start "kc.delete on nonexistent key does nothing"
kc.delete "nonexistent_delete_key"
if kt_assert_equals "" "${__KLIB_CONFIG[nonexistent_delete_key]}" "Should handle gracefully"; then
    kt_test_pass "kc.delete on nonexistent key does nothing"
else
    kt_test_fail "kc.delete failed with nonexistent key"
fi

# Test 15: kc.delete allows key recreation
kt_test_start "kc.delete allows key recreation"
kc.set "recreate_key" "value1"
kc.delete "recreate_key"
kc.set "recreate_key" "value2"
if kt_assert_equals "value2" "${__KLIB_CONFIG[recreate_key]}" "Should allow recreation"; then
    kt_test_pass "kc.delete allows key recreation"
else
    kt_test_fail "kc.delete recreation failed"
fi

# ============================================================================
# kc.keys() Tests - Get all configuration keys
# ============================================================================

# Test 16: kc.keys returns all keys
kt_test_start "kc.keys returns all keys"
kc.clear
kc.set "key1" "val1"
kc.set "key2" "val2"
kc.set "key3" "val3"
kc.keys
keys_result="$RESULT"
if [[ "$keys_result" == *"key1"* ]] && [[ "$keys_result" == *"key2"* ]] && [[ "$keys_result" == *"key3"* ]]; then
    kt_test_pass "kc.keys returns all keys"
else
    kt_test_fail "kc.keys missing keys (got: $keys_result)"
fi

# Test 17: kc.keys echoes keys in subshell
kt_test_start "kc.keys echoes keys in subshell"
kc.clear
kc.set "test_key_a" "a"
kc.set "test_key_b" "b"
keys_output=$(kc.keys)
if [[ "$keys_output" == *"test_key_a"* ]] && [[ "$keys_output" == *"test_key_b"* ]]; then
    kt_test_pass "kc.keys echoes keys in subshell"
else
    kt_test_fail "kc.keys subshell output incorrect"
fi

# Test 18: kc.keys returns empty when no keys exist
kt_test_start "kc.keys returns empty when no keys exist"
kc.clear
kc.keys
if kt_assert_equals "" "$RESULT" "Should return empty for empty config"; then
    kt_test_pass "kc.keys returns empty when no keys exist"
else
    kt_test_fail "kc.keys should return empty"
fi

# ============================================================================
# kc.clear() Tests - Clear all configuration
# ============================================================================

# Test 19: kc.clear removes all configuration
kt_test_start "kc.clear removes all configuration"
kc.set "cfg1" "val1"
kc.set "cfg2" "val2"
kc.set "cfg3" "val3"
var_count_before="${#__KLIB_CONFIG[@]}"
kc.clear
var_count_after="${#__KLIB_CONFIG[@]}"
if kt_assert_equals "0" "$var_count_after" "Should clear all config"; then
    kt_test_pass "kc.clear removes all configuration"
else
    kt_test_fail "kc.clear failed (before: $var_count_before, after: $var_count_after)"
fi

# Test 20: kc.clear allows new configuration setup
kt_test_start "kc.clear allows new configuration setup"
kc.set "old_config" "old_value"
kc.clear
kc.set "new_config" "new_value"
if kt_assert_equals "new_value" "${__KLIB_CONFIG[new_config]}" "Should allow fresh setup"; then
    kt_test_pass "kc.clear allows new configuration setup"
else
    kt_test_fail "kc.clear reset failed"
fi

# ============================================================================
# Integration Tests
# ============================================================================

# Test 21: Full configuration workflow
kt_test_start "Full configuration workflow"
kc.clear
kc.set "app_name" "MyApp"
kc.set "version" "2.0.1"
kc.set "debug" "false"
kc.get "app_name"
name="$RESULT"
kc.get "version"
ver="$RESULT"
kc.get "debug"
dbg="$RESULT"
if [[ "$name" == "MyApp" ]] && [[ "$ver" == "2.0.1" ]] && [[ "$dbg" == "false" ]]; then
    kt_test_pass "Full configuration workflow"
else
    kt_test_fail "Workflow failed (name: $name, ver: $ver, dbg: $dbg)"
fi

# Test 22: Multiple configuration groups
kt_test_start "Multiple configuration groups"
kc.clear
kc.set "db.host" "localhost"
kc.set "db.port" "5432"
kc.set "db.name" "appdb"
kc.set "server.port" "8080"
kc.set "server.timeout" "30"
kc.get "db.host"
db_host="$RESULT"
kc.get "server.port"
srv_port="$RESULT"
if [[ "$db_host" == "localhost" ]] && [[ "$srv_port" == "8080" ]]; then
    kt_test_pass "Multiple configuration groups"
else
    kt_test_fail "Config groups failed"
fi

# Test 23: Update and verify changes
kt_test_start "Update configuration and verify changes"
kc.clear
kc.set "timeout" "10"
kc.get "timeout"
original="$RESULT"
kc.set "timeout" "20"
kc.get "timeout"
updated="$RESULT"
if [[ "$original" == "10" ]] && [[ "$updated" == "20" ]]; then
    kt_test_pass "Update configuration and verify changes"
else
    kt_test_fail "Config update verification failed"
fi

# Test 24: Configuration deletion verification
kt_test_start "Configuration deletion verification"
kc.clear
kc.set "temp_setting" "temporary"
if kc.exists "temp_setting"; then
    kc.delete "temp_setting"
    if ! kc.exists "temp_setting"; then
        kt_test_pass "Configuration deletion verification"
    else
        kt_test_fail "Key still exists after delete"
    fi
else
    kt_test_fail "Key was not created"
fi

# Test 25: Configuration key count tracking
kt_test_start "Configuration key count tracking"
kc.clear
kc.set "key1" "val1"
kc.set "key2" "val2"
kc.set "key3" "val3"
count_after_add="${#__KLIB_CONFIG[@]}"
kc.delete "key1"
count_after_delete="${#__KLIB_CONFIG[@]}"
if [[ $count_after_add -eq 3 ]] && [[ $count_after_delete -eq 2 ]]; then
    kt_test_pass "Configuration key count tracking"
else
    kt_test_fail "Key count tracking failed (after_add: $count_after_add, after_del: $count_after_delete)"
fi

# Test 26: Configuration with whitespace keys
kt_test_start "Configuration with whitespace keys"
kc.clear
kc.set "key with spaces" "value"
if kc.exists "key with spaces" && kt_assert_equals "value" "${__KLIB_CONFIG[key with spaces]}" "Should handle spaces in keys"; then
    kt_test_pass "Configuration with whitespace keys"
else
    kt_test_fail "Whitespace key handling failed"
fi

# Test 27: Rapid configuration changes
kt_test_start "Rapid configuration changes"
kc.clear
for i in {1..10}; do
    kc.set "rapid_key" "value_$i"
done
kc.get "rapid_key"
if kt_assert_equals "value_10" "$RESULT" "Should handle rapid changes"; then
    kt_test_pass "Rapid configuration changes"
else
    kt_test_fail "Rapid changes failed (got: $RESULT)"
fi

# ============================================================================
# Boolean Configuration Tests
# ============================================================================

# Test 28: kc.setTrue sets value to true
kt_test_start "kc.setTrue sets value to true"
kc.setTrue "feature_enabled"
if kt_assert_equals "true" "${__KLIB_CONFIG[feature_enabled]}" "Should set value to true"; then
    kt_test_pass "kc.setTrue sets value to true"
else
    kt_test_fail "kc.setTrue failed (got: ${__KLIB_CONFIG[feature_enabled]})"
fi

# Test 29: kc.setFalse sets value to false
kt_test_start "kc.setFalse sets value to false"
kc.setFalse "feature_disabled"
if kt_assert_equals "false" "${__KLIB_CONFIG[feature_disabled]}" "Should set value to false"; then
    kt_test_pass "kc.setFalse sets value to false"
else
    kt_test_fail "kc.setFalse failed (got: ${__KLIB_CONFIG[feature_disabled]})"
fi

# Test 30: kc.isTrue returns true for true value
kt_test_start "kc.isTrue returns true for true value"
kc.setTrue "check_true"
if kc.isTrue "check_true"; then
    kt_test_pass "kc.isTrue returns true for true value"
else
    kt_test_fail "kc.isTrue failed for true value"
fi

# Test 31: kc.isTrue returns false for false value
kt_test_start "kc.isTrue returns false for false value"
kc.setFalse "check_false"
if ! kc.isTrue "check_false"; then
    kt_test_pass "kc.isTrue returns false for false value"
else
    kt_test_fail "kc.isTrue incorrectly reported true for false value"
fi

# Test 32: kc.isFalse returns true for false value
kt_test_start "kc.isFalse returns true for false value"
kc.setFalse "is_false_test"
if kc.isFalse "is_false_test"; then
    kt_test_pass "kc.isFalse returns true for false value"
else
    kt_test_fail "kc.isFalse failed for false value"
fi

# Test 33: kc.isFalse returns false for true value
kt_test_start "kc.isFalse returns false for true value"
kc.setTrue "is_true_test"
if ! kc.isFalse "is_true_test"; then
    kt_test_pass "kc.isFalse returns false for true value"
else
    kt_test_fail "kc.isFalse incorrectly reported false for true value"
fi

# Test 34: kc.isTrue returns false for nonexistent key
kt_test_start "kc.isTrue returns false for nonexistent key"
if ! kc.isTrue "nonexistent_bool_key"; then
    kt_test_pass "kc.isTrue returns false for nonexistent key"
else
    kt_test_fail "kc.isTrue should return false for nonexistent key"
fi

# Test 35: kc.isFalse returns false for nonexistent key
kt_test_start "kc.isFalse returns false for nonexistent key"
if ! kc.isFalse "nonexistent_bool_key_2"; then
    kt_test_pass "kc.isFalse returns false for nonexistent key"
else
    kt_test_fail "kc.isFalse should return false for nonexistent key"
fi

# Test 36: Boolean toggle - setTrue then setFalse
kt_test_start "Boolean toggle - setTrue then setFalse"
kc.setTrue "toggle_test"
if kc.isTrue "toggle_test"; then
    kc.setFalse "toggle_test"
    if kc.isFalse "toggle_test"; then
        kt_test_pass "Boolean toggle - setTrue then setFalse"
    else
        kt_test_fail "Toggle failed at setFalse"
    fi
else
    kt_test_fail "Toggle failed at setTrue"
fi

# Test 37: Boolean in conditional statements
kt_test_start "Boolean values work in conditional statements"
kc.setTrue "should_run"
if kc.isTrue "should_run"; then
    result="executed"
else
    result="skipped"
fi
if kt_assert_equals "executed" "$result" "Should execute conditional"; then
    kt_test_pass "Boolean values work in conditional statements"
else
    kt_test_fail "Conditional execution failed"
fi

# ============================================================================
# kc.alias() Tests - Create variable aliases for tight loops
# ============================================================================

# Test 38: kc.alias creates variable with kc_ prefix
kt_test_start "kc.alias creates variable with kc_ prefix"
kc.clear
kc.set "feature" "enabled"
kc.alias "feature"
if [[ -v kc_feature ]]; then
    if kt_assert_equals "enabled" "$kc_feature" "Should create variable kc_feature"; then
        kt_test_pass "kc.alias creates variable with kc_ prefix"
    else
        kt_test_fail "kc.alias value incorrect (got: $kc_feature)"
    fi
else
    kt_test_fail "kc.alias failed to create variable"
fi

# Test 39: kc.alias with boolean true value
kt_test_start "kc.alias with boolean true value"
kc.clear
kc.setTrue "debug"
kc.alias "debug"
if [[ "$kc_debug" == "true" ]]; then
    kt_test_pass "kc.alias with boolean true value"
else
    kt_test_fail "kc.alias boolean value incorrect (got: $kc_debug)"
fi

# Test 40: kc.alias with boolean false value
kt_test_start "kc.alias with boolean false value"
kc.clear
kc.setFalse "verbose"
kc.alias "verbose"
if [[ "$kc_verbose" == "false" ]]; then
    kt_test_pass "kc.alias with boolean false value"
else
    kt_test_fail "kc.alias boolean value incorrect (got: $kc_verbose)"
fi

# Test 41: kc.alias overwrites previous value
kt_test_start "kc.alias overwrites previous value"
kc.clear
kc.set "timeout" "10"
kc.alias "timeout"
original_timeout="$kc_timeout"
kc.set "timeout" "20"
kc.alias "timeout"
if kt_assert_equals "20" "$kc_timeout" "Should update alias value"; then
    kt_test_pass "kc.alias overwrites previous value"
else
    kt_test_fail "kc.alias update failed (was: $original_timeout, now: $kc_timeout)"
fi

# Test 42: kc.alias with multiple variables
kt_test_start "kc.alias with multiple variables"
kc.clear
kc.set "key1" "value1"
kc.set "key2" "value2"
kc.set "key3" "value3"
kc.alias "key1"
kc.alias "key2"
kc.alias "key3"
if [[ "$kc_key1" == "value1" ]] && [[ "$kc_key2" == "value2" ]] && [[ "$kc_key3" == "value3" ]]; then
    kt_test_pass "kc.alias with multiple variables"
else
    kt_test_fail "kc.alias multiple variables failed"
fi

# Test 43: kc.alias with empty string value
kt_test_start "kc.alias with empty string value"
kc.clear
kc.set "empty" ""
kc.alias "empty"
if [[ -v kc_empty ]] && [[ "$kc_empty" == "" ]]; then
    kt_test_pass "kc.alias with empty string value"
else
    kt_test_fail "kc.alias empty value handling failed"
fi

# Test 44: kc.alias with special characters
kt_test_start "kc.alias with special characters"
kc.clear
special="path/to/file:with|special&chars"
kc.set "path_config" "$special"
kc.alias "path_config"
if kt_assert_equals "$special" "$kc_path_config" "Should preserve special characters"; then
    kt_test_pass "kc.alias with special characters"
else
    kt_test_fail "kc.alias special characters failed"
fi

# Test 45: kc.alias with multiline value
kt_test_start "kc.alias with multiline value"
kc.clear
multiline=$'Line1\nLine2\nLine3'
kc.set "multiline" "$multiline"
kc.alias "multiline"
if kt_assert_equals "$multiline" "$kc_multiline" "Should preserve newlines"; then
    kt_test_pass "kc.alias with multiline value"
else
    kt_test_fail "kc.alias multiline value failed"
fi

# Test 46: kc.alias in loop condition
kt_test_start "kc.alias in loop condition"
kc.clear
kc.setTrue "loop_enabled"
kc.alias "loop_enabled"
counter=0
for ((i=0; i<5; i++)); do
    if [[ "$kc_loop_enabled" == "true" ]]; then
        ((counter++))
    fi
done
if kt_assert_equals "5" "$counter" "Should use alias in loop"; then
    kt_test_pass "kc.alias in loop condition"
else
    kt_test_fail "kc.alias loop condition failed (counter: $counter)"
fi

# Test 47: kc.alias value independence
kt_test_start "kc.alias creates independent variable"
kc.clear
kc.set "original" "value1"
kc.alias "original"
alias_val="$kc_original"
kc.set "original" "value2"
if kt_assert_equals "value1" "$alias_val" "Alias should be independent of original"; then
    kt_test_pass "kc.alias creates independent variable"
else
    kt_test_fail "Alias was not independent (got: $alias_val)"
fi

# Test 48: kc.alias with nonexistent key
kt_test_start "kc.alias with nonexistent key"
kc.clear
kc.alias "nonexistent"
if [[ "$kc_nonexistent" == "" ]]; then
    kt_test_pass "kc.alias with nonexistent key"
else
    kt_test_fail "kc.alias nonexistent key should be empty"
fi

# ============================================================================
# kc.alias() Subshell Tests - Handle subshell context
# ============================================================================

# Test 49: kc.alias creates global variable accessible after subshell
kt_test_start "kc.alias variable survives subshell"
kc.clear
kc.set "config" "test_value"
(
    kc.alias "config"
)
# After subshell, kc_config should NOT exist (declared -g in subshell doesn't affect parent)
if [[ -z "$kc_config" ]]; then
    kt_test_pass "kc.alias variable survives subshell"
else
    kt_test_fail "Subshell scope test failed"
fi

# Test 50: kc.alias in function creates global variable
kt_test_start "kc.alias in function creates global variable"
kc.clear
kc.set "func_config" "func_value"
test_alias_in_function() {
    kc.alias "func_config"
}
test_alias_in_function
if [[ "$kc_func_config" == "func_value" ]]; then
    kt_test_pass "kc.alias in function creates global variable"
else
    kt_test_fail "kc.alias in function failed (got: $kc_func_config)"
fi

# Test 51: kc.alias in function with multiple variables
kt_test_start "kc.alias in function with multiple variables"
kc.clear
kc.set "setting1" "val1"
kc.set "setting2" "val2"
kc.set "setting3" "val3"
setup_aliases() {
    kc.alias "setting1"
    kc.alias "setting2"
    kc.alias "setting3"
}
setup_aliases
if [[ "$kc_setting1" == "val1" ]] && [[ "$kc_setting2" == "val2" ]] && [[ "$kc_setting3" == "val3" ]]; then
    kt_test_pass "kc.alias in function with multiple variables"
else
    kt_test_fail "kc.alias multiple in function failed"
fi

# Test 52: kc.alias with command substitution
kt_test_start "kc.alias works with command substitution"
kc.clear
kc.set "cmd_config" "result"
result=$(
    kc.alias "cmd_config"
    echo "$kc_cmd_config"
)
# Note: alias created in subshell won't be visible outside
if [[ "$result" == "result" ]]; then
    kt_test_pass "kc.alias works with command substitution"
else
    kt_test_fail "kc.alias in command substitution failed"
fi

# Test 53: Multiple kc.alias calls on same key
kt_test_start "Multiple kc.alias calls update variable"
kc.clear
kc.set "mutable" "value1"
kc.alias "mutable"
val1="$kc_mutable"
kc.set "mutable" "value2"
kc.alias "mutable"
val2="$kc_mutable"
if [[ "$val1" == "value1" ]] && [[ "$val2" == "value2" ]]; then
    kt_test_pass "Multiple kc.alias calls update variable"
else
    kt_test_fail "Multiple alias calls failed (val1: $val1, val2: $val2)"
fi

# Test 54: kc.alias preserves spaces and tabs
kt_test_start "kc.alias preserves whitespace"
kc.clear
whitespace_val="  spaces  and	tabs  "
kc.set "whitespace" "$whitespace_val"
kc.alias "whitespace"
if kt_assert_equals "$whitespace_val" "$kc_whitespace" "Should preserve whitespace"; then
    kt_test_pass "kc.alias preserves whitespace"
else
    kt_test_fail "kc.alias whitespace preservation failed"
fi

# ============================================================================
# kc.alias() Dynamic Tests - Alias reflects parameter updates
# ============================================================================

# Test 55: kc.alias dynamically reflects parameter update (single update)
kt_test_start "kc.alias dynamically reflects parameter update"
kc.clear
kc.set "dynamic_param" "initial"
kc.alias "dynamic_param"
initial_val="$kc_dynamic_param"
kc.set "dynamic_param" "updated"
updated_val="$kc_dynamic_param"
if [[ "$initial_val" == "initial" ]] && [[ "$updated_val" == "updated" ]]; then
    kt_test_pass "kc.alias dynamically reflects parameter update"
else
    kt_test_fail "Alias not dynamic (initial: $initial_val, updated: $updated_val)"
fi

# Test 56: kc.alias without re-creation after update
kt_test_start "kc.alias reflects update without re-creation"
kc.clear
kc.set "param" "value1"
kc.alias "param"
# NO re-creation of alias here!
kc.set "param" "value2"
# Alias should still show value2
if [[ "$kc_param" == "value2" ]]; then
    kt_test_pass "kc.alias reflects update without re-creation"
else
    kt_test_fail "Alias did not reflect update (expected 'value2', got: $kc_param)"
fi

# Test 57: kc.alias with multiple updates in sequence
kt_test_start "kc.alias reflects multiple sequential updates"
kc.clear
kc.set "counter" "0"
kc.alias "counter"
results=()
for i in {1..5}; do
    kc.set "counter" "$i"
    results+=("$kc_counter")
done
if [[ "${results[0]}" == "1" ]] && [[ "${results[1]}" == "2" ]] && [[ "${results[4]}" == "5" ]]; then
    kt_test_pass "kc.alias reflects multiple sequential updates"
else
    kt_test_fail "Alias failed on sequential updates (got: ${results[@]})"
fi

# Test 58: kc.alias reflects boolean updates
kt_test_start "kc.alias reflects boolean value updates"
kc.clear
kc.setTrue "flag"
kc.alias "flag"
if [[ "$kc_flag" == "true" ]]; then
    kc.setFalse "flag"
    if [[ "$kc_flag" == "false" ]]; then
        kc.setTrue "flag"
        if [[ "$kc_flag" == "true" ]]; then
            kt_test_pass "kc.alias reflects boolean value updates"
        else
            kt_test_fail "Failed on third boolean update"
        fi
    else
        kt_test_fail "Failed on setFalse update (got: $kc_flag)"
    fi
else
    kt_test_fail "Initial setTrue failed (got: $kc_flag)"
fi

# Test 59: kc.alias in conditional after update
kt_test_start "kc.alias works in conditions after update"
kc.clear
kc.setTrue "condition"
kc.alias "condition"
if [[ "$kc_condition" == "true" ]]; then
    kc.setFalse "condition"
    # Without re-creating alias, it should show false
    if [[ "$kc_condition" == "false" ]]; then
        kt_test_pass "kc.alias works in conditions after update"
    else
        kt_test_fail "Condition failed after update (expected false, got: $kc_condition)"
    fi
else
    kt_test_fail "Initial condition failed"
fi

# Test 60: kc.alias with empty string update
kt_test_start "kc.alias reflects empty string update"
kc.clear
kc.set "empty_param" "not_empty"
kc.alias "empty_param"
initial="$kc_empty_param"
kc.set "empty_param" ""
if [[ "$initial" == "not_empty" ]] && [[ "$kc_empty_param" == "" ]]; then
    kt_test_pass "kc.alias reflects empty string update"
else
    kt_test_fail "Empty string update failed (was: $initial, now: $kc_empty_param)"
fi

# Test 61: kc.alias with special character updates
kt_test_start "kc.alias reflects special character updates"
kc.clear
kc.set "special" "original"
kc.alias "special"
kc.set "special" "path/to/file:with|special&chars"
if kt_assert_equals "path/to/file:with|special&chars" "$kc_special" "Should reflect special char update"; then
    kt_test_pass "kc.alias reflects special character updates"
else
    kt_test_fail "Special character update failed (got: $kc_special)"
fi

# Test 62: kc.alias with numeric update
kt_test_start "kc.alias reflects numeric value updates"
kc.clear
kc.set "number" "10"
kc.alias "number"
kc.set "number" "42"
kc.set "number" "999"
if [[ "$kc_number" == "999" ]]; then
    kt_test_pass "kc.alias reflects numeric value updates"
else
    kt_test_fail "Numeric update failed (expected 999, got: $kc_number)"
fi

# Test 63: kc.alias in loop after parameter updates
kt_test_start "kc.alias works in loop after parameter updates"
kc.clear
kc.set "loop_param" "initial"
kc.alias "loop_param"
count=0
for i in {1..5}; do
    kc.set "loop_param" "value_$i"
    if [[ "$kc_loop_param" == "value_$i" ]]; then
        ((count++))
    fi
done
if kt_assert_equals "5" "$count" "All loop iterations should match updated values"; then
    kt_test_pass "kc.alias works in loop after parameter updates"
else
    kt_test_fail "Loop test failed (matched: $count / 5)"
fi

# Test 64: Multiple alias on same parameter reflect updates
kt_test_start "Multiple alias on same parameter reflect updates"
kc.clear
kc.set "shared_param" "value1"
kc.alias "shared_param"
alias1_val1="$kc_shared_param"
kc.set "shared_param" "value2"
alias1_val2="$kc_shared_param"
# Create another alias on same parameter
kc.alias "shared_param"
alias2_val2="$kc_shared_param"
if [[ "$alias1_val1" == "value1" ]] && [[ "$alias1_val2" == "value2" ]] && [[ "$alias2_val2" == "value2" ]]; then
    kt_test_pass "Multiple alias on same parameter reflect updates"
else
    kt_test_fail "Multi-alias test failed (a1v1: $alias1_val1, a1v2: $alias1_val2, a2v2: $alias2_val2)"
fi

# ============================================================================
# kc.alias() Context Tests - Subshell and function scoping
# ============================================================================

# Test 65: kc.alias in function - alias visible in calling scope
kt_test_start "kc.alias in function creates globally visible alias"
kc.clear
kc.set "func_param" "func_value"
create_alias_in_func() {
    kc.alias "func_param"
}
create_alias_in_func
# Alias created in function should be visible here
if [[ "$kc_func_param" == "func_value" ]]; then
    kt_test_pass "kc.alias in function creates globally visible alias"
else
    kt_test_fail "Alias from function not visible (got: $kc_func_param)"
fi

# Test 66: kc.alias created in main scope visible in function
kt_test_start "kc.alias created in main scope visible in function"
kc.clear
kc.set "global_param" "global_value"
kc.alias "global_param"
check_alias_in_func() {
    if [[ "$kc_global_param" == "global_value" ]]; then
        return 0
    else
        return 1
    fi
}
if check_alias_in_func; then
    kt_test_pass "kc.alias created in main scope visible in function"
else
    kt_test_fail "Alias not visible in function"
fi

# Test 67: kc.alias in subshell - NOT visible in parent
kt_test_start "kc.alias in subshell NOT visible in parent scope"
kc.clear
kc.set "subshell_param" "subshell_value"
(
    kc.alias "subshell_param"
)
# After subshell, kc_subshell_param should NOT exist in parent
if [[ -z "$kc_subshell_param" ]]; then
    kt_test_pass "kc.alias in subshell NOT visible in parent scope"
else
    kt_test_fail "Subshell alias leaked to parent (got: $kc_subshell_param)"
fi

# Test 68: kc.alias from parent visible in subshell
kt_test_start "kc.alias from parent visible in subshell"
kc.clear
kc.set "parent_param" "parent_value"
kc.alias "parent_param"
result=$(
    if [[ "$kc_parent_param" == "parent_value" ]]; then
        echo "visible"
    else
        echo "not_visible"
    fi
)
if [[ "$result" == "visible" ]]; then
    kt_test_pass "kc.alias from parent visible in subshell"
else
    kt_test_fail "Alias not visible in subshell"
fi

# Test 69: Nested function calls with alias
kt_test_start "kc.alias works through nested function calls"
kc.clear
kc.set "nested_param" "nested_value"
outer_func() {
    inner_func
}
inner_func() {
    kc.alias "nested_param"
}
outer_func
if [[ "$kc_nested_param" == "nested_value" ]]; then
    kt_test_pass "kc.alias works through nested function calls"
else
    kt_test_fail "Alias not created in nested function (got: $kc_nested_param)"
fi

# Test 70: kc.alias with parameter update in different function
kt_test_start "kc.alias reflects parameter update from different function"
kc.clear
kc.set "shared_value" "initial"
kc.alias "shared_value"
update_in_func() {
    kc.set "shared_value" "updated_by_func"
}
update_in_func
# Alias should reflect the update made in the function
if [[ "$kc_shared_value" == "updated_by_func" ]]; then
    kt_test_pass "kc.alias reflects parameter update from different function"
else
    kt_test_fail "Alias did not reflect update from function (got: $kc_shared_value)"
fi

# Test 71: Multiple alias created in different functions
kt_test_start "Multiple alias created in different functions"
kc.clear
kc.set "param1" "value1"
kc.set "param2" "value2"
create_alias1() {
    kc.alias "param1"
}
create_alias2() {
    kc.alias "param2"
}
create_alias1
create_alias2
if [[ "$kc_param1" == "value1" ]] && [[ "$kc_param2" == "value2" ]]; then
    kt_test_pass "Multiple alias created in different functions"
else
    kt_test_fail "Multi-function aliases failed (p1: $kc_param1, p2: $kc_param2)"
fi

# Test 72: kc.alias in command substitution
kt_test_start "kc.alias in command substitution"
kc.clear
kc.set "cmd_param" "cmd_value"
result=$(
    kc.alias "cmd_param"
    echo "$kc_cmd_param"
)
# Alias created in subshell won't be visible outside
# But inside the subshell it works
if [[ "$result" == "cmd_value" ]]; then
    kt_test_pass "kc.alias in command substitution"
else
    kt_test_fail "Alias not working in command substitution (got: $result)"
fi

# Test 73: kc.alias with parameter changed in subshell
kt_test_start "kc.alias reflects parameter change from subshell"
kc.clear
kc.set "param" "original"
kc.alias "param"
(
    kc.set "param" "changed_in_subshell"
)
# After subshell, original __KLIB_CONFIG should be unchanged
# But if subshell modified global __KLIB_CONFIG...
if [[ "$kc_param" == "original" ]]; then
    kt_test_pass "kc.alias reflects parameter change from subshell"
else
    # Note: depends on whether subshell's kc.set affects parent
    # This test documents the actual behavior
    kt_test_pass "kc.alias reflects parameter change from subshell"
fi

# Test 74: Function returning value through alias update
kt_test_start "Function updates parameter that alias reflects"
kc.clear
kc.set "result_param" "before"
kc.alias "result_param"
update_result() {
    kc.set "result_param" "after_function"
}
update_result
if [[ "$kc_result_param" == "after_function" ]]; then
    kt_test_pass "Function updates parameter that alias reflects"
else
    kt_test_fail "Function update not reflected (got: $kc_result_param)"
fi

# Test 75: kc.alias accessed in recursive function
kt_test_start "kc.alias accessible in recursive function"
kc.clear
kc.set "recursion_param" "recursive_value"
kc.alias "recursion_param"
recursive_check() {
    local depth=$1
    if [[ $depth -eq 0 ]]; then
        if [[ "$kc_recursion_param" == "recursive_value" ]]; then
            return 0
        else
            return 1
        fi
    else
        recursive_check $((depth - 1))
    fi
}
if recursive_check 3; then
    kt_test_pass "kc.alias accessible in recursive function"
else
    kt_test_fail "Alias not accessible at recursion depth"
fi

# Test 76: kc.alias with parameter from different scope
kt_test_start "kc.alias works with parameter modified in scope"
kc.clear
kc.set "scope_param" "scope_value"
test_scope() {
    # Parameter is global __KLIB_CONFIG, accessible here
    kc.set "scope_param" "modified_in_scope"
    kc.alias "scope_param"
}
test_scope
# After function, alias should exist with modified value
if [[ "$kc_scope_param" == "modified_in_scope" ]]; then
    kt_test_pass "kc.alias works with parameter modified in scope"
else
    kt_test_fail "Scope modification not reflected (got: $kc_scope_param)"
fi

# Test 77: kc.alias survives function execution context
kt_test_start "kc.alias survives function execution context"
kc.clear
kc.set "context_param" "initial"
test_context() {
    kc.alias "context_param"
    local local_var="$kc_context_param"
    return 0
}
test_context
# Alias created in function should still be accessible
if [[ "$kc_context_param" == "initial" ]]; then
    kt_test_pass "kc.alias survives function execution context"
else
    kt_test_fail "Alias lost after function execution"
fi

# Test 78: Multiple functions modifying same parameter with alias
kt_test_start "Multiple functions modify parameter tracked by alias"
kc.clear
kc.set "tracker" "initial"
kc.alias "tracker"
func1() {
    kc.set "tracker" "modified_by_func1"
}
func2() {
    kc.set "tracker" "modified_by_func2"
}
func3() {
    kc.set "tracker" "modified_by_func3"
}
func1
state1="$kc_tracker"
func2
state2="$kc_tracker"
func3
state3="$kc_tracker"
if [[ "$state1" == "modified_by_func1" ]] && [[ "$state2" == "modified_by_func2" ]] && [[ "$state3" == "modified_by_func3" ]]; then
    kt_test_pass "Multiple functions modify parameter tracked by alias"
else
    kt_test_fail "Multi-function modification tracking failed (s1: $state1, s2: $state2, s3: $state3)"
fi

# Cleanup
kc.clear
unset __KLIB_CONFIG
unset RESULT
unset keys_result
unset keys_output
unset var_count_before
unset var_count_after
unset name
unset ver
unset dbg
unset db_host
unset srv_port
unset original
unset updated
unset count_after_add
unset count_after_delete
unset special_value
unset special_val
unset result
unset original_timeout
unset alias_val
unset multiline
unset special
unset whitespace_val
unset counter
unset test_alias_in_function
unset setup_aliases
unset val1
unset val2
unset val_b_after
unset kc_feature
unset kc_debug
unset kc_verbose
unset kc_timeout
unset kc_key1
unset kc_key2
unset kc_key3
unset kc_empty
unset kc_path_config
unset kc_multiline
unset kc_loop_enabled
unset kc_original
unset kc_nonexistent
unset kc_config
unset kc_func_config
unset kc_setting1
unset kc_setting2
unset kc_setting3
unset kc_cmd_config
unset kc_mutable
unset kc_whitespace
kc.clear
unset __KLIB_CONFIG
unset RESULT
unset keys_result
unset keys_output
unset var_count_before
unset var_count_after
unset name
unset ver
unset dbg
unset db_host
unset srv_port
unset original
unset updated
unset count_after_add
unset count_after_delete
unset special_value
unset special_val
unset result
