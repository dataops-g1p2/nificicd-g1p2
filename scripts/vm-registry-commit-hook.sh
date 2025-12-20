#!/bin/bash
# VM Registry Commit Hook - Triggers GitHub Workflow
# Auto-installed by Ansible during VM provisioning
# Location: ~/nificicd-g1p2/.git/hooks/post-commit

# DO NOT use 'set -e' - it causes silent failures

# ============================================
# CONFIGURATION
# ============================================
# Source the environment configuration
if [ -f "$HOME/.nifi_cicd_env" ]; then
    source "$HOME/.nifi_cicd_env" 2>/dev/null || true
fi

GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_PAT:-}"
ENVIRONMENT="${NIFI_ENV:-development}"

# ============================================
# COLORS & LOGGING
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_debug() {
    [ "${DEBUG:-0}" = "1" ] && echo -e "${CYAN}[DEBUG]${NC} $1"
}

# ============================================
# DETECT CURRENT BRANCH
# ============================================
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "develop")
log_info "Current branch: $CURRENT_BRANCH"

# Determine if this is a feature branch
if [[ "$CURRENT_BRANCH" == feature/* ]] || [[ "$CURRENT_BRANCH" == hotfix/* ]] || [[ "$CURRENT_BRANCH" == bugfix/* ]]; then
    log_info "Feature/hotfix/bugfix branch detected - PR will target 'develop'"
    IS_FEATURE_BRANCH="true"
else
    IS_FEATURE_BRANCH="false"
fi

# ============================================
# VALIDATION
# ============================================
# Check if this commit affects flows/ or registry_data/
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || echo "")

log_debug "Changed files: $CHANGED_FILES"

if [ -z "$CHANGED_FILES" ]; then
    log_warning "No changed files detected - skipping webhook"
    exit 0
fi

if ! echo "$CHANGED_FILES" | grep -qE '^(flows/|registry_data/)'; then
    log_info "No flows or registry_data changes - skipping webhook"
    log_debug "Changed files don't match pattern: ^(flows/|registry_data/)"
    exit 0
fi

# Validate required environment variables
MISSING_VARS=()
[ -z "$GITHUB_REPO" ] && MISSING_VARS+=("GITHUB_REPO")
[ -z "$GITHUB_TOKEN" ] && MISSING_VARS+=("GITHUB_PAT")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_error "Missing required environment variables: ${MISSING_VARS[*]}"
    echo ""
    log_info "Add these to your ~/.nifi_cicd_env:"
    echo ""
    echo "  export GITHUB_REPO='your-org/your-repo'"
    echo "  export GITHUB_PAT='ghp_xxxxxxxxxxxx'"
    echo "  export NIFI_ENV='$ENVIRONMENT'"
    echo ""
    echo "Then run: source ~/.nifi_cicd_env"
    exit 1
fi

# Validate GitHub PAT format
if [[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
    log_error "Invalid GitHub PAT format"
    log_info "Expected format: ghp_xxxxxxxxxxxx or github_pat_xxxxxxxxxxxx"
    exit 1
fi

# ============================================
# GATHER COMMIT INFORMATION
# ============================================
log_info "Gathering commit information..."

COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || echo "No message")
COMMIT_AUTHOR=$(git log -1 --pretty=%an 2>/dev/null || echo "unknown")
COMMIT_DATE=$(git log -1 --pretty=%ai 2>/dev/null || echo "unknown")
COMMIT_SHORT=${COMMIT_SHA:0:7}
VM_HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

# Count changed files by type
FLOW_CHANGES=$(echo "$CHANGED_FILES" | awk '/^flows\// {count++} END {print count+0}')
REGISTRY_CHANGES=$(echo "$CHANGED_FILES" | awk '/^registry_data\// {count++} END {print count+0}')

log_success "Commit detected"
log_info "  Branch: $CURRENT_BRANCH"
log_info "  SHA: $COMMIT_SHORT"
log_info "  Author: $COMMIT_AUTHOR"
log_info "  Message: $COMMIT_MSG"
log_info "  Flows changed: $FLOW_CHANGES"
log_info "  Registry data changed: $REGISTRY_CHANGES"

# ============================================
# BUILD WEBHOOK PAYLOAD
# ============================================
log_debug "Building webhook payload..."

# Build changed_files array using jq
CHANGED_FILES_JSON=$(echo "$CHANGED_FILES" | grep -v '^$' | jq -R -s -c 'split("\n") | map(select(length > 0))')

# If jq failed or returned empty, create empty array
if [ -z "$CHANGED_FILES_JSON" ] || [ "$CHANGED_FILES_JSON" = "null" ]; then
    CHANGED_FILES_JSON="[]"
fi

# Build the complete payload - NOTE: is_feature_branch must be a string for jq
PAYLOAD=$(jq -n \
    --arg event_type "vm-registry-commit" \
    --arg environment "$ENVIRONMENT" \
    --arg branch "$CURRENT_BRANCH" \
    --arg commit_sha "$COMMIT_SHA" \
    --arg commit_message "$COMMIT_MSG" \
    --arg commit_author "$COMMIT_AUTHOR" \
    --arg commit_date "$COMMIT_DATE" \
    --arg vm_hostname "$VM_HOSTNAME" \
    --argjson flow_changes "$FLOW_CHANGES" \
    --argjson registry_changes "$REGISTRY_CHANGES" \
    --argjson changed_files "$CHANGED_FILES_JSON" \
    --arg triggered_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg is_feature_branch "$IS_FEATURE_BRANCH" \
    '{
        event_type: $event_type,
        client_payload: {
            environment: $environment,
            branch: $branch,
            commit_sha: $commit_sha,
            commit_message: $commit_message,
            commit_author: $commit_author,
            commit_date: $commit_date,
            vm_hostname: $vm_hostname,
            flow_changes: $flow_changes,
            registry_changes: $registry_changes,
            changed_files: $changed_files,
            triggered_at: $triggered_at,
            is_feature_branch: $is_feature_branch
        }
    }')

log_debug "Payload: $PAYLOAD"

# Validate JSON before sending
if ! echo "$PAYLOAD" | jq empty 2>/dev/null; then
    log_error "Invalid JSON payload generated"
    log_debug "Payload was: $PAYLOAD"
    exit 1
fi

# ============================================
# TRIGGER GITHUB WORKFLOW
# ============================================
if [ "$IS_FEATURE_BRANCH" = "true" ]; then
    log_info "Triggering GitHub workflow for feature branch '$CURRENT_BRANCH' → develop..."
else
    log_info "Triggering GitHub workflow for '$ENVIRONMENT' environment..."
fi

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/$GITHUB_REPO/dispatches" \
  -d "$PAYLOAD" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

log_debug "HTTP Code: $HTTP_CODE"
log_debug "Response: $RESPONSE_BODY"

# ============================================
# HANDLE RESPONSE
# ============================================
if [ "$HTTP_CODE" = "204" ]; then
    log_success "✅ Workflow triggered successfully!"
    echo ""
    log_info "GitHub Actions will now:"
    
    if [ "$IS_FEATURE_BRANCH" = "true" ]; then
        echo "  1. Sync changes from VM to GitHub"
        echo "  2. Create PR from '$CURRENT_BRANCH' → 'develop'"
        echo "  3. Wait for team review"
        echo "  4. After merge: Deploy to $ENVIRONMENT environment"
    else
        case $ENVIRONMENT in
            development)
                echo "  1. Sync changes from VM to GitHub"
                echo "  2. Create PR to 'develop' branch"
                echo "  3. After merge: Deploy to Development environment"
                echo "  4. Auto-promote to Staging and Production"
                ;;
            staging)
                echo "  1. Sync changes from VM to GitHub"
                echo "  2. Create PR to 'staging' branch"
                echo "  3. After merge: Deploy to Staging environment"
                echo "  4. Auto-promote to Production"
                ;;
            production)
                echo "  1. Sync changes from VM to GitHub"
                echo "  2. Create PR to 'main' branch"
                echo "  3. After merge: Deploy to Production environment"
                ;;
        esac
    fi
    
    echo ""
    log_info "Monitor progress: https://github.com/$GITHUB_REPO/actions"
    exit 0
fi

# Error handling
case $HTTP_CODE in
    401)
        log_error "Authentication failed (HTTP 401)"
        log_info "Your GitHub PAT may be invalid or expired"
        ;;
    404)
        log_error "Repository not found (HTTP 404)"
        log_info "Check GITHUB_REPO: $GITHUB_REPO"
        ;;
    403)
        log_error "Forbidden (HTTP 403)"
        log_info "Your PAT may lack required permissions (repo, workflow)"
        ;;
    422)
        log_error "Unprocessable Entity (HTTP 422)"
        [ -n "$RESPONSE_BODY" ] && log_debug "Response: $RESPONSE_BODY"
        ;;
    400)
        log_error "Bad Request (HTTP 400)"
        [ -n "$RESPONSE_BODY" ] && log_error "Response: $RESPONSE_BODY"
        ;;
    *)
        log_error "Failed to trigger workflow (HTTP $HTTP_CODE)"
        [ -n "$RESPONSE_BODY" ] && log_error "Response: $RESPONSE_BODY"
        ;;
esac

log_warning "Workflow trigger failed, but commit was successful"
log_info "You can manually trigger at:"
log_info "  https://github.com/$GITHUB_REPO/actions/workflows/webhook-trigger.yml"