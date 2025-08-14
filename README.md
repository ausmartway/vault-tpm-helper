# Vault TPM Helper

A Go application that performs Vault certificate authentication using TPM-protected private keys.

## Overview

This program uses a Trusted Platform Module (TPM) 2.0 to securely store and use private keys for client certificate authentication when connecting to HTTPS servers. The private key never leaves the TPM hardware, providing enhanced security.

**Note**: The implementation properly loads the existing TSS2-format key from `client.key.pem` and uses it with the corresponding certificate for TPM-backed authentication.

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
- `client.cert.pem` - Client certificate in PEM format
- `client.key.pem` - Client private key in TSS2 format

## Usage

### Basic Usage

```bash
./vault-tpm-helper
```

This uses default settings:
- Certificate: `client.cert.pem`
- Private key: `client.key.pem`
- Vault URL: from VAULT_ADDR environment variable or `https://nginx:443`
- TPM device: `/dev/tpmrm0`

### Command Line Options

```bash
./vault-tpm-helper [options]
```

#### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-client-key` | `client.key.pem` | Path to client private key |
|------|---------|-------------|
| `-client-cert` | `client.cert.pem` | Path to client certificate file |
| `-vaultaddr` | VAULT_ADDR env var | Vault server URL (optional if VAULT_ADDR is set) |
| `-tmp-path` | `/dev/tmperm0` | Path to TPM device (optional) |
| `-ca` | _(none)_ | Path to CA certificate bundle (optional) |
| `-authpath` | `cert` | Vault authentication path |
| `-name` | `""` | Name parameter for authentication (optional) |
| `-debug` | `false` | Enable debug output (optional) |

#### Example with Custom Settings

```bash
./vault-tpm-helper \
  -cert /path/to/my-cert.pem \
  -vaultaddr https://api.example.com:8443 \
  -ca /etc/ssl/certs/ca-bundle.pem
```

### Request Format

The program automatically constructs the authentication request with:
- URL path: `/v1/auth/{authpath}/login`
- Content-Type: `application/json`
- Body: `{"name": "{name}"}`

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

The program performs TPM-backed client certificate authentication directly. The output shows the extracted client token from the Vault authentication response.

## Current Limitations

- **TSS2 Key Loading**: The program now properly loads the existing TSS2-format key from `client.key.pem` and matches it with the corresponding certificate.
- **Certificate Match**: The program uses the existing TPM-protected key that matches the provided certificate.

## Working Implementation

The program uses the existing TPM-protected key and certificate for authentication:

1. Loads the TSS2 format private key from TPM
2. Uses the matching client certificate
3. Performs mutual TLS authentication with Vault
4. Extracts and displays the client token

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