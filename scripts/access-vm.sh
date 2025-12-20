#!/bin/bash

# access-vm.sh - Connect to Azure VMs provisioned by GitHub Actions workflow
# This script uses the repository-level SSH key to connect to environment VMs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-your-github-username}"
REPO_NAME="${GITHUB_REPOSITORY_NAME:-your-repo-name}"
GH_TOKEN="${GH_TOKEN:-}"
SSH_KEY_PATH="${HOME}/.ssh/deploy_key"
VM_USERNAME="azureuser"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
    
    # Check if ssh is installed
    if ! command -v ssh &> /dev/null; then
        print_error "SSH client is not installed"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed"
        echo "Install it with: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to authenticate with GitHub
authenticate_github() {
    print_info "Authenticating with GitHub..."
    
    if [ -n "$GH_TOKEN" ]; then
        echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null
    fi
    
    if ! gh auth status 2>&1 | grep -q "Logged in"; then
        print_error "GitHub CLI authentication failed"
        echo ""
        echo "Please authenticate using one of these methods:"
        echo "  1. Run: gh auth login"
        echo "  2. Set GH_TOKEN environment variable: export GH_TOKEN=your_token"
        exit 1
    fi
    
    print_success "GitHub authentication successful"
}

# Function to get SSH private key from repository secrets
get_ssh_key() {
    print_info "Retrieving SSH private key from repository secrets..."
    
    # Note: gh CLI cannot directly read secrets, so we need to inform the user
    if [ ! -f "$SSH_KEY_PATH" ]; then
        print_warning "SSH key not found at: $SSH_KEY_PATH"
        echo ""
        echo "To setup your SSH key:"
        echo "  1. Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
        echo "  2. Copy the value of SSH_PRIVATE_KEY secret"
        echo "  3. Save it to: $SSH_KEY_PATH"
        echo ""
        echo "Or run these commands:"
        echo "  mkdir -p ~/.ssh"
        echo "  # Paste your SSH private key, then press Ctrl+D"
        echo "  cat > $SSH_KEY_PATH"
        echo "  chmod 600 $SSH_KEY_PATH"
        echo ""
        read -p "Press Enter after you've saved the SSH key, or Ctrl+C to exit..."
        
        if [ ! -f "$SSH_KEY_PATH" ]; then
            print_error "SSH key still not found"
            exit 1
        fi
    fi
    
    # Verify key permissions
    chmod 600 "$SSH_KEY_PATH"
    print_success "SSH key configured"
}

# Function to get VM IP for an environment
get_vm_ip() {
    local environment=$1
    local vm_ip=""
    
    print_info "Getting VM IP for $environment environment..." >&2
    
    # Try to get from environment secrets
    vm_ip=$(gh secret list --env "$environment" --repo "$REPO_OWNER/$REPO_NAME" 2>/dev/null | grep "VM_PUBLIC_IP" | awk '{print $1}')
    
    if [ -z "$vm_ip" ] || [ "$vm_ip" == "VM_PUBLIC_IP" ]; then
        # Try alternative method using Azure CLI if available
        if command -v az &> /dev/null; then
            print_info "Trying to get IP from Azure..." >&2
            local rg=""
            local vm_name=""
            
            case $environment in
                development)
                    rg="rg-nificicd-g1p2-dev"
                    vm_name="vm-nifi-development"
                    ;;
                staging)
                    rg="rg-nificicd-g1p2-staging"
                    vm_name="vm-nifi-staging"
                    ;;
                production)
                    rg="rg-nificicd-g1p2-prod"
                    vm_name="vm-nifi-production"
                    ;;
            esac
            
            if [ -n "$rg" ] && [ -n "$vm_name" ]; then
                vm_ip=$(az vm show -d --resource-group "$rg" --name "$vm_name" --query publicIps -o tsv 2>/dev/null)
            fi
        fi
    fi
    
    if [ -z "$vm_ip" ] || [ "$vm_ip" == "VM_PUBLIC_IP" ]; then
        print_error "Could not retrieve VM IP for $environment" >&2
        echo "" >&2
        echo "Please provide the IP address manually:" >&2
        read -p "VM IP: " vm_ip </dev/tty
    fi
    
    echo "$vm_ip"
}

# Function to test SSH connection
test_connection() {
    local ip=$1
    print_info "Testing SSH connection to $ip..." >&2
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "$VM_USERNAME@$ip" "echo 'Connection successful'" &>/dev/null; then
        print_success "SSH connection test successful" >&2
        return 0
    else
        print_error "SSH connection test failed" >&2
        return 1
    fi
}

# Function to connect to VM
connect_to_vm() {
    local environment=$1
    local vm_ip=$2
    
    echo ""
    print_success "Connecting to $environment VM at $vm_ip"
    print_info "Username: $VM_USERNAME"
    print_info "SSH Key: $SSH_KEY_PATH"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Add host to known_hosts to avoid prompt
    ssh-keyscan -H "$vm_ip" >> ~/.ssh/known_hosts 2>/dev/null
    
    # Connect to VM
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$VM_USERNAME@$vm_ip"
}

# Function to show VM information
show_vm_info() {
    local environment=$1
    local vm_ip=$2
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        VM Connection Information       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "  Environment:  $environment"
    echo "  IP Address:   $vm_ip"
    echo "  Username:     $VM_USERNAME"
    echo "  SSH Key:      $SSH_KEY_PATH"
    echo ""
    echo "  NiFi URL:     https://$vm_ip:8443/nifi"
    echo "  Registry URL: http://$vm_ip:18080/nifi-registry"
    echo ""
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ENVIRONMENT]

Connect to Azure VMs provisioned by GitHub Actions workflow.

ENVIRONMENT:
    development, dev, d     Connect to development environment
    staging, stage, s       Connect to staging environment
    production, prod, p     Connect to production environment

OPTIONS:
    -i, --info              Show VM information only (don't connect)
    -t, --test              Test SSH connection only
    -u, --username USER     Override default username (default: $VM_USERNAME)
    -k, --key PATH          Override SSH key path (default: $SSH_KEY_PATH)
    -r, --repo OWNER/REPO   Override repository (default: $REPO_OWNER/$REPO_NAME)
    -h, --help              Display this help message

EXAMPLES:
    $0 development          Connect to development VM
    $0 -i staging           Show staging VM info
    $0 -t production        Test production VM connection
    $0 -u myuser dev        Connect to dev VM with custom username

ENVIRONMENT VARIABLES:
    GH_TOKEN                GitHub Personal Access Token
    GITHUB_REPOSITORY_OWNER Repository owner (overrides default)
    GITHUB_REPOSITORY_NAME  Repository name (overrides default)

PREREQUISITES:
    - GitHub CLI (gh) installed and authenticated
    - SSH client installed
    - jq installed
    - SSH private key from repository secrets

EOF
}

# Main function
main() {
    local environment=""
    local info_only=false
    local test_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -i|--info)
                info_only=true
                shift
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -u|--username)
                VM_USERNAME="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            -r|--repo)
                IFS='/' read -r REPO_OWNER REPO_NAME <<< "$2"
                shift 2
                ;;
            development|dev|d)
                environment="development"
                shift
                ;;
            staging|stage|s)
                environment="staging"
                shift
                ;;
            production|prod|p)
                environment="production"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
        esac
    done
    
    # If no environment specified, prompt user
    if [ -z "$environment" ]; then
        echo ""
        echo "Select environment:"
        echo "  1) Development"
        echo "  2) Staging"
        echo "  3) Production"
        echo ""
        read -p "Enter choice [1-3]: " choice
        
        case $choice in
            1) environment="development" ;;
            2) environment="staging" ;;
            3) environment="production" ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    echo ""
    echo "╔══════════════════════════════════╗"
    echo "║       Azure VM Access Tool       ║"
    echo "╚══════════════════════════════════╝"
    echo ""
    
    # Run checks
    check_prerequisites
    authenticate_github
    get_ssh_key
    
    # Get VM IP
    vm_ip=$(get_vm_ip "$environment")
    
    if [ -z "$vm_ip" ] || [ "$vm_ip" == "null" ]; then
        print_error "Failed to get VM IP for $environment environment"
        echo ""
        echo "Make sure:"
        echo "  1. The VM has been provisioned"
        echo "  2. The provision workflow completed successfully"
        echo "  3. You have access to the repository secrets"
        exit 1
    fi
    
    print_success "VM IP retrieved: $vm_ip"
    
    # Show info if requested
    if [ "$info_only" = true ]; then
        show_vm_info "$environment" "$vm_ip"
        exit 0
    fi
    
    # Test connection if requested
    if [ "$test_only" = true ]; then
        if test_connection "$vm_ip"; then
            show_vm_info "$environment" "$vm_ip"
            exit 0
        else
            print_error "Connection test failed"
            exit 1
        fi
    fi
    
    # Test connection before connecting
    if ! test_connection "$vm_ip"; then
        print_warning "SSH connection test failed, but attempting to connect anyway..."
    fi
    
    # Show info
    show_vm_info "$environment" "$vm_ip"
    
    # Connect to VM
    read -p "Press Enter to connect, or Ctrl+C to cancel..."
    connect_to_vm "$environment" "$vm_ip"
}

# Run main function
main "$@"