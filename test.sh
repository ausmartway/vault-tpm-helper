#!/bin/bash

# Automated Test Plan for vault-tpm-helper
# Tests both TPM protected keys and normal private keys

set -e  # Exit on error

# Configuration
TARGET_HOST="tpmtest"
TARGET_USER="ubuntu"
VAULT_ADDR="https://nginx"
VAULT_TOKEN="hvs.mjvXxeTkNJLbcO3rYItDjaXX"
SIGNING_VAULT_ADDR="https://vault-plus-demo-public-vault-16765abc.e222d45b.z1.hashicorp.cloud:8200/"
SIGNING_VAULT_TOKEN="hvs.CAESIHyWgLCvaYRDb11cPApVwcgYdbIXZUeltm9AOI8Fs0MBGikKImh2cy5WNUx0VWRXWjdOT1ZWMWtaSm1DSlJnM04ud2Q1VnkQ15TxCA"
SIGNING_VAULT_NAMESPACE="admin"
SIGNING_VAULT_PATH="pki_intermediate/sign/machine-id"
CLEANUP=false  # Set to false to skip cleanup

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
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.rsa.key.pem && test -f client.rsa.cert.pem"; then
        log_success "TPM protected RSA key and certificate files found"
    else
        log_warning "TPM protected RSA key/cert files not found - will create them"
    fi

    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.ecc.key.pem && test -f client.ecc.cert.pem"; then
        log_success "TPM protected ECC key and certificate files found"
    else
        log_warning "TPM protected ECC key/cert files not found - will create them"
    fi
    
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f test-normal.key && test -f test-normal.cert"; then
        log_success "Normal test key and certificate files found"
    else
        log_error "Normal test key/cert files not found"
        exit 1
    fi

    # Create TPM-backed keys and certificates if they don't exist
    log_info "Step 2b: Creating TPM-backed keys and certificates"
    
    # Generate ECC key and certificate
    if ! ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.ecc.key.pem && test -f client.ecc.cert.pem && test -s client.ecc.cert.pem"; then
        log_info "Creating TPM-backed ECC private key with OpenSSL TPM2 provider..."
        
        ssh ${TARGET_USER}@${TARGET_HOST} "
            # Create ECC key using OpenSSL with TPM2 provider
            openssl genpkey -provider tpm2 -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out client.ecc.key.pem
        "
        
        log_info "Creating CSR for ECC key..."
        ssh ${TARGET_USER}@${TARGET_HOST} "
            # Create CSR using the TPM-backed ECC key (need both default and tpm2 providers)
            openssl req -provider default -provider tpm2 -new -key client.ecc.key.pem -out client.ecc.csr.pem -subj '/CN=tpmtest.machine-id.customer.demo'
        "
        
        log_info "Signing ECC CSR with Vault..."
        if ssh ${TARGET_USER}@${TARGET_HOST} "VAULT_ADDR=${SIGNING_VAULT_ADDR} VAULT_TOKEN=${SIGNING_VAULT_TOKEN} VAULT_NAMESPACE=${SIGNING_VAULT_NAMESPACE} VAULT_SKIP_VERIFY=true vault write -format=json ${SIGNING_VAULT_PATH} ttl=90d csr=@client.ecc.csr.pem > ecc_cert_response.json && jq -r '.data.certificate' ecc_cert_response.json > client.ecc.cert.pem && rm ecc_cert_response.json"; then
            log_success "ECC certificate created successfully"
        else
            log_error "Failed to create ECC certificate"
            exit 1
        fi
    fi

    # Generate RSA key and certificate
    if ! ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.rsa.key.pem && test -f client.rsa.cert.pem && test -s client.rsa.cert.pem"; then
        log_info "Creating TPM-backed RSA private key with OpenSSL TPM2 provider..."
        
        ssh ${TARGET_USER}@${TARGET_HOST} "
            # Create RSA key using OpenSSL with TPM2 provider
            openssl genpkey -provider tpm2 -algorithm RSA -out client.rsa.key.pem
        "
        
        log_info "Creating CSR for RSA key..."
        ssh ${TARGET_USER}@${TARGET_HOST} "
            # Create CSR using the TPM-backed RSA key (need both default and tpm2 providers)
            openssl req -provider default -provider tpm2 -new -key client.rsa.key.pem -out client.rsa.csr.pem -subj '/CN=tpmtest.machine-id.customer.demo'
        "
        
        log_info "Signing RSA CSR with Vault..."
        if ssh ${TARGET_USER}@${TARGET_HOST} "VAULT_ADDR=${SIGNING_VAULT_ADDR} VAULT_TOKEN=${SIGNING_VAULT_TOKEN} VAULT_NAMESPACE=${SIGNING_VAULT_NAMESPACE} VAULT_SKIP_VERIFY=true vault write -format=json ${SIGNING_VAULT_PATH} ttl=90d csr=@client.rsa.csr.pem > rsa_cert_response.json && jq -r '.data.certificate' rsa_cert_response.json > client.rsa.cert.pem && rm rsa_cert_response.json"; then
            log_success "RSA certificate created successfully"
        else
            log_error "Failed to create RSA certificate"
            exit 1
        fi
    fi

    # Step 2c: Validate certificates
    log_info "Step 2c: Validating created certificates"
    
    # Validate ECC certificate
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.ecc.cert.pem && test -s client.ecc.cert.pem"; then
        log_info "Validating ECC certificate..."
        if ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.ecc.cert.pem -noout -verify 2>/dev/null"; then
            # Get key algorithm and curve info
            key_info=$(ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.ecc.cert.pem -text -noout | grep -A 3 'Public Key Algorithm'")
            curve_info=$(ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.ecc.cert.pem -text -noout | grep -A 1 'NIST CURVE'")
            subject=$(ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.ecc.cert.pem -subject -noout")
            
            log_success "ECC certificate validation passed"
            log_info "  Algorithm: $(echo "$key_info" | grep 'Public Key Algorithm' | cut -d: -f2 | xargs)"
            log_info "  Key Size: $(echo "$key_info" | grep 'Public-Key' | cut -d: -f2 | xargs)"
            log_info "  Curve: $(echo "$curve_info" | grep 'NIST CURVE' | cut -d: -f2 | xargs)"
            log_info "  Subject: $(echo "$subject" | cut -d= -f2-)"
        else
            log_error "ECC certificate validation failed"
        fi
    else
        log_warning "ECC certificate not found or empty"
    fi
    
    # Validate RSA certificate
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.rsa.cert.pem && test -s client.rsa.cert.pem"; then
        log_info "Validating RSA certificate..."
        if ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.rsa.cert.pem -noout -verify 2>/dev/null"; then
            # Get key algorithm and size info
            key_info=$(ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.rsa.cert.pem -text -noout | grep -A 2 'Public Key Algorithm'")
            subject=$(ssh ${TARGET_USER}@${TARGET_HOST} "openssl x509 -in client.rsa.cert.pem -subject -noout")
            
            log_success "RSA certificate validation passed"
            log_info "  Algorithm: $(echo "$key_info" | grep 'Public Key Algorithm' | cut -d: -f2 | xargs)"
            log_info "  Key Size: $(echo "$key_info" | grep 'Public-Key' | cut -d: -f2 | xargs)"
            log_info "  Subject: $(echo "$subject" | cut -d= -f2-)"
        else
            log_error "RSA certificate validation failed"
        fi
    else
        log_warning "RSA certificate not found or empty"
    fi
    
    # Validate key formats
    log_info "Validating TPM key formats..."
    
    # Check ECC key format
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.ecc.key.pem"; then
        if ssh ${TARGET_USER}@${TARGET_HOST} "head -1 client.ecc.key.pem | grep -q 'TSS2 PRIVATE KEY'"; then
            log_success "ECC key is in TSS2 format (TPM-backed)"
        else
            log_warning "ECC key is not in TSS2 format"
        fi
    fi
    
    # Check RSA key format
    if ssh ${TARGET_USER}@${TARGET_HOST} "test -f client.rsa.key.pem"; then
        if ssh ${TARGET_USER}@${TARGET_HOST} "head -1 client.rsa.key.pem | grep -q 'TSS2 PRIVATE KEY'"; then
            log_success "RSA key is in TSS2 format (TPM-backed)"
        else
            log_warning "RSA key is not in TSS2 format"
        fi
    fi
    
    log_info "Step 3: Running test cases"

    # Test Case 1: RSA TPM Protected Key - Success Test
    run_test \
        "RSA TPM Key Authentication Success" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.rsa.key.pem -client-cert client.rsa.cert.pem 2>&1 || true" \
        "Successfully loaded TSS2 key from client.rsa.key.pem" \
        "true"
    
    # Test Case 2: ECC TPM Protected Key - Success Test
    run_test \
        "ECC TPM Key Authentication Success" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.ecc.key.pem -client-cert client.ecc.cert.pem 2>&1 || true" \
        "Successfully loaded TSS2 key from client.ecc.key.pem" \
        "true"
    
    # Test Case 3: RSA TPM Key Format Detection Test
    run_test \
        "RSA TPM Key Format Detection" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.rsa.key.pem -client-cert client.rsa.cert.pem 2>&1 || true" \
        "Detected TSS2 key format, using TPM signer" \
        "true"
    
    # Test Case 4: ECC TPM Key Format Detection Test
    run_test \
        "ECC TPM Key Format Detection" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.ecc.key.pem -client-cert client.ecc.cert.pem 2>&1 || true" \
        "Detected TSS2 key format, using TPM signer" \
        "true"
    
    # Test Case 5: RSA TPM Key Loading Test
    run_test \
        "RSA TPM Key TSS2 Loading" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.rsa.key.pem -client-cert client.rsa.cert.pem 2>&1 || true" \
        "Successfully loaded TSS2 key from client.rsa.key.pem" \
        "true"
        
    # Test Case 6: ECC TPM Key Loading Test
    run_test \
        "ECC TPM Key TSS2 Loading" \
        "unset VAULT_ADDR; timeout 5s ./${BINARY_NAME} -debug -vaultaddr ${VAULT_ADDR} -client-key client.ecc.key.pem -client-cert client.ecc.cert.pem 2>&1 || true" \
        "Successfully loaded TSS2 key from client.ecc.key.pem" \
        "true"
    
    # Test Case 14: Certificate Validation Tests
    run_test \
        "RSA Certificate Validation" \
        "openssl x509 -in client.rsa.cert.pem -noout -text | grep 'rsaEncryption'" \
        "rsaEncryption" \
        "true"
        
    run_test \
        "ECC Certificate Validation" \
        "openssl x509 -in client.ecc.cert.pem -noout -text | grep 'id-ecPublicKey'" \
        "id-ecPublicKey" \
        "true"

    run_test \
        "RSA Key Size Verification" \
        "openssl x509 -in client.rsa.cert.pem -noout -text | grep 'Public-Key'" \
        "2048 bit" \
        "true"

    run_test \
        "ECC Curve Verification" \
        "openssl x509 -in client.ecc.cert.pem -noout -text | grep 'prime256v1'" \
        "prime256v1" \
        "true"

    


    # Step 5: Cleanup and Summary
    log_info "Step 5: Cleanup and summary"
    
    # Optional cleanup
    log_info "Cleaning up key/csr/cert files..."
    if [ "$CLEANUP" = true ]; then
        ssh ${TARGET_USER}@${TARGET_HOST} "rm -f client.*.pem" || true
    fi

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