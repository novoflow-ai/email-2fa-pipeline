#!/bin/bash
# manage-senders.sh
# Manage application-level sender whitelisting and check SES status

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================"
echo -e "  Sender Whitelist Management"
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
ENV=$(jq -r .env "$SETUP_FILE")
ENV_DIR=$(dirname "$SETUP_FILE")

# Function to check SES sandbox status
check_ses_status() {
    echo -e "\n${YELLOW}Checking SES Account Status...${NC}"
    
    ACCOUNT_STATUS=$(aws sesv2 get-account --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || echo "{}")
    PRODUCTION_ACCESS=$(echo "$ACCOUNT_STATUS" | jq -r '.ProductionAccessEnabled // false')
    
    if [ "$PRODUCTION_ACCESS" = "true" ]; then
        echo -e "${GREEN}✅ Production Access: ENABLED${NC}"
        echo -e "  You can receive emails from ANY sender!"
        echo -e "  Application-level whitelisting still applies for security."
    else
        echo -e "${YELLOW}⚠️  Sandbox Mode: ACTIVE${NC}"
        echo -e "  AWS will block emails from unverified senders."
        echo -e "  Run ${GREEN}./scripts/request-production-access.sh${NC} to fix this."
    fi
}

# Function to list customer whitelists
list_customer_whitelists() {
    echo -e "\n${YELLOW}Customer Sender Whitelists:${NC}"
    echo -e "These control which senders can trigger 2FA extraction per customer.\n"
    
    # Extract tenant configs from main.tf
    if [ ! -f "$ENV_DIR/main.tf" ]; then
        echo -e "${RED}main.tf not found${NC}"
        return
    fi
    
    # Parse tenant configs
    echo -e "${BLUE}Customer         Email                          Allowed Senders${NC}"
    echo -e "─────────────────────────────────────────────────────────────────────"
    
    # Extract each tenant and their whitelist
    awk '/tenant_configs = {/,/^  }/' "$ENV_DIR/main.tf" | \
    awk '/".*" = {/,/}/' | \
    awk '
        /".*" = {/ { 
            gsub(/"/, "", $1)
            tenant = $1
        }
        /sender_allowlist/ {
            gsub(/.*\[/, "")
            gsub(/\].*/, "")
            gsub(/"/, "")
            if (tenant) {
                printf "%-15s  %-30s %s\n", tenant, tenant "@auth.novoflow.io", $0
                tenant = ""
            }
        }
    '
    
    echo ""
    echo -e "${YELLOW}Note:${NC} '*' means accept from ALL senders"
}

# Function to update customer whitelist
update_customer_whitelist() {
    echo -e "\n${YELLOW}Update Customer Whitelist${NC}"
    
    # List current customers
    echo -e "\nAvailable customers:"
    grep '".*" = {' "$ENV_DIR/main.tf" | grep -v tenant_configs | sed 's/.*"\(.*\)".*/  - \1/'
    
    echo ""
    read -p "Customer name to update: " CUSTOMER
    
    if [ -z "$CUSTOMER" ]; then
        echo -e "${RED}Customer name required${NC}"
        return
    fi
    
    # Check if customer exists
    if ! grep -q "\"$CUSTOMER\" = {" "$ENV_DIR/main.tf"; then
        echo -e "${RED}Customer '$CUSTOMER' not found${NC}"
        return
    fi
    
    # Get current whitelist
    CURRENT=$(awk "/\"$CUSTOMER\" = {/,/}/" "$ENV_DIR/main.tf" | grep sender_allowlist | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"')
    
    echo -e "\nCurrent whitelist: ${BLUE}$CURRENT${NC}"
    echo -e "\nEnter new allowed senders:"
    echo -e "  • Use '*' to accept from all senders"
    echo -e "  • Comma-separate multiple: sender1@domain.com,sender2@domain.com"
    echo -e "  • Use @domain.com to accept all from a domain"
    
    read -p "New whitelist: " NEW_WHITELIST
    
    if [ -z "$NEW_WHITELIST" ]; then
        echo -e "${RED}Whitelist cannot be empty${NC}"
        return
    fi
    
    # Format the whitelist for Terraform
    if [ "$NEW_WHITELIST" = "*" ]; then
        FORMATTED='["*"]'
    else
        # Convert comma-separated to JSON array
        FORMATTED=$(echo "$NEW_WHITELIST" | awk '{
            gsub(/,/, "\", \""); 
            gsub(/^/, "[\""); 
            gsub(/$/, "\"]")
            print
        }')
    fi
    
    # Update main.tf
    sed -i.bak "/\"$CUSTOMER\" = {/,/}/ s/sender_allowlist = .*/sender_allowlist = $FORMATTED/" "$ENV_DIR/main.tf"
    
    echo -e "${GREEN}✓ Updated whitelist for $CUSTOMER${NC}"
    echo -e "\n${YELLOW}To apply changes:${NC}"
    echo -e "  cd $ENV_DIR && terraform apply"
}

# Main menu
while true; do
    echo -e "\n${BLUE}Choose an option:${NC}"
    echo "1. Check SES status"
    echo "2. View customer whitelists"
    echo "3. Update customer whitelist"
    echo "4. Request production access"
    echo "0. Exit"
    
    read -p "Option: " choice
    
    case $choice in
        1)
            check_ses_status
            ;;
        2)
            list_customer_whitelists
            ;;
        3)
            update_customer_whitelist
            ;;
        4)
            echo -e "\n${YELLOW}To request production access, run:${NC}"
            echo -e "${GREEN}./scripts/request-production-access.sh${NC}"
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
done