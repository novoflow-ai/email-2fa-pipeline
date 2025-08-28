#!/bin/bash
# request-production-access.sh
# Helper script to request SES production access

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================"
echo -e "  SES Production Access Request"
echo -e "======================================${NC}"

# Check if setup has been run
SETUP_FILE=$(find . -path "*/envs/*/setup-outputs.json" 2>/dev/null | head -1)
if [ -z "$SETUP_FILE" ] || [ ! -f "$SETUP_FILE" ]; then
    echo -e "${RED}❌ Infrastructure not set up. Run setup-infrastructure.sh first.${NC}"
    exit 1
fi

# Load setup outputs
AWS_PROFILE=$(jq -r .aws_profile "$SETUP_FILE")
REGION=$(jq -r .region "$SETUP_FILE")

echo -e "\n${YELLOW}Current SES Status:${NC}"

# Check current status
ACCOUNT_STATUS=$(aws sesv2 get-account --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || echo "{}")
PRODUCTION_ACCESS=$(echo "$ACCOUNT_STATUS" | jq -r '.ProductionAccessEnabled // false')

if [ "$PRODUCTION_ACCESS" = "true" ]; then
    echo -e "${GREEN}✅ You already have production access!${NC}"
    echo -e "Any email address can send to your pipeline."
    exit 0
fi

echo -e "${YELLOW}⚠️  You are in SANDBOX mode${NC}"
echo -e "Only verified senders can send emails to your pipeline."

# Get current quotas
QUOTA=$(aws ses get-send-quota --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || echo "{}")
DAILY_QUOTA=$(echo "$QUOTA" | jq -r '.Max24HourSend // 0')

echo -e "\nCurrent Limits:"
echo -e "  • Daily quota: ${DAILY_QUOTA} emails/day"
echo -e "  • Can only receive from verified addresses"

echo -e "\n${BLUE}Production Access Benefits:${NC}"
echo -e "  ✅ Receive from ANY sender (no verification needed)"
echo -e "  ✅ Send to ANY recipient"
echo -e "  ✅ Higher sending limits"
echo -e "  ✅ No manual sender verification"

echo -e "\n${YELLOW}Information for AWS Request:${NC}"
echo -e "${BLUE}Use Case:${NC}"
echo -e "  2FA code extraction service for healthcare systems."
echo -e "  We receive forwarded 2FA emails from various automated"
echo -e "  services (Epic, Cerner, RoyalSecure, etc.) and extract"
echo -e "  the codes for HIPAA-compliant healthcare applications."

echo -e "\n${BLUE}Email Type:${NC}"
echo -e "  Transactional (receiving 2FA codes)"

echo -e "\n${BLUE}Compliance:${NC}"
echo -e "  HIPAA-compliant infrastructure with encryption,"
echo -e "  short data retention, and audit logging."

echo -e "\n${BLUE}Volume:${NC}"
echo -e "  Estimate: 100-1000 2FA emails per day"

echo -e "\n${BLUE}Bounce Handling:${NC}"
echo -e "  Automated via SES notifications to SQS/DLQ"

echo -e "\n${YELLOW}Steps to Request:${NC}"
echo -e "1. Go to AWS Console → SES → Account dashboard"
echo -e "2. Click 'Request production access'"
echo -e "3. Fill the form with the information above"
echo -e "4. Submit and wait 24-48 hours"

# Generate console URL
CONSOLE_URL="https://console.aws.amazon.com/ses/home?region=${REGION}#/account"

echo -e "\n${BLUE}AWS Console URL:${NC}"
echo "$CONSOLE_URL"

read -p "Open AWS Console now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Try to open in browser
    if command -v open >/dev/null 2>&1; then
        open "$CONSOLE_URL"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$CONSOLE_URL"
    else
        echo -e "${YELLOW}Please open this URL in your browser:${NC}"
        echo "$CONSOLE_URL"
    fi
fi

echo -e "\n${GREEN}Good luck with your request!${NC}"
echo -e "AWS typically responds within 24-48 hours."
echo -e "\n${YELLOW}While waiting, you can:${NC}"
echo -e "• Test with emails you control (gmail, etc.)"
echo -e "• Configure application-level whitelists"
echo -e "• Document which 2FA services each customer uses"
