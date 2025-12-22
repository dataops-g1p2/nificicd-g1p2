#!/bin/bash
# VM Registry Commit Hook - Triggers GitHub Workflow
# Location: ~/nificicd-g1p2/.git/hooks/post-commit
# Enhanced with: commit batching, file size validation, improved error handling

# ===========================
# CONFIGURATION & SETUP
# ===========================
[ -f "$HOME/.nifi_cicd_env" ] && source "$HOME/.nifi_cicd_env" 2>/dev/null

GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_PAT:-}"
ENVIRONMENT="${NIFI_ENV:-development}"

# Lock and batch control
LOCK_FILE="/tmp/nifi-webhook-trigger.lock"
LAST_TRIGGER_FILE="/tmp/nifi-last-trigger-timestamp"
BATCH_WINDOW=10  # seconds
MAX_FILE_SIZE=10485760  # 10MB

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_debug() { [ "${DEBUG:-0}" = "1" ] && echo -e "${CYAN}[DEBUG]${NC} $1"; }

# ===========================
# LOCK & BATCH MANAGEMENT
# ===========================
# Check for concurrent execution
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)))
    if [ $LOCK_AGE -lt 30 ]; then
        log_info "Another webhook trigger in progress (${LOCK_AGE}s ago) - skipping to avoid duplicates"
        exit 0
    fi
    rm -f "$LOCK_FILE"  # Remove stale lock
fi

touch "$LOCK_FILE"
trap "rm -f '$LOCK_FILE'" EXIT

# Implement commit batching window
if [ -f "$LAST_TRIGGER_FILE" ]; then
    TIME_SINCE_LAST=$(($(date +%s) - $(cat "$LAST_TRIGGER_FILE")))
    if [ $TIME_SINCE_LAST -lt $BATCH_WINDOW ]; then
        log_info "Batching commits (${TIME_SINCE_LAST}s since last, waiting ${BATCH_WINDOW}s) - changes will be in next batch"
        exit 0
    fi
fi
date +%s > "$LAST_TRIGGER_FILE"

# ===========================
# BRANCH & FILE VALIDATION
# ===========================
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "develop")
log_info "Current branch: $CURRENT_BRANCH"

IS_FEATURE_BRANCH="false"
[[ "$CURRENT_BRANCH" == feature/* ]] || [[ "$CURRENT_BRANCH" == hotfix/* ]] || [[ "$CURRENT_BRANCH" == bugfix/* ]] && {
    log_info "Feature/hotfix/bugfix branch detected - PR will target 'develop'"
    IS_FEATURE_BRANCH="true"
}

# Get and validate changed files
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || echo "")
log_debug "Changed files: $CHANGED_FILES"

[ -z "$CHANGED_FILES" ] && { log_warning "No changed files detected - skipping webhook"; exit 0; }

echo "$CHANGED_FILES" | grep -qE '^(flows/|registry_data/)' || {
    log_info "No flows or registry_data changes - skipping webhook"
    log_debug "Changed files don't match pattern: ^(flows/|registry_data/)"
    exit 0
}

# Validate file sizes
log_debug "Validating file sizes..."
for FILE in $CHANGED_FILES; do
    if [ -f "$FILE" ]; then
        FILE_SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null || echo 0)
        if [ "$FILE_SIZE" -gt "$MAX_FILE_SIZE" ]; then
            log_error "File too large: $FILE ($((FILE_SIZE / 1024 / 1024))MB exceeds 10MB limit)"
            log_info "Consider using Git LFS for large files"
            log_info "To fix: git rm --cached $FILE; git commit --amend"
            exit 1
        fi
    fi
done

# ===========================
# ENVIRONMENT VALIDATION
# ===========================
MISSING_VARS=()
[ -z "$GITHUB_REPO" ] && MISSING_VARS+=("GITHUB_REPO")
[ -z "$GITHUB_TOKEN" ] && MISSING_VARS+=("GITHUB_PAT")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_error "Missing required environment variables: ${MISSING_VARS[*]}"
    echo ""
    log_info "Add these to your ~/.nifi_cicd_env:"
    echo "  export GITHUB_REPO='your-org/your-repo'"
    echo "  export GITHUB_PAT='ghp_xxxxxxxxxxxx'"
    echo "  export NIFI_ENV='$ENVIRONMENT'"
    exit 1
fi

[[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_) ]] && {
    log_error "Invalid GitHub PAT format - should start with 'ghp_' or 'github_pat_'"
    exit 1
}

# ===========================
# RATE LIMIT CHECK
# ===========================
RATE_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/rate_limit" 2>/dev/null)
if [ $? -eq 0 ]; then
    REMAINING=$(echo "$RATE_INFO" | jq -r '.rate.remaining' 2>/dev/null || echo "unknown")
    if [ "$REMAINING" != "unknown" ] && [ "$REMAINING" -lt 10 ]; then
        RESET_TIME=$(echo "$RATE_INFO" | jq -r '.rate.reset' 2>/dev/null || echo "unknown")
        log_warning "GitHub API rate limit low: $REMAINING requests remaining"
        [ "$RESET_TIME" != "unknown" ] && log_info "Rate limit resets in $(( (RESET_TIME - $(date +%s)) / 60 )) minutes"
    fi
fi

# ===========================
# GATHER COMMIT INFORMATION
# ===========================
log_info "Gathering commit information..."

COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || echo "No message")
COMMIT_AUTHOR="$(git log -1 --pretty=%an 2>/dev/null || echo "unknown") <$(git log -1 --pretty=%ae 2>/dev/null || echo "unknown")>"
COMMIT_SHORT=${COMMIT_SHA:0:7}
VM_HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

FLOW_CHANGES=$(echo "$CHANGED_FILES" | grep -c '^flows/' || echo 0)
REGISTRY_CHANGES=$(echo "$CHANGED_FILES" | grep -c '^registry_data/' || echo 0)

log_success "Commit detected"
log_info "  Branch: $CURRENT_BRANCH | SHA: $COMMIT_SHORT | Author: $COMMIT_AUTHOR"
log_info "  Message: $COMMIT_MSG"
log_info "  Changes: $FLOW_CHANGES flows, $REGISTRY_CHANGES registry"

# ===========================
# COMMIT MESSAGE VALIDATION
# ===========================
if ! echo "$COMMIT_MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?: .+'; then
    log_debug "Commit doesn't follow conventional format. Recommended: type(scope): description"
fi
[ ${#COMMIT_MSG} -lt 10 ] && log_warning "Commit message is very short (${#COMMIT_MSG} chars) - consider adding more context"

# ===========================
# BUILD WEBHOOK PAYLOAD
# ===========================
log_debug "Building webhook payload..."

# Truncate file list if needed (max 50 files)
CHANGED_FILES_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
CHANGED_FILES_JSON=$(echo "$CHANGED_FILES" | head -n 50 | grep -v '^$' | jq -R -s -c 'split("\n") | map(select(length > 0))')
[ -z "$CHANGED_FILES_JSON" ] || [ "$CHANGED_FILES_JSON" = "null" ] && CHANGED_FILES_JSON="[]"
[ "$CHANGED_FILES_COUNT" -gt 50 ] && log_warning "Changed files list truncated: $CHANGED_FILES_COUNT total, sending first 50"

# Build payload (exactly 10 properties - GitHub API limit)
PAYLOAD=$(jq -n \
    --arg event_type "vm-registry-commit" \
    --arg environment "$ENVIRONMENT" \
    --arg branch "$CURRENT_BRANCH" \
    --arg commit_sha "$COMMIT_SHA" \
    --arg commit_message "$COMMIT_MSG" \
    --arg commit_author "$COMMIT_AUTHOR" \
    --arg vm_hostname "$VM_HOSTNAME" \
    --argjson flow_changes "$FLOW_CHANGES" \
    --argjson registry_changes "$REGISTRY_CHANGES" \
    --argjson changed_files "$CHANGED_FILES_JSON" \
    --arg is_feature_branch "$IS_FEATURE_BRANCH" \
    '{event_type: $event_type, client_payload: {environment: $environment, branch: $branch, commit_sha: $commit_sha, commit_message: $commit_message, commit_author: $commit_author, vm_hostname: $vm_hostname, flow_changes: $flow_changes, registry_changes: $registry_changes, changed_files: $changed_files, is_feature_branch: $is_feature_branch}}')

log_debug "Payload: $PAYLOAD"

# Validate payload
echo "$PAYLOAD" | jq empty 2>/dev/null || {
    log_error "Invalid JSON payload generated"
    log_debug "Payload content: $PAYLOAD"
    exit 1
}

PROP_COUNT=$(echo "$PAYLOAD" | jq '.client_payload | keys | length')
log_debug "Property count: $PROP_COUNT (max: 10)"
[ "$PROP_COUNT" -gt 10 ] && {
    log_error "Too many properties: $PROP_COUNT (max: 10) - GitHub API will reject"
    exit 1
}

# ===========================
# TRIGGER GITHUB WORKFLOW
# ===========================
[ "$IS_FEATURE_BRANCH" = "true" ] && \
    log_info "Triggering GitHub workflow for feature branch '$CURRENT_BRANCH' -> develop..." || \
    log_info "Triggering GitHub workflow for '$ENVIRONMENT' environment..."

# Retry with exponential backoff
MAX_RETRIES=3
SUCCESS=false

for RETRY_COUNT in $(seq 0 $((MAX_RETRIES - 1))); do
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/$GITHUB_REPO/dispatches" \
        -d "$PAYLOAD" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    log_debug "HTTP Code: $HTTP_CODE"
    [ -n "$RESPONSE_BODY" ] && log_debug "Response: $RESPONSE_BODY"

    if [ "$HTTP_CODE" = "204" ]; then
        SUCCESS=true
        break
    elif [ $RETRY_COUNT -lt $((MAX_RETRIES - 1)) ]; then
        WAIT_TIME=$((3 * (RETRY_COUNT + 1)))
        log_warning "Attempt $((RETRY_COUNT + 1)) failed (HTTP $HTTP_CODE), retrying in ${WAIT_TIME}s..."
        sleep $WAIT_TIME
    fi
done

# ===========================
# HANDLE RESULT
# ===========================
if [ "$SUCCESS" = "true" ]; then
    log_success "Workflow triggered successfully!"
    echo ""
    log_info "GitHub Actions will now:"
    
    if [ "$IS_FEATURE_BRANCH" = "true" ]; then
        echo "  1. Sync changes from VM to GitHub"
        echo "  2. Create PR from '$CURRENT_BRANCH' -> 'develop'"
        echo "  3. Wait for team review"
        echo "  4. After merge: Deploy to $ENVIRONMENT environment"
    else
        TARGET_BRANCH=$([ "$ENVIRONMENT" = "production" ] && echo "main" || echo "$ENVIRONMENT")
        echo "  1. Sync changes from VM to GitHub"
        echo "  2. Create PR to '$TARGET_BRANCH' branch"
        echo "  3. After merge: Deploy to ${ENVIRONMENT^}"
    fi
    
    echo ""
    log_info "Monitor progress: https://github.com/$GITHUB_REPO/actions"
    echo "$(date -Iseconds) | SUCCESS | $COMMIT_SHORT | $ENVIRONMENT | $COMMIT_AUTHOR" >> ~/.nifi_cicd_hook.log
    exit 0
fi

# Handle errors
case $HTTP_CODE in
    401) log_error "Authentication failed (HTTP 401) - PAT may have expired"; log_info "Update PAT in ~/.nifi_cicd_env" ;;
    404) log_error "Repository not found (HTTP 404) - Check GITHUB_REPO: $GITHUB_REPO" ;;
    403) log_error "Forbidden (HTTP 403) - Check PAT scopes ('repo', 'workflow'), rate limits, or IP restrictions" ;;
    422) log_error "Unprocessable Entity (HTTP 422) - Too many properties (>10), invalid event_type, or malformed JSON"; log_debug "Response: $RESPONSE_BODY" ;;
    400) log_error "Bad Request (HTTP 400)"; log_debug "Response: $RESPONSE_BODY" ;;
    *) log_error "Failed to trigger workflow (HTTP $HTTP_CODE)"; [ -n "$RESPONSE_BODY" ] && log_debug "Response: $RESPONSE_BODY" ;;
esac

echo "$(date -Iseconds) | FAILED | $COMMIT_SHORT | $ENVIRONMENT | HTTP $HTTP_CODE" >> ~/.nifi_cicd_hook.log
log_warning "Workflow trigger failed after $MAX_RETRIES attempts, but commit was successful"
log_info "Manual trigger: https://github.com/$GITHUB_REPO/actions/workflows/webhook-trigger.yml"
log_info "Or run: nifi_trigger_workflow 'Manual trigger for $COMMIT_SHORT'"

exit 1