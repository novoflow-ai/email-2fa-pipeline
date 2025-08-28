#!/bin/bash
# Update scripts to use correct API Gateway configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Update API Gateway Configuration"
echo "======================================"

# Check if setup has been run
SETUP_FILE=$(find . -path "*/envs/*/setup-outputs.json" 2>/dev/null | head -1)
if [ -z "$SETUP_FILE" ] || [ ! -f "$SETUP_FILE" ]; then
    echo -e "${RED}❌ Infrastructure not set up. Run setup-infrastructure.sh first.${NC}"
    exit 1
fi

# Load setup outputs
AWS_PROFILE=$(jq -r .aws_profile "$SETUP_FILE")
REGION=$(jq -r .region "$SETUP_FILE")
ENV=$(jq -r .env "$SETUP_FILE")

# API Gateway configuration
API_ID="ph8a9c26u5"
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev"
API_KEY="188e3f32b6e6f40485b62727113035048dd469e2749a31386673088adc3047d6"

echo -e "\n${YELLOW}Current Configuration:${NC}"
echo "  Profile: $AWS_PROFILE"
echo "  Region: $REGION"
echo "  Environment: $ENV"
echo "  API Gateway: $API_URL"
echo ""

# Update setup-outputs.json with API info
echo -e "${YELLOW}Updating setup outputs...${NC}"
jq --arg url "$API_URL" --arg key "$API_KEY" --arg id "$API_ID" \
  '. + {api_gateway_url: $url, api_gateway_id: $id, api_key: $key}' \
  "$SETUP_FILE" > "$SETUP_FILE.tmp" && mv "$SETUP_FILE.tmp" "$SETUP_FILE"
echo -e "${GREEN}✓ Updated setup-outputs.json${NC}"

# Update all customer README files with correct API URL
echo -e "\n${YELLOW}Updating customer documentation...${NC}"
for customer_readme in customers/*-README.md; do
    if [ -f "$customer_readme" ]; then
        customer_name=$(basename "$customer_readme" -README.md)
        echo -e "  Updating $customer_name..."
        sed -i.bak "s|https://your-api-gateway-url|$API_URL|g" "$customer_readme"
        rm -f "${customer_readme}.bak"
    fi
done
echo -e "${GREEN}✓ Customer READMEs updated${NC}"

# Create updated test script that uses API Gateway
echo -e "\n${YELLOW}Creating API test script...${NC}"
cat > scripts/test-api.sh <<'EOF'
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

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

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
EOF

chmod +x scripts/test-api.sh
echo -e "${GREEN}✓ Created test-api.sh${NC}"

# Create script to provision API keys in API Gateway
echo -e "\n${YELLOW}Creating API key provisioning script...${NC}"
cat > scripts/provision-api-key.sh <<'EOF'
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
EOF

chmod +x scripts/provision-api-key.sh
echo -e "${GREEN}✓ Created provision-api-key.sh${NC}"

# Summary
echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}✅ API Configuration Updated!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}What was updated:${NC}"
echo "  • setup-outputs.json: Added API Gateway URL and key"
echo "  • Customer READMEs: Updated with correct API URL"
echo "  • test-api.sh: New script to test via API Gateway"
echo "  • provision-api-key.sh: Script to add customer keys to API Gateway"
echo ""
echo -e "${YELLOW}For existing customers:${NC}"
echo "  Run: ./scripts/provision-api-key.sh <customer-name>"
echo ""
echo -e "${YELLOW}To test the API:${NC}"
echo "  Run: ./scripts/test-api.sh <email>"
echo ""
echo -e "${GREEN}API Endpoint: $API_URL/codes${NC}"
