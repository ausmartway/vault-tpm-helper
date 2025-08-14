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

	keyfile "github.com/foxboron/go-tpm-keyfiles"
	"github.com/google/go-tpm/tpm2/transport"
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

	flag.StringVar(&config.TPMPath, "tpm-path", "/dev/tpmrm0", "Path to TPM device")
	flag.StringVar(&config.CertPath, "client-cert", "client.cert.pem", "Path to client certificate")
	flag.StringVar(&config.KeyPath, "client-key", "client.key.pem", "Path to client private key")
	flag.StringVar(&config.ServerURL, "vaultaddr", "", "Vault server URL (optional if VAULT_ADDR env var is set)")
	flag.StringVar(&config.CAPath, "ca", "", "Path to CA certificate bundle (optional)")
	flag.StringVar(&config.AuthPath, "authpath", "cert", "Vault authentication path")
	flag.StringVar(&config.Name, "name", "", "Name parameter for authentication (optional)")
	flag.BoolVar(&config.Debug, "debug", false, "Enable debug output")
	flag.Parse()

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

	// Create TPM signer using TSS2 key
	tmpSigner, err := createTPMSigner(config.TPMPath, config.KeyPath, config.Debug)
	if err != nil {
		return fmt.Errorf("failed to create TPM signer: %w", err)
	}

	// Create TLS certificate
	tlsCert := tls.Certificate{
		Certificate: [][]byte{cert.Raw},
		PrivateKey:  tmpSigner,
	}

	// Configure TLS
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
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
	}

	// Create HTTP client
	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}

	// Build the authentication URL path using the authpath parameter
	authURL := fmt.Sprintf("%s/v1/auth/%s/login", config.ServerURL, config.AuthPath)

	// Create the request body
	jsonBody := []byte(fmt.Sprintf(`{"name": "%s"}`, config.Name))

	// Make request
	resp, err := httpClient.Post(authURL, "application/json", bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	// Parse JSON response
	var authResp AuthResponse
	if err := json.Unmarshal(body, &authResp); err != nil {
		return fmt.Errorf("failed to parse JSON response: %w", err)
	}

	// Output client token
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
