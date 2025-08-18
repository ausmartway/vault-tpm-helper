.PHONY: build deploy clean test run release release-snapshot install-goreleaser

BINARY_NAME=vault-tpm-helper
TARGET_HOST=tpmtest
TARGET_USER=ubuntu
GOOS=linux
GOARCH=arm64
VERSION ?= $(shell git describe --tags --always --dirty)

build:
	@echo "Building for $(GOOS)/$(GOARCH)..."
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags="-X main.version=$(VERSION)" -o $(BINARY_NAME) .
	@echo "Build complete: $(BINARY_NAME)"

deploy: build
	@echo "Deploying to $(TARGET_USER)@$(TARGET_HOST)..."
	scp $(BINARY_NAME) $(TARGET_USER)@$(TARGET_HOST):~/
	@echo "Deployment complete"

test:
	@echo "Running Go tests..."
	go test -v ./...
	@echo "Running vault-tpm-helper validation..."
	@echo "Usage: ./$(BINARY_NAME) -vaultaddr https://vault-server"

run: deploy
	@echo "Running on remote host..."
	ssh $(TARGET_USER)@$(TARGET_HOST) "./$(BINARY_NAME) --help"

clean:
	@echo "Cleaning build artifacts..."
	rm -f $(BINARY_NAME)
	rm -rf dist/
	@echo "Clean complete"

install-goreleaser:
	@echo "Installing GoReleaser..."
	@if ! command -v goreleaser &> /dev/null; then \
		echo "GoReleaser not found. Installing..."; \
		go install github.com/goreleaser/goreleaser@latest; \
	else \
		echo "GoReleaser already installed"; \
	fi

release-check: install-goreleaser
	@echo "Checking GoReleaser configuration..."
	GITHUB_USER=$${GITHUB_USER:-$(shell whoami)} goreleaser check

release-snapshot: install-goreleaser clean
	@echo "Creating snapshot release..."
	GITHUB_USER=$${GITHUB_USER:-$(shell whoami)} goreleaser build --snapshot --clean
	@echo "Snapshot release created in dist/"

release: install-goreleaser clean
	@echo "Creating release..."
	@if [ -z "$(shell git tag --points-at HEAD)" ]; then \
		echo "Error: No git tag found at HEAD. Please tag your commit first."; \
		echo "Example: git tag v1.0.0 && git push origin v1.0.0"; \
		exit 1; \
	fi
	GITHUB_USER=$${GITHUB_USER:-$(shell whoami)} goreleaser release --clean

release-dry-run: install-goreleaser
	@echo "Dry run release..."
	GITHUB_USER=$${GITHUB_USER:-$(shell whoami)} goreleaser release --snapshot --skip=publish --clean

version:
	@echo "Version: $(VERSION)"

help:
	@echo "Available targets:"
	@echo "  build            - Cross-compile for $(GOOS)/$(GOARCH)"
	@echo "  deploy           - Build and copy binary to $(TARGET_USER)@$(TARGET_HOST)"
	@echo "  test             - Run Go tests and show usage"
	@echo "  run              - Deploy and run help on remote host"
	@echo "  clean            - Remove build artifacts"
	@echo "  install-goreleaser - Install GoReleaser"
	@echo "  release-check    - Check GoReleaser configuration"
	@echo "  release-snapshot - Create snapshot release (no git tag required)"
	@echo "  release-dry-run  - Test release process without publishing"
	@echo "  release          - Create and publish release (requires git tag)"
	@echo "  version          - Show current version"
	@echo "  help             - Show this help message"