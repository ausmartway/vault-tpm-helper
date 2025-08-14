.PHONY: build deploy clean test run

BINARY_NAME=vault-tpm-helper
TARGET_HOST=tpmtest
TARGET_USER=ubuntu
GOOS=linux
GOARCH=arm64

build:
	@echo "Building for $(GOOS)/$(GOARCH)..."
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -o $(BINARY_NAME) .
	@echo "Build complete: $(BINARY_NAME)"

deploy: build
	@echo "Deploying to $(TARGET_USER)@$(TARGET_HOST)..."
	scp $(BINARY_NAME) $(TARGET_USER)@$(TARGET_HOST):~/
	@echo "Deployment complete"

test:
	@echo "Running validation test with OpenSSL TPM2 provider..."
	@echo "Reference command:"
	@echo "cat nginx.txt|openssl s_client -provider tpm2 -provider default -propquery '?provider=tpm2' -connect nginx:443 -cert tpmtest.cert.pem -key tpmtest.key.pem -quiet| awk '/^HTTP/ {p=1} p {print}' | awk 'BEGIN {RS=\"\\r\\n\\r\\n\"} NR==2 {print}' | jq .auth.client_token"

run: deploy
	@echo "Running on remote host..."
	ssh $(TARGET_USER)@$(TARGET_HOST) "./$(BINARY_NAME) --help"

clean:
	@echo "Cleaning build artifacts..."
	rm -f $(BINARY_NAME)
	@echo "Clean complete"

help:
	@echo "Available targets:"
	@echo "  build   - Cross-compile for $(GOOS)/$(GOARCH)"
	@echo "  deploy  - Build and copy binary to $(TARGET_USER)@$(TARGET_HOST)"
	@echo "  test    - Show OpenSSL validation command"
	@echo "  run     - Deploy and run help on remote host"
	@echo "  clean   - Remove build artifacts"
	@echo "  help    - Show this help message"