#!/bin/bash

# Release script for vault-tpm-helper
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if version argument is provided
if [ $# -eq 0 ]; then
    log_error "Usage: $0 <version>"
    log_info "Example: $0 v1.0.0"
    exit 1
fi

VERSION=$1

# Validate version format
if [[ ! $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format. Use semantic versioning (e.g., v1.0.0)"
    exit 1
fi

log_info "Preparing release $VERSION"

# Check if we're in a git repository
if [ ! -d .git ]; then
    log_error "Not in a git repository"
    exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    log_error "Working directory is not clean. Please commit or stash changes."
    git status --short
    exit 1
fi

# Check if on main/master branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    log_warning "Not on main/master branch. Current branch: $CURRENT_BRANCH"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Release cancelled"
        exit 0
    fi
fi

# Check if tag already exists
if git tag -l | grep -q "^$VERSION$"; then
    log_error "Tag $VERSION already exists"
    exit 1
fi

# Run tests
log_info "Running tests..."
if ! make test; then
    log_error "Tests failed"
    exit 1
fi

# Check GoReleaser configuration
log_info "Checking GoReleaser configuration..."
if ! make release-check; then
    log_error "GoReleaser configuration check failed"
    exit 1
fi

# Create git tag
log_info "Creating git tag $VERSION..."
git tag -a "$VERSION" -m "Release $VERSION"

# Push tag to remote
log_info "Pushing tag to remote..."
git push origin "$VERSION"

# Create release
log_info "Creating release with GoReleaser..."
if make release; then
    log_success "Release $VERSION created successfully!"
    log_info "Check the release at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^/]*\/[^/]*\).*/\1/' | sed 's/\.git$//')/releases/tag/$VERSION"
else
    log_error "Release creation failed"
    log_warning "You may need to delete the tag: git tag -d $VERSION && git push origin :refs/tags/$VERSION"
    exit 1
fi