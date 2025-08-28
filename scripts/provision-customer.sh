#!/bin/bash
# Provision a new customer email address for 2FA code collection
# Creates: [customer]@auth.novoflow.io

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Provision Customer 2FA Email"
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
SES_DOMAIN=$(jq -r .ses_domain "$SETUP_FILE")

echo -e "\n${YELLOW}Provisioning new customer email${NC}"
echo -e "Domain: ${BLUE}@${SES_DOMAIN}${NC}\n"

# Get customer details
read -p "Customer name (e.g., acme, walmart): " CUSTOMER_NAME
CUSTOMER_NAME=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -d '[:punct:]')

# Validate customer name
if [[ ! "$CUSTOMER_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}❌ Invalid customer name. Use only lowercase letters, numbers, and hyphens.${NC}"
    exit 1
fi

# Create email address
EMAIL_ADDRESS="${CUSTOMER_NAME}@${SES_DOMAIN}"

# Check if already exists
echo -e "\n${YELLOW}Checking availability...${NC}"
EXISTING=$(aws ses describe-receipt-rule \
    --rule-set-name "inbound-auth-hipaa-$ENV" \
    --rule-name "2fa-emails-hipaa-$ENV" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" 2>/dev/null | jq -r '.Rule.Recipients[]' | grep -c "^$EMAIL_ADDRESS$" || true)

if [ "$EXISTING" -gt 0 ]; then
    echo -e "${RED}❌ Email $EMAIL_ADDRESS already exists${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Email available${NC}"

# Optional: Get customer contact info for documentation
echo -e "\n${YELLOW}Customer Information (optional, press Enter to skip)${NC}"
read -p "Company full name: " COMPANY_NAME
read -p "Technical contact email: " TECH_CONTACT
read -p "Use case description: " USE_CASE

# Generate API key (optional - for future authentication)
API_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | head -c 64 | base64 | tr -d '/+=' | cut -c -32)

# Summary
echo -e "\n${BLUE}Configuration Summary:${NC}"
echo "  Customer ID: $CUSTOMER_NAME"
echo "  Email Address: $EMAIL_ADDRESS"
echo "  Environment: $ENV"
if [ ! -z "$COMPANY_NAME" ]; then
    echo "  Company: $COMPANY_NAME"
fi
echo ""
echo -e "${YELLOW}This will create:${NC}"
echo "  • Email recipient: $EMAIL_ADDRESS"
echo "  • Auto-extraction of 2FA codes from any sender"
echo "  • API access to retrieve codes"
echo ""
read -p "Provision this customer? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

# Update Terraform configuration
echo -e "\n${YELLOW}Updating configuration...${NC}"
ENV_DIR="envs/$ENV"

# Backup files
cp "$ENV_DIR/main.tf" "$ENV_DIR/main.tf.backup"
cp "$ENV_DIR/terraform.tfvars" "$ENV_DIR/terraform.tfvars.backup"

# Add tenant configuration with wildcard sender allowlist
# Update main.tf - Use awk instead of sed for better multiline handling
awk -v customer="$CUSTOMER_NAME" '
    /tenant_configs = \{/ { in_block = 1 }
    in_block && /^  \}/ { 
        print "    \"" customer "\" = {"
        print "      sender_allowlist = [\"*\"]  # Accept from any sender"
        print "      regex_profile    = \"universal\"  # Matches various 2FA formats"
        print "    }"
    }
    { print }
' "$ENV_DIR/main.tf" > "$ENV_DIR/main.tf.new"
mv "$ENV_DIR/main.tf.new" "$ENV_DIR/main.tf"

# Update recipients
CURRENT_RECIPIENTS=$(grep "recipients" "$ENV_DIR/terraform.tfvars" | sed 's/.*\[\(.*\)\].*/\1/')
if [ -z "$CURRENT_RECIPIENTS" ] || [ "$CURRENT_RECIPIENTS" = '""' ]; then
    NEW_RECIPIENTS="\"$EMAIL_ADDRESS\""
else
    NEW_RECIPIENTS="$CURRENT_RECIPIENTS, \"$EMAIL_ADDRESS\""
fi
sed -i.tmp "s/recipients = \[.*\]/recipients = [$NEW_RECIPIENTS]/" "$ENV_DIR/terraform.tfvars"

# Apply changes
echo -e "\n${YELLOW}Applying changes...${NC}"
cd "$ENV_DIR"
terraform plan -target=module.ses_inbound.aws_ses_receipt_rule.inbound_to_s3 -target=module.twofa_parser -out=tfplan

echo -e "\n${GREEN}Ready to deploy!${NC}"
echo "To apply changes, run:"
echo -e "${BLUE}cd $ENV_DIR && terraform apply tfplan${NC}"

# Create customer documentation
cd ../..
mkdir -p "customers"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "customers/${CUSTOMER_NAME}.json" <<EOF
{
  "customer_id": "$CUSTOMER_NAME",
  "email": "$EMAIL_ADDRESS",
  "api_key": "$API_KEY",
  "environment": "$ENV",
  "created": "$TIMESTAMP",
  "company": "$COMPANY_NAME",
  "tech_contact": "$TECH_CONTACT",
  "use_case": "$USE_CASE",
  "status": "active"
}
EOF

# Get API URL from setup outputs
API_URL=$(jq -r .api_gateway_url "$SETUP_FILE" 2>/dev/null || echo "https://your-api-gateway-url")

# Create customer README
cat > "customers/${CUSTOMER_NAME}-README.md" <<EOF
# Customer: $CUSTOMER_NAME

## Access Details

- **Email Address**: \`$EMAIL_ADDRESS\`
- **API Key**: \`$API_KEY\`
- **Environment**: $ENV
- **Created**: $TIMESTAMP

## How It Works

1. Forward or redirect 2FA emails to: \`$EMAIL_ADDRESS\`
2. Our system automatically extracts the verification code
3. Retrieve the code via API (see below)

## API Usage

### Retrieve Latest Code

\`\`\`bash
curl -X POST $API_URL/codes \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: $API_KEY" \\
  -d '{
    "recipient": "$EMAIL_ADDRESS"
  }'
\`\`\`

### Response Format

\`\`\`json
{
  "code": "123456",
  "recipient": "$EMAIL_ADDRESS",
  "expiresAt": "2025-01-01T12:00:00Z"
}
\`\`\`

### Status Codes

- \`200\`: Code found and returned
- \`404\`: No active code found
- \`401\`: Invalid API key
- \`429\`: Rate limit exceeded

## Code Extraction

The system automatically extracts codes from various formats:
- "Your verification code is: 123456"
- "Code: 123456"
- "OTP: 123456"
- "2FA: 123456"
- Any 4-8 digit number in the email

## Important Notes

- Codes expire after 15 minutes
- Each code can only be retrieved once (marked as USED)
- All emails are encrypted and deleted after processing
- HIPAA compliant infrastructure

## Support

For technical support or issues:
- Email: support@novoflow.io
- Include your customer ID: $CUSTOMER_NAME
EOF

# Provision API key in API Gateway
echo -e "\n${YELLOW}Provisioning API key in API Gateway...${NC}"

# Get API Gateway config
API_ID=$(jq -r .api_gateway_id "$SETUP_FILE" 2>/dev/null || echo "ph8a9c26u5")

# Check if key already exists
EXISTING_KEY=$(aws apigateway get-api-keys \
    --profile "$AWS_PROFILE" \
    --region "$REGION" \
    --name-query "$CUSTOMER_NAME-key" \
    --query "items[0].id" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "None" ]; then
    echo -e "  ${YELLOW}API key already exists${NC}"
else
    # Create API key
    KEY_ID=$(aws apigateway create-api-key \
        --profile "$AWS_PROFILE" \
        --region "$REGION" \
        --name "$CUSTOMER_NAME-key" \
        --description "2FA API key for $EMAIL_ADDRESS" \
        --value "$API_KEY" \
        --enabled \
        --query 'id' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$KEY_ID" ] && [ "$KEY_ID" != "None" ]; then
        echo -e "  ${GREEN}✓ Created API key${NC}"
        
        # Get usage plan
        USAGE_PLAN=$(aws apigateway get-usage-plans \
            --profile "$AWS_PROFILE" \
            --region "$REGION" \
            --query "items[?apiStages[?apiId=='$API_ID']].id | [0]" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$USAGE_PLAN" ] && [ "$USAGE_PLAN" != "None" ]; then
            # Associate with usage plan
            aws apigateway create-usage-plan-key \
                --profile "$AWS_PROFILE" \
                --region "$REGION" \
                --usage-plan-id "$USAGE_PLAN" \
                --key-id "$KEY_ID" \
                --key-type API_KEY >/dev/null 2>&1
            echo -e "  ${GREEN}✓ Associated with usage plan${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️ Could not create API key (may need manual setup)${NC}"
    fi
fi

echo -e "\n${GREEN}✅ Customer provisioned successfully!${NC}"
echo ""
echo -e "${BLUE}Customer Details:${NC}"
echo "  Email: $EMAIL_ADDRESS"
echo "  API Key: $API_KEY"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Apply Terraform changes: cd $ENV_DIR && terraform apply tfplan"
echo "2. Share credentials: customers/${CUSTOMER_NAME}-README.md"
echo "3. Test the integration: ./scripts/test-api.sh $EMAIL_ADDRESS"
echo ""
echo -e "${GREEN}The customer can now forward 2FA emails to $EMAIL_ADDRESS${NC}"
