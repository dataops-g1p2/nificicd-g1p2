#!/bin/bash
set -e

# ============================================================================
# NiFi Flow Auto-Import Script
# ============================================================================
# Automatically imports NiFi flow definitions via the REST API
# Supports both direct upload (NiFi 1.10+) and component-by-component import
# Version: 2.3.1 - Fixed info() stderr redirect and processor ID validation

# Configuration from environment variables
NIFI_URL="${NIFI_URL:-https://localhost:8443}"
NIFI_USERNAME="${NIFI_USERNAME:-admin}"
NIFI_PASSWORD="${NIFI_PASSWORD}"
FLOWS_DIR="${FLOWS_DIR:-./flows}"
BACKUP_DIR="${FLOWS_DIR}/backups"
IMPORT_LATEST_ONLY="${IMPORT_LATEST_ONLY:-true}"
DEBUG="${DEBUG:-false}"

# NEW: Selective import - can be set via environment or command line
FLOW_NAME="${FLOW_NAME:-}"
FLOW_PATTERN="${FLOW_PATTERN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${YELLOW}🔍 [DEBUG] $1${NC}" >&2
    fi
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

show_usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  FLOW_NAME=<name>           Import specific flow by name (without .json)"
    echo "  FLOW_PATTERN=<pattern>     Import flows matching pattern (glob)"
    echo "  IMPORT_LATEST_ONLY=true/false  Import from latest backup or flows dir"
    echo "  IMPORT_ALL_BACKUPS=true    Import all flows from all backups"
    echo "  DEBUG=true                 Enable debug output"
    echo ""
    echo "Examples:"
    echo "  # Import specific flow"
    echo "  FLOW_NAME=MyUseCase1 $0"
    echo ""
    echo "  # Import flows matching pattern"
    echo "  FLOW_PATTERN='MyUseCase*' $0"
    echo ""
    echo "  # Import all flows from latest backup"
    echo "  IMPORT_LATEST_ONLY=true $0"
    echo ""
    echo "  # Import all flows from flows directory"
    echo "  IMPORT_LATEST_ONLY=false $0"
    echo ""
}

# ============================================================================
# VALIDATION
# ============================================================================

if [ -z "$NIFI_PASSWORD" ]; then
    error "NIFI_PASSWORD environment variable is required"
    exit 1
fi

if [ ! -d "$FLOWS_DIR" ]; then
    error "Flows directory not found: $FLOWS_DIR"
    exit 1
fi

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

echo "==========================="
echo "Automated NiFi Flow Import"
echo "==========================="
echo "NiFi URL: $NIFI_URL"
echo "Flows Directory: $FLOWS_DIR"

if [ -n "$FLOW_NAME" ]; then
    echo "Import Mode: Single flow"
    echo "Flow Name: $FLOW_NAME"
elif [ -n "$FLOW_PATTERN" ]; then
    echo "Import Mode: Pattern matching"
    echo "Pattern: $FLOW_PATTERN"
elif [ "$IMPORT_ALL_BACKUPS" = "true" ]; then
    echo "Import Mode: All backups"
elif [ "$IMPORT_LATEST_ONLY" = "true" ]; then
    echo "Import Mode: Latest backup only"
else
    echo "Import Mode: All flows from directory"
fi
echo ""

# ============================================================================
# FLOW FILE SELECTION LOGIC
# ============================================================================

select_flows() {
    local source_dir="$1"
    local flow_files=()
    
    if [ -n "$FLOW_NAME" ]; then
        # Import specific flow by name
        local flow_file="${source_dir}/${FLOW_NAME}.json"
        
        if [ -f "$flow_file" ]; then
            flow_files=("$flow_file")
            info "Found specified flow: $FLOW_NAME.json"
        else
            error "Flow not found: $flow_file"
            info "Available flows in $source_dir:"
            ls -1 "$source_dir"/*.json 2>/dev/null | xargs -n1 basename | sed 's/^/  • /' || echo "  (none)"
            exit 1
        fi
        
    elif [ -n "$FLOW_PATTERN" ]; then
        # Import flows matching pattern
        flow_files=($(find "$source_dir" -maxdepth 1 -name "${FLOW_PATTERN}.json" -type f 2>/dev/null))
        
        if [ ${#flow_files[@]} -eq 0 ]; then
            error "No flows found matching pattern: ${FLOW_PATTERN}"
            info "Available flows in $source_dir:"
            ls -1 "$source_dir"/*.json 2>/dev/null | xargs -n1 basename | sed 's/^/  • /' || echo "  (none)"
            exit 1
        fi
        
        info "Found ${#flow_files[@]} flow(s) matching pattern '$FLOW_PATTERN'"
        
    else
        # Import all flows from directory
        flow_files=($(find "$source_dir" -maxdepth 1 -name "*.json" -type f 2>/dev/null))
        
        if [ ${#flow_files[@]} -eq 0 ]; then
            warning "No flow files found in $source_dir"
            return 1
        fi
        
        info "Found ${#flow_files[@]} flow file(s) in directory"
    fi
    
    # Return flow files array
    printf '%s\n' "${flow_files[@]}"
}

# Determine which flows to import
if [ "$IMPORT_ALL_BACKUPS" = "true" ]; then
    # Import all flows from all backup directories
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_DIRS=($(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r))
        
        if [ ${#BACKUP_DIRS[@]} -eq 0 ]; then
            warning "No backup directories found in $BACKUP_DIR"
            info "Run 'make export-flows' to create backups"
            exit 0
        fi
        
        info "Found ${#BACKUP_DIRS[@]} backup directory(ies) to import"
        echo ""
        
        # Collect all flow files from all backups
        FLOW_FILES=()
        for backup_dir in "${BACKUP_DIRS[@]}"; do
            backup_name=$(basename "$backup_dir")
            
            # Use select_flows function for each backup
            mapfile -t backup_files < <(select_flows "$backup_dir" 2>/dev/null || true)
            
            if [ ${#backup_files[@]} -gt 0 ]; then
                info "Backup: $backup_name (${#backup_files[@]} files)"
                FLOW_FILES+=("${backup_files[@]}")
            fi
        done
        IMPORT_SOURCE="$BACKUP_DIR (all backups)"
    else
        error "Backup directory not found: $BACKUP_DIR"
        info "Run 'make export-flows' to create backups"
        exit 1
    fi
    
elif [ "$IMPORT_LATEST_ONLY" = "true" ]; then
    # Check if backups directory exists
    if [ -d "$BACKUP_DIR" ]; then
        # Find the latest backup directory
        LATEST_BACKUP=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n 1)
        
        if [ -n "$LATEST_BACKUP" ]; then
            info "Latest backup found: $(basename "$LATEST_BACKUP")"
            IMPORT_SOURCE="$LATEST_BACKUP"
            
            # Use select_flows function
            mapfile -t FLOW_FILES < <(select_flows "$IMPORT_SOURCE")
        else
            warning "No backups found in $BACKUP_DIR"
            info "Falling back to flows directory: $FLOWS_DIR"
            IMPORT_SOURCE="$FLOWS_DIR"
            
            # Use select_flows function
            mapfile -t FLOW_FILES < <(select_flows "$IMPORT_SOURCE")
        fi
    else
        info "No backup directory found, using flows directory"
        IMPORT_SOURCE="$FLOWS_DIR"
        
        # Use select_flows function
        mapfile -t FLOW_FILES < <(select_flows "$IMPORT_SOURCE")
    fi
    
else
    # Import from the main flows directory (exclude backups)
    IMPORT_SOURCE="$FLOWS_DIR"
    
    # Use select_flows function
    mapfile -t FLOW_FILES < <(select_flows "$IMPORT_SOURCE")
fi

if [ ${#FLOW_FILES[@]} -eq 0 ]; then
    warning "No flow files to import"
    
    if [ -n "$FLOW_NAME" ]; then
        info "Tried to import: $FLOW_NAME.json"
    elif [ -n "$FLOW_PATTERN" ]; then
        info "Tried to import pattern: ${FLOW_PATTERN}.json"
    fi
    
    echo ""
    info "Available flows:"
    if [ -d "$FLOWS_DIR" ]; then
        ls -1 "$FLOWS_DIR"/*.json 2>/dev/null | xargs -n1 basename | sed 's/^/  • /' || echo "  (none)"
    fi
    echo ""
    show_usage
    exit 0
fi

echo -e "${BLUE}📦 Found ${#FLOW_FILES[@]} flow file(s) to import${NC}"
echo -e "${CYAN}Source: $IMPORT_SOURCE${NC}"
for flow_file in "${FLOW_FILES[@]}"; do
    echo -e "  • $(basename "$flow_file")"
done
echo ""

# ============================================================================
# NIFI CONNECTION & AUTHENTICATION
# ============================================================================

wait_for_nifi() {
    echo -e "${YELLOW}⏳ Waiting for NiFi to be ready...${NC}"
    max_attempts=60
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sk "${NIFI_URL}/nifi-api/access/config" >/dev/null 2>&1; then
            success "NiFi is responding!"
            break
        fi
        attempt=$((attempt + 1))
        debug "Attempt $attempt/$max_attempts..."
        sleep 5
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "NiFi did not become ready in time"
        return 1
    fi
    
    echo -e "${YELLOW}Waiting for NiFi authentication to be ready...${NC}"
    auth_attempts=0
    max_auth_attempts=20
    
    local encoded_username=$(printf '%s' "$NIFI_USERNAME" | jq -sRr @uri)
    local encoded_password=$(printf '%s' "$NIFI_PASSWORD" | jq -sRr @uri)
    
    while [ $auth_attempts -lt $max_auth_attempts ]; do
        token_test=$(curl -sk -w "%{http_code}" -X POST "${NIFI_URL}/nifi-api/access/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=${encoded_username}&password=${encoded_password}" \
            -o /dev/null 2>&1)
        
        debug "Auth check attempt $((auth_attempts + 1))/$max_auth_attempts - HTTP $token_test"
        
        if [ "$token_test" = "200" ] || [ "$token_test" = "201" ]; then
            success "Authentication is ready!"
            return 0
        elif [ "$token_test" = "401" ]; then
            error "Authentication failed - check credentials"
            error "Username: $NIFI_USERNAME"
            error "Password length: ${#NIFI_PASSWORD}"
            info "Run: make setup-password ENV=local && make restart"
            return 1
        elif [ "$token_test" = "400" ]; then
            warning "Got HTTP 400 - authentication may not be configured correctly"
            debug "This might mean single-user auth is not enabled"
            if [ $auth_attempts -ge 5 ]; then
                error "Persistent HTTP 400 error - authentication not properly configured"
                info "Check your compose.local.yml for SINGLE_USER_CREDENTIALS_* variables"
                return 1
            fi
        elif [ "$token_test" = "409" ]; then
            debug "NiFi still initializing (HTTP 409)... waiting"
        else
            debug "Got HTTP $token_test, waiting..."
        fi
        
        auth_attempts=$((auth_attempts + 1))
        sleep 5
    done
    
    error "Authentication did not become ready in time"
    info "Last HTTP code: $token_test"
    return 1
}

get_nifi_token() {
    debug "Getting authentication token..."
    debug "Username: $NIFI_USERNAME"
    debug "Password length: ${#NIFI_PASSWORD}"
    
    local token_response
    local http_code
    
    local encoded_username=$(printf '%s' "$NIFI_USERNAME" | jq -sRr @uri)
    local encoded_password=$(printf '%s' "$NIFI_PASSWORD" | jq -sRr @uri)
    
    debug "Encoded username: $encoded_username"
    debug "Making token request to: ${NIFI_URL}/nifi-api/access/token"
    
    token_response=$(curl -sk -w "\n%{http_code}" -X POST "${NIFI_URL}/nifi-api/access/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${encoded_username}&password=${encoded_password}" \
        2>&1)
    
    http_code=$(echo "$token_response" | tail -n1)
    local token=$(echo "$token_response" | sed '$d')
    
    debug "Token request HTTP code: $http_code"
    
    if [ "$DEBUG" = "true" ] && [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        debug "Response body (first 500 chars): ${token:0:500}"
    fi
    
    if [ "$http_code" = "400" ]; then
        error "Bad Request (HTTP 400)"
        error "This usually means:"
        error "  1. Username/password contains invalid characters"
        error "  2. Request format is incorrect"
        error "  3. NiFi authentication is not properly configured"
        if [ "$DEBUG" = "true" ]; then
            debug "Full error response: $token"
        fi
        info "Try: make setup-password ENV=local && make restart"
        return 1
    fi
    
    if [ "$http_code" = "409" ]; then
        error "NiFi is not ready yet (HTTP 409 - Conflict)"
        error "This usually means NiFi is still initializing"
        info "Wait 30-60 seconds and try again"
        return 1
    fi
    
    if [ "$http_code" = "401" ]; then
        error "Authentication failed (HTTP 401)"
        error "Check your credentials in .env file"
        info "Regenerate password: make setup-password ENV=local"
        return 1
    fi
    
    if [ "$http_code" = "403" ]; then
        error "Forbidden (HTTP 403)"
        error "Single-user authentication may not be configured"
        return 1
    fi
    
    if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
        error "Unexpected HTTP code: $http_code"
        if [ "$DEBUG" = "true" ]; then
            debug "Full response: $token"
        fi
        return 1
    fi
    
    if [ -z "$token" ]; then
        error "Empty token received"
        return 1
    fi
    
    if echo "$token" | grep -qi "error\|unable\|invalid"; then
        error "Error in token response"
        if [ "$DEBUG" = "true" ]; then
            debug "Token response: $token"
        fi
        return 1
    fi
    
    debug "Token received (length: ${#token})"
    
    # Output ONLY the token to stdout
    echo "$token"
    return 0
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    local token=$(get_nifi_token)
    if [ -z "$token" ]; then
        error "Failed to get authentication token"
        return 1
    fi
    
    debug "Making $method request to $endpoint"
    if [ "$DEBUG" = "true" ] && [ -n "$data" ]; then
        debug "Request payload (first 300 chars): ${data:0:300}"
    fi
    
    local response
    local http_code
    
    if [ -n "$data" ]; then
        response=$(curl -sk -w "\n%{http_code}" -X "$method" \
            "${NIFI_URL}${endpoint}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -sk -w "\n%{http_code}" -X "$method" \
            "${NIFI_URL}${endpoint}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" 2>/dev/null)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    debug "HTTP Code: $http_code"
    
    if [ "$http_code" -ge 400 ]; then
        debug "Full error response: $body"
        return 1
    fi
    
    echo "$body"
    return 0
}

# ============================================================================
# NIFI VERSION DETECTION
# ============================================================================

detect_nifi_version() {
    debug "Detecting NiFi version..."
    
    local about_response=$(curl -sk "${NIFI_URL}/nifi-api/flow/about" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local version=$(echo "$about_response" | grep -o '"niFiVersion":"[^"]*"' | cut -d'"' -f4)
        debug "NiFi version: $version"
        echo "$version"
        return 0
    fi
    
    debug "Could not detect NiFi version"
    echo "unknown"
    return 1
}

# ============================================================================
# IMPORT METHOD 1: DIRECT UPLOAD (NiFi 1.10+)
# ============================================================================

upload_flow_definition() {
    local pg_id=$1
    local flow_file=$2
    local flow_name=$3
    local token=$4
    
    debug "Attempting direct flow upload..."
    debug "Process group: $pg_id"
    debug "Flow file: $flow_file"
    
    if [ ! -f "$flow_file" ]; then
        error "Flow file does not exist: $flow_file"
        return 1
    fi
    
    local posX=$((100 + RANDOM % 400))
    local posY=$((100 + RANDOM % 400))
    
    local response
    local http_code
    
    response=$(curl -sk -w "\n%{http_code}" -X POST \
        "${NIFI_URL}/nifi-api/process-groups/${pg_id}/process-groups/upload" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: multipart/form-data" \
        -F "groupName=${flow_name}" \
        -F "positionX=${posX}" \
        -F "positionY=${posY}" \
        -F "file=@${flow_file}" \
        2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    debug "Upload HTTP code: $http_code"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        success "Direct upload successful!"
        echo "$body"
        return 0
    fi
    
    debug "Direct upload not available (HTTP $http_code)"
    return 1
}

# ============================================================================
# IMPORT METHOD 2: COMPONENT-BY-COMPONENT
# ============================================================================

import_flow_components() {
    local pg_id=$1
    local flow_file=$2
    local flow_name=$3
    
    info "Importing flow components for '$flow_name'..."
    
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is required for component import"
        info "Install with: sudo apt-get install -y jq (Linux) or brew install jq (Mac)"
        return 1
    fi
    
    local flow_json=$(cat "$flow_file")
    
    debug "Validating flow structure..."
    local has_root_group=$(echo "$flow_json" | jq 'has("rootGroup")' 2>/dev/null)
    local has_flow_contents=$(echo "$flow_json" | jq 'has("flowContents")' 2>/dev/null)
    debug "Flow structure - has rootGroup: $has_root_group, has flowContents: $has_flow_contents"
    
    local processors=$(echo "$flow_json" | jq -c '.rootGroup.processors[]? // .flowContents.processors[]? // empty' 2>/dev/null)
    
    if [ -z "$processors" ]; then
        error "No processors found in flow definition"
        return 1
    fi
    
    local processor_count=$(echo "$processors" | wc -l | tr -d ' ')
    info "Found $processor_count processor(s) to import"
    
    local id_map_file="/tmp/nifi_id_map_${pg_id}.txt"
    > "$id_map_file"
    
    while IFS= read -r processor; do
        local old_id=$(echo "$processor" | jq -r '.identifier')
        local name=$(echo "$processor" | jq -r '.name')
        local type=$(echo "$processor" | jq -r '.type')
        local pos_x=$(echo "$processor" | jq -r '.position.x')
        local pos_y=$(echo "$processor" | jq -r '.position.y')
        local bundle=$(echo "$processor" | jq -c '.bundle')
        local properties=$(echo "$processor" | jq -c '.properties')
        local schedule_period=$(echo "$processor" | jq -r '.schedulingPeriod // "0 sec"')
        local schedule_strategy=$(echo "$processor" | jq -r '.schedulingStrategy // "TIMER_DRIVEN"')
        local comments=$(echo "$processor" | jq -r '.comments // ""')
        local auto_term=$(echo "$processor" | jq -c '.autoTerminatedRelationships // []')
        
        debug "Creating processor: $name ($type) with old_id=$old_id"
        
        local processor_payload=$(cat <<EOF
{
  "revision": {
    "version": 0
  },
  "component": {
    "type": "$type",
    "bundle": $bundle,
    "name": "$name",
    "position": {
      "x": $pos_x,
      "y": $pos_y
    },
    "config": {
      "properties": $properties,
      "schedulingPeriod": "$schedule_period",
      "schedulingStrategy": "$schedule_strategy",
      "concurrentlySchedulableTaskCount": 1,
      "comments": "$comments",
      "autoTerminatedRelationships": $auto_term
    }
  }
}
EOF
)
        
        local proc_response=$(api_call "POST" "/nifi-api/process-groups/${pg_id}/processors" "$processor_payload")
        
        if [ $? -eq 0 ]; then
            # Validate that we got a proper JSON response
            if ! echo "$proc_response" | jq empty 2>/dev/null; then
                error "  Failed to create: $name (Invalid JSON response)"
                if [ "$DEBUG" = "true" ]; then
                    debug "Response: $proc_response"
                fi
                continue
            fi
            
            # Try multiple paths for ID extraction
            local new_id=$(echo "$proc_response" | jq -r '.id // .component.id // .revision.componentId // empty')
            
            # Validate the new_id was extracted successfully
            if [ -z "$new_id" ] || [ "$new_id" = "null" ]; then
                if [ "$DEBUG" = "true" ]; then
                    debug "Failed to extract processor ID from response for: $name"
                    debug "Response length: ${#proc_response} chars"
                    debug "Response (first 500 chars): ${proc_response:0:500}"
                    debug "Tried paths: .id, .component.id, .revision.componentId"
                fi
                
                # Fallback: Query NiFi to find the processor by name
                warning "  Failed to extract ID from response, querying NiFi for: $name"
                sleep 1  # Give NiFi a moment to register the processor
                
                local query_response=$(api_call "GET" "/nifi-api/process-groups/${pg_id}/processors" "")
                if [ $? -eq 0 ]; then
                    new_id=$(echo "$query_response" | jq -r \
                        ".processors[] | select(.component.name == \"$name\") | .id // empty")
                    
                    if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
                        debug "  Successfully retrieved ID by querying NiFi: $new_id"
                    fi
                fi
                
                # If still no ID found, skip mapping
                if [ -z "$new_id" ] || [ "$new_id" = "null" ]; then
                    warning "  Created: $name (ID: UNKNOWN - skipping mapping)"
                    continue
                fi
            fi
            
            echo "$old_id:$new_id" >> "$id_map_file"
            debug "Mapped $old_id -> $new_id"
            success "  Created: $name (ID: $new_id)"
        else
            error "  Failed to create: $name"
        fi
    done <<< "$processors"
    
    debug "Waiting for processors to be fully initialized..."
    sleep 2
    
    if [ ! -s "$id_map_file" ]; then
        error "No ID mappings were created!"
        return 1
    fi
    
    local mapped_count=$(wc -l < "$id_map_file" | tr -d ' ')
    debug "Created $mapped_count ID mappings"
    
    local connections=$(echo "$flow_json" | jq -c '.rootGroup.connections[]? // .flowContents.connections[]? // empty' 2>/dev/null)
    
    if [ -n "$connections" ]; then
        info "Creating connections..."
        
        if [ "$DEBUG" = "true" ]; then
            debug "Reading ID mappings from $id_map_file:"
            cat "$id_map_file" | while read line; do
                debug "  Mapping: $line"
            done
        fi
        
        local conn_count=0
        local conn_success=0
        
        echo "$connections" | while IFS= read -r connection; do
            conn_count=$((conn_count + 1))
            
            local source_id=$(echo "$connection" | jq -r '.source.id')
            local dest_id=$(echo "$connection" | jq -r '.destination.id')
            local relationships=$(echo "$connection" | jq -c '.selectedRelationships')
            
            debug "Processing connection $conn_count: $source_id -> $dest_id"
            
            local new_source_id=$(grep "^${source_id}:" "$id_map_file" 2>/dev/null | cut -d: -f2)
            local new_dest_id=$(grep "^${dest_id}:" "$id_map_file" 2>/dev/null | cut -d: -f2)
            
            debug "Mapped source: $source_id -> $new_source_id"
            debug "Mapped dest: $dest_id -> $new_dest_id"
            
            if [ -z "$new_source_id" ]; then
                error "  Failed to map source ID: $source_id"
                if [ "$DEBUG" = "true" ]; then
                    debug "  Available IDs in mapping file:"
                    cat "$id_map_file" | sed 's/^/    /'
                fi
                continue
            fi
            
            if [ -z "$new_dest_id" ]; then
                error "  Failed to map destination ID: $dest_id"
                continue
            fi
            
            debug "Creating connection: $new_source_id -> $new_dest_id (relationships: $relationships)"
            
            local conn_payload=$(cat <<EOF
{
  "revision": {
    "clientId": "nifi-cli",
    "version": 0
  },
  "disconnectedNodeAcknowledged": false,
  "component": {
    "source": {
      "id": "$new_source_id",
      "type": "PROCESSOR",
      "groupId": "$pg_id"
    },
    "destination": {
      "id": "$new_dest_id",
      "type": "PROCESSOR",
      "groupId": "$pg_id"
    },
    "selectedRelationships": $relationships,
    "backPressureDataSizeThreshold": "1 GB",
    "backPressureObjectThreshold": 10000,
    "flowFileExpiration": "0 sec"
  }
}
EOF
)
            
            if [ "$DEBUG" = "true" ]; then
                debug "Connection payload: $conn_payload"
            fi
            
            local conn_response=$(api_call "POST" "/nifi-api/process-groups/${pg_id}/connections" "$conn_payload" 2>&1)
            local conn_exit_code=$?
            
            if [ $conn_exit_code -eq 0 ]; then
                conn_success=$((conn_success + 1))
                success "  Created connection: $new_source_id → $new_dest_id"
            else
                error "  Failed to create connection: $new_source_id → $new_dest_id"
                if [ "$DEBUG" = "true" ]; then
                    debug "  Error response: $conn_response"
                fi
            fi
        done
        
        local expected_count=$(echo "$connections" | wc -l | tr -d ' ')
        info "Expected $expected_count connection(s)"
    fi
    
    # Import labels
    local labels=$(echo "$flow_json" | jq -c '.rootGroup.labels[]? // .flowContents.labels[]? // empty' 2>/dev/null)

    if [ -n "$labels" ]; then
        local label_count=$(echo "$labels" | wc -l | tr -d ' ')
        info "Creating $label_count label(s)..."
        
        local label_num=0
        
        echo "$labels" | while IFS= read -r label; do
            label_num=$((label_num + 1))
            
            local label_text=$(echo "$label" | jq -r '.label')
            local pos_x=$(echo "$label" | jq -r '.position.x')
            local pos_y=$(echo "$label" | jq -r '.position.y')
            local width=$(echo "$label" | jq -r '.width')
            local height=$(echo "$label" | jq -r '.height')
            local style=$(echo "$label" | jq -c '.style // {}')
            
            debug "Creating label $label_num at position ($pos_x, $pos_y) with size ${width}x${height}"
            
            local label_payload=$(jq -n \
                --arg labeltext "$label_text" \
                --argjson x "$pos_x" \
                --argjson y "$pos_y" \
                --argjson w "$width" \
                --argjson h "$height" \
                --argjson style "$style" \
                '{
                    revision: {version: 0},
                    component: {
                        label: $labeltext,
                        position: {x: $x, y: $y},
                        width: $w,
                        height: $h,
                        style: $style
                    }
                }')
            
            if [ "$DEBUG" = "true" ]; then
                debug "Label payload (first 300 chars): ${label_payload:0:300}"
            fi
            
            local label_response=$(api_call "POST" "/nifi-api/process-groups/${pg_id}/labels" "$label_payload" 2>&1)
            local label_exit_code=$?
            
            if [ $label_exit_code -eq 0 ]; then
                success "  Created label $label_num"
                debug "  Label ID: $(echo "$label_response" | jq -r '.id // "unknown"')"
            else
                error "  Failed to create label $label_num"
                debug "  Label error response: $label_response"
            fi
        done
        
        debug "Verifying label creation..."
        local verify_labels=$(api_call "GET" "/nifi-api/process-groups/${pg_id}/labels" "" 2>/dev/null)
        if [ $? -eq 0 ]; then
            local actual_label_count=$(echo "$verify_labels" | jq '.labels | length' 2>/dev/null || echo "0")
            info "Verification: $actual_label_count label(s) exist in process group"
        fi
    else
        debug "No labels found in flow definition"
    fi
    
    debug "Verifying created components..."
    local verify_processors=$(api_call "GET" "/nifi-api/process-groups/${pg_id}/processors" "" 2>/dev/null)
    if [ $? -eq 0 ]; then
        local actual_proc_count=$(echo "$verify_processors" | jq '.processors | length' 2>/dev/null || echo "0")
        local expected_proc_count=$(wc -l < "$id_map_file" | tr -d ' ')
        
        if [ "$actual_proc_count" -eq "$expected_proc_count" ]; then
            info "Verification: All $actual_proc_count processor(s) created successfully"
        else
            warning "Verification: Expected $expected_proc_count processors, found $actual_proc_count"
        fi
    fi
    
    local verify_connections=$(api_call "GET" "/nifi-api/process-groups/${pg_id}/connections" "" 2>/dev/null)
    if [ $? -eq 0 ]; then
        local actual_conn_count=$(echo "$verify_connections" | jq '.connections | length' 2>/dev/null || echo "0")
        info "Verification: $actual_conn_count connection(s) exist in process group"
    fi
    
    rm -f "$id_map_file"
    
    return 0
}

# ============================================================================
# MAIN IMPORT LOGIC
# ============================================================================

import_flow() {
    local flow_file=$1
    local flow_name=$(basename "$flow_file" .json)
    
    echo -e "${BLUE}📥 Importing: $flow_name${NC}"
    echo -e "${CYAN}   File: $flow_file${NC}"
    
    if ! cat "$flow_file" | jq empty 2>/dev/null; then
        error "Invalid JSON in flow file"
        return 1
    fi
    
    TOKEN=$(get_nifi_token)
    if [ -z "$TOKEN" ]; then
        error "Authentication failed"
        return 1
    fi
    
    info "→ Method 1: Direct flow upload..."
    set +e
    upload_flow_definition "$ROOT_PG_ID" "$flow_file" "$flow_name" "$TOKEN"
    UPLOAD_SUCCESS=$?
    set -e
    
    if [ $UPLOAD_SUCCESS -eq 0 ]; then
        return 0
    fi
    
    info "→ Method 2: Component-by-component import..."
    
    local pg_payload=$(cat <<EOF
{
  "revision": {
    "version": 0
  },
  "component": {
    "name": "$flow_name",
    "position": {
      "x": $((100 + RANDOM % 400)),
      "y": $((100 + RANDOM % 400))
    }
  }
}
EOF
)
    
    local pg_response=$(api_call "POST" "/nifi-api/process-groups/${ROOT_PG_ID}/process-groups" "$pg_payload")
    if [ $? -ne 0 ]; then
        error "Failed to create process group"
        return 1
    fi
    
    local new_pg_id=$(echo "$pg_response" | jq -r '.component.id // .id')
    
    if [ -z "$new_pg_id" ]; then
        error "Failed to extract process group ID"
        return 1
    fi
    
    success "  Process group created: $new_pg_id"
    
    if import_flow_components "$new_pg_id" "$flow_file" "$flow_name"; then
        success "  Components imported successfully!"
        return 0
    else
        error "  Component import failed"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

wait_for_nifi || exit 1

echo -e "${BLUE}🔐 Testing authentication...${NC}"
TOKEN=$(get_nifi_token)
if [ -z "$TOKEN" ]; then
    error "Authentication failed - check your credentials"
    exit 1
fi
success "Authentication successful"
echo ""

echo -e "${BLUE}🌐 Getting root process group...${NC}"
ROOT_PG=$(api_call "GET" "/nifi-api/flow/process-groups/root" "")

if [ -z "$ROOT_PG" ]; then
    error "Failed to get root process group"
    exit 1
fi

ROOT_PG_ID=$(echo "$ROOT_PG" | jq -r '.processGroupFlow.id // .id // "root"' 2>/dev/null)
success "Root Process Group ID: $ROOT_PG_ID"
echo ""

NIFI_VERSION=$(detect_nifi_version)
if [ "$NIFI_VERSION" != "unknown" ]; then
    info "NiFi Version: $NIFI_VERSION"
    echo ""
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

for FLOW_FILE in "${FLOW_FILES[@]}"; do
    if import_flow "$FLOW_FILE"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        success "✅ Flow '$(basename "$FLOW_FILE" .json)' imported successfully!"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        error "Failed to import flow '$(basename "$FLOW_FILE" .json)'"
    fi
    echo ""
done

echo "╔════════════════════════════╗"
echo "  Import Summary              "
echo "╚════════════════════════════╝"
success "Successfully Imported: $SUCCESS_COUNT"
if [ $FAIL_COUNT -gt 0 ]; then
    error "Failed:                $FAIL_COUNT"
fi
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    success "🎉 Flow import completed!"
    info "🌐 Access NiFi at: ${NIFI_URL}/nifi"
    echo ""
    info "📋 Next steps:"
    echo "  1. Open NiFi UI"
    echo "  2. Double-click the process group"
    echo "  3. Start the processors (select all → right-click → Start)"
    echo ""
    
    if [ -n "$FLOW_NAME" ]; then
        info "✨ Imported specific flow: $FLOW_NAME"
    elif [ -n "$FLOW_PATTERN" ]; then
        info "✨ Imported flows matching pattern: $FLOW_PATTERN"
    elif [ "$IMPORT_LATEST_ONLY" = "true" ] && [ -n "$LATEST_BACKUP" ]; then
        info "✨ Imported from latest backup: $(basename "$LATEST_BACKUP")"
    fi
    
    exit 0
else
    error "No flows were imported successfully"
    echo ""
    info "💡 Troubleshooting:"
    echo "  1. Enable debug mode: DEBUG=true make import-flows-auto"
    echo "  2. Check NiFi logs: make logs-nifi"
    echo "  3. Verify credentials: make echo"
    echo "  4. Ensure jq is installed: which jq"
    echo "  5. List available flows: ls -la flows/"
    
    if [ -n "$FLOW_NAME" ]; then
        echo "  6. Check flow name: FLOW_NAME=$FLOW_NAME"
    elif [ -n "$FLOW_PATTERN" ]; then
        echo "  6. Check pattern: FLOW_PATTERN=$FLOW_PATTERN"
    fi
    
    echo ""
    show_usage
    exit 1
fi