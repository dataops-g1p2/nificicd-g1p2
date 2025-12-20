#!/bin/bash

################################################################################
# NiFi Registry Flow Export Tool - Production Version
################################################################################
# This script exports flow definitions from NiFi Registry
# Supports:
#   - Interactive mode: Select bucket and flow to export
#   - List mode: Display available buckets and flows
#   - Auto-commit: Automatically commit exported flows to Git
#   - Direct export: Use --bucket-id and --flow-id for automation
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Default configuration
REGISTRY_URL="${REGISTRY_URL:-http://localhost:18080}"
OUTPUT_DIR="${OUTPUT_DIR:-./flows}"
AUTO_COMMIT="${AUTO_COMMIT:-false}"
DEBUG="${DEBUG:-false}"

# Parse command line arguments
LIST_BUCKETS=false
LIST_FLOWS=false
LIST_VERSIONS=false
BUCKET_ID=""
FLOW_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --list-buckets)
            LIST_BUCKETS=true
            shift
            ;;
        --list-flows)
            LIST_FLOWS=true
            shift
            ;;
        --list-versions)
            LIST_VERSIONS=true
            shift
            ;;
        --bucket-id)
            BUCKET_ID="$2"
            shift 2
            ;;
        --flow-id)
            FLOW_ID="$2"
            shift 2
            ;;
        --auto-commit)
            AUTO_COMMIT=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help)
            cat << 'EOF'
NiFi Registry Flow Export Tool

Usage:
  export-flow.sh [OPTIONS]

Options:
  --list-buckets          List all buckets in Registry
  --list-flows            List flows in a bucket (requires --bucket-id or interactive)
  --list-versions         List all flows and their versions
  --bucket-id ID          Specify bucket ID for export
  --flow-id ID            Specify flow ID for export
  --auto-commit           Automatically commit exported flows to Git
  --debug                 Enable debug output
  --help                  Show this help message

Environment Variables:
  REGISTRY_URL            NiFi Registry URL (default: http://localhost:18080)
  OUTPUT_DIR              Output directory for flows (default: ./flows)
  AUTO_COMMIT             Auto-commit to Git (default: false)
  DEBUG                   Debug mode (default: false)

Examples:
  # Interactive mode
  export-flow.sh

  # List all buckets
  export-flow.sh --list-buckets

  # Export specific flow
  export-flow.sh --bucket-id <bucket-id> --flow-id <flow-id>

  # Export with auto-commit
  export-flow.sh --bucket-id <bucket-id> --flow-id <flow-id> --auto-commit

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}▶${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✅${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC}  $1" >&2
}

log_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

header() {
    echo "" >&2
    echo "╔═══════════════════════════════════════════════╗" >&2
    echo "║        NiFi Registry Flow Export Tool         ║" >&2
    echo "╚═══════════════════════════════════════════════╝" >&2
    echo "" >&2
}

print_info() {
    echo -e "${CYAN}[INFO]${NC}  Configuration:" >&2
    echo "  Registry URL: $REGISTRY_URL" >&2
    echo "  Output Dir:   $OUTPUT_DIR" >&2
    echo "  Auto-commit:  $AUTO_COMMIT" >&2
    echo "  Debug:        $DEBUG" >&2
    echo "" >&2
}

# Check if NiFi Registry is available
check_registry() {
    log_info "Checking NiFi Registry availability..."
    
    local access_url="$REGISTRY_URL/nifi-registry-api/access"
    
    if ! curl -sf "$access_url" > /dev/null 2>&1; then
        log_error "Cannot connect to NiFi Registry at $REGISTRY_URL"
        
        # Diagnostic info
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$access_url" 2>/dev/null || echo "000")
        
        echo "" >&2
        echo "Diagnostics:" >&2
        echo "  URL: $access_url" >&2
        echo "  HTTP Code: $http_code" >&2
        echo "" >&2
        
        log_warning "Make sure NiFi Registry is running and accessible"
        return 1
    fi
    
    log_success "NiFi Registry is ready"
    return 0
}

# Fetch all buckets
fetch_buckets() {
    log_debug "Fetching buckets from $REGISTRY_URL/nifi-registry-api/buckets"
    
    local response
    response=$(curl -sf "$REGISTRY_URL/nifi-registry-api/buckets" 2>/dev/null)
    
    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        log_error "No buckets found in Registry"
        return 1
    fi
    
    echo "$response"
}

# Display buckets
display_buckets() {
    local buckets="${1:-}"
    
    if [ -z "$buckets" ]; then
        log_error "No buckets data provided"
        return 1
    fi
    
    echo "" >&2
    echo "╔═══════════════════════════════════════════╗" >&2
    echo "║       Available Buckets in Registry       ║" >&2
    echo "╚═══════════════════════════════════════════╝" >&2
    echo "" >&2
    
    local count=0
    while IFS= read -r bucket; do
        if [ -n "$bucket" ] && [ "$bucket" != "null" ]; then
            local name
            local id
            local desc
            local created
            
            name=$(echo "$bucket" | jq -r '.name // "Unknown"')
            id=$(echo "$bucket" | jq -r '.identifier // "Unknown"')
            desc=$(echo "$bucket" | jq -r '.description // "No description"')
            created=$(echo "$bucket" | jq -r '.createdTimestamp // "Unknown"')
            
            # Format timestamp
            if [ "$created" != "Unknown" ] && [ "$created" != "null" ]; then
                created=$(date -d "@$((created / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$created")
            fi
            
            echo -e "  ${GREEN}[BUCKET]${NC} ${BLUE}$name${NC}" >&2
            echo "     ID: $id" >&2
            echo "     Description: $desc" >&2
            echo "     Created: $created" >&2
            echo "" >&2
            
            ((count++)) || true
        fi
    done < <(echo "$buckets" | jq -c '.[]' 2>/dev/null || echo "")
    
    echo "Total buckets: $count" >&2
    echo "" >&2
}

# Fetch flows from a bucket
fetch_flows() {
    local bucket_id="$1"
    
    log_debug "Fetching flows from bucket: $bucket_id"
    
    local response
    response=$(curl -sf "$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows" 2>/dev/null)
    
    if [ -z "$response" ]; then
        log_error "Failed to fetch flows from bucket"
        return 1
    fi
    
    echo "$response"
}

# Display flows
display_flows() {
    local flows="${1:-}"
    local bucket_name="${2:-Unknown}"
    
    if [ -z "$flows" ]; then
        log_error "No flows data provided"
        return 1
    fi
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "      Flows in Bucket: $bucket_name       " >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    local flow_count
    flow_count=$(echo "$flows" | jq '. | length' 2>/dev/null || echo "0")
    
    if ! [[ "$flow_count" =~ ^[0-9]+$ ]] || [ "$flow_count" -eq 0 ]; then
        log_warning "No flows found in this bucket"
        echo "" >&2
        return 0
    fi
    
    local index=1
    while IFS= read -r flow; do
        if [ -n "$flow" ] && [ "$flow" != "null" ]; then
            local name
            local id
            local desc
            local modified
            
            name=$(echo "$flow" | jq -r '.name // "Unknown"')
            id=$(echo "$flow" | jq -r '.identifier // "Unknown"')
            desc=$(echo "$flow" | jq -r '.description // "No description"')
            modified=$(echo "$flow" | jq -r '.modifiedTimestamp // "Unknown"')
            
            # Format timestamp
            if [ "$modified" != "Unknown" ] && [ "$modified" != "null" ]; then
                modified=$(date -d "@$((modified / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$modified")
            fi
            
            echo -e "  ${CYAN}[$index]${NC} ${GREEN}[FLOW]${NC} ${BLUE}$name${NC}" >&2
            echo "       ID: $id" >&2
            echo "       Description: $desc" >&2
            echo "       Last Modified: $modified" >&2
            echo "" >&2
            
            ((index++)) || true
        fi
    done < <(echo "$flows" | jq -c '.[]' 2>/dev/null || echo "")
    
    echo "Total flows: $((index - 1))" >&2
    echo "" >&2
}

# Get flow versions
get_flow_versions() {
    local bucket_id="$1"
    local flow_id="$2"
    
    log_debug "Fetching versions for flow: $flow_id in bucket: $bucket_id"
    
    local response
    response=$(curl -sf "$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows/$flow_id/versions" 2>/dev/null)
    
    if [ -z "$response" ]; then
        log_error "Failed to fetch flow versions"
        return 1
    fi
    
    echo "$response"
}

# Export flow version
export_flow_version() {
    local bucket_id="$1"
    local flow_id="$2"
    local version="$3"
    local flow_name="$4"
    
    log_info "Exporting flow '$flow_name' version $version..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Sanitize flow name for filename
    local safe_name
    safe_name=$(echo "$flow_name" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    local output_file="$OUTPUT_DIR/${safe_name}.json"
    
    # Fetch flow version
    local flow_content
    flow_content=$(curl -sf "$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows/$flow_id/versions/$version" 2>/dev/null)
    
    if [ -z "$flow_content" ]; then
        log_error "Failed to export flow version"
        return 1
    fi
    
    # Validate JSON
    if ! echo "$flow_content" | jq empty 2>/dev/null; then
        log_error "Invalid JSON received for flow"
        return 1
    fi
    
    # Save to file with pretty formatting
    echo "$flow_content" | jq '.' > "$output_file"
    
    log_success "Flow exported to: $output_file"
    
    # Auto-commit if enabled
    if [ "$AUTO_COMMIT" = true ]; then
        commit_to_git "$output_file" "$flow_name" "$version"
    fi
}

# Commit exported flow to Git
commit_to_git() {
    local file="$1"
    local flow_name="$2"
    local version="$3"
    
    log_info "Committing to Git..."
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warning "Not a Git repository. Skipping commit."
        return 0
    fi
    
    git add "$file"
    
    if git diff --staged --quiet; then
        log_warning "No changes to commit"
        return 0
    fi
    
    git commit -m "Export NiFi flow: $flow_name (v$version)" \
               -m "Exported from NiFi Registry" \
               -m "Flow: $flow_name" \
               -m "Version: $version" \
               -m "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    
    log_success "Changes committed to Git"
}

# Interactive bucket selection
select_bucket_interactive() {
    local buckets="${1:-}"
    
    if [ -z "$buckets" ]; then
        log_error "No buckets data provided"
        return 1
    fi
    
    local bucket_count
    bucket_count=$(echo "$buckets" | jq '. | length' 2>/dev/null || echo "0")
    
    if ! [[ "$bucket_count" =~ ^[0-9]+$ ]] || [ "$bucket_count" -eq 0 ]; then
        log_error "No buckets available"
        return 1
    fi
    
    if [ "$bucket_count" -eq 1 ]; then
        local bucket_name
        bucket_name=$(echo "$buckets" | jq -r '.[0].name')
        log_info "Using only available bucket: $bucket_name"
        echo "$buckets" | jq -r '.[0].identifier'
        return 0
    fi
    
    display_buckets "$buckets"
    
    echo "" >&2
    read -p "Enter bucket number (1-$bucket_count) or bucket ID: " selection >&2
    
    if [ -z "$selection" ]; then
        log_error "No selection provided"
        return 1
    fi
    
    # Check if selection is a number
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [ "$selection" -lt 1 ] || [ "$selection" -gt "$bucket_count" ]; then
            log_error "Invalid selection: must be between 1 and $bucket_count"
            return 1
        fi
        local index=$((selection - 1))
        local bucket_id
        bucket_id=$(echo "$buckets" | jq -r ".[$index].identifier")
        if [ -z "$bucket_id" ] || [ "$bucket_id" = "null" ]; then
            log_error "Failed to get bucket ID"
            return 1
        fi
        echo "$bucket_id"
    else
        # Assume it's a bucket ID
        local exists
        exists=$(echo "$buckets" | jq -r ".[] | select(.identifier == \"$selection\") | .identifier")
        if [ -z "$exists" ] || [ "$exists" = "null" ]; then
            log_error "Bucket ID not found: $selection"
            return 1
        fi
        echo "$selection"
    fi
}

# Interactive flow selection
select_flow_interactive() {
    local flows="${1:-}"
    
    if [ -z "$flows" ]; then
        log_error "No flows data provided"
        return 1
    fi
    
    local flow_count
    flow_count=$(echo "$flows" | jq '. | length' 2>/dev/null || echo "0")
    
    if ! [[ "$flow_count" =~ ^[0-9]+$ ]] || [ "$flow_count" -eq 0 ]; then
        log_error "No flows available to select"
        return 1
    fi
    
    echo "" >&2
    read -p "Enter flow number (1-$flow_count) or flow ID: " selection >&2
    
    if [ -z "$selection" ]; then
        log_error "No selection provided"
        return 1
    fi
    
    # Check if selection is a number
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [ "$selection" -lt 1 ] || [ "$selection" -gt "$flow_count" ]; then
            log_error "Invalid selection: must be between 1 and $flow_count"
            return 1
        fi
        local index=$((selection - 1))
        local flow_id
        local flow_name
        flow_id=$(echo "$flows" | jq -r ".[$index].identifier")
        flow_name=$(echo "$flows" | jq -r ".[$index].name")
        
        if [ -z "$flow_id" ] || [ "$flow_id" = "null" ]; then
            log_error "Failed to get flow ID"
            return 1
        fi
        
        echo "$flow_id|$flow_name"
    else
        # Assume it's a flow ID
        local flow_name
        flow_name=$(echo "$flows" | jq -r ".[] | select(.identifier == \"$selection\") | .name")
        
        if [ -z "$flow_name" ] || [ "$flow_name" = "null" ]; then
            log_error "Flow ID not found: $selection"
            return 1
        fi
        
        echo "$selection|$flow_name"
    fi
}

# Display all versions
display_all_versions() {
    local buckets="${1:-}"
    
    if [ -z "$buckets" ]; then
        log_error "No buckets data provided"
        return 1
    fi
    
    local total_buckets=0
    local total_flows=0
    local total_versions=0
    
    while IFS= read -r bucket; do
        if [ -n "$bucket" ] && [ "$bucket" != "null" ]; then
            local bucket_name
            local bucket_id
            bucket_name=$(echo "$bucket" | jq -r '.name // "Unknown"')
            bucket_id=$(echo "$bucket" | jq -r '.identifier // "Unknown"')
            
            ((total_buckets++)) || true
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo -e "${MAGENTA}BUCKET:${NC} ${BLUE}$bucket_name${NC}    " >&2
            echo "   ID: $bucket_id                                     " >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            
            local flows
            flows=$(fetch_flows "$bucket_id")
            local flow_count
            flow_count=$(echo "$flows" | jq '. | length' 2>/dev/null || echo "0")
            
            if ! [[ "$flow_count" =~ ^[0-9]+$ ]] || [ "$flow_count" -eq 0 ]; then
                echo -e "   ${YELLOW}No flows in this bucket${NC}" >&2
                echo "" >&2
                continue
            fi
            
            while IFS= read -r flow; do
                if [ -n "$flow" ] && [ "$flow" != "null" ]; then
                    local flow_name
                    local flow_id
                    flow_name=$(echo "$flow" | jq -r '.name // "Unknown"')
                    flow_id=$(echo "$flow" | jq -r '.identifier // "Unknown"')
                    
                    ((total_flows++)) || true
                    
                    echo ""
                    echo -e "   ${GREEN}FLOW:${NC} ${CYAN}$flow_name${NC}" >&2
                    echo "      ID: $flow_id" >&2
                    
                    local versions
                    versions=$(get_flow_versions "$bucket_id" "$flow_id")
                    local version_count
                    version_count=$(echo "$versions" | jq '. | length' 2>/dev/null || echo "0")
                    
                    if ! [[ "$version_count" =~ ^[0-9]+$ ]] || [ "$version_count" -eq 0 ]; then
                        echo -e "      ${YELLOW}No versions found${NC}" >&2
                        continue
                    fi
                    
                    echo -e "      ${BLUE}Versions (${version_count} total):${NC}" >&2
                    echo "" >&2
                    
                    local ver_index=1
                    while IFS= read -r version; do
                        if [ -n "$version" ] && [ "$version" != "null" ]; then
                            local ver_num
                            local ver_comment
                            local ver_timestamp
                            
                            ver_num=$(echo "$version" | jq -r '.version // "Unknown"')
                            ver_comment=$(echo "$version" | jq -r '.comments // "No comment"')
                            ver_timestamp=$(echo "$version" | jq -r '.timestamp // "Unknown"')
                            
                            if [ "$ver_timestamp" != "Unknown" ] && [ "$ver_timestamp" != "null" ]; then
                                ver_timestamp=$(date -d "@$((ver_timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ver_timestamp")
                            fi
                            
                            ((total_versions++)) || true
                            
                            if [ "$ver_index" -eq 1 ]; then
                                echo -e "      ${GREEN}▸ Version $ver_num${NC} ${YELLOW}(LATEST)${NC}" >&2
                            else
                                echo -e "      ${CYAN}▸ Version $ver_num${NC}" >&2
                            fi
                            
                            echo "         Comment: $ver_comment" >&2
                            echo "         Date: $ver_timestamp" >&2
                            echo "" >&2
                            
                            ((ver_index++)) || true
                        fi
                    done < <(echo "$versions" | jq -c '.[]' 2>/dev/null || echo "")
                fi
            done < <(echo "$flows" | jq -c '.[]' 2>/dev/null || echo "")
        fi
    done < <(echo "$buckets" | jq -c '.[]' 2>/dev/null || echo "")
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo -e "${GREEN}SUMMARY${NC}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "   Total Buckets: $total_buckets" >&2
    echo "   Total Flows: $total_flows" >&2
    echo "   Total Versions: $total_versions" >&2
    echo "" >&2
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    header
    print_info
    
    if ! check_registry; then
        exit 1
    fi
    
    # List buckets mode
    if [ "$LIST_BUCKETS" = true ]; then
        log_info "Fetching buckets from Registry..."
        buckets=$(fetch_buckets)
        display_buckets "$buckets"
        exit 0
    fi
    
    # List versions mode
    if [ "$LIST_VERSIONS" = true ]; then
        log_info "Fetching all buckets and their flow versions..."
        buckets=$(fetch_buckets)
        echo "" >&2
        echo "╔════════════════════════════════════════════╗" >&2
        echo "║     All Flows and Versions in Registry     ║" >&2
        echo "╚════════════════════════════════════════════╝" >&2
        display_all_versions "$buckets"
        exit 0
    fi
    
    # Fetch buckets
    log_info "Fetching available buckets..."
    buckets=$(fetch_buckets)
    
    # Select or validate bucket
    if [ -z "$BUCKET_ID" ]; then
        BUCKET_ID=$(select_bucket_interactive "$buckets")
        if [ $? -ne 0 ] || [ -z "$BUCKET_ID" ]; then
            log_error "Failed to select bucket"
            exit 1
        fi
    fi
    
    # Validate bucket and get name
    bucket_name=$(echo "$buckets" | jq -r ".[] | select(.identifier == \"$BUCKET_ID\") | .name")
    if [ -z "$bucket_name" ] || [ "$bucket_name" = "null" ]; then
        log_error "Bucket not found with ID: $BUCKET_ID"
        exit 1
    fi
    
    log_info "Selected bucket: $bucket_name"
    
    # List flows mode
    if [ "$LIST_FLOWS" = true ]; then
        flows=$(fetch_flows "$BUCKET_ID")
        if [ $? -ne 0 ]; then
            log_error "Failed to fetch flows"
            exit 1
        fi
        display_flows "$flows" "$bucket_name"
        exit 0
    fi
    
    # Fetch flows
    log_info "Fetching flows from bucket..."
    flows=$(fetch_flows "$BUCKET_ID")
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch flows"
        exit 1
    fi
    
    # Display flows if interactive
    if [ -z "$FLOW_ID" ]; then
        display_flows "$flows" "$bucket_name"
        
        flow_count=$(echo "$flows" | jq '. | length' 2>/dev/null || echo "0")
        if ! [[ "$flow_count" =~ ^[0-9]+$ ]] || [ "$flow_count" -eq 0 ]; then
            log_error "No flows available in this bucket"
            exit 1
        fi
    fi
    
    # Select or validate flow
    if [ -z "$FLOW_ID" ]; then
        flow_info=$(select_flow_interactive "$flows")
        if [ $? -ne 0 ] || [ -z "$flow_info" ]; then
            log_error "Failed to select flow"
            exit 1
        fi
        FLOW_ID=$(echo "$flow_info" | cut -d'|' -f1)
        flow_name=$(echo "$flow_info" | cut -d'|' -f2)
    else
        flow_name=$(echo "$flows" | jq -r ".[] | select(.identifier == \"$FLOW_ID\") | .name")
        if [ -z "$flow_name" ] || [ "$flow_name" = "null" ]; then
            log_error "Flow not found with ID: $FLOW_ID"
            exit 1
        fi
    fi
    
    log_info "Selected flow: $flow_name"
    
    # Get versions
    log_info "Fetching flow versions..."
    versions=$(get_flow_versions "$BUCKET_ID" "$FLOW_ID")
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch flow versions"
        exit 1
    fi
    
    version_count=$(echo "$versions" | jq '. | length' 2>/dev/null || echo "0")
    if ! [[ "$version_count" =~ ^[0-9]+$ ]] || [ "$version_count" -eq 0 ]; then
        log_error "No versions found for this flow"
        exit 1
    fi
    
    log_info "Found $version_count version(s)"
    
    # Get latest version
    latest_version=$(echo "$versions" | jq -r '.[0].version // 1')
    log_info "Latest version: $latest_version"
    
    # Export
    export_flow_version "$BUCKET_ID" "$FLOW_ID" "$latest_version" "$flow_name"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to export flow"
        exit 1
    fi
    
    echo "" >&2
    log_success "Export complete!"
    echo "" >&2
}

main "$@"