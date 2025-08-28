#!/bin/bash
# List all provisioned customers and their status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Customer Email Accounts"
echo "======================================"

# Check if setup has been run
# Get script's parent directory (project root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SETUP_FILE=$(find "$PROJECT_ROOT" -path "*/envs/*/setup-outputs.json" 2>/dev/null | head -1)
if [ -z "$SETUP_FILE" ] || [ ! -f "$SETUP_FILE" ]; then
    echo -e "${RED}❌ Infrastructure not set up. Run setup-infrastructure.sh first.${NC}"
    exit 1
fi

# Load setup outputs
AWS_PROFILE=$(jq -r .aws_profile "$SETUP_FILE")
REGION=$(jq -r .region "$SETUP_FILE")
ENV=$(jq -r .env "$SETUP_FILE")
SES_DOMAIN=$(jq -r .ses_domain "$SETUP_FILE")

echo -e "\n${CYAN}Environment: $ENV${NC}"
echo -e "${CYAN}Domain: @$SES_DOMAIN${NC}\n"

# List customers from local config
if [ -d "customers" ] && [ "$(ls -A customers/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
    echo -e "${BLUE}Provisioned Customers:${NC}\n"
    
    printf "%-20s %-35s %-10s %-20s\n" "Customer ID" "Email" "Status" "Created"
    printf "%-20s %-35s %-10s %-20s\n" "────────────" "─────────────────────" "──────" "──────────"
    
    for customer_file in customers/*.json; do
        if [ -f "$customer_file" ]; then
            CUSTOMER_ID=$(jq -r .customer_id "$customer_file")
            EMAIL=$(jq -r .email "$customer_file")
            STATUS=$(jq -r .status "$customer_file")
            CREATED=$(jq -r .created "$customer_file" | cut -d'T' -f1)
            
            # Color code status
            case $STATUS in
                active) STATUS_COLOR="${GREEN}Active${NC}";;
                inactive) STATUS_COLOR="${YELLOW}Inactive${NC}";;
                *) STATUS_COLOR="${RED}Unknown${NC}";;
            esac
            
            printf "%-20s %-35s %-10b %-20s\n" "$CUSTOMER_ID" "$EMAIL" "$STATUS_COLOR" "$CREATED"
        fi
    done
    
    # Count totals
    TOTAL=$(ls customers/*.json 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo -e "${YELLOW}Total: $TOTAL customers${NC}"
else
    echo -e "${YELLOW}No customers provisioned yet.${NC}"
    echo -e "Run ${BLUE}./scripts/provision-customer.sh${NC} to add your first customer."
fi

# Show recent 2FA activity
echo -e "\n${BLUE}Recent 2FA Activity (last 24 hours):${NC}\n"

# Get activity from DynamoDB
YESTERDAY=$(date -u -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s)

aws dynamodb scan \
    --table-name "2fa-codes-$ENV" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --output json 2>/dev/null | jq -r '.Items[] | 
    select(.expiresAt.N | tonumber > '$YESTERDAY') | 
    "\(.recipient.S)|\(.status.S)|\(.processedAt.S // .sk.S)"' | \
    sort -t'|' -k3 -r | head -10 | while IFS='|' read -r recipient status timestamp; do
    
    # Extract customer name from email
    customer=$(echo "$recipient" | cut -d'@' -f1)
    
    # Format timestamp
    time_display=$(echo "$timestamp" | cut -d'T' -f2 | cut -d'.' -f1)
    date_display=$(echo "$timestamp" | cut -d'T' -f1)
    
    # Status icon
    case $status in
        ACTIVE) icon="🟢";;
        USED) icon="✓";;
        *) icon="?";;
    esac
    
    printf "  %s %-15s %-25s %s %s\n" "$icon" "$customer" "$recipient" "$date_display" "$time_display"
done

if [ $? -ne 0 ] || [ -z "$(aws dynamodb scan --table-name "2fa-codes-$ENV" --region "$REGION" --profile "$AWS_PROFILE" --output json 2>/dev/null | jq '.Items[]')" ]; then
    echo "  No recent activity"
fi

# Show API endpoint
echo -e "\n${BLUE}API Endpoint:${NC}"
API_URL=$(cd envs/$ENV && terraform output -raw twofa_api_url 2>/dev/null || echo "Not deployed")
if [ "$API_URL" != "Not deployed" ]; then
    echo "  $API_URL/codes"
    echo ""
    echo -e "${YELLOW}Example API call:${NC}"
    echo "  curl -X POST $API_URL/codes \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -H \"X-API-Key: <customer-api-key>\" \\"
    echo "    -d '{\"recipient\": \"<customer>@$SES_DOMAIN\"}'"
else
    echo "  Not yet deployed"
fi

echo -e "\n${CYAN}Commands:${NC}"
echo "  Provision customer:  ./scripts/provision-customer.sh"
echo "  Test customer:       ./scripts/test-customer.sh <customer-id>"
echo "  Remove customer:     ./scripts/remove-customer.sh"
