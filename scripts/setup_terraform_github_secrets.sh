#!/bin/bash

# Terraform-specific script to update GitHub secrets from Terraform outputs
# This script reads Terraform outputs and pushes infrastructure secrets to GitHub
# Usage: ./setup_terraform_github_secrets.sh [environment] [--from-terraform]
# Environment: development, staging, production, or all (default: all)
# --from-terraform: Flag indicating this is being called from terraform apply

REPO="saadkhalmadani/nifi-cicd"
ENVIRONMENT=${1:-all}
FROM_TERRAFORM=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_DIR/azure-vm-terraform"

# Check for --from-terraform flag
if [[ "$2" == "--from-terraform" ]] || [[ "$1" == "--from-terraform" ]]; then
    FROM_TERRAFORM=true
    if [[ "$1" == "--from-terraform" ]]; then
        ENVIRONMENT="all"
    fi
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}▶${NC} $1"
}

# Function to ensure GitHub environments exist
ensure_github_environments() {
    local environments=("development" "staging" "production")
    
    print_info "Checking GitHub environments..."
    
    for env in "${environments[@]}"; do
        # Check if environment exists using gh api
        if gh api "repos/$REPO/environments/$env" >/dev/null 2>&1; then
            print_status "Environment '$env' exists"
        else
            print_warning "Environment '$env' does not exist, creating..."
            # Create the environment
            if gh api --method PUT "repos/$REPO/environments/$env" >/dev/null 2>&1; then
                print_status "Created environment '$env'"
            else
                print_error "Failed to create environment '$env'"
                print_info "You may need to create it manually at:"
                echo "  https://github.com/$REPO/settings/environments/new"
            fi
        fi
    done
    echo ""
}

# Function to update .env file with actual VM IP
update_env_file() {
    local env=$1
    local public_ip=$2
    
    if [ -z "$public_ip" ]; then
        print_warning "No public IP to update .env file for $env"
        return
    fi
    
    local env_file=""
    case "$env" in
        development)
            env_file="$PROJECT_DIR/.env.development"
            ;;
        staging)
            env_file="$PROJECT_DIR/.env.staging"
            ;;
        production)
            env_file="$PROJECT_DIR/.env.production"
            ;;
        *)
            return
            ;;
    esac
    
    if [ ! -f "$env_file" ]; then
        print_warning ".env file not found: $env_file"
        return
    fi
    
    print_step "Updating $env_file with IP: $public_ip"
    
    # Update PUBLIC_IP (cross-platform sed)
    if grep -q "^PUBLIC_IP=" "$env_file"; then
        sed -i.bak "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null || \
        sed -i '' "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null
        print_status "Updated PUBLIC_IP"
    fi
    
    # Update VM_PUBLIC_IP
    if grep -q "^VM_PUBLIC_IP=" "$env_file"; then
        sed -i.bak "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null || \
        sed -i '' "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null
        print_status "Updated VM_PUBLIC_IP"
    fi
    
    # Update NIFI_WEB_PROXY_HOST
    if grep -q "^NIFI_WEB_PROXY_HOST=" "$env_file"; then
        sed -i.bak "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$env_file" 2>/dev/null || \
        sed -i '' "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$env_file" 2>/dev/null
        print_status "Updated NIFI_WEB_PROXY_HOST"
    fi
    
    # Remove backup file
    rm -f "${env_file}.bak"
}

# Function to update secrets from Terraform outputs for a specific environment
update_secrets_from_terraform() {
    local env=$1
    
    # Map environment names
    local env_name=""
    case "$env" in
        development|dev)
            env_name="development"
            ;;
        staging)
            env_name="staging"
            ;;
        production|prod)
            env_name="production"
            ;;
        *)
            print_error "Invalid environment: $env"
            return 1
            ;;
    esac
    
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo " 🔧 Terraform Outputs → GitHub Secrets"
    echo "         Environment: $env_name"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    # Check if Terraform directory exists
    if [ ! -d "$TF_DIR" ]; then
        print_error "Terraform directory not found: $TF_DIR"
        return 1
    fi
    
    cd "$TF_DIR"
    
    # Initialize Terraform with the appropriate backend config
    print_info "Initializing Terraform for $env_name..."
    if ! terraform init -reconfigure -backend-config="backend-configs/${env_name}.tfbackend" > /dev/null 2>&1; then
        print_error "Failed to initialize Terraform for $env_name"
        print_info "Backend config: backend-configs/${env_name}.tfbackend"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Check if Terraform state exists
    if ! terraform state list > /dev/null 2>&1; then
        print_warning "No Terraform state found for $env_name"
        print_info "Deploy infrastructure first: make tf-apply ENV=$env_name"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it to parse Terraform outputs."
        print_info "Install: sudo apt-get install jq  # or  brew install jq"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    print_info "Extracting Terraform outputs for $env_name..."
    
    # Get outputs in JSON format
    OUTPUTS=$(terraform output -json 2>/dev/null)
    
    if [ -z "$OUTPUTS" ] || [ "$OUTPUTS" = "{}" ]; then
        print_warning "No Terraform outputs found for $env_name"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Extract individual values
    local vm_public_ip=$(echo "$OUTPUTS" | jq -r '.vm_public_ip.value // empty')
    local public_ip=$(echo "$OUTPUTS" | jq -r '.public_ip.value // empty')
    local nifi_https_url=$(echo "$OUTPUTS" | jq -r '.nifi_https_url.value // empty')
    local nifi_registry_url=$(echo "$OUTPUTS" | jq -r '.nifi_registry_url.value // empty')
    
    # Construct additional URLs
    local nifi_http_url=""
    if [ -n "$public_ip" ]; then
        nifi_http_url="http://${public_ip}:8080/nifi"
    fi
    
    # Update .env file with actual IP
    echo ""
    print_info "Updating .env file for $env_name..."
    update_env_file "$env_name" "$public_ip"
    
    local success_count=0
    local fail_count=0
    
    echo ""
    print_info "Setting GitHub environment secrets for: $env_name"
    echo ""
    
    # Function to set environment secret
    set_env_secret() {
        local secret_name=$1
        local secret_value=$2
        
        if [ -z "$secret_value" ]; then
            print_warning "Skipping empty value for $secret_name"
            return
        fi
        
        local error_output=$(echo "$secret_value" | gh secret set "$secret_name" --env "$env_name" --repo "$REPO" 2>&1)
        if [ $? -eq 0 ]; then
            if [ ${#secret_value} -gt 40 ]; then
                print_status "$secret_name = ${secret_value:0:30}..."
            else
                print_status "$secret_name = $secret_value"
            fi
            ((success_count++))
        else
            print_error "Failed to set $secret_name"
            if [[ "$error_output" == *"could not create or update secret"* ]] || [[ "$error_output" == *"environment not found"* ]]; then
                print_warning "Environment '$env_name' may not exist. Create it at:"
                echo "  https://github.com/$REPO/settings/environments/new"
            fi
            echo "  Error: $error_output" | head -1
            ((fail_count++))
        fi
    }
    
    # Set infrastructure secrets as environment secrets
    print_info "Setting infrastructure secrets..."
    set_env_secret "VM_PUBLIC_IP" "$vm_public_ip"
    set_env_secret "PUBLIC_IP" "$public_ip"
    set_env_secret "NIFI_HTTP_URL" "$nifi_http_url"
    set_env_secret "NIFI_HTTPS_URL" "$nifi_https_url"
    set_env_secret "NIFI_REGISTRY_URL" "$nifi_registry_url"
    
    echo ""
    echo "───────────────────────────────────────────────────────────────────────────"
    echo " Results for $env_name: ${GREEN}$success_count updated${NC}, ${RED}$fail_count failed${NC}"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    cd "$PROJECT_DIR"
}

# Function to remove redundant repository-level secrets
remove_redundant_repo_secrets() {
    echo ""
    echo "─────────────────────────────────────────────────"
    echo " 🧹 Cleaning Up Redundant Repository Secrets "
    echo "─────────────────────────────────────────────────"
    echo ""
    
    # List of secrets that should be removed from repository level
    # (they are now environment-specific)
    local redundant_secrets=(
        "VM_USERNAME"
        "SSH_PRIVATE_KEY"
        "VM_PUBLIC_IP"
        "PUBLIC_IP"
        "SSH_CMD"
        "NIFI_HTTP_URL"
        "NIFI_HTTPS_URL"
        "NIFI_REGISTRY_URL"
    )
    
    print_info "Checking for redundant repository-level secrets..."
    echo ""
    
    local removed_count=0
    local not_found_count=0
    
    for secret in "${redundant_secrets[@]}"; do
        # Check if secret exists at repository level
        if gh secret list --repo "$REPO" | grep -q "^${secret}"; then
            print_step "Removing repository secret: $secret"
            if gh secret delete "$secret" --repo "$REPO" 2>/dev/null; then
                print_status "Removed $secret from repository"
                ((removed_count++))
            else
                print_warning "Failed to remove $secret (may not exist or no permission)"
            fi
        else
            print_info "Secret $secret not found at repository level (already clean)"
            ((not_found_count++))
        fi
    done
    
    echo ""
    echo "───────────────────────────────────────────────────────────────────────────"
    echo " Cleanup: ${GREEN}$removed_count removed${NC}, ${BLUE}$not_found_count already clean${NC}"
    echo "───────────────────────────────────────────────────────────────────────────"
    echo ""
    
    if [ $removed_count -gt 0 ]; then
        print_info "✅ Repository secrets cleaned up successfully!"
        print_info "These secrets are now managed at the environment level"
    fi
}

# Main function
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "🔧 Terraform Outputs → GitHub Environment Secrets "
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        print_error "GitHub CLI is not authenticated"
        echo ""
        echo "Please run: ${BLUE}gh auth login${NC}"
        echo ""
        exit 1
    fi
    
    print_status "GitHub CLI authenticated"
    
    # Get current repository
    local current_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
    if [ -z "$current_repo" ]; then
        print_error "Could not determine current repository"
        exit 1
    fi
    
    REPO="$current_repo"
    print_info "Repository: $REPO"
    echo ""
    
    # Ensure GitHub environments exist before setting secrets
    ensure_github_environments
    
    # Remove redundant repository-level secrets first (only if not called from terraform)
    if [ "$FROM_TERRAFORM" = false ]; then
        remove_redundant_repo_secrets
    fi
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Update secrets from Terraform outputs
    case "$ENVIRONMENT" in
        development|dev)
            update_secrets_from_terraform "development"
            ;;
        staging)
            update_secrets_from_terraform "staging"
            ;;
        production|prod)
            update_secrets_from_terraform "production"
            ;;
        all)
            update_secrets_from_terraform "development"
            update_secrets_from_terraform "staging"
            update_secrets_from_terraform "production"
            ;;
        *)
            print_error "Invalid environment '$ENVIRONMENT'"
            echo ""
            echo "Usage: $0 [development|staging|production|all] [--from-terraform]"
            echo ""
            echo "Examples:"
            echo "  $0 development     # Update development infrastructure secrets"
            echo "  $0 staging         # Update staging infrastructure secrets"
            echo "  $0 production      # Update production infrastructure secrets"
            echo "  $0 all             # Update all infrastructure secrets"
            echo ""
            exit 1
            ;;
    esac
    
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo " ✅ Terraform Secrets Update Complete! "
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    if [ "$FROM_TERRAFORM" = false ]; then
        print_info "Summary of changes:"
        echo ""
        echo "  📋 Repository-level secrets (kept):"
        echo "     • GH_TOKEN (GitHub API access)"
        echo ""
        echo "  🌍 Environment-level secrets (updated per environment):"
        echo "     • SSH_PRIVATE_KEY"
        echo "     • VM_USERNAME"
        echo "     • VM_PUBLIC_IP"
        echo "     • PUBLIC_IP"
        echo "     • NIFI_HTTP_URL"
        echo "     • NIFI_HTTPS_URL"
        echo "     • NIFI_REGISTRY_URL"
        echo "     • NIFI_* (all NiFi configuration)"
        echo ""
        print_info "Verify secrets at:"
        echo "   Repository: https://github.com/$REPO/settings/secrets/actions"
        echo "   Environments: https://github.com/$REPO/settings/environments"
        echo ""
        print_info ".env files updated with Terraform IPs:"
        echo "   • .env.development"
        echo "   • .env.staging"
        echo "   • .env.production"
        echo ""
        print_info "Next steps:"
        echo "   1. Commit updated .env files: git add .env.* && git commit -m 'Update IPs from Terraform'"
        echo "   2. Re-run setup_nifi_github_secrets.sh to sync .env → GitHub secrets"
        echo "   3. Push to develop/staging/main to trigger deployment"
        echo ""
    fi
}

# Run main function
main "$@"