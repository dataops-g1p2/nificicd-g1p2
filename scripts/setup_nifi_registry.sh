#!/bin/bash

# Enhanced Setup NiFi Registry Script
# This script creates buckets in NiFi Registry for all flows in the flows/ directory
# Version: 2.2.0

set -e

# Configuration
REGISTRY_URL="${REGISTRY_URL:-http://localhost:18080}"
REGISTRY_CLIENT_URL="${REGISTRY_CLIENT_URL:-http://nifi-registry:18080}"
FLOWS_DIR="${FLOWS_DIR:-./flows}"
DEFAULT_BUCKET="nifi-flows"
CREATE_PER_FLOW_BUCKETS="${CREATE_PER_FLOW_BUCKETS:-false}"
SPECIFIC_FLOW="${SPECIFIC_FLOW:-}"
SPECIFIC_FLOWS="${SPECIFIC_FLOWS:-}"
SKIP_DEFAULT_BUCKET="${SKIP_DEFAULT_BUCKET:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Utility functions
info() {
    echo -e "${CYAN}$1${NC}"
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warning() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}

highlight() {
    echo -e "${MAGENTA}$1${NC}"
}

echo "══════════════════════════════════"
echo "  NiFi Registry Setup - Enhanced  "
echo "══════════════════════════════════"
info "Registry URL: $REGISTRY_URL"
info "Registry Client URL: $REGISTRY_CLIENT_URL"
info "Flows Directory: $FLOWS_DIR"
info "Create per-flow buckets: $CREATE_PER_FLOW_BUCKETS"
info "Skip default bucket: $SKIP_DEFAULT_BUCKET"
if [ -n "$SPECIFIC_FLOW" ]; then
    info "Specific flow: $SPECIFIC_FLOW"
elif [ -n "$SPECIFIC_FLOWS" ]; then
    info "Specific flows: $SPECIFIC_FLOWS"
fi
echo ""

# Wait for NiFi Registry to be ready
info "Waiting for NiFi Registry to be ready..."
max_attempts=30
attempt=0
while ! curl -sf "$REGISTRY_URL/nifi-registry" > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        error "NiFi Registry did not start in time"
        exit 1
    fi
    echo "   Attempt $attempt/$max_attempts - waiting..."
    sleep 2
done

success "NiFi Registry is ready!"
echo ""

# Function to create a bucket
create_bucket() {
    local bucket_name=$1
    local description=$2

    info "Creating bucket: $bucket_name"

    local bucket_data=$(cat <<EOF
{
  "name": "$bucket_name",
  "description": "$description",
  "allowPublicRead": false
}
EOF
)

    local response=$(curl -s -X POST "$REGISTRY_URL/nifi-registry-api/buckets" \
        -H "Content-Type: application/json" \
        -d "$bucket_data" \
        -w "\n%{http_code}" 2>&1)

    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        success "  Bucket '$bucket_name' created successfully!"
        if command -v jq >/dev/null 2>&1; then
            echo "$body" | jq -r '"  ID: \(.identifier)"' 2>/dev/null || true
        fi
        return 0
    elif [ "$http_code" = "409" ]; then
        warning "  Bucket '$bucket_name' already exists"
        return 0
    else
        error "  Failed to create bucket (HTTP $http_code)"
        if [ -n "$body" ]; then
            echo "  Response: $body"
        fi
        return 1
    fi
}

# Create default bucket (skip if SKIP_DEFAULT_BUCKET is true)
if [ "$SKIP_DEFAULT_BUCKET" = "true" ]; then
    info "Skipping default bucket creation (already exists)"
    echo ""
else
    create_bucket "$DEFAULT_BUCKET" "Default bucket for storing all NiFi flow versions"
    echo ""
fi

# Check if flows directory exists
if [ ! -d "$FLOWS_DIR" ]; then
    warning "Flows directory not found: $FLOWS_DIR"
    warning "Skipping per-flow bucket creation"
else
    # Determine which flows to process
    if [ -n "$SPECIFIC_FLOW" ]; then
        # Single specific flow
        if [ -f "$FLOWS_DIR/$SPECIFIC_FLOW.json" ]; then
            flow_files=("$FLOWS_DIR/$SPECIFIC_FLOW.json")
            info "Processing specific flow: $SPECIFIC_FLOW"
        else
            error "Flow file not found: $FLOWS_DIR/$SPECIFIC_FLOW.json"
            exit 1
        fi
    elif [ -n "$SPECIFIC_FLOWS" ]; then
        # Multiple specific flows (comma-separated)
        IFS=',' read -ra FLOW_ARRAY <<< "$SPECIFIC_FLOWS"
        flow_files=()
        info "Processing specific flows: $SPECIFIC_FLOWS"
        echo ""
        for flow in "${FLOW_ARRAY[@]}"; do
            # Trim whitespace
            flow=$(echo "$flow" | xargs)
            if [ -f "$FLOWS_DIR/$flow.json" ]; then
                flow_files+=("$FLOWS_DIR/$flow.json")
                info "  Found: $flow.json"
            else
                warning "  Flow file not found: $FLOWS_DIR/$flow.json (skipping)"
            fi
        done

        if [ ${#flow_files[@]} -eq 0 ]; then
            error "None of the specified flows were found"
            exit 1
        fi
    else
        # All flows in directory
        flow_files=($(find "$FLOWS_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | sort))
        info "Processing all flows in directory"
    fi

    if [ ${#flow_files[@]} -eq 0 ]; then
        warning "No flow files found to process"
    else
        info "Found ${#flow_files[@]} flow file(s) to process"
        echo ""

        # List flows
        echo "Flow Files to Process:"
        for flow_file in "${flow_files[@]}"; do
            flow_name=$(basename "$flow_file" .json)
            echo "  • $flow_name"
        done
        echo ""

        # Create per-flow buckets if enabled
        if [ "$CREATE_PER_FLOW_BUCKETS" = "true" ]; then
            info "Creating individual buckets for each flow..."
            echo ""

            bucket_count=0
            for flow_file in "${flow_files[@]}"; do
                flow_name=$(basename "$flow_file" .json)

                # Convert flow name to bucket-friendly format
                # Remove special characters, convert to lowercase
                bucket_name=$(echo "$flow_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

                # Ensure bucket name is not too long (max 100 chars for safety)
                if [ ${#bucket_name} -gt 100 ]; then
                    bucket_name="${bucket_name:0:100}"
                fi

                if create_bucket "$bucket_name" "Bucket for $flow_name flow versions"; then
                    bucket_count=$((bucket_count + 1))
                fi
            done
            echo ""
            success "Created/verified $bucket_count bucket(s) for flows"
            echo ""
        else
            info "Per-flow buckets disabled (set CREATE_PER_FLOW_BUCKETS=true to enable)"
            info "All flows will use the default bucket: $DEFAULT_BUCKET"
            echo ""
        fi
    fi
fi

# List all buckets
echo "════════════════════════════"
echo "  Registry Buckets Summary  "
echo "════════════════════════════"
info "Listing all buckets in registry..."
echo ""

buckets_response=$(curl -s "$REGISTRY_URL/nifi-registry-api/buckets")

if command -v jq >/dev/null 2>&1; then
    bucket_count=$(echo "$buckets_response" | jq 'length' 2>/dev/null || echo "0")

    if [ "$bucket_count" -gt 0 ]; then
        success "Total buckets: $bucket_count"
        echo ""
        echo "$buckets_response" | jq -r '.[] | " \(.name)\n     ID: \(.identifier)\n     Created: \(.createdTimestamp | . / 1000 | strftime("%Y-%m-%d %H:%M:%S"))\n"' 2>/dev/null || \
        echo "$buckets_response" | jq '.'
    else
        warning "No buckets found in registry"
    fi
else
    echo "$buckets_response"
fi

echo ""
echo "══════════════"
echo "  Next Steps  "
echo "══════════════"
echo ""
echo "1. 🌐 Access NiFi Registry:"
echo "   ${BLUE}$REGISTRY_URL/nifi-registry${NC}"
echo ""
echo "2. 🔗 Connect NiFi to Registry:"
echo "   a) In NiFi, click hamburger menu (☰) → Controller Settings"
echo "   b) Go to 'Registry Clients' tab"
echo "   c) Click '+' to add new Registry Client:"
echo "      • Name: ${CYAN}NiFi Registry${NC}"
highlight "      • URL: ${CYAN}${REGISTRY_CLIENT_URL}${NC}"
echo ""
echo "   ${YELLOW}💡 Important URL Configuration:${NC}"
echo "   ${CYAN}   For Local Docker:${NC} http://nifi-registry:18080"
echo "   ${CYAN}   For Azure/Remote:${NC} http://<VM_PUBLIC_IP>:18080"
echo ""
echo "   d) Click 'Add' to save"
echo ""
echo "3. Version Control Your Flows:"
echo "   a) Right-click on any Process Group"
echo "   b) Select ${CYAN}Version → Start version control${NC}"
echo "   c) Choose bucket: ${CYAN}$DEFAULT_BUCKET${NC}"
echo "   d) Enter flow name and commit message"
echo ""
echo "4. Import Flows to Registry:"
echo "   ${CYAN}make import-flows-auto${NC}  (imports all flows)"
echo "   ${CYAN}make import-flow FLOW=MyFlow${NC}  (import specific flow)"
echo ""
echo "5. Export Flow from Registry:"
echo "   ${CYAN}make export-flow-from-registry${NC}"
echo "   ${CYAN}make export-flows-from-registry${NC}  (export all)"
echo ""
echo "6. Create Buckets for Specific Flows:"
echo "   ${CYAN}make setup-registry-buckets FLOW=MyFlow${NC}  (single flow)"
echo "   ${CYAN}make setup-registry-buckets FLOWS=Flow1,Flow2${NC}  (multiple flows)"
echo ""

if [ "$CREATE_PER_FLOW_BUCKETS" = "true" ]; then
    echo "Per-flow buckets created:"
    echo "   You can now version each flow in its own bucket for better organization"
    echo ""
fi

if [ -n "$SPECIFIC_FLOW" ]; then
    bucket_name=$(echo "$SPECIFIC_FLOW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    echo "Bucket created for flow:"
    echo "  Flow: ${CYAN}$SPECIFIC_FLOW${NC}"
    echo "  Bucket: ${CYAN}$bucket_name${NC}"
    echo ""
elif [ -n "$SPECIFIC_FLOWS" ]; then
    echo "Buckets created for specified flows:"
    IFS=',' read -ra FLOW_ARRAY <<< "$SPECIFIC_FLOWS"
    for flow in "${FLOW_ARRAY[@]}"; do
        flow=$(echo "$flow" | xargs)
        bucket_name=$(echo "$flow" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
        echo "   ${CYAN}$flow${NC} → ${CYAN}$bucket_name${NC}"
    done
    echo ""
fi

# Save registry connection info to a file for easy reference
CONNECTION_INFO_FILE="$FLOWS_DIR/registry-connection-info.txt"
cat > "$CONNECTION_INFO_FILE" << EOF
═══════════════════════════════════════
 NiFi Registry Connection Information
═══════════════════════════════════════
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Registry Client URL (for NiFi):
  ${REGISTRY_CLIENT_URL}

Registry Web UI:
  ${REGISTRY_URL}/nifi-registry

Default Bucket:
  ${DEFAULT_BUCKET}

Quick Reference:
  - This URL is used when configuring the Registry Client in NiFi
  - In Controller Settings → Registry Clients → Add
  - Copy the URL above into the "URL" field

Environment-specific URLs:
  Local Docker:  http://nifi-registry:18080
  Development:   http://<DEV_VM_IP>:18080
  Staging:       http://<STAGING_VM_IP>:18080
  Production:    http://<PROD_VM_IP>:18080

Command Examples:
  Setup all buckets:       make setup-registry-buckets
  Setup specific flow:     make setup-registry-buckets FLOW=MyFlow
  Setup multiple flows:    make setup-registry-buckets FLOWS=Flow1,Flow2,Flow3
EOF

success "Connection info saved to: $CONNECTION_INFO_FILE"
echo ""

echo "════════════════════════════════════"
success "NiFi Registry setup complete! 🎉 "
echo "════════════════════════════════════"
echo ""
highlight "Registry Client URL for NiFi: ${REGISTRY_CLIENT_URL}"
echo ""

exit 0