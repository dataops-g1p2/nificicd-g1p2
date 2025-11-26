#!/bin/bash

# Setup NiFi Registry Script
# This script creates buckets in NiFi Registry for version control

set -e

REGISTRY_URL="http://localhost:18080"
BUCKET_NAME="${1:-nifi-flows}"

echo "🔧 Setting up NiFi Registry..."
echo "Registry URL: $REGISTRY_URL"
echo "Bucket Name: $BUCKET_NAME"
echo ""

# Wait for NiFi Registry to be ready
echo "⏳ Waiting for NiFi Registry to be ready..."
max_attempts=15
attempt=0
while ! curl -sf "$REGISTRY_URL/nifi-registry" > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "❌ Error: NiFi Registry did not start in time"
        exit 1
    fi
    echo "   Attempt $attempt/$max_attempts - waiting..."
    sleep 2
done

echo "NiFi Registry is ready!"
echo ""

# Create bucket using REST API
echo "Creating bucket: $BUCKET_NAME"
BUCKET_DATA=$(cat <<EOF
{
  "name": "$BUCKET_NAME",
  "description": "Bucket for storing NiFi flow versions",
  "allowPublicRead": false
}
EOF
)

RESPONSE=$(curl -s -X POST "$REGISTRY_URL/nifi-registry-api/buckets" \
    -H "Content-Type: application/json" \
    -d "$BUCKET_DATA" \
    -w "\n%{http_code}" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "Bucket created successfully!"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" = "409" ]; then
    echo "ℹBucket already exists"
else
    echo "Warning: Unexpected response (HTTP $HTTP_CODE)"
    echo "$BODY"
fi

echo ""
echo "Listing all buckets:"
curl -s "$REGISTRY_URL/nifi-registry-api/buckets" | jq '.' 2>/dev/null || \
    curl -s "$REGISTRY_URL/nifi-registry-api/buckets"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Access NiFi Registry: $REGISTRY_URL/nifi-registry"
echo "2. In NiFi, connect to this registry:"
echo "   - Click the hamburger menu (top-right) → Controller Settings"
echo "   - Go to 'Registry Clients' tab"
echo "   - Add a new Registry Client:"
echo "     • Name: NiFi Registry"
echo "     • URL: http://nifi-registry:18080"
echo "3. Version control your flows by right-clicking on process groups"
echo "   and selecting 'Version' → 'Start version control'"
echo ""
echo "NiFi Registry setup complete!"