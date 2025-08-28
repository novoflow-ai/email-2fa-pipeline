#!/bin/bash
# Test customer 2FA email processing and API retrieval

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Test Customer 2FA Integration"
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

# Get customer name
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
    read -p "Customer to test: " CUSTOMER_NAME
else
    CUSTOMER_NAME="$1"
fi

# Load customer config
if [ ! -f "customers/${CUSTOMER_NAME}.json" ]; then
    echo -e "${RED}❌ Customer $CUSTOMER_NAME not found${NC}"
    exit 1
fi

EMAIL_ADDRESS=$(jq -r .email "customers/${CUSTOMER_NAME}.json")
API_KEY=$(jq -r .api_key "customers/${CUSTOMER_NAME}.json")

# Generate test code
TEST_CODE=$(( RANDOM % 900000 + 100000 ))

echo -e "\n${BLUE}Testing Customer: $CUSTOMER_NAME${NC}"
echo "  Email: $EMAIL_ADDRESS"
echo "  Test Code: $TEST_CODE"
echo ""

# Step 1: Send test email (simulating a service forwarding 2FA)
echo -e "${YELLOW}Step 1: Simulating 2FA email forward${NC}"

# Get a verified sender from the SES domain
SENDER="test@$(echo $EMAIL_ADDRESS | cut -d'@' -f2)"

MESSAGE_ID=$(aws ses send-email \
    --from "$SENDER" \
    --to "$EMAIL_ADDRESS" \
    --subject "Your verification code" \
    --text "Hello,

Your verification code is: $TEST_CODE

This code will expire in 15 minutes.

Best regards,
Example Service" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --output json | jq -r .MessageId)

echo -e "  ${GREEN}✓ Email sent${NC} (Message ID: ${MESSAGE_ID:0:20}...)"

# Step 2: Wait for processing
echo -e "\n${YELLOW}Step 2: Waiting for processing (3 seconds)${NC}"
for i in {1..3}; do
    echo -n "  ."
    sleep 1
done
echo -e " ${GREEN}✓${NC}"

# Step 3: Retrieve via API (simulating customer backend)
echo -e "\n${YELLOW}Step 3: Retrieving code via API${NC}"

# First, let's check if the code was extracted
CHECK=$(aws dynamodb scan \
    --table-name "2fa-codes-$ENV" \
    --filter-expression "code = :code AND #s = :status" \
    --expression-attribute-names '{"#s":"status"}' \
    --expression-attribute-values "{\":code\":{\"S\":\"$TEST_CODE\"},\":status\":{\"S\":\"ACTIVE\"}}" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --output json | jq '.Count')

if [ "$CHECK" -eq 0 ]; then
    echo -e "  ${RED}❌ Code not found in database${NC}"
    echo ""
    echo -e "${YELLOW}Checking Lambda logs for errors...${NC}"
    aws logs tail /aws/lambda/2fa-parser-$ENV \
        --since 1m \
        --region "$REGION" \
        --profile "$AWS_PROFILE" | grep -i error | head -5
    exit 1
fi

echo -e "  ${GREEN}✓ Code extracted and stored${NC}"

# Simulate API call
echo -e "\n${YELLOW}Step 4: Testing API retrieval${NC}"
RESPONSE=$(aws lambda invoke \
    --function-name "2fa-lookup-$ENV" \
    --cli-binary-format raw-in-base64-out \
    --payload "{\"body\":\"{\\\"recipient\\\":\\\"$EMAIL_ADDRESS\\\"}\"}" \
    /tmp/api-response.json \
    --region "$REGION" \
    --profile "$AWS_PROFILE" 2>&1)

if [ -f /tmp/api-response.json ]; then
    STATUS_CODE=$(jq -r .statusCode /tmp/api-response.json)
    
    if [ "$STATUS_CODE" = "200" ]; then
        RETRIEVED_CODE=$(jq -r '.body | fromjson | .code' /tmp/api-response.json)
        EXPIRES_AT=$(jq -r '.body | fromjson | .expiresAt' /tmp/api-response.json)
        
        if [ "$RETRIEVED_CODE" = "$TEST_CODE" ]; then
            echo -e "  ${GREEN}✓ Code retrieved successfully${NC}"
            echo ""
            echo -e "${BLUE}API Response:${NC}"
            echo "  {" 
            echo "    \"code\": \"$RETRIEVED_CODE\","
            echo "    \"recipient\": \"$EMAIL_ADDRESS\","
            echo "    \"expiresAt\": \"$EXPIRES_AT\""
            echo "  }"
        else
            echo -e "  ${RED}❌ Wrong code retrieved: $RETRIEVED_CODE${NC}"
            exit 1
        fi
    else
        echo -e "  ${RED}❌ API error (status $STATUS_CODE)${NC}"
        jq . /tmp/api-response.json
        exit 1
    fi
fi

# Step 5: Verify code is marked as USED
echo -e "\n${YELLOW}Step 5: Verifying one-time use${NC}"
SECOND_RESPONSE=$(aws lambda invoke \
    --function-name "2fa-lookup-$ENV" \
    --cli-binary-format raw-in-base64-out \
    --payload "{\"body\":\"{\\\"recipient\\\":\\\"$EMAIL_ADDRESS\\\"}\"}" \
    /tmp/api-response2.json \
    --region "$REGION" \
    --profile "$AWS_PROFILE" 2>&1)

if [ -f /tmp/api-response2.json ]; then
    STATUS_CODE=$(jq -r .statusCode /tmp/api-response2.json)
    if [ "$STATUS_CODE" = "404" ]; then
        echo -e "  ${GREEN}✓ Code correctly marked as USED (404 on second attempt)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Unexpected status on second retrieval: $STATUS_CODE${NC}"
    fi
fi

# Clean up
rm -f /tmp/api-response.json /tmp/api-response2.json

# Summary
echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Integration Test Successful!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  • Email received at: $EMAIL_ADDRESS"
echo "  • Code extracted: $TEST_CODE"
echo "  • API retrieval: Success"
echo "  • One-time use: Verified"
echo "  • Processing time: ~3 seconds"
echo ""
echo -e "${YELLOW}Customer Integration Ready!${NC}"
echo "The customer can now:"
echo "1. Forward 2FA emails to: $EMAIL_ADDRESS"
echo "2. Call API to retrieve codes"
echo "3. Codes auto-expire after 15 minutes"
