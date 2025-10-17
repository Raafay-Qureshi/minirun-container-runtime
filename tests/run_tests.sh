#!/bin/bash


# MiniRun Container Runtime - Test Runner
# 
# Runs all unit and integration tests
# Verifies namespace isolation, cgroups, and CLI functionality
#
# Usage: ./tests/run_tests.sh [options]
# Options:
#   --unit-only         Run only unit tests
#   --integration-only  Run only integration tests
#   --verbose          Show detailed output


set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
UNIT_DIR="$SCRIPT_DIR/unit"
INTEGRATION_DIR="$SCRIPT_DIR/integration"

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Configuration
RUN_UNIT=true
RUN_INTEGRATION=true
VERBOSE=false


# Print functions

print_message() {
    echo -e "${1}${2}${NC}"
}

print_success() {
    print_message "$GREEN" "✓ $1"
}

print_error() {
    print_message "$RED" "✗ $1"
}

print_info() {
    print_message "$BLUE" "ℹ $1"
}


# Parse arguments

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --unit-only)
                RUN_INTEGRATION=false
                shift
                ;;
            --integration-only)
                RUN_UNIT=false
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --unit-only         Run only unit tests"
                echo "  --integration-only  Run only integration tests"
                echo "  -v, --verbose       Show detailed output"
                echo "  -h, --help          Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}


# Run a single test and track results

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$VERBOSE" = true ]; then
        print_info "Running: $test_name"
        if eval "$test_command"; then
            print_success "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "$test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("$test_name")
            return 1
        fi
    else
        if eval "$test_command" &>/dev/null; then
            print_success "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "$test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("$test_name")
            return 1
        fi
    fi
}


# Compile unit tests

compile_unit_tests() {
    print_message "$BLUE" "Compiling unit tests..."
    
    local compiled=0
    if [ -d "$UNIT_DIR" ]; then
        for test_file in "$UNIT_DIR"/test_*.c; do
            if [ -f "$test_file" ]; then
                local test_name=$(basename "$test_file" .c)
                local test_bin="$UNIT_DIR/$test_name"
                
                if gcc -o "$test_bin" "$test_file" -Wall -Wextra 2>/dev/null; then
                    chmod +x "$test_bin"
                    compiled=$((compiled + 1))
                else
                    print_error "Failed to compile $test_name"
                fi
            fi
        done
    fi
    
    if [ $compiled -gt 0 ]; then
        print_success "Compiled $compiled unit test(s)"
    else
        print_info "No unit tests to compile"
    fi
}


# Run unit tests

run_unit_tests() {
    print_message "$BLUE" "\n════════════════════════════════════════════════"
    print_message "$BLUE" "  Running Unit Tests"
    print_message "$BLUE" "════════════════════════════════════════════════\n"
    
    compile_unit_tests
    
    # Run compiled C tests
    if [ -d "$UNIT_DIR" ]; then
        for test_bin in "$UNIT_DIR"/test_*; do
            if [ -f "$test_bin" ] && [ -x "$test_bin" ] && [[ ! "$test_bin" =~ \.c$ ]]; then
                local test_name=$(basename "$test_bin")
                run_test "$test_name" "sudo $test_bin"
            fi
        done
    fi
    
    # Basic sanity tests
    run_test "Binary exists" "[ -f '$PROJECT_ROOT/bin/container_runtime' ]"
    run_test "Binary is executable" "[ -x '$PROJECT_ROOT/bin/container_runtime' ]"
    run_test "CLI exists" "[ -f '$PROJECT_ROOT/minirun' ]"
    run_test "CLI is executable" "[ -x '$PROJECT_ROOT/minirun' ]"
    run_test "Root filesystem exists" "[ -d '$PROJECT_ROOT/myroot' ]"
    run_test "Root filesystem has binaries" "[ -f '$PROJECT_ROOT/myroot/bin/bash' ]"
}


# Run integration tests

run_integration_tests() {
    print_message "$BLUE" "\n════════════════════════════════════════════════"
    print_message "$BLUE" "  Running Integration Tests"
    print_message "$BLUE" "════════════════════════════════════════════════\n"
    
    # Run Python integration tests
    if [ -d "$INTEGRATION_DIR" ]; then
        for test_file in "$INTEGRATION_DIR"/test_*.py; do
            if [ -f "$test_file" ]; then
                local test_name=$(basename "$test_file")
                run_test "$test_name" "python3 $test_file"
            fi
        done
    fi
    
    # Test CLI commands
    run_test "CLI help command" "$PROJECT_ROOT/minirun --help"
    run_test "CLI list command" "$PROJECT_ROOT/minirun list"
    
    # Test container creation (non-destructive)
    local test_container="test-$(date +%s)"
    run_test "Create test container" "$PROJECT_ROOT/minirun create $test_container"
    run_test "List shows container" "$PROJECT_ROOT/minirun list | grep -q $test_container"
    run_test "Container info command" "$PROJECT_ROOT/minirun info $test_container"
    run_test "Delete test container" "$PROJECT_ROOT/minirun delete $test_container"
    run_test "Container deleted" "! $PROJECT_ROOT/minirun list | grep -q $test_container"
}


# Generate test report

generate_report() {
    print_message "$BLUE" "\n════════════════════════════════════════════════"
    print_message "$BLUE" "  Test Results Summary"
    print_message "$BLUE" "════════════════════════════════════════════════\n"
    
    echo "Tests Run:    $TESTS_RUN"
    print_message "$GREEN" "Passed:       $TESTS_PASSED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        print_message "$RED" "Failed:       $TESTS_FAILED"
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    else
        echo "Failed:       0"
        echo ""
        print_success "All tests passed! 🎉"
        echo ""
    fi
    
    # Calculate success rate
    if [ $TESTS_RUN -gt 0 ]; then
        local success_rate=$(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED/$TESTS_RUN)*100}")
        echo "Success Rate: $success_rate%"
    fi
}


# Main test execution

main() {
    # Print banner
    clear
    print_message "$BLUE" "╔════════════════════════════════════════════════╗"
    print_message "$BLUE" "║   MiniRun Container Runtime - Test Suite      ║"
    print_message "$BLUE" "╚════════════════════════════════════════════════╝"
    
    parse_args "$@"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run tests
    if [ "$RUN_UNIT" = true ]; then
        run_unit_tests
    fi
    
    if [ "$RUN_INTEGRATION" = true ]; then
        run_integration_tests
    fi
    
    # Generate report
    generate_report
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main "$@"