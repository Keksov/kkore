#!/bin/bash
# tests.sh - Test runner for kklass tests using kktests framework
# Usage: ./tests.sh [OPTIONS]

set -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load test framework (kktests)
KKTESTS_LIB_DIR="$(cd "$SCRIPT_DIR/../../kktests" && pwd)"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Parse command line arguments
kk_runner_parse_args "$@"

# Show test execution info
kk_test_section "Starting kklass Test Suite"

# Find test files - look for numbered test files [0-9][0-9][0-9]_*.sh
test_files=()
while IFS= read -r file; do
    test_files+=("$file")
done < <(kk_runner_find_tests "$SCRIPT_DIR" | grep '/[0-9][0-9][0-9]_')

if [[ ${#test_files[@]} -eq 0 ]]; then
    kk_test_error "No test files found in $SCRIPT_DIR"
    exit 1
fi

# Show test files to be executed in info mode
if [[ "$VERBOSITY" == "info" ]]; then
    echo "Found ${#test_files[@]} test file(s):"
    for f in "${test_files[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo ""
fi

# Execute all tests
kk_runner_execute_tests "$SCRIPT_DIR"

# Display final results
echo ""
kk_test_show_results "${FAILED_TEST_FILES[@]}"

# Exit with appropriate code
exit $?
