#!/bin/bash

# publish.sh - Automated publishing script with version tagging
# Usage: ./publish.sh [commit_message]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository!"
    exit 1
fi

# Get the commit message from argument or prompt user
if [ -n "$1" ]; then
    COMMIT_MESSAGE="$1"
else
    echo -n "Enter commit message: "
    read COMMIT_MESSAGE
    if [ -z "$COMMIT_MESSAGE" ]; then
        print_error "Commit message cannot be empty!"
        exit 1
    fi
fi

print_status "Starting publish process..."

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
    print_warning "No changes to commit!"
    echo -n "Continue with tagging only? (y/n): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    SKIP_COMMIT=true
else
    SKIP_COMMIT=false
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
print_status "Current branch: $CURRENT_BRANCH"

# Get the latest tag to determine next version
LATEST_TAG=$(git tag -l "v*" | sort -V | tail -n 1)

if [ -z "$LATEST_TAG" ]; then
    # No existing tags, start with v1.0.0
    NEW_VERSION="v1.0.0"
    print_status "No existing tags found. Starting with $NEW_VERSION"
else
    print_status "Latest tag: $LATEST_TAG"

    # Extract version numbers (assuming format vX.Y.Z)
    if [[ $LATEST_TAG =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        PATCH=${BASH_REMATCH[3]}

        # Increment patch version
        NEW_PATCH=$((PATCH + 1))
        NEW_VERSION="v${MAJOR}.${MINOR}.${NEW_PATCH}"
    else
        print_error "Could not parse version from tag: $LATEST_TAG"
        exit 1
    fi
fi

print_status "New version will be: $NEW_VERSION"

# Confirm before proceeding
echo -n "Proceed with publish? This will:"
echo ""
if [ "$SKIP_COMMIT" = false ]; then
    echo "  1. Add all changes to git"
    echo "  2. Commit with message: '$COMMIT_MESSAGE'"
fi
echo "  3. Create tag: $NEW_VERSION"
echo "  4. Push to origin with new tag"
echo -n "Continue? (y/n): "
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_error "Aborted by user"
    exit 1
fi

# Add and commit changes (if there are any)
if [ "$SKIP_COMMIT" = false ]; then
    print_status "Adding all changes..."
    git add .

    print_status "Committing changes..."
    git commit -m "$COMMIT_MESSAGE

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    print_success "Changes committed successfully"
fi

# Create the new tag
print_status "Creating tag: $NEW_VERSION"
git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION

$COMMIT_MESSAGE

🤖 Generated with [Claude Code](https://claude.ai/code)"
print_success "Tag created: $NEW_VERSION"

# Push to origin with the new tag only
print_status "Pushing to origin..."
git push origin "$CURRENT_BRANCH"
print_status "Pushing tag $NEW_VERSION..."
git push origin "$NEW_VERSION"

print_success "🎉 Successfully published $NEW_VERSION!"
print_status "Summary:"
echo "  - Branch: $CURRENT_BRANCH"
echo "  - Version: $NEW_VERSION"
if [ "$SKIP_COMMIT" = false ]; then
    echo "  - Commit: $COMMIT_MESSAGE"
fi
echo "  - Pushed to origin with tag $NEW_VERSION"

# Show the latest commits and tags
print_status "Recent commits:"
git log --oneline -5

print_status "Recent tags:"
git tag -l "v*" | sort -V | tail -5