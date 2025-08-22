# Vault TPM Helper - Project Instructions

## Project Overview

This is a Go application that performs Vault certificate authentication using
TPM-protected private keys for enhanced security.

## Development Commands

### Build

```bash
make build
```

### Test

```bash
make test
# or
go test ./...
```

### Run

```bash
./vault-tpm-helper
# or with debug
./vault-tpm-helper -debug
```

### Deploy

```bash
make deploy
```

## Key Project Details

- **Language**: Go
- **Main functionality**: TPM-backed certificate authentication with HashiCorp Vault
- **Key files**:
  - `main.go` - Main application logic
  - `client.cert.pem` - Client certificate (expected)
  - `client.key.pem` - Client private key in TSS2 or standard format
  - `Makefile` - Build and deployment commands

## Architecture Notes

- Supports dual-mode authentication (TPM TSS2 keys and standard private keys)
- Auto-detects key format using `isTSS2Key()` function
- Supports both RSA and ECC key types in both TSS2 and standard formats
- Uses hardware TPM for secure key operations
- Implements mutual TLS authentication with Vault

## Security Considerations

- Private keys never leave TPM hardware when using TSS2 format
- InsecureSkipVerify is enabled for testing (should be disabled in production)
- CA certificates can be provided via `-ca` flag for proper verification

## Dependencies

- `github.com/foxboron/go-tpm-keyfiles` - TSS2 key file handling
- `github.com/google/go-tpm/tpm2/transport` - TPM transport layer
- Standard Go crypto libraries

## Environment Setup

- Requires TPM 2.0 hardware and software stack
- Ubuntu ARM64 recommended
- TPM device typically at `/dev/tpmrm0`

## Testing Notes

- Use `test.sh` for integration testing
- Vault server environment required for full testing
- Debug mode available via `-debug` flag
