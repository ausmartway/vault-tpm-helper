# Vault TPM Helper

A Go application that performs Vault certificate authentication using TPM-protected private keys.

## Overview

This program uses a Trusted Platform Module (TPM) 2.0 to securely store and use private keys for client certificate authentication when connecting to HTTPS servers. The private key never leaves the TPM hardware, providing enhanced security.

**Note**: The current implementation creates a new TPM attestation key rather than loading the existing TSS2-format key from `tpmtest.key.pem`. This demonstrates the TPM integration concept while the TSS2 key loading functionality is still being refined.

## Prerequisites

### System Requirements
- Ubuntu ARM64 system with TPM 2.0 chip
- TPM 2.0 software stack installed
- Client certificate file

### TPM Software Stack Installation

On Ubuntu, install the required TPM libraries:

```bash
sudo apt update
sudo apt install -y tpm2-tools libtpm2-pkcs11-1 libtpm2-pkcs11-dev
```

### File Requirements

The program expects these files to be present:
- `tpmtest.cert.pem` - Client certificate in PEM format
- `nginx.txt` - Request payload data

## Usage

### Basic Usage

```bash
./vault-tpm-helper
```

This uses default settings:
- Certificate: `tpmtest.cert.pem`
- Server: `https://nginx:443`
- Request data: `nginx.txt`
- TPM device: `/dev/tpm0`

### Command Line Options

```bash
./vault-tpm-helper [options]
```

#### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-cert` | `tpmtest.cert.pem` | Path to client certificate file |
| `-server` | `https://nginx:443` | Target HTTPS server URL |
| `-request` | `nginx.txt` | Request data file path |
| `-tpm-path` | `/dev/tpm0` | Path to TPM device |
| `-ca` | _(none)_ | Path to CA certificate bundle (optional) |

#### Example with Custom Settings

```bash
./vault-tpm-helper \
  -cert /path/to/my-cert.pem \
  -server https://api.example.com:8443 \
  -request payload.json \
  -ca /etc/ssl/certs/ca-bundle.pem
```

### Sample Request File

The `nginx.txt` file should contain the complete HTTP request:

```
POST /v1/auth/cert/login HTTP/1.1
Host: nginx:443
Content-Type: application/json
Content-Length: 13
Connection: close

{"name": ""}
```

## How It Works

1. **TPM Initialization**: Opens connection to TPM device (`/dev/tpm0`)
2. **Key Creation**: Creates a new RSA attestation key in the TPM
3. **Certificate Loading**: Reads the client certificate from PEM file
4. **TLS Configuration**: Creates TLS config with TPM-backed certificate
5. **HTTPS Request**: Performs mutual TLS authentication with target server
6. **Response Processing**: Parses JSON response and extracts `auth.client_token`

## Output

The program outputs the client token from the server response:

```bash
$ ./vault-tpm-helper
hvs.CAESII8ZnxgCr-XpHnPD1ESvlizTZjMVZjrnboV9zP9htRmMGiMKHGh2cy5qN2hhY0wyR0tWME9ITUpjcjlVQXQ5M2IQl6mfBg
```

## Validation

You can validate the setup using OpenSSL with the TPM2 provider:

```bash
cat nginx.txt | openssl s_client \
  -provider tpm2 \
  -provider default \
  -propquery '?provider=tpm2' \
  -connect nginx:443 \
  -cert tpmtest.cert.pem \
  -key tpmtest.key.pem \
  -quiet | \
  awk '/^HTTP/ {p=1} p {print}' | \
  awk 'BEGIN {RS="\r\n\r\n"} NR==2 {print}' | \
  jq .auth.client_token
```

This command should produce the same client token format.

## Current Limitations

- **TSS2 Key Loading**: The program currently creates a new TPM attestation key instead of loading the existing TSS2-format key from `tpmtest.key.pem`. This means the key won't match the certificate exactly.
- **Certificate Mismatch**: Since a new key is generated, it won't match the provided certificate, which may cause TLS handshake failures.

## Working Alternative

For demonstration purposes, to see the TPM integration working:

1. Generate a new certificate that matches the TPM key:
```bash
# This would require additional certificate generation steps
```

2. Or use the proven OpenSSL method shown in the validation section above.

## Troubleshooting

### TPM Device Access

If you get permission errors accessing `/dev/tpm0`:

```bash
# Check TPM device permissions
ls -la /dev/tpm*

# Add user to tss group (if needed)
sudo usermod -a -G tss $USER

# Logout and login again for group changes to take effect
```

### TPM Device Not Found

If `/dev/tpm0` doesn't exist:

```bash
# Check for TPM in kernel logs
sudo dmesg | grep -i tpm

# Check if TPM is enabled in BIOS/UEFI
# Enable TPM 2.0 in system firmware settings
```

### Certificate/Key Issues

- The current implementation creates a new TPM key that won't match the existing certificate
- For production use, either:
  - Generate a new certificate for the TPM-generated key, or
  - Implement proper TSS2 key loading to use the existing key

### Connection Issues

- Verify the target server URL is correct
- Check network connectivity to the target server
- Ensure the server supports client certificate authentication

## Security Notes

- Private keys are protected by the TPM hardware and never exposed in memory
- TPM provides hardware-based key storage and cryptographic operations
- Keys cannot be extracted from the TPM once imported
- Each TPM operation is hardware-attested

## Dependencies

This program uses the following Go libraries:
- `github.com/google/go-tpm-tools/client` - High-level TPM operations
- `github.com/google/go-tpm/tpm2/transport` - TPM transport layer
- Standard Go crypto libraries for TLS and certificate handling

## Building from Source

If you need to rebuild the binary:

```bash
# Install Go 1.21 or later
# Clone the source code
# Run build command
make build

# Deploy to remote host
make deploy
```

## Future Improvements

- Implement proper TSS2 key format loading
- Add support for existing persistent TPM handles
- Enhanced error handling and logging
- Support for different key types (ECC, RSA variants)

## Support

For issues with:
- **TPM operations**: Check TPM 2.0 software stack installation
- **Certificate errors**: Generate matching certificate for TPM key
- **Network issues**: Test connectivity and server configuration
- **Permission errors**: Check TPM device access permissions