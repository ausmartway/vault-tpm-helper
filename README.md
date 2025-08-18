# Vault TPM Helper

A Go application that performs Vault certificate authentication using TPM-protected private keys.

## Overview

This program uses a Trusted Platform Module (TPM) 2.0 to securely store and use private keys for client certificate authentication with Vault. The private key never leaves the TPM hardware, providing enhanced security.

## Prerequisites

- Ubuntu ARM64 system with TPM 2.0 chip
- TPM 2.0 software stack installed

### Installation

```bash
sudo apt update
sudo apt install -y tpm2-tools tpm2-openssl openssl
```

### OpenSSL Configuration

Create or update `/etc/ssl/openssl.cnf` to include the TPM2 provider:

```ini
# Add this section to /etc/ssl/openssl.cnf

[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
tpm2 = tpm2_sect

[default_sect]
activate = 1

[tpm2_sect]
module = /usr/lib/aarch64-linux-gnu/ossl-modules/tpm2.so
```

Alternatively, create a local OpenSSL config file for TPM operations:

```bash
# Create tpm2-openssl.cnf
cat > tpm2-openssl.cnf << 'EOF'
openssl_conf = openssl_init

[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
tpm2 = tpm2_sect

[default_sect]
activate = 1

[tpm2_sect]
activate = 1
module = /usr/lib/aarch64-linux-gnu/ossl-modules/tpm2.so
EOF

# Use with OpenSSL commands
export OPENSSL_CONF=./tpm2-openssl.cnf
```

Verify TPM2 provider is available:

```bash
openssl list -providers | grep -i tpm
```

You should see output like:
```
  tpm2
    name: TPM 2.0 Provider
    version: 1.1.0
    status: active
```

## Quick Start

**Note**: Make sure OpenSSL is configured with the TPM2 provider (see OpenSSL Configuration section above).

### 1. Generate TPM-Backed Key

```bash
# Generate ECC private key in TPM
openssl genpkey \
    -provider tpm2 \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:prime256v1 \
    -out client.key.pem

# Or generate RSA key
openssl genpkey \
    -provider tpm2 \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:2048 \
    -out client.key.pem
```

### 2. Create Certificate Signing Request

```bash
openssl req \
    -provider default \
    -provider tpm2 \
    -new \
    -key client.key.pem \
    -out client.csr.pem \
    -subj '/CN=hostname.example.com'
```

### 3. Get Certificate from CA

**Important**: Use a proper Certificate Authority. Never use self-signed certificates in production.

With Vault PKI:

```bash
vault write -format=json pki/sign/client-cert \
    csr=@client.csr.pem \
    ttl=90d | \
    jq -r '.data.certificate' > client.cert.pem
```

### 4. Run Authentication

```bash
./vault-tpm-helper
```

## Usage

### Basic Usage

```bash
./vault-tpm-helper
```

Uses default files:
- Certificate: `client.cert.pem`
- Private key: `client.key.pem`
- Vault URL: from `VAULT_ADDR` environment variable

### Command Line Options

| Flag | Default | Description |
|------|---------|-------------|
| `-client-cert` | `client.cert.pem` | Client certificate file |
| `-client-key` | `client.key.pem` | Client private key file |
| `-vaultaddr` | `$VAULT_ADDR` | Vault server URL |
| `-tpm-path` | `/dev/tpmrm0` | TPM device path |
| `-debug` | `false` | Enable debug output |

### Example

```bash
./vault-tpm-helper \
    -client-cert my-cert.pem \
    -client-key my-key.pem \
    -vaultaddr https://vault.example.com \
    -debug
```

## How It Works

1. Loads TPM-backed private key from file
2. Loads client certificate from file
3. Performs mutual TLS authentication with Vault
4. Outputs the Vault authentication token

## Output

The program outputs the Vault client token:

```bash
$ ./vault-tpm-helper
hvs.CAESII8ZnxgCr-XpHnPD1ESvlizTZjMVZjrnboV9zP9htRmMGiMKHGh2cy5qN2hhY0wyR0tWME9ITUpjcjlVQXQ5M2IQl6mfBg
```

## Troubleshooting

### TPM Permission Errors

```bash
# Add user to tss group
sudo usermod -a -G tss $USER

# Check TPM device permissions
ls -la /dev/tpm*
```

### TPM Provider Not Found

```bash
# Install tpm2-openssl package
sudo apt install tpm2-openssl

# Check if OpenSSL config includes TPM2 provider
openssl list -providers

# If TPM2 provider not found, check OpenSSL configuration
# Make sure /etc/ssl/openssl.cnf includes the TPM2 provider section
# Or use local config file:
export OPENSSL_CONF=./tpm2-openssl.cnf
openssl list -providers
```

### Key Verification

```bash
# Check if key is TSS2 format (TPM-backed)
head -1 client.key.pem
# Should show: -----BEGIN TSS2 PRIVATE KEY-----
```

## Security Notes

- Private keys are protected by TPM hardware and never exposed in memory
- Keys are loaded transiently (not stored persistently in TPM NVRAM)
- Always use proper Certificate Authorities for signing certificates
- TPM provides hardware-based cryptographic operations

## Building

```bash
make build
make deploy
```

## Dependencies

- `github.com/foxboron/go-tpm-keyfiles` - TSS2 key file handling
- `github.com/google/go-tpm` - TPM communication
- Standard Go crypto libraries
