#!/bin/bash

################################################################################
# Export All Flows from NiFi Registry - Production Version
################################################################################
# This script exports all flows from all buckets in NiFi Registry
# and saves them to the flows/ directory
#
# Features:
# - Robust error handling and detailed logging
# - Graceful handling of empty registries
# - Comprehensive diagnostics on failure
# - Proper exit codes for CI/CD integration
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
REGISTRY_URL="${REGISTRY_URL:-http://localhost:18080}"
OUTPUT_DIR="${OUTPUT_DIR:-./flows}"
DEBUG="${DEBUG:-false}"

# Statistics
TOTAL_BUCKETS=0
TOTAL_FLOWS=0
TOTAL_EXPORTED=0
TOTAL_FAILED=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}▶${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC}  $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${CYAN}🔍${NC} DEBUG: $1"
    fi
}

header() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║  Export All Flows from NiFi Registry  ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
}

# Enhanced registry check with detailed diagnostics
check_registry() {
    log_info "Checking NiFi Registry availability..."
    
    local access_url="$REGISTRY_URL/nifi-registry-api/access"
    log_debug "Testing URL: $access_url"
    
    if ! curl -sf "$access_url" > /dev/null 2>&1; then
        log_error "Cannot connect to NiFi Registry at $REGISTRY_URL"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Diagnostic Information:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Test basic connectivity
        echo ""
        echo "1. Testing connectivity to $REGISTRY_URL..."
        if curl -s --connect-timeout 5 "$REGISTRY_URL" > /dev/null 2>&1; then
            echo "   ✓ Base URL is reachable"
        else
            echo "   ✗ Cannot reach base URL"
        fi
        
        # Test API endpoint with HTTP code
        echo ""
        echo "2. Testing API endpoint: $access_url"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$access_url" 2>/dev/null || echo "000")
        echo "   HTTP Status Code: $http_code"
        
        case "$http_code" in
            000)
                echo "   ✗ Connection failed (timeout or network error)"
                ;;
            404)
                echo "   ✗ API endpoint not found"
                echo "   → Check Registry URL and API version"
                ;;
            503)
                echo "   ✗ Service unavailable"
                echo "   → Registry may still be starting up"
                ;;
            200|301)
                echo "   ✓ Registry is responding but curl -sf failed"
                echo "   → This might be a redirect issue"
                ;;
        esac
        
        # Show detailed response
        echo ""
        echo "3. Detailed connection attempt:"
        curl -v --connect-timeout 10 "$access_url" 2>&1 | head -20
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warning "Verify NiFi Registry is running and accessible"
        return 1
    fi
    
    log_success "NiFi Registry is ready"
    return 0
}

# Fetch all buckets with error handling
fetch_buckets() {
    local buckets_url="$REGISTRY_URL/nifi-registry-api/buckets"
    log_debug "Fetching buckets from $buckets_url"
    
    local response
    response=$(curl -sf "$buckets_url" 2>&1)
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        log_error "Failed to fetch buckets (curl exit: $curl_exit)"
        log_debug "Response: $response"
        return 1
    fi
    
    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        log_debug "Empty buckets response (new registry)"
        echo "[]"
        return 0
    fi
    
    # Validate JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response from Registry"
        log_debug "Response: $response"
        return 1
    fi
    
    echo "$response"
}

# Fetch flows from a bucket
fetch_flows() {
    local bucket_id="$1"
    local flows_url="$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows"
    
    log_debug "Fetching flows from bucket: $bucket_id"
    
    local response
    response=$(curl -sf "$flows_url" 2>&1)
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        log_error "Failed to fetch flows from bucket $bucket_id"
        log_debug "URL: $flows_url"
        log_debug "Response: $response"
        return 1
    fi
    
    echo "$response"
}

# Get flow versions
get_flow_versions() {
    local bucket_id="$1"
    local flow_id="$2"
    local versions_url="$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows/$flow_id/versions"
    
    log_debug "Fetching versions for flow: $flow_id"
    
    local response
    response=$(curl -sf "$versions_url" 2>&1)
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        log_error "Failed to fetch flow versions"
        log_debug "URL: $versions_url"
        log_debug "Response: $response"
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
    
    log_debug "Exporting flow '$flow_name' version $version..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Sanitize flow name for filename
    local safe_name
    safe_name=$(echo "$flow_name" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    local output_file="$OUTPUT_DIR/${safe_name}.json"
    
    # Fetch flow version
    local version_url="$REGISTRY_URL/nifi-registry-api/buckets/$bucket_id/flows/$flow_id/versions/$version"
    local flow_content
    
    flow_content=$(curl -sf "$version_url" 2>&1)
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        log_error "Failed to export flow: $flow_name"
        log_debug "URL: $version_url"
        log_debug "Response: $flow_content"
        ((TOTAL_FAILED++)) || true
        return 1
    fi
    
    # Validate JSON before saving
    if ! echo "$flow_content" | jq empty 2>/dev/null; then
        log_error "Invalid JSON received for flow: $flow_name"
        log_debug "Content: $flow_content"
        ((TOTAL_FAILED++)) || true
        return 1
    fi
    
    # Save to file with pretty formatting
    echo "$flow_content" | jq '.' > "$output_file"
    
    echo -e "      ${GREEN}✓${NC} Exported: $output_file (v$version)"
    ((TOTAL_EXPORTED++)) || true
}

# Export all flows from all buckets
export_all_flows() {
    local buckets="$1"
    
    log_info "Starting export of all flows..."
    echo ""
    
    # Check if buckets is empty
    local bucket_count
    bucket_count=$(echo "$buckets" | jq '. | length' 2>/dev/null || echo "0")
    
    if [ "$bucket_count" -eq 0 ]; then
        log_warning "No buckets found in Registry"
        echo ""
        echo "This is normal for:"
        echo "  • Newly deployed NiFi Registry instances"
        echo "  • Fresh installations without imported flows"
        echo ""
        echo "To add flows:"
        echo "  1. Create flows in NiFi"
        echo "  2. Version control them to Registry"
        echo "  3. Run this export script again"
        echo ""
        return 0
    fi
    
    log_info "Found $bucket_count bucket(s)"
    
    while IFS= read -r bucket; do
        if [ -n "$bucket" ] && [ "$bucket" != "null" ]; then
            local bucket_name
            local bucket_id
            bucket_name=$(echo "$bucket" | jq -r '.name // "Unknown"')
            bucket_id=$(echo "$bucket" | jq -r '.identifier // "Unknown"')
            
            ((TOTAL_BUCKETS++)) || true
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo -e "${MAGENTA}📦 BUCKET:${NC} ${BLUE}$bucket_name${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            # Fetch flows in this bucket
            local flows
            if ! flows=$(fetch_flows "$bucket_id"); then
                log_error "Skipping bucket due to fetch error"
                continue
            fi
            
            local flow_count
            flow_count=$(echo "$flows" | jq '. | length' 2>/dev/null || echo "0")
            
            if [ "${flow_count:-0}" -lt 1 ]; then
                echo -e "   ${YELLOW}No flows in this bucket${NC}"
                echo ""
                continue
            fi
            
            echo -e "   Found ${CYAN}$flow_count${NC} flow(s)"
            echo ""
            
            # Export each flow
            while IFS= read -r flow; do
                if [ -n "$flow" ] && [ "$flow" != "null" ]; then
                    local flow_name
                    local flow_id
                    flow_name=$(echo "$flow" | jq -r '.name // "Unknown"')
                    flow_id=$(echo "$flow" | jq -r '.identifier // "Unknown"')
                    
                    ((TOTAL_FLOWS++)) || true
                    
                    echo -e "   ${GREEN}📊${NC} Processing: ${CYAN}$flow_name${NC}"
                    
                    # Fetch versions
                    local versions
                    if ! versions=$(get_flow_versions "$bucket_id" "$flow_id"); then
                        echo -e "      ${YELLOW}⚠ Failed to get versions${NC}"
                        ((TOTAL_FAILED++)) || true
                        continue
                    fi
                    
                    local version_count
                    version_count=$(echo "$versions" | jq '. | length' 2>/dev/null || echo "0")
                    
                    if [ "${version_count:-0}" -lt 1 ]; then
                        echo -e "      ${YELLOW}⚠ No versions found${NC}"
                        ((TOTAL_FAILED++)) || true
                        continue
                    fi
                    
                    # Get latest version
                    local latest_version
                    latest_version=$(echo "$versions" | jq -r '.[0].version // 1')
                    
                    # Export latest version
                    export_flow_version "$bucket_id" "$flow_id" "$latest_version" "$flow_name"
                    echo ""
                fi
            done < <(echo "$flows" | jq -c '.[]' 2>/dev/null || echo "")
        fi
    done < <(echo "$buckets" | jq -c '.[]' 2>/dev/null || echo "")
}

# Print summary and return appropriate exit code
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}📊 EXPORT SUMMARY${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Total Buckets:         $TOTAL_BUCKETS"
    echo "   Total Flows:           $TOTAL_FLOWS"
    echo "   Successfully Exported: $TOTAL_EXPORTED"
    echo "   Failed:                $TOTAL_FAILED"
    echo "   Output Directory:      $OUTPUT_DIR"
    echo ""
    
    # Handle different scenarios
    if [ $TOTAL_BUCKETS -eq 0 ]; then
        echo -e "${BLUE}ℹ️  No buckets found in Registry${NC}"
        echo "   This is normal for a newly deployed instance"
        echo ""
        return 0  # Success - empty registry is OK
    fi
    
    if [ $TOTAL_FLOWS -eq 0 ]; then
        echo -e "${BLUE}ℹ️  No flows found to export${NC}"
        echo "   Buckets exist but contain no flows"
        echo ""
        return 0  # Success - empty buckets are OK
    fi
    
    if [ $TOTAL_EXPORTED -gt 0 ]; then
        echo -e "${GREEN}✅ Export completed successfully!${NC}"
        echo ""
        echo "Exported files:"
        if ls "$OUTPUT_DIR"/*.json 1> /dev/null 2>&1; then
            ls -lh "$OUTPUT_DIR"/*.json
        else
            echo "   (No files found)"
        fi
        echo ""
        return 0  # Success
    fi
    
    # If we found flows but exported none, that's an error
    if [ $TOTAL_FLOWS -gt 0 ] && [ $TOTAL_EXPORTED -eq 0 ]; then
        echo -e "${RED}❌ Failed to export any flows${NC}"
        echo "   Found $TOTAL_FLOWS flow(s) but none were exported"
        echo ""
        return 1  # Failure
    fi
    
    # Partial success
    if [ $TOTAL_FAILED -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Export completed with errors${NC}"
        echo "   Exported: $TOTAL_EXPORTED / $TOTAL_FLOWS flows"
        echo ""
        return 1  # Failure due to partial exports
    fi
    
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    header
    
    echo -e "${CYAN}ℹ️${NC}  Configuration:"
    echo "   Registry URL:     $REGISTRY_URL"
    echo "   Output Directory: $OUTPUT_DIR"
    echo "   Debug Mode:       $DEBUG"
    echo ""
    
    # Check registry availability
    if ! check_registry; then
        log_error "Registry availability check failed"
        exit 1
    fi
    
    # Fetch all buckets
    log_info "Fetching all buckets..."
    local buckets
    if ! buckets=$(fetch_buckets); then
        log_error "Failed to fetch buckets from Registry"
        exit 1
    fi
    
    # Export all flows
    export_all_flows "$buckets"
    
    # Print summary and exit with appropriate code
    if ! print_summary; then
        log_error "Export completed with errors"
        exit 1
    fi
    
    log_success "Done!"
    echo ""
    exit 0
}

# Run main function
main "$@"