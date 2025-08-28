#!/bin/bash
# Provision API key in API Gateway for a customer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Provision API Key in API Gateway"
echo "======================================"

# Check if setup has been run
SETUP_FILE=$(find . -path "*/envs/*/setup-outputs.json" 2>/dev/null | head -1)
if [ -z "$SETUP_FILE" ] || [ ! -f "$SETUP_FILE" ]; then
    echo -e "${RED}❌ Infrastructure not set up.${NC}"
    exit 1
fi

# Load setup outputs
AWS_PROFILE=$(jq -r .aws_profile "$SETUP_FILE")
REGION=$(jq -r .region "$SETUP_FILE")
API_ID=$(jq -r .api_gateway_id "$SETUP_FILE")

if [ -z "$1" ]; then
    echo "Usage: $0 <customer-name>"
    exit 1
fi

CUSTOMER_NAME="$1"

# Load customer config
if [ ! -f "customers/${CUSTOMER_NAME}.json" ]; then
    echo -e "${RED}❌ Customer $CUSTOMER_NAME not found${NC}"
    exit 1
fi

EMAIL=$(jq -r .email "customers/${CUSTOMER_NAME}.json")
STORED_KEY=$(jq -r .api_key "customers/${CUSTOMER_NAME}.json")

echo -e "\n${YELLOW}Provisioning API key for:${NC}"
echo "  Customer: $CUSTOMER_NAME"
echo "  Email: $EMAIL"
echo "  Key Value: ${STORED_KEY:0:10}..."
echo ""

# Check if key already exists
EXISTING_KEY=$(aws apigateway get-api-keys \
    --profile "$AWS_PROFILE" \
    --region "$REGION" \
    --name-query "$CUSTOMER_NAME-key" \
    --query "items[0].id" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "None" ]; then
    echo -e "${YELLOW}⚠️ API key already exists for $CUSTOMER_NAME${NC}"
    echo "  Key ID: $EXISTING_KEY"
else
    # Create API key
    echo -e "${YELLOW}Creating API key...${NC}"
    KEY_ID=$(aws apigateway create-api-key \
        --profile "$AWS_PROFILE" \
        --region "$REGION" \
        --name "$CUSTOMER_NAME-key" \
        --description "2FA API key for $EMAIL" \
        --value "$STORED_KEY" \
        --enabled \
        --query 'id' \
        --output text)
    
    echo -e "${GREEN}✓ Created API key: $KEY_ID${NC}"
    
    # Get usage plan (assuming there's one for the API)
    USAGE_PLAN=$(aws apigateway get-usage-plans \
        --profile "$AWS_PROFILE" \
        --region "$REGION" \
        --query "items[?apiStages[?apiId=='$API_ID']].id | [0]" \
        --output text)
    
    if [ ! -z "$USAGE_PLAN" ] && [ "$USAGE_PLAN" != "None" ]; then
        # Associate with usage plan
        echo -e "${YELLOW}Associating with usage plan...${NC}"
        aws apigateway create-usage-plan-key \
            --profile "$AWS_PROFILE" \
            --region "$REGION" \
            --usage-plan-id "$USAGE_PLAN" \
            --key-id "$KEY_ID" \
            --key-type API_KEY >/dev/null
        
        echo -e "${GREEN}✓ Associated with usage plan${NC}"
    else
        echo -e "${YELLOW}⚠️ No usage plan found. API key created but not associated.${NC}"
    fi
fi

echo -e "\n${GREEN}✅ API key ready for $CUSTOMER_NAME${NC}"
