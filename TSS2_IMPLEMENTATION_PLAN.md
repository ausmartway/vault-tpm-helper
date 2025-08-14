# TSS2 Private Key Implementation Plan

## Current Problem

The Go program creates a new TPM key instead of using the existing `tpmtest.key.pem` file, which is in TSS2 format:

```text
-----BEGIN TSS2 PRIVATE KEY-----
MIIB8gYGZ4EFCgEDoAMBAQECBEAAAAEEggEYARYAAQALAAYAcgAAABAAEAgAAAAA
AAEAz/Q3XRKz7uLpR+r5c6OMXT8VB2xvAaGY6BJ71NVlSrqI4iFGmdxMccmHIw1g
ZYWMcxg3LkTOWaC/WfSyIDJvXOR8ITt1L7RYlzcQStLYJPlaVYdetuavK8+FUozc
q8VZrbs/RsAwN2xM9vH/VPbzmBmo3CuDYnTxW0R6x6JECdUuda1zPBfdLeDmoG3U
-----END TSS2 PRIVATE KEY-----
```

## Solution: Implement TSS2 Key Loading

### Step 1: Add TSS2 Dependencies

Add the step-crypto library to handle TSS2 format:

```bash
go get go.step.sm/crypto/tpm
go get go.step.sm/crypto/tpm/tss2
```

### Step 2: Update Import Statements

```go
import (
    // existing imports...
    "go.step.sm/crypto/tpm"
    "go.step.sm/crypto/tpm/tss2"
)
```

### Step 3: Implement TSS2 Key Loading Function

Create a function to load TSS2 private key from PEM file:

```go
func loadTSS2Key(keyPath string) (*tss2.TPMKey, error) {
    // 1. Read PEM file
    keyPEM, err := os.ReadFile(keyPath)
    if err != nil {
        return nil, fmt.Errorf("failed to read key file: %w", err)
    }

    // 2. Decode PEM block
    block, _ := pem.Decode(keyPEM)
    if block == nil || block.Type != "TSS2 PRIVATE KEY" {
        return nil, fmt.Errorf("invalid TSS2 private key format")
    }

    // 3. Parse TSS2 private key from ASN.1 DER
    tss2Key, err := tss2.ParsePrivateKey(block.Bytes)
    if err != nil {
        return nil, fmt.Errorf("failed to parse TSS2 key: %w", err)
    }

    return tss2Key, nil
}
```

### Step 4: Update TPM Signer Creation

Modify `createTPMSigner` to use the TSS2 key:

```go
func createTPMSigner(tpmPath, keyPath string) (crypto.Signer, error) {
    // 1. Load TSS2 key from file
    tss2Key, err := loadTSS2Key(keyPath)
    if err != nil {
        return nil, fmt.Errorf("failed to load TSS2 key: %w", err)
    }

    // 2. Open TPM
    tpmInstance, err := tpm.OpenTPM(tpmPath)
    if err != nil {
        return nil, fmt.Errorf("failed to open TPM: %w", err)
    }

    // 3. Create crypto.Signer from TSS2 key
    ctx := context.Background()
    signer, err := tpm.CreateTSS2Signer(ctx, tpmInstance, tss2Key)
    if err != nil {
        return nil, fmt.Errorf("failed to create TSS2 signer: %w", err)
    }

    return signer, nil
}
```

### Step 5: Update Main Function Call

Update the function signature in `run()`:

```go
// Before:
tmpSigner, err := createTPMSigner(config.TPMPath, config.TPMHandle)

// After:
tmpSigner, err := createTPMSigner(config.TPMPath, config.KeyPath)
```

### Step 6: Remove Handle-Related Code

Remove the unnecessary handle-related configuration:
- Remove `TPMHandle` from `Config` struct
- Remove the handle flag from `main()`
- Simplify the function to use the key file directly

### Step 7: Update go.mod

Update dependencies:

```go
module tpm-https-client

go 1.21

require (
    github.com/google/go-tpm-tools v0.4.4
    github.com/google/go-tpm v0.9.0
    go.step.sm/crypto v0.x.x  // Add latest version
)
```

### Step 8: Test Implementation

1. **Build**: `make build`
2. **Deploy**: `make deploy` 
3. **Test**: `ssh ubuntu@tpmtest "./tpm-https-client"`
4. **Verify**: Compare output with OpenSSL reference command

### Step 9: Handle Potential Issues

**Expected Challenges:**
- TSS2 API is marked as experimental
- May need to handle different TSS2 format variations
- TPM context and session management

**Fallback Options:**
- Use `tpm2tools` package from go-tpm-tools
- Implement direct PEM parsing if needed
- Use openssl command execution as bridge

### Step 10: Validation

The implementation should produce the same result as:

```bash
cat nginx.txt | openssl s_client \
  -provider tpm2 -provider default \
  -propquery '?provider=tpm2' \
  -connect nginx:443 \
  -cert tpmtest.cert.pem \
  -key tpmtest.key.pem \
  -quiet | \
  awk '/^HTTP/ {p=1} p {print}' | \
  awk 'BEGIN {RS="\r\n\r\n"} NR==2 {print}' | \
  jq .auth.client_token
```

## Expected Outcome

After implementation:
- ✅ Uses existing `tpmtest.key.pem` TSS2 format key
- ✅ Key matches the certificate exactly  
- ✅ TLS handshake succeeds
- ✅ Extracts `auth.client_token` from JSON response
- ✅ Produces same result as OpenSSL validation command

## Implementation Priority

**Phase 1**: Basic TSS2 loading (Steps 1-6)
**Phase 2**: Testing and debugging (Steps 7-8)  
**Phase 3**: Error handling and validation (Steps 9-10)

This plan addresses the root requirement: use the existing TPM key, not create a new one.