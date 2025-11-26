#!/bin/bash

# Script to remove all GitHub environment secrets
# Usage: ./remove_github_secrets.sh [environment]
# Environment: development, staging, production, or all (default: all)

REPO="saadkhalmadani/nifi-cicd"
ENVIRONMENT=${1:-all}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
    exit 1
fi

# Get current repository
CURRENT_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
if [ -n "$CURRENT_REPO" ]; then
    REPO="$CURRENT_REPO"
fi

# Function to remove all secrets from an environment
remove_secrets_from_env() {
    local env=$1
    
    echo ""
    print_info "Removing secrets from $env environment..."
    
    # Get list of all secrets for this environment
    local secrets=$(gh secret list --env "$env" --repo "$REPO" 2>/dev/null | awk '{print $1}')
    
    if [ -z "$secrets" ]; then
        print_warning "No secrets found in $env environment"
        return 0
    fi
    
    local count=0
    for secret in $secrets; do
        if gh secret delete "$secret" --env "$env" --repo "$REPO" 2>/dev/null; then
            print_status "Deleted secret: $secret"
            ((count++))
        else
            print_error "Failed to delete secret: $secret"
        fi
    done
    
    print_status "Removed $count secrets from $env environment"
}

# Main execution
echo "═══════════════════════════════════════════"
echo "  GitHub Environment Secrets Removal Tool  "
echo "═══════════════════════════════════════════"
echo ""
print_info "Repository: $REPO"
print_info "Target: $ENVIRONMENT"
echo ""

# Confirm before deletion
read -p "Are you sure you want to remove ALL secrets from $ENVIRONMENT? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_warning "Operation cancelled by user"
    exit 0
fi

if [ "$ENVIRONMENT" == "all" ]; then
    remove_secrets_from_env "development"
    remove_secrets_from_env "staging"
    remove_secrets_from_env "production"
else
    remove_secrets_from_env "$ENVIRONMENT"
fi

echo ""
echo "══════════════════════════════"
echo " ✅ Secrets Removal Complete  "
echo "══════════════════════════════"