#!/bin/bash

# Automated Test Plan for vault-tpm-helper
# Tests both TPM protected keys and normal private keys

set -e  # Exit on error

# Configuration
TARGET_HOST="tpmtest"
TARGET_USER="ubuntu"
VAULT_ADDR="https://nginx"
VAULT_TOKEN="hvs.mjvXxeTkNJLbcO3rYItDjaXX"
BINARY_NAME="vault-tpm-helper"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test function template
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    local should_succeed="$4"  # true/false
    
    log_info "Running test: $test_name"
    
    # Execute test command and capture output
    if output=$(ssh ${TARGET_USER}@${TARGET_HOST} "$test_command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Check if test should succeed or fail
    if [[ "$should_succeed" == "true" ]]; then
        if [[ $exit_code -eq 0 ]] && [[ $output == *"$expected_pattern"* ]]; then
            log_success "$test_name - Output contains expected pattern: $expected_pattern"
        else
            log_error "$test_name - Expected success but got exit code $exit_code or missing pattern"
            echo "Output: $output"
        fi
    else
        if [[ $exit_code -ne 0 ]] && [[ $output == *"$expected_pattern"* ]]; then
            log_success "$test_name - Expected failure with pattern: $expected_pattern"
        else
            log_error "$test_name - Expected failure but got exit code $exit_code or missing pattern"
            echo "Output: $output"
        fi
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "🚀 Starting vault-tpm-helper Test Suite"
    echo "=========================================="
    
    # Step 1: Build and deploy
    log_info "Step 1: Building and deploying to $TARGET_HOST"
    
    log_info "Building for Linux ARM64..."
    if ! make build; then
        log_error "Build failed"
        exit 1
    fi
    
    log_info "Deploying to $TARGET_HOST..."
    if ! make deploy; then
        log_error "Deployment failed"
        exit 1
    fi
    
    log_success "Build and deployment completed"
    
    # Step 2: Verify remote environment
    log_info "Step 2: Verifying remote environment"
    
    # Check if binary exists and is executable
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -x ./${BINARY_NAME}"; then
        log_success "Binary is executable on target host"
    else
        log_error "Binary is not executable on target host"
        exit 1
    fi
    
    # Check if TPM device exists
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -c /dev/tpmrm0"; then
        log_success "TPM device /dev/tpmrm0 is available"
    else
        log_warning "TPM device /dev/tpmrm0 not found - some tests may fail"
    fi
    
    # Check if key files exist
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.key.pem && test -f client.cert.pem"; then
        log_success "TPM protected key and certificate files found"
    else
        log_error "TPM protected key/cert files not found"
        exit 1
    fi
    
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f test-normal.key && test -f test-normal.cert"; then
        log_success "Normal test key and certificate files found"
    else
        log_error "Normal test key/cert files not found"
        exit 1
    fi
    
    # Step 3: Test Cases
    log_info "Step 3: Running test cases"
    
    # Test Case 1: TPM Protected Key - Success Test
    run_test \
        "TPM Key Authentication Success" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "hvs\." \
        "true"
    
    # Test Case 2: TPM Protected Key - Detection Test
    run_test \
        "TPM Key Format Detection" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "Detected TSS2 key format, using TPM signer" \
        "true"
    
    # Test Case 3: TPM Protected Key - TSS2 Loading Test
    run_test \
        "TPM Key TSS2 Loading" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "Successfully loaded TSS2 key from client.key.pem" \
        "true"
    
    # Test Case 4: Normal Key - Format Detection Test
    run_test \
        "Normal Key Format Detection" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -client-key test-normal.key -client-cert test-normal.cert -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "Detected standard private key format, using normal signer" \
        "true"
    
    # Test Case 5: Normal Key - Loading Test
    run_test \
        "Normal Key Loading" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -client-key test-normal.key -client-cert test-normal.cert -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "Successfully loaded normal private key from test-normal.key" \
        "true"
    
    # Test Case 6: Wrong Vault URL - Error Handling Test
    run_test \
        "Error Handling - Invalid Vault URL" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -debug -vaultaddr https://nonexistent-vault.example.com 2>&1" \
        "failed to make request" \
        "false"
    
    # Test Case 7: Missing Certificate File - Error Test
    run_test \
        "Error Handling - Missing Certificate" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -client-cert nonexistent.cert -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "failed to load certificate" \
        "false"
    
    # Test Case 8: Missing Key File - Error Test
    run_test \
        "Error Handling - Missing Key File" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -client-key nonexistent.key -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "failed to create signer" \
        "false"
    
    # Test Case 9: Help Output Test
    run_test \
        "Help Output" \
        "./${BINARY_NAME} --help 2>&1" \
        "Usage of" \
        "true"
    
    # Test Case 10: HTTPS Connection Test
    run_test \
        "HTTPS Connection Verification" \
        "unset VAULT_ADDR; ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} 2>&1" \
        "https://nginx/v1/auth/cert/login" \
        "true"
    
    # Step 4: Performance and Edge Cases
    log_info "Step 4: Performance and edge case testing"
    
    # Test Case 11: Multiple rapid requests (stress test)
    log_info "Running stress test with 3 rapid TPM requests..."
    for i in {1..3}; do
        run_test \
            "Stress Test Request $i" \
            "unset VAULT_ADDR; timeout 10s ./${BINARY_NAME} -vaultaddr ${VAULT_ADDR} 2>&1" \
            "hvs\." \
            "true"
    done
    
    # Step 5: Cleanup and Summary
    log_info "Step 5: Cleanup and summary"
    
    # Optional cleanup
    log_info "Cleaning up temporary files..."
    ssh ${TARGET_USER}@${TARGET_HOST} "rm -f test-output-*.log" || true
    
    # Test Summary
    echo "=========================================="
    echo "📊 Test Suite Summary"
    echo "=========================================="
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Enable verbose output"
    echo "  --dry-run      Show what would be tested without executing"
    echo ""
    echo "Environment Variables:"
    echo "  VAULT_ADDR     Vault server address (default: https://nginx)"
    echo "  VAULT_TOKEN    Vault root token (default: hvs.mjvXxeTkNJLbcO3rYItDjaXX)"
    echo "  TARGET_HOST    Target test host (default: tpmtest)"
    echo "  TARGET_USER    Target user (default: ubuntu)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        --dry-run)
            log_info "DRY RUN MODE - Would execute the following tests:"
            echo "1. Build and deploy vault-tpm-helper to $TARGET_HOST"
            echo "2. Verify remote environment and dependencies"
            echo "3. Test TPM protected key authentication"
            echo "4. Test normal private key authentication"
            echo "5. Test error handling and edge cases"
            echo "6. Run stress tests"
            echo "7. Generate summary report"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"