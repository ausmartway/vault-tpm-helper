package main

import (
	"bytes"
	"crypto"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	keyfile "github.com/foxboron/go-tpm-keyfiles"
	"github.com/google/go-tpm/tpm2/transport"
)

// Version information set during build
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
	builtBy = "unknown"
)

type Config struct {
	TPMPath   string
	CertPath  string
	KeyPath   string
	ServerURL string
	CAPath    string
	AuthPath  string
	Name      string
	Debug     bool
}

type AuthResponse struct {
	Auth struct {
		ClientToken string `json:"client_token"`
	} `json:"auth"`
}

func main() {
	config := &Config{}
	var showVersion bool

	flag.StringVar(&config.TPMPath, "tmp-path", "/dev/tpmrm0", "Path to TPM device")
	flag.StringVar(&config.CertPath, "client-cert", "client.cert.pem", "Path to client certificate")
	flag.StringVar(&config.KeyPath, "client-key", "client.key.pem", "Path to client private key")
	flag.StringVar(&config.ServerURL, "vaultaddr", "", "Vault server URL (optional if VAULT_ADDR env var is set)")
	flag.StringVar(&config.CAPath, "ca", "", "Path to CA certificate bundle (optional)")
	flag.StringVar(&config.AuthPath, "authpath", "cert", "Vault authentication path")
	flag.StringVar(&config.Name, "name", "", "Name parameter for authentication (optional)")
	flag.BoolVar(&config.Debug, "debug", false, "Enable debug output")
	flag.BoolVar(&showVersion, "version", false, "Show version information")
	flag.Parse()

	if showVersion {
		fmt.Printf("vault-tpm-helper %s\n", version)
		fmt.Printf("  commit: %s\n", commit)
		fmt.Printf("  built: %s\n", date)
		fmt.Printf("  built by: %s\n", builtBy)
		return
	}

	// Determine vault URL: VAULT_ADDR env var takes precedence, then vaultaddr flag
	vaultURL := os.Getenv("VAULT_ADDR")
	if vaultURL == "" {
		vaultURL = config.ServerURL
	}
	if vaultURL == "" {
		log.Fatalf("Error: Vault URL must be provided via VAULT_ADDR environment variable or -vaultaddr flag")
	}
	config.ServerURL = vaultURL

	if err := run(config); err != nil {
		log.Fatalf("Error: %v", err)
	}
}

func run(config *Config) error {

	// Load certificate
	cert, err := loadCertificate(config.CertPath)
	if err != nil {
		return fmt.Errorf("failed to load certificate: %w", err)
	}

	// Create signer (either TPM or normal private key)
	signer, err := createSigner(config.TPMPath, config.KeyPath, config.Debug)
	if err != nil {
		return fmt.Errorf("failed to create signer: %w", err)
	}

	// Create TLS certificate
	tlsCert := tls.Certificate{
		Certificate: [][]byte{cert.Raw},
		PrivateKey:  signer,
	}

	// Configure TLS
	tlsConfig := &tls.Config{
		Certificates:       []tls.Certificate{tlsCert},
		InsecureSkipVerify: false, // For testing - should be removed in production
	}

	if config.Debug {
		fmt.Printf("Debug: TLS certificate configured\n")
		fmt.Printf("Debug: Certificate subject: %s\n", cert.Subject.String())
		fmt.Printf("Debug: Certificate issuer: %s\n", cert.Issuer.String())
	}

	// Load CA certificates if provided
	if config.CAPath != "" {
		caCert, err := os.ReadFile(config.CAPath)
		if err != nil {
			return fmt.Errorf("failed to read CA certificate: %w", err)
		}
		caCertPool := x509.NewCertPool()
		caCertPool.AppendCertsFromPEM(caCert)
		tlsConfig.RootCAs = caCertPool
		tlsConfig.InsecureSkipVerify = false // Use proper verification when CA is provided

		if config.Debug {
			fmt.Printf("Debug: CA certificate loaded from %s\n", config.CAPath)
		}
	}

	// Create HTTP client
	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}

	// Build the authentication URL path using the authpath parameter
	authURL := fmt.Sprintf("%s/v1/auth/%s/login", config.ServerURL, config.AuthPath)

	if config.Debug {
		fmt.Printf("Debug: Authentication URL: %s\n", authURL)
	}

	// Create the request body
	jsonBody := []byte(fmt.Sprintf(`{"name": "%s"}`, config.Name))

	if config.Debug {
		fmt.Printf("Debug: Request body: %s\n", string(jsonBody))
	}

	// Make request
	if config.Debug {
		fmt.Printf("Debug: Making POST request to Vault...\n")
	}
	resp, err := httpClient.Post(authURL, "application/json", bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if config.Debug {
		fmt.Printf("Debug: Received response with status: %s\n", resp.Status)
		fmt.Printf("Debug: Response status code: %d\n", resp.StatusCode)
	}

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	if config.Debug {
		fmt.Printf("Debug: Response body: %s\n", string(body))
	}

	// Check if the response was successful
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("vault authentication failed with status %d: %s", resp.StatusCode, string(body))
	}

	// Parse JSON response
	var authResp AuthResponse
	if err := json.Unmarshal(body, &authResp); err != nil {
		return fmt.Errorf("failed to parse JSON response: %w", err)
	}

	if config.Debug {
		fmt.Printf("Debug: Parsed auth response successfully\n")
		fmt.Printf("Debug: Client token length: %d\n", len(authResp.Auth.ClientToken))
	}

	// Output client token
	if authResp.Auth.ClientToken == "" {
		return fmt.Errorf("received empty client token from Vault")
	}

	fmt.Println(authResp.Auth.ClientToken)

	return nil
}

func loadCertificate(certPath string) (*x509.Certificate, error) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate file: %w", err)
	}

	block, _ := pem.Decode(certPEM)
	if block == nil {
		return nil, fmt.Errorf("failed to parse certificate PEM")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse certificate: %w", err)
	}

	return cert, nil
}

func isTSS2Key(keyPath string) (bool, error) {
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return false, fmt.Errorf("failed to read key file: %w", err)
	}

	// Check for TSS2 PRIVATE KEY block type
	block, _ := pem.Decode(keyPEM)
	if block == nil {
		return false, fmt.Errorf("failed to parse key PEM")
	}

	// TSS2 keys typically use "TSS2 PRIVATE KEY" block type
	if block.Type == "TSS2 PRIVATE KEY" {
		return true, nil
	}

	// Also check if the content looks like TSS2 format by trying to decode it
	// This works for both RSA and ECC TSS2 keys
	if strings.Contains(block.Type, "PRIVATE KEY") {
		_, err := keyfile.Decode(keyPEM)
		if err == nil {
			return true, nil
		}
	}

	return false, nil
}

func createSigner(tpmPath, keyPath string, debug bool) (crypto.Signer, error) {
	isTSS2, err := isTSS2Key(keyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to determine key format: %w", err)
	}

	if isTSS2 {
		if debug {
			fmt.Printf("Debug: Detected TSS2 key format, using TPM signer\n")
		}
		return createTPMSigner(tpmPath, keyPath, debug)
	} else {
		if debug {
			fmt.Printf("Debug: Detected standard private key format, using normal signer\n")
		}
		return createNormalSigner(keyPath, debug)
	}
}

func createNormalSigner(keyPath string, debug bool) (crypto.Signer, error) {
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read key file: %w", err)
	}

	block, _ := pem.Decode(keyPEM)
	if block == nil {
		return nil, fmt.Errorf("failed to parse key PEM")
	}

	var signer crypto.Signer
	switch block.Type {
	case "RSA PRIVATE KEY":
		key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("failed to parse RSA private key: %w", err)
		}
		signer = key
	case "PRIVATE KEY":
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("failed to parse PKCS8 private key: %w", err)
		}
		var ok bool
		signer, ok = key.(crypto.Signer)
		if !ok {
			return nil, fmt.Errorf("key does not implement crypto.Signer")
		}
	case "EC PRIVATE KEY":
		key, err := x509.ParseECPrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("failed to parse EC private key: %w", err)
		}
		signer = key
	default:
		return nil, fmt.Errorf("unsupported private key type: %s", block.Type)
	}

	if debug {
		fmt.Printf("Debug: Successfully loaded normal private key from %s\n", keyPath)
	}

	return signer, nil
}

func createTPMSigner(tpmPath, keyPath string, debug bool) (crypto.Signer, error) {
	// 1. Read TSS2 key PEM file
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read key file: %w", err)
	}

	// 2. Parse TSS2 key using go-tpm-keyfiles (pass entire PEM content)
	tmpKey, err := keyfile.Decode(keyPEM)
	if err != nil {
		return nil, fmt.Errorf("failed to decode TSS2 key: %w", err)
	}

	// 3. Open TPM transport (keep connection open for signer)
	rwc, err := transport.OpenTPM(tpmPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open TPM: %w", err)
	}
	// Note: NOT closing rwc here - the signer needs it to remain open

	// 4. Create a crypto.Signer directly from the TPM key
	signer, err := tmpKey.Signer(rwc, []byte{}, []byte{}) // empty owner auth and auth
	if err != nil {
		rwc.Close() // Close on error
		return nil, fmt.Errorf("failed to create signer: %w", err)
	}

	if debug {
		fmt.Printf("Debug: Successfully loaded TSS2 key from %s\n", keyPath)
	}
	return signer, nil
}
