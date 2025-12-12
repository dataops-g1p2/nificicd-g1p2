#!/bin/bash

# NiFi CI/CD script to update GitHub secrets from .env files
# This script reads NiFi configuration from .env files and pushes secrets to GitHub
# Usage: ./setup_nifi_github_secrets.sh [environment] [options]
# Environment: development, staging, production, or all (default: all)
# Options:
#   --ssh-key /path/to/key    Use existing SSH key
#   --auto-setup              Automatically generate SSH key and configure VM
#   --vm-ip <ip>              VM IP address for auto-setup
#   --vm-user <username>      VM username for auto-setup (default: azureuser)
#   --vm-password <password>  VM password for initial setup (will use key after)
#   --from-env                Update secrets from .env files (skip SSH setup)
#   --with-terraform          Also pull IPs from Terraform outputs
#   --skip-ssh                Skip SSH key setup entirely (for CI/CD)

REPO="saadkhalmadani/nificicd-g1p2"
ENVIRONMENT=${1:-all}
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_DIR/azure-vm-terraform"
AUTO_SETUP=false
VM_IP=""
VM_USER="azureuser"
VM_PASSWORD=""
FROM_ENV=false
WITH_TERRAFORM=false
SKIP_SSH=false

# Detect if running in GitHub Actions
IS_GITHUB_ACTIONS=false
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    IS_GITHUB_ACTIONS=true
    SKIP_SSH=true  # Automatically skip SSH setup in GitHub Actions
    print_info "Detected GitHub Actions environment - SSH setup will be skipped"
fi

# Parse arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-key)
            SSH_KEY_PATH="$2"
            SKIP_SSH=false  # User explicitly provided SSH key
            shift 2
            ;;
        --auto-setup)
            AUTO_SETUP=true
            SKIP_SSH=false
            shift
            ;;
        --vm-ip)
            VM_IP="$2"
            shift 2
            ;;
        --vm-user)
            VM_USER="$2"
            shift 2
            ;;
        --vm-password)
            VM_PASSWORD="$2"
            shift 2
            ;;
        --from-env)
            FROM_ENV=true
            shift
            ;;
        --with-terraform)
            WITH_TERRAFORM=true
            shift
            ;;
        --skip-ssh)
            SKIP_SSH=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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

print_success() {
    echo -e "${CYAN}★${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate SSH key
validate_ssh_key() {
    local key_path=$1
    
    if [ ! -f "$key_path" ]; then
        return 1
    fi
    
    # Check if it's a valid SSH private key
    if ! ssh-keygen -l -f "$key_path" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Function to generate SSH key pair
generate_ssh_key() {
    print_step "Generating new SSH key pair..."
    
    local key_path=$1
    local key_dir=$(dirname "$key_path")
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    # Backup existing key if it exists
    if [ -f "$key_path" ]; then
        local backup_path="${key_path}.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "Backing up existing key to: $backup_path"
        mv "$key_path" "$backup_path"
        if [ -f "${key_path}.pub" ]; then
            mv "${key_path}.pub" "${backup_path}.pub"
        fi
    fi
    
    # Generate new key
    if ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "github-actions-deploy-$(date +%Y%m%d)" >/dev/null 2>&1; then
        chmod 600 "$key_path"
        chmod 644 "${key_path}.pub"
        print_status "Generated new SSH key pair"
        print_info "Private key: $key_path"
        print_info "Public key: ${key_path}.pub"
        
        # Show fingerprint
        local fingerprint=$(ssh-keygen -l -f "$key_path" 2>/dev/null)
        print_info "Fingerprint: $fingerprint"
        
        return 0
    else
        print_error "Failed to generate SSH key"
        return 1
    fi
}

# Function to configure VM with SSH key
configure_vm_ssh() {
    local vm_ip=$1
    local vm_user=$2
    local vm_password=$3
    local key_path=$4
    
    print_step "Configuring VM SSH access..."
    
    # Check if sshpass is available for password authentication
    if [ -n "$vm_password" ] && ! command_exists sshpass; then
        print_warning "sshpass not found, attempting to install..."
        if command_exists apt-get; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y sshpass >/dev/null 2>&1
        elif command_exists yum; then
            sudo yum install -y sshpass >/dev/null 2>&1
        elif command_exists brew; then
            brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1
        else
            print_error "Cannot install sshpass. Please install it manually or use SSH key authentication"
            return 1
        fi
    fi
    
    local public_key=$(cat "${key_path}.pub")
    
    print_info "Adding public key to VM: ${vm_user}@${vm_ip}"
    
    # Create SSH config script
    local setup_script=$(cat <<'SETUP_EOF'
#!/bin/bash
set -e

# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Backup existing authorized_keys
if [ -f ~/.ssh/authorized_keys ]; then
    cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup.$(date +%Y%m%d_%H%M%S)
fi

# Add public key to authorized_keys
echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys

# Remove duplicates
sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp
mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys

# Set correct permissions
chmod 600 ~/.ssh/authorized_keys

# Ensure SSH daemon allows public key authentication
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
sudo sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

# Restart SSH service (try different service names)
sudo systemctl restart sshd 2>/dev/null || \
sudo systemctl restart ssh 2>/dev/null || \
sudo service sshd restart 2>/dev/null || \
sudo service ssh restart 2>/dev/null || true

echo "SSH key configured successfully"
SETUP_EOF
)
    
    # Execute setup on VM
    if [ -n "$vm_password" ]; then
        # Use password authentication
        print_info "Using password authentication to configure VM..."
        
        # Test connection first
        if ! sshpass -p "$vm_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${vm_user}@${vm_ip}" "echo 'Connection test successful'" >/dev/null 2>&1; then
            print_error "Cannot connect to VM with provided credentials"
            return 1
        fi
        
        # Run setup script
        if echo "$setup_script" | sshpass -p "$vm_password" ssh -o StrictHostKeyChecking=no "${vm_user}@${vm_ip}" "PUBLIC_KEY='$public_key' bash -s"; then
            print_status "VM SSH configuration completed"
        else
            print_error "Failed to configure VM SSH"
            return 1
        fi
    else
        # Try using existing SSH key or default
        print_info "Attempting to use existing SSH authentication..."
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${vm_user}@${vm_ip}" "echo 'Connection test successful'" >/dev/null 2>&1; then
            if echo "$setup_script" | ssh -o StrictHostKeyChecking=no "${vm_user}@${vm_ip}" "PUBLIC_KEY='$public_key' bash -s"; then
                print_status "VM SSH configuration completed"
            else
                print_error "Failed to configure VM SSH"
                return 1
            fi
        else
            print_error "Cannot connect to VM. Please provide --vm-password or ensure SSH access is already configured"
            return 1
        fi
    fi
    
    # Test the new key
    print_step "Testing new SSH key..."
    sleep 2  # Give SSH daemon time to reload
    
    if ssh -i "$key_path" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${vm_user}@${vm_ip}" "echo 'SSH key authentication successful'" >/dev/null 2>&1; then
        print_success "SSH key authentication working! ✨"
        return 0
    else
        print_error "SSH key authentication test failed"
        print_warning "Checking VM SSH configuration..."
        
        # Try to diagnose the issue
        if [ -n "$vm_password" ]; then
            print_info "Verifying authorized_keys on VM..."
            sshpass -p "$vm_password" ssh -o StrictHostKeyChecking=no "${vm_user}@${vm_ip}" "ls -la ~/.ssh/authorized_keys; tail -n 5 ~/.ssh/authorized_keys" 2>&1 | head -10
        fi
        
        return 1
    fi
}

# Function to automatically setup SSH
auto_setup_ssh() {
    echo ""
    echo "╔═══════════════════════╗"
    echo " 🔐 Automatic SSH Setup  "
    echo "╚═══════════════════════╝"
    echo ""
    
    # Validate inputs
    if [ -z "$VM_IP" ]; then
        print_error "VM IP address is required for auto-setup"
        echo ""
        echo "Usage: $0 --auto-setup --vm-ip <ip> [--vm-user <user>] [--vm-password <password>]"
        echo ""
        return 1
    fi
    
    print_info "VM IP: $VM_IP"
    print_info "VM User: $VM_USER"
    print_info "SSH Key Path: $SSH_KEY_PATH"
    echo ""
    
    # Step 1: Generate SSH key if it doesn't exist or is invalid
    if ! validate_ssh_key "$SSH_KEY_PATH"; then
        generate_ssh_key "$SSH_KEY_PATH" || return 1
    else
        print_status "Using existing valid SSH key: $SSH_KEY_PATH"
        local fingerprint=$(ssh-keygen -l -f "$SSH_KEY_PATH" 2>/dev/null)
        print_info "Fingerprint: $fingerprint"
    fi
    
    echo ""
    
    # Step 2: Configure VM
    configure_vm_ssh "$VM_IP" "$VM_USER" "$VM_PASSWORD" "$SSH_KEY_PATH" || return 1
    
    echo ""
    print_success "Automatic SSH setup completed successfully!"
    echo ""
    
    return 0
}

# Function to get current GH CLI token
get_gh_token() {
    local token=""
    
    # Try to get token from gh CLI
    if command -v gh >/dev/null 2>&1; then
        token=$(gh auth token 2>/dev/null || echo "")
    fi
    
    # Fallback to environment variables
    if [ -z "$token" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
        token="$GITHUB_TOKEN"
    elif [ -z "$token" ] && [ -n "${GH_TOKEN:-}" ]; then
        token="$GH_TOKEN"
    fi
    
    echo "$token"
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

# Function to ensure .env files exist
ensure_env_files() {
    local env_files=(".env.development" ".env.staging" ".env.production")
    
    print_info "Checking .env files..."
    
    for env_file in "${env_files[@]}"; do
        if [ -f "$PROJECT_DIR/$env_file" ]; then
            print_status "File '$env_file' exists"
        else
            print_warning "File '$env_file' does not exist, creating template..."
            # Create a template .env file with ALL required variables
            cat > "$PROJECT_DIR/$env_file" <<'EOF'
# NiFi Registry Configuration
NIFI_REGISTRY_PORT=18080
NIFI_REGISTRY_HOST=0.0.0.0

# NiFi Core Configuration
NIFI_USERNAME=admin
NIFI_PASSWORD=
NIFI_SENSITIVE_PROPS_KEY=
NIFI_ELECTION_MAX_WAIT=1 min
NIFI_HTTPS_PORT=8443
NIFI_WEB_HTTPS_HOST=0.0.0.0

# VM Infrastructure (Updated automatically by Terraform after apply)
PUBLIC_IP=
VM_PUBLIC_IP=
NIFI_WEB_PROXY_HOST=:8443

# SSH Configuration
VM_SSH_PORT=22
VM_USERNAME=azureuser
EOF
            print_status "Created template '$env_file'"
            echo ""
            print_info "Run 'make setup-passwords' to generate secure passwords"
        fi
    done
    echo ""
}

# Function to setup repository-level secrets (shared across all environments)
setup_repository_secrets() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo " 📦 Repository-Level Secrets (Shared) "
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    local success_count=0
    local fail_count=0
    
    # Function to set repository secret
    set_repo_secret() {
        local secret_name=$1
        local secret_value=$2
        
        if [ -z "$secret_value" ]; then
            print_warning "Skipping $secret_name (no value provided)"
            return
        fi
        
        local error_output=$(echo "$secret_value" | gh secret set "$secret_name" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "$secret_name"
            ((success_count++))
        else
            print_error "Failed to set $secret_name"
            echo "  Error: $error_output" | head -1
            ((fail_count++))
        fi
    }
    
    # GH_TOKEN - GitHub Personal Access Token for API access
    echo ""
    print_info "Setting up GH_TOKEN..."
    
    local gh_token=$(get_gh_token)
    
    if [ -n "$gh_token" ]; then
        print_status "Found GitHub token from gh CLI"
        set_repo_secret "GH_TOKEN" "$gh_token"
        
        echo ""
        print_info "This token will be used for:"
        echo "  • GitHub API interactions in workflows"
        echo "  • Creating/updating environments"
        echo "  • Managing workflow runs"
    else
        print_warning "No GitHub token found"
        print_info "The GH_TOKEN secret is required for production workflows"
        echo ""
        print_info "To set up GH_TOKEN:"
        echo "  1. Create a Personal Access Token at:"
        echo "     https://github.com/settings/tokens/new"
        echo "  2. Select these scopes:"
        echo "     - repo (full control)"
        echo "     - workflow"
        echo "     - admin:repo_hook"
        echo "  3. Run: gh secret set GH_TOKEN"
        echo "  4. Or set it manually at:"
        echo "     https://github.com/$REPO/settings/secrets/actions"
        echo ""
        ((fail_count++))
    fi
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo " Repository Secrets: ${GREEN}$success_count set${NC}, ${RED}$fail_count failed${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
}

# Function to setup environment-specific SSH secrets
setup_environment_ssh_secrets() {
    local env=$1
    
    # Skip SSH setup if flag is set
    if [ "$SKIP_SSH" = true ]; then
        print_warning "Skipping SSH key setup for environment: $env (--skip-ssh flag set)"
        if [ "$IS_GITHUB_ACTIONS" = true ]; then
            print_info "SSH secrets must be configured manually in GitHub Actions environments"
            print_info "Run this script locally with --auto-setup or add secrets via GitHub UI"
        fi
        return 0
    fi
    
    echo ""
    print_info "Setting up SSH secrets for environment: $env"
    
    local success_count=0
    local fail_count=0
    
    # Function to set environment secret
    set_env_secret() {
        local secret_name=$1
        local secret_value=$2
        
        if [ -z "$secret_value" ]; then
            print_warning "Skipping $secret_name (no value provided)"
            return
        fi
        
        local error_output=$(echo "$secret_value" | gh secret set "$secret_name" --env "$env" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "$secret_name (environment: $env)"
            ((success_count++))
        else
            print_error "Failed to set $secret_name for $env"
            if [[ "$error_output" == *"could not create or update secret"* ]] || [[ "$error_output" == *"environment not found"* ]]; then
                print_warning "Environment '$env' may not exist. Create it at:"
                echo "  https://github.com/$REPO/settings/environments/new"
            fi
            echo "  Error: $error_output" | head -1
            ((fail_count++))
        fi
    }
    
    # Set SSH_PRIVATE_KEY per environment
    print_info "Processing SSH key: $SSH_KEY_PATH"
    
    if validate_ssh_key "$SSH_KEY_PATH"; then
        print_status "SSH key is valid"
        
        # Show key fingerprint for verification
        local fingerprint=$(ssh-keygen -l -f "$SSH_KEY_PATH" 2>/dev/null)
        print_info "Key fingerprint: $fingerprint"
        
        local ssh_key_content=$(cat "$SSH_KEY_PATH")
        
        # Validate key format
        if [[ "$ssh_key_content" == *"BEGIN"*"PRIVATE KEY"* ]] && [[ "$ssh_key_content" == *"END"*"PRIVATE KEY"* ]]; then
            set_env_secret "SSH_PRIVATE_KEY" "$ssh_key_content"
        else
            print_error "SSH key format appears invalid"
            ((fail_count++))
        fi
    else
        print_warning "SSH key not found or invalid: $SSH_KEY_PATH"
        print_info "SSH_PRIVATE_KEY secret will not be set for this environment"
        print_info "To fix:"
        print_info "  1. Run locally: $0 $env --auto-setup --vm-ip <ip> --vm-password <pass>"
        print_info "  2. Or manually add via GitHub UI:"
        print_info "     https://github.com/$REPO/settings/environments"
    fi
    
    # Set VM_USERNAME per environment
    if [ -n "$VM_USER" ]; then
        set_env_secret "VM_USERNAME" "$VM_USER"
    else
        print_warning "VM_USERNAME not set, using default 'azureuser'"
        set_env_secret "VM_USERNAME" "azureuser"
    fi
    
    return $fail_count
}

# Function to get IP from Terraform outputs
get_terraform_outputs() {
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
            return 1
            ;;
    esac
    
    # Check if Terraform directory exists
    if [ ! -d "$TF_DIR" ]; then
        return 1
    fi
    
    cd "$TF_DIR"
    
    # Initialize Terraform with the appropriate backend config
    if ! terraform init -reconfigure -backend-config="backend-configs/${env_name}.tfbackend" > /dev/null 2>&1; then
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Check if Terraform state exists
    if ! terraform state list > /dev/null 2>&1; then
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Get outputs in JSON format
    local outputs=$(terraform output -json 2>/dev/null)
    
    cd "$PROJECT_DIR"
    
    if [ -z "$outputs" ] || [ "$outputs" = "{}" ]; then
        return 1
    fi
    
    # Extract values and export them
    export TF_VM_PUBLIC_IP=$(echo "$outputs" | jq -r '.vm_public_ip.value // empty')
    export TF_PUBLIC_IP=$(echo "$outputs" | jq -r '.public_ip.value // empty')
    
    return 0
}

# Function to update .env file with Terraform IPs
update_env_file_with_terraform() {
    local env=$1
    local env_file=$2
    local public_ip=$3
    
    if [ -z "$public_ip" ] || [ ! -f "$env_file" ]; then
        return 1
    fi
    
    print_step "Updating $env_file with Terraform IP: $public_ip"
    
    # Update PUBLIC_IP
    sed -i.bak "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null || \
    sed -i '' "s|^PUBLIC_IP=.*|PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null
    
    # Update VM_PUBLIC_IP
    sed -i.bak "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null || \
    sed -i '' "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=${public_ip}|g" "$env_file" 2>/dev/null
    
    # Update NIFI_WEB_PROXY_HOST
    sed -i.bak "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$env_file" 2>/dev/null || \
    sed -i '' "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=${public_ip}:8443|g" "$env_file" 2>/dev/null
    
    # Remove backup files
    rm -f "${env_file}.bak"
    
    print_status "Updated $env_file with Terraform outputs"
    
    return 0
}

# Function to update NiFi secrets from .env files for a specific environment
update_nifi_secrets_from_env() {
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
    echo "╔══════════════════════════════════════════╗"
    echo "   🔧 NiFi Configuration → GitHub Secrets      "
    echo "           Environment: $env_name              "
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    # Setup SSH secrets for this environment (only if not skipping)
    if [ "$SKIP_SSH" = false ]; then
        print_step "Setting up SSH authentication secrets..."
        setup_environment_ssh_secrets "$env_name"
        echo ""
    else
        print_info "Skipping SSH secret setup (will be configured separately)"
        echo ""
    fi
    
    # Check if WITH_TERRAFORM flag is set and try to get Terraform outputs
    if [ "$WITH_TERRAFORM" = true ]; then
        print_step "Attempting to fetch Terraform outputs for $env_name..."
        if get_terraform_outputs "$env_name"; then
            if [ -n "$TF_PUBLIC_IP" ]; then
                print_status "Retrieved IP from Terraform: $TF_PUBLIC_IP"
                update_env_file_with_terraform "$env_name" "$PROJECT_DIR/$env_file" "$TF_PUBLIC_IP"
            fi
        else
            print_warning "Could not fetch Terraform outputs (may not be deployed yet)"
        fi
        echo ""
    fi
    
    # Check if .env file exists
    if [ ! -f "$PROJECT_DIR/$env_file" ]; then
        print_warning "File $env_file not found, skipping"
        return 1
    fi
    
    print_info "Reading from $env_file..."
    
    # Validate .env file (check for empty passwords)
    if grep -q "NIFI_PASSWORD=$" "$PROJECT_DIR/$env_file" 2>/dev/null; then
        print_error "File $env_file has empty NIFI_PASSWORD - run 'make setup-passwords' first"
        echo ""
        return 1
    fi
    
    if grep -q "NIFI_SENSITIVE_PROPS_KEY=$" "$PROJECT_DIR/$env_file" 2>/dev/null; then
        print_error "File $env_file has empty NIFI_SENSITIVE_PROPS_KEY - run 'make setup-passwords' first"
        echo ""
        return 1
    fi
    
    # Source the environment file safely
    set -a
    source "$PROJECT_DIR/$env_file"
    set +a
    
    local success_count=0
    local fail_count=0
    
    echo ""
    print_info "Setting GitHub environment secrets for: $env_name"
    echo ""
    
    # Function to set environment secret
    set_env_secret() {
        local secret_name=$1
        local secret_value=$2
        local display_value="${secret_value:0:20}"
        
        if [ -z "$secret_value" ] || [[ "$secret_value" == *"GENERATE"* ]] || [[ "$secret_value" == *"REPLACE"* ]] || [[ "$secret_value" == *"TBD"* ]]; then
            print_warning "Skipping $secret_name (not configured: '$secret_value')"
            return
        fi
        
        local error_output=$(echo "$secret_value" | gh secret set "$secret_name" --env "$env_name" 2>&1)
        if [ $? -eq 0 ]; then
            if [ ${#secret_value} -gt 50 ]; then
                print_status "$secret_name = ${display_value}... (${#secret_value} chars)"
            else
                print_status "$secret_name"
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
    
    # Set NiFi configuration secrets from .env file
    print_info "📋 NiFi Application Secrets"
    set_env_secret "NIFI_REGISTRY_PORT" "${NIFI_REGISTRY_PORT:-}"
    set_env_secret "NIFI_REGISTRY_HOST" "${NIFI_REGISTRY_HOST:-}"
    set_env_secret "REGISTRY_URL" "${REGISTRY_URL:-}"  
    set_env_secret "NIFI_USERNAME" "${NIFI_USERNAME:-}"
    set_env_secret "NIFI_PASSWORD" "${NIFI_PASSWORD:-}"
    set_env_secret "NIFI_SENSITIVE_KEY" "${NIFI_SENSITIVE_PROPS_KEY:-}"
    set_env_secret "NIFI_HTTPS_PORT" "${NIFI_HTTPS_PORT:-}"
    set_env_secret "NIFI_WEB_HTTPS_HOST" "${NIFI_WEB_HTTPS_HOST:-}"
    set_env_secret "NIFI_WEB_PROXY_HOST" "${NIFI_WEB_PROXY_HOST:-}"
    set_env_secret "NIFI_ELECTION_MAX_WAIT" "${NIFI_ELECTION_MAX_WAIT:-}"
    set_env_secret "NIFI_URL" "${NIFI_URL:-}" 

    # Set VM/Infrastructure secrets from .env file
    echo ""
    print_info "🖥️  VM/Infrastructure Secrets"
    set_env_secret "VM_PUBLIC_IP" "${VM_PUBLIC_IP:-}"
    set_env_secret "PUBLIC_IP" "${PUBLIC_IP:-}"
    set_env_secret "VM_SSH_PORT" "${VM_SSH_PORT:-22}"
    set_env_secret "VM_USERNAME" "${VM_USERNAME:-azureuser}"
    
    # Set computed URL secrets if we have an IP
    if [ -n "${PUBLIC_IP:-}" ]; then
        echo ""
        print_info "🌐 Service URLs"
        set_env_secret "NIFI_HTTP_URL" "http://${PUBLIC_IP}:8080/nifi"
        set_env_secret "NIFI_HTTPS_URL" "https://${PUBLIC_IP}:8443/nifi"
        set_env_secret "NIFI_REGISTRY_URL" "http://${PUBLIC_IP}:18080/nifi-registry"
        set_env_secret "REGISTRY_URL" "${REGISTRY_URL:-http://${PUBLIC_IP}:18080}"    # ADD THIS LINE
        set_env_secret "NIFI_URL" "${NIFI_URL:-https://${PUBLIC_IP}:8443}"            # ADD THIS LINE
    fi
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    echo " Results for $env_name: ${GREEN}$success_count updated${NC}, ${RED}$fail_count failed${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
}

# Main function
main() {
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║  🔧 NiFi Configuration → GitHub Secrets Setup  ║"
    echo "╚════════════════════════════════════════════════╝"
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
    
    # Automatic SSH setup if requested (skip if FROM_ENV mode)
    if [ "$AUTO_SETUP" = true ] && [ "$FROM_ENV" = false ]; then
        auto_setup_ssh || exit 1
    fi
    
    # Setup repository-level secrets first (only if not FROM_ENV mode and not AUTO_SETUP)
    if [ "$FROM_ENV" = false ] && [ "$AUTO_SETUP" = false ]; then
        setup_repository_secrets
    fi
    
    # Ensure GitHub environments exist before setting secrets
    ensure_github_environments
    
    # Ensure .env files exist
    ensure_env_files
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Update NiFi secrets from .env files
    case "$ENVIRONMENT" in
        development|dev)
            update_nifi_secrets_from_env "development"
            ;;
        staging)
            update_nifi_secrets_from_env "staging"
            ;;
        production|prod)
            update_nifi_secrets_from_env "production"
            ;;
        all)
            update_nifi_secrets_from_env "development"
            update_nifi_secrets_from_env "staging"
            update_nifi_secrets_from_env "production"
            ;;
        *)
            print_error "Invalid environment '$ENVIRONMENT'"
            echo ""
            echo "Usage: $0 [environment] [options]"
            echo ""
            echo "Environments:"
            echo "  development|dev    Update development secrets"
            echo "  staging            Update staging secrets"
            echo "  production|prod    Update production secrets"
            echo "  all                Update all environments (default)"
            echo ""
            echo "Options:"
            echo "  --ssh-key <path>           Use existing SSH key"
            echo "  --auto-setup               Automatically generate and configure SSH"
            echo "  --vm-ip <ip>               VM IP address (required for --auto-setup)"
            echo "  --vm-user <username>       VM username (default: azureuser)"
            echo "  --vm-password <password>   VM password for initial setup"
            echo "  --from-env                 Update only from .env files (skip SSH)"
            echo "  --with-terraform           Also pull IPs from Terraform outputs"
            echo ""
            echo "Examples:"
            echo "  # Update from .env files only"
            echo "  $0 all --from-env"
            echo ""
            echo "  # Update from .env + Terraform outputs"
            echo "  $0 all --with-terraform"
            echo ""
            echo "  # Manual setup with existing key"
            echo "  $0 all --ssh-key ~/.ssh/id_rsa"
            echo ""
            echo "  # Automatic setup with password"
            echo "  $0 all --auto-setup --vm-ip 1.2.3.4 --vm-password 'MyPassword123!'"
            echo ""
            exit 1
            ;;
    esac
    
    echo ""
    echo "╔════════════════════╗"
    echo "║ ✅ Setup Complete! ║"
    echo "╚════════════════════╝"
    echo ""
    print_info "Verify secrets at:"
    echo "   Repository: https://github.com/$REPO/settings/secrets/actions"
    echo "   Environments: https://github.com/$REPO/settings/environments"
    echo ""
    
    if [ "$FROM_ENV" = false ]; then
        print_info "Next steps:"
        echo "   1. Deploy infrastructure: make tf-apply-all"
        echo "   2. Update secrets with Terraform outputs: $0 all --with-terraform"
        echo "   3. Deploy SSH keys: make deploy-ssh-keys-all"
        echo "   4. Deploy flows: make deploy-flows-all"
        echo ""
    else
        print_info "Secrets synchronized from .env files"
        if [ "$WITH_TERRAFORM" = true ]; then
            print_info ".env files updated with Terraform IPs"
        fi
        print_info "SSH_PRIVATE_KEY uploaded to all environments"
        echo ""
    fi
}

# Run main function
main "$@"