#!/bin/bash
# Script to access Azure VMs - works with fresh VMs (no pre-existing setup)

set -e

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=============================="
echo " Azure VM Direct Access"
echo "=============================="
echo ""

# Parse environment argument (development, staging, production)
ENVIRONMENT=${1:-development}

# Configuration based on environment
case "$ENVIRONMENT" in
    development|dev)
        RESOURCE_GROUP="rg-nifi-cicd-dev"
        VM_NAME="vm-nifi-development"
        ENV_DISPLAY="Development"
        ;;
    staging)
        RESOURCE_GROUP="rg-nifi-cicd-staging"
        VM_NAME="vm-nifi-staging"
        ENV_DISPLAY="Staging"
        ;;
    production|prod)
        RESOURCE_GROUP="rg-nifi-cicd-prod"
        VM_NAME="vm-nifi-production"
        ENV_DISPLAY="Production"
        ;;
    *)
        echo -e "${RED}✗ Unknown environment: $ENVIRONMENT${NC}"
        echo ""
        echo "Usage: $0 [development|staging|production]"
        echo ""
        echo "Examples:"
        echo "  $0 development    # or 'dev'"
        echo "  $0 staging"
        echo "  $0 production     # or 'prod'"
        exit 1
        ;;
esac

VM_USERNAME="azureuser"

echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     ${ENV_DISPLAY} Environment Access      ${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${BLUE}VM Name:${NC} $VM_NAME"
echo -e "${BLUE}Username:${NC} $VM_USERNAME"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}✗ Azure CLI is not installed${NC}"
    echo ""
    echo "Install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    echo ""
    echo "Quick install:"
    echo "  macOS:   brew install azure-cli"
    echo "  Linux:   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo "  Windows: winget install Microsoft.AzureCLI"
    exit 1
fi

# Check if logged in
echo "🔐 Checking Azure authentication..."
if ! az account show &>/dev/null; then
    echo -e "${YELLOW}🔄 Not logged into Azure. Logging in...${NC}"
    echo ""
    az login
    echo ""
fi

echo -e "${GREEN}✅ Azure CLI authenticated${NC}"
echo ""

# Show current subscription
CURRENT_SUB=$(az account show --query "name" -o tsv)
echo -e "${BLUE}Current Subscription:${NC} $CURRENT_SUB"
echo ""

echo "1️⃣  Getting VM Public IP..."
VM_IP=$(az vm show -d --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query publicIps -o tsv 2>/dev/null)

if [ -z "$VM_IP" ]; then
    echo -e "${RED}✗ Could not retrieve VM IP address${NC}"
    echo ""
    echo "Possible issues:"
    echo "  • VM doesn't exist in this subscription"
    echo "  • VM is stopped or deallocated"
    echo "  • Wrong subscription selected"
    echo "  • Resource group or VM name is incorrect"
    echo ""
    
    read -p "Do you want to switch subscription? (y/n): " switch
    if [ "$switch" = "y" ] || [ "$switch" = "Y" ]; then
        echo ""
        echo "Available subscriptions:"
        az account list --query "[].{Name:name, ID:id, IsDefault:isDefault}" -o table
        echo ""
        read -p "Enter subscription ID: " sub_id
        
        if [ -n "$sub_id" ]; then
            az account set --subscription "$sub_id"
            echo ""
            echo "Switched to subscription: $(az account show --query name -o tsv)"
            echo ""
            VM_IP=$(az vm show -d --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query publicIps -o tsv 2>/dev/null)
        fi
    fi
    
    if [ -z "$VM_IP" ]; then
        echo ""
        echo -e "${RED}✗ Cannot find VM. Exiting.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ VM IP: $VM_IP${NC}"
echo ""

# Check VM status
echo "2️⃣  Checking VM status..."
VM_STATUS=$(az vm get-instance-view \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
    -o tsv 2>/dev/null)

if [ -z "$VM_STATUS" ]; then
    echo -e "${YELLOW}⚠️  Could not determine VM status${NC}"
    VM_STATUS="Unknown"
else
    echo -e "${BLUE}Status:${NC} $VM_STATUS"
fi

if [ "$VM_STATUS" != "VM running" ] && [ "$VM_STATUS" != "Unknown" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  VM is not running!${NC}"
    echo ""
    read -p "Do you want to start the VM? (y/n): " start_vm
    if [ "$start_vm" = "y" ] || [ "$start_vm" = "Y" ]; then
        echo ""
        echo "Starting VM..."
        az vm start --resource-group "$RESOURCE_GROUP" --name "$VM_NAME"
        echo ""
        echo "Waiting for VM to be ready..."
        sleep 30
        echo -e "${GREEN}✅ VM started${NC}"
    else
        echo ""
        echo "Cannot connect to stopped VM. Exiting."
        exit 1
    fi
fi
echo ""

# Get the public key that's configured on the VM
echo "3️⃣  Retrieving VM's SSH public key..."
VM_PUBLIC_KEY=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "osProfile.linuxConfiguration.ssh.publicKeys[0].keyData" \
    -o tsv 2>/dev/null)

if [ -z "$VM_PUBLIC_KEY" ]; then
    echo -e "${RED}✗ No SSH key found on VM${NC}"
    echo ""
    echo "This VM doesn't have an SSH key configured."
    echo "You need to configure SSH access first."
    exit 1
fi

echo -e "${GREEN}✅ Found SSH key on VM${NC}"
echo ""

# Create temporary key file
TEMP_KEY_DIR="$HOME/.ssh/temp_vm_keys"
mkdir -p "$TEMP_KEY_DIR"
chmod 700 "$TEMP_KEY_DIR"

TEMP_KEY_FILE="$TEMP_KEY_DIR/${ENVIRONMENT}_vm_key"

# Try to find matching private key in common locations
echo "4️⃣  Searching for matching SSH private key..."
FOUND_KEY=""

# Search in .ssh directory
if [ -d "$HOME/.ssh" ]; then
    while IFS= read -r key_file; do
        if [ -f "$key_file" ] && [[ ! "$key_file" == *.pub ]]; then
            # Try to generate public key from private key
            LOCAL_PUB=$(ssh-keygen -y -f "$key_file" 2>/dev/null || echo "")
            if [ -n "$LOCAL_PUB" ]; then
                # Compare with VM's public key
                if [ "$LOCAL_PUB" = "$VM_PUBLIC_KEY" ]; then
                    echo -e "${GREEN}✅ Found matching key: $(basename $key_file)${NC}"
                    FOUND_KEY="$key_file"
                    break
                fi
            fi
        fi
    done < <(find "$HOME/.ssh" -type f -name "id_*" -o -name "*_rsa" -o -name "*_key" 2>/dev/null)
fi

if [ -z "$FOUND_KEY" ]; then
    echo -e "${YELLOW}⚠️  No matching private key found locally${NC}"
    echo ""
    echo "The VM has an SSH key configured, but you don't have the matching private key."
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         OPTIONS TO GET SSH ACCESS                     ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}▶ Option 1: Paste the private key now${NC}"
    echo ""
    echo "   If you have the private key, you can paste it directly."
    echo ""
    
    read -p "Do you want to paste the private key? (y/n): " paste_key
    
    if [ "$paste_key" = "y" ] || [ "$paste_key" = "Y" ]; then
        echo ""
        echo -e "${BLUE}Paste the ENTIRE private key (including BEGIN/END lines)${NC}"
        echo "Press Ctrl+D when done:"
        echo ""
        
        # Read multi-line input
        KEY_CONTENT=""
        while IFS= read -r line; do
            KEY_CONTENT="${KEY_CONTENT}${line}"$'\n'
        done
        
        # Save to temporary file
        echo "$KEY_CONTENT" > "$TEMP_KEY_FILE"
        chmod 600 "$TEMP_KEY_FILE"
        
        # Verify it's a valid key
        if ssh-keygen -y -f "$TEMP_KEY_FILE" &>/dev/null; then
            # Verify it matches the VM's key
            PASTED_PUB=$(ssh-keygen -y -f "$TEMP_KEY_FILE" 2>/dev/null)
            if [ "$PASTED_PUB" = "$VM_PUBLIC_KEY" ]; then
                echo ""
                echo -e "${GREEN}✅ Valid key! Testing connection...${NC}"
                FOUND_KEY="$TEMP_KEY_FILE"
            else
                echo ""
                echo -e "${RED}✗ This key doesn't match the VM's key${NC}"
                rm -f "$TEMP_KEY_FILE"
                exit 1
            fi
        else
            echo ""
            echo -e "${RED}✗ Invalid SSH key format${NC}"
            rm -f "$TEMP_KEY_FILE"
            exit 1
        fi
    else
        echo ""
        echo -e "${BLUE}▶ Option 2: Generate new key pair${NC}"
        echo ""
        echo "   This will create a new SSH key and update the VM."
        echo ""
        
        read -p "Generate new SSH key pair? (y/n): " generate_new
        
        if [ "$generate_new" = "y" ] || [ "$generate_new" = "Y" ]; then
            NEW_KEY_PATH="$HOME/.ssh/${ENVIRONMENT}_vm_key"
            
            echo ""
            echo -e "${BLUE}🔑 Generating new SSH key pair...${NC}"
            
            # Backup old key if exists
            if [ -f "$NEW_KEY_PATH" ]; then
                BACKUP="${NEW_KEY_PATH}.backup.$(date +%s)"
                mv "$NEW_KEY_PATH" "$BACKUP"
                [ -f "${NEW_KEY_PATH}.pub" ] && mv "${NEW_KEY_PATH}.pub" "${BACKUP}.pub"
                echo -e "${YELLOW}Old key backed up to: $BACKUP${NC}"
            fi
            
            ssh-keygen -t rsa -b 4096 -f "$NEW_KEY_PATH" -N "" -C "${ENVIRONMENT}-vm-$(date +%Y%m%d)"
            
            echo -e "${GREEN}✅ SSH key generated${NC}"
            echo ""
            
            # Update VM with new key
            echo -e "${BLUE}📤 Updating VM with new SSH public key...${NC}"
            az vm user update \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VM_NAME" \
                --username "$VM_USERNAME" \
                --ssh-key-value "$(cat ${NEW_KEY_PATH}.pub)"
            
            echo -e "${GREEN}✅ VM updated with new SSH key${NC}"
            echo ""
            echo "⏳ Waiting 20 seconds for Azure to apply changes..."
            sleep 20
            
            FOUND_KEY="$NEW_KEY_PATH"
            
            echo ""
            echo -e "${YELLOW}📋 Save these keys for future access:${NC}"
            echo ""
            echo -e "${BLUE}Private Key (keep secret!):${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            cat "$NEW_KEY_PATH"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo -e "${BLUE}Public Key:${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            cat "${NEW_KEY_PATH}.pub"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
        else
            echo ""
            echo "Exiting. Cannot connect without a valid SSH key."
            exit 1
        fi
    fi
fi

# At this point, FOUND_KEY should have a valid key
if [ -n "$FOUND_KEY" ]; then
    # Ensure correct permissions
    chmod 600 "$FOUND_KEY"
    
    echo ""
    echo "5️⃣  Testing SSH connection..."
    
    if ssh -i "$FOUND_KEY" \
        -o ConnectTimeout=15 \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        "$VM_USERNAME@$VM_IP" "echo 'Connection test successful'" &>/dev/null; then
        
        echo -e "${GREEN}✅ Connection test successful!${NC}"
        echo ""
        echo "=============================="
        echo -e "${GREEN}✅ READY TO CONNECT${NC}"
        echo "=============================="
        echo ""
        echo -e "${BLUE}Environment:${NC} $ENV_DISPLAY"
        echo -e "${BLUE}VM IP:${NC} $VM_IP"
        echo -e "${BLUE}Username:${NC} $VM_USERNAME"
        echo ""
        echo "Connecting to VM..."
        echo "=============================="
        echo ""
        
        # Always clean application folders before connecting
        echo ""
        echo "6️⃣  Cleaning application folders..."
        ssh -i "$FOUND_KEY" \
            -o ConnectTimeout=15 \
            -o StrictHostKeyChecking=no \
            "$VM_USERNAME@$VM_IP" \
            "rm -rf ~/nifi-cicd ~/*-backups ~/deployment-* 2>/dev/null || true" 2>/dev/null
        
        echo -e "${GREEN}✅ Application folders cleaned${NC}"
        echo ""
        echo "=============================="
        echo "Connecting to VM..."
        echo "=============================="
        echo ""
        
        ssh -i "$FOUND_KEY" "$VM_USERNAME@$VM_IP"
        
        # Cleanup temp key if used
        if [[ "$FOUND_KEY" == *"/temp_vm_keys/"* ]]; then
            rm -f "$FOUND_KEY"
        fi
        
        exit 0
    else
        echo -e "${RED}✗ Connection test failed${NC}"
        echo ""
        echo "This might be a Network Security Group (NSG) issue."
        echo ""
        echo -e "${BLUE}Your current public IP:${NC} $(curl -s ifconfig.me 2>/dev/null || echo 'Unable to detect')"
        echo ""
        echo "Try adding your IP to the NSG:"
        echo ""
        echo "az network nsg rule create \\"
        echo "  --resource-group $RESOURCE_GROUP \\"
        echo "  --nsg-name ${VM_NAME}-nsg \\"
        echo "  --name AllowMyIP \\"
        echo "  --priority 1010 \\"
        echo "  --source-address-prefixes \$(curl -s ifconfig.me)/32 \\"
        echo "  --destination-port-ranges 22 \\"
        echo "  --access Allow \\"
        echo "  --protocol Tcp"
        echo ""
        
        # Cleanup temp key if used
        if [[ "$FOUND_KEY" == *"/temp_vm_keys/"* ]]; then
            rm -f "$FOUND_KEY"
        fi
        
        exit 1
    fi
fi

echo ""
echo -e "${RED}✗ Unexpected error. Could not establish connection.${NC}"
exit 1