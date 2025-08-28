#!/bin/bash
# Test customer 2FA API retrieval via API Gateway

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Test 2FA API Gateway Integration"
echo "======================================"

# Check if setup has been run
SETUP_FILE=$(find . -path "*/envs/*/setup-outputs.json" 2>/dev/null | head -1)
if [ -z "$SETUP_FILE" ] || [ ! -f "$SETUP_FILE" ]; then
    echo -e "${RED}❌ Infrastructure not set up.${NC}"
    exit 1
fi

# Load setup outputs including API config
API_URL=$(jq -r .api_gateway_url "$SETUP_FILE")
API_KEY=$(jq -r .api_key "$SETUP_FILE")

# Get customer email
if [ -z "$1" ]; then
    echo -e "${YELLOW}Available customers:${NC}"
    for customer_file in customers/*.json; do
        if [ -f "$customer_file" ]; then
            customer=$(basename "$customer_file" .json)
            email=$(jq -r .email "$customer_file")
            echo "  • $customer ($email)"
        fi
    done
    echo ""
    read -p "Customer email to test: " EMAIL
else
    EMAIL="$1"
fi

echo -e "\n${YELLOW}Testing API Gateway${NC}"
echo "  URL: $API_URL/codes"
echo "  Email: $EMAIL"
echo ""

# Call API
echo -e "${BLUE}Calling API...${NC}"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/codes" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d "{\"recipient\":\"$EMAIL\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo -e "\n${BLUE}Response:${NC}"
echo "  Status: $HTTP_CODE"
echo "  Body: $BODY"

if [ "$HTTP_CODE" = "200" ]; then
    CODE=$(echo "$BODY" | jq -r .code)
    echo -e "\n${GREEN}✅ Success! Code: $CODE${NC}"
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "\n${YELLOW}⚠️ No active code found (this is normal if no recent email)${NC}"
else
    echo -e "\n${RED}❌ API Error${NC}"
fi
