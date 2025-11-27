#!/bin/bash

# Complete secrets synchronization script
# Syncs BOTH .env configs AND Terraform outputs to GitHub secrets
# Usage: ./sync_all_secrets.sh [environment]
# Environment: development, staging, production, or all (default: all)

REPO="saadkhalmadani/nifi-cicd"
ENVIRONMENT=${1:-all}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_DIR/azure-vm-terraform"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠ ${NC} $1"; }
print_step() { echo -e "${MAGENTA}▶${NC} $1"; }
print_success() { echo -e "${CYAN}★${NC} $1"; }

# Function to sync all secrets for an environment
sync_environment_secrets() {
    local env=$1
    
    # Map environment names
    local env_name=""
    local env_file=""
    case "$env" in
        development|dev)
            env_name="development"
            env_file=".env.development"
            ;;
        staging)
            env_name="staging"
            env_file=".env.staging"
            ;;
        production|prod)
            env_name="production"
            env_file=".env.production"
            ;;
        *)
            print_error "Invalid environment: $env"
            return 1
            ;;
    esac
    
    echo ""
    echo "╔═════════════════════════════════════════════════════╗"
    echo "║  📦 Complete Secrets Sync: $env_name"
    echo "╚═════════════════════════════════════════════════════╝"
    echo ""
    
    # Check if .env file exists
    if [ ! -f "$PROJECT_DIR/$env_file" ]; then
        print_error "File $env_file not found!"
        print_info "Run 'make setup-passwords' first"
        return 1
    fi
    
    # Validate .env file
    if grep -q "NIFI_PASSWORD=$" "$PROJECT_DIR/$env_file" 2>/dev/null; then
        print_error "Empty NIFI_PASSWORD in $env_file"
        print_info "Run 'make setup-passwords' to generate secure passwords"
        return 1
    fi
    
    # Source the environment file
    print_step "Loading configuration from $env_file..."
    set -a
    source "$PROJECT_DIR/$env_file"
    set +a
    
    local success_count=0
    local fail_count=0
    
    # Function to set environment secret
    set_env_secret() {
        local secret_name=$1
        local secret_value=$2
        local display_value="${secret_value:0:25}"
        
        if [ -z "$secret_value" ]; then
            print_warning "Skipping $secret_name (empty value)"
            return
        fi
        
        local error_output=$(echo "$secret_value" | gh secret set "$secret_name" --env "$env_name" --repo "$REPO" 2>&1)
        if [ $? -eq 0 ]; then
            if [ ${#secret_value} -gt 50 ]; then
                print_status "$secret_name = ${display_value}... (${#secret_value} chars)"
            else
                print_status "$secret_name"
            fi
            ((success_count++))
        else
            print_error "Failed to set $secret_name"
            echo "  Error: $error_output" | head -1
            ((fail_count++))
        fi
    }
    
    # ==========================================
    # SECTION 1: NiFi Application Secrets
    # ==========================================
    echo ""
    print_info "📋 Section 1: NiFi Application Configuration"
    echo ""
    
    set_env_secret "NIFI_REGISTRY_PORT" "${NIFI_REGISTRY_PORT:-18080}"
    set_env_secret "NIFI_REGISTRY_HOST" "${NIFI_REGISTRY_HOST:-0.0.0.0}"
    set_env_secret "NIFI_USERNAME" "${NIFI_USERNAME:-admin}"
    set_env_secret "NIFI_PASSWORD" "${NIFI_PASSWORD}"
    set_env_secret "NIFI_SENSITIVE_KEY" "${NIFI_SENSITIVE_PROPS_KEY}"
    set_env_secret "NIFI_HTTPS_PORT" "${NIFI_HTTPS_PORT:-8443}"
    set_env_secret "NIFI_WEB_HTTPS_HOST" "${NIFI_WEB_HTTPS_HOST:-0.0.0.0}"
    set_env_secret "NIFI_ELECTION_MAX_WAIT" "${NIFI_ELECTION_MAX_WAIT:-1 min}"
    
    # ==========================================
    # SECTION 2: VM/Infrastructure Secrets
    # ==========================================
    echo ""
    print_info "🖥️  Section 2: VM/Infrastructure Configuration"
    echo ""
    
    set_env_secret "VM_USERNAME" "${VM_USERNAME:-azureuser}"
    set_env_secret "VM_SSH_PORT" "${VM_SSH_PORT:-22}"
    
    # Try to get IP from .env first
    local vm_public_ip="${VM_PUBLIC_IP}"
    local public_ip="${PUBLIC_IP}"
    
    # If IPs are empty or placeholder, try to get from Terraform
    if [ -z "$vm_public_ip" ] || [[ "$vm_public_ip" == *"REPLACE"* ]] || [[ "$vm_public_ip" == *"TBD"* ]]; then
        print_step "Fetching IPs from Terraform outputs..."
        
        cd "$TF_DIR"
        
        # Initialize Terraform
        if terraform init -reconfigure -backend-config="backend-configs/${env_name}.tfbackend" > /dev/null 2>&1; then
            # Get outputs
            local tf_outputs=$(terraform output -json 2>/dev/null)
            
            if [ -n "$tf_outputs" ] && [ "$tf_outputs" != "{}" ]; then
                vm_public_ip=$(echo "$tf_outputs" | jq -r '.vm_public_ip.value // empty')
                public_ip=$(echo "$tf_outputs" | jq -r '.public_ip.value // empty')
                
                if [ -n "$vm_public_ip" ]; then
                    print_status "Retrieved IP from Terraform: $vm_public_ip"
                    
                    # Update .env file with actual IP
                    print_step "Updating $env_file with Terraform IP..."
                    sed -i.bak "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${vm_public_ip}|g" "$PROJECT_DIR/$env_file" 2>/dev/null || \
                    sed -i '' "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${vm_public_ip}|g" "$PROJECT_DIR/$env_file" 2>/dev/null
                    
                    sed -i.bak "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$PROJECT_DIR/$env_file" 2>/dev/null || \
                    sed -i '' "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$PROJECT_DIR/$env_file" 2>/dev/null
                    
                    sed -i.bak "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$PROJECT_DIR/$env_file" 2>/dev/null || \
                    sed -i '' "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$PROJECT_DIR/$env_file" 2>/dev/null
                    
                    rm -f "$PROJECT_DIR/${env_file}.bak"
                    print_status "Updated $env_file with Terraform outputs"
                fi
            else
                print_warning "No Terraform outputs found for $env_name"
                print_info "Deploy infrastructure first: make tf-apply ENV=$env_name"
            fi
        else
            print_warning "Could not initialize Terraform for $env_name"
        fi
        
        cd "$PROJECT_DIR"
    fi
    
    # Set IP-based secrets
    set_env_secret "VM_PUBLIC_IP" "$vm_public_ip"
    set_env_secret "PUBLIC_IP" "$public_ip"
    
    # Set NIFI_WEB_PROXY_HOST from .env or construct from IP
    local nifi_proxy_host="${NIFI_WEB_PROXY_HOST}"
    if [ -z "$nifi_proxy_host" ] && [ -n "$public_ip" ]; then
        nifi_proxy_host="${public_ip}:8443"
    fi
    set_env_secret "NIFI_WEB_PROXY_HOST" "$nifi_proxy_host"
    
    # ==========================================
    # SECTION 3: Computed URLs
    # ==========================================
    echo ""
    print_info "🌐 Section 3: Service URLs"
    echo ""
    
    if [ -n "$public_ip" ]; then
        set_env_secret "NIFI_HTTP_URL" "http://${public_ip}:8080/nifi"
        set_env_secret "NIFI_HTTPS_URL" "https://${public_ip}:8443/nifi"
        set_env_secret "NIFI_REGISTRY_URL" "http://${public_ip}:18080/nifi-registry"
    else
        print_warning "No public IP available - skipping URL secrets"
    fi
    
    # ==========================================
    # Summary
    # ==========================================
    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo " Results for $env_name: ${GREEN}$success_count updated${NC}, ${RED}$fail_count failed${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
    
    return $fail_count
}

# Main function
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🔄 Complete Secrets Synchronization Tool            ║"
    echo "║  .env + Terraform → GitHub Environment Secrets       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    # Check GitHub CLI authentication
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
    
    # Check jq availability
    if ! command -v jq &> /dev/null; then
        print_warning "jq not installed - Terraform output parsing may fail"
        print_info "Install: sudo apt-get install jq  # or  brew install jq"
    fi
    
    echo ""
    
    # Sync secrets for requested environment(s)
    local total_failures=0
    
    case "$ENVIRONMENT" in
        development|dev)
            sync_environment_secrets "development"
            total_failures=$?
            ;;
        staging)
            sync_environment_secrets "staging"
            total_failures=$?
            ;;
        production|prod)
            sync_environment_secrets "production"
            total_failures=$?
            ;;
        all)
            sync_environment_secrets "development"
            total_failures=$((total_failures + $?))
            
            sync_environment_secrets "staging"
            total_failures=$((total_failures + $?))
            
            sync_environment_secrets "production"
            total_failures=$((total_failures + $?))
            ;;
        *)
            print_error "Invalid environment: $ENVIRONMENT"
            echo ""
            echo "Usage: $0 [development|staging|production|all]"
            echo ""
            echo "Examples:"
            echo "  $0 development     # Sync development secrets"
            echo "  $0 all             # Sync all environments (default)"
            echo ""
            exit 1
            ;;
    esac
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  ✅ Synchronization Complete!                        ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    if [ $total_failures -eq 0 ]; then
        print_success "All secrets synchronized successfully!"
    else
        print_warning "Some secrets failed to sync (check logs above)"
    fi
    
    echo ""
    print_info "What was synchronized:"
    echo ""
    echo "  📋 NiFi Application Secrets:"
    echo "     • NIFI_USERNAME, NIFI_PASSWORD, NIFI_SENSITIVE_KEY"
    echo "     • NIFI_REGISTRY_PORT, NIFI_REGISTRY_HOST"
    echo "     • NIFI_HTTPS_PORT, NIFI_WEB_HTTPS_HOST"
    echo "     • NIFI_WEB_PROXY_HOST, NIFI_ELECTION_MAX_WAIT"
    echo ""
    echo "  🖥️  VM/Infrastructure Secrets:"
    echo "     • VM_PUBLIC_IP, PUBLIC_IP"
    echo "     • VM_USERNAME, VM_SSH_PORT"
    echo ""
    echo "  🌐 Service URLs:"
    echo "     • NIFI_HTTP_URL, NIFI_HTTPS_URL"
    echo "     • NIFI_REGISTRY_URL"
    echo ""
    print_info "Verify at: https://github.com/$REPO/settings/secrets/actions"
    echo ""
    print_info "Next steps:"
    echo "  1. Deploy SSH keys: make deploy-ssh-keys-all"
    echo "  2. Deploy flows: make deploy-flows-all"
    echo "  3. Test deployment workflow: git push origin develop"
    echo ""
    
    exit $total_failures
}

main "$@"