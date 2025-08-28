#!/bin/bash
# Edit customer configuration (regex profiles, sender allowlist)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Edit Customer Configuration"
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
ENV_DIR=$(dirname "$SETUP_FILE")

# Function to display available regex profiles
show_regex_profiles() {
    echo -e "\n${BLUE}Available Regex Profiles:${NC}"
    echo ""
    echo -e "${CYAN}standard${NC} - Basic patterns for common 2FA formats"
    echo "  • Matches: 'code: 123456', 'verification code: 123456'"
    echo "  • Supports 4-8 digit codes"
    echo ""
    echo -e "${CYAN}universal${NC} - Comprehensive pattern matching (recommended)"
    echo "  • Matches: code, OTP, 2FA, token, pin, passcode"
    echo "  • Case-insensitive, multiple formats"
    echo "  • Includes fallback for any standalone 6-digit number"
    echo ""
    echo -e "${CYAN}alphanumeric${NC} - For codes with letters and numbers"
    echo "  • Matches: 'code: ABC123', 'token: X9Y8Z7'"
    echo "  • Supports 4-8 character alphanumeric codes"
    echo ""
    echo -e "${CYAN}royalhealth${NC} - Optimized for Royal Health EHR emails"
    echo "  • Matches: 'Use verification code 130651'"
    echo "  • Handles Royal Health specific format"
    echo "  • Includes universal fallback patterns"
    echo ""
    echo -e "${CYAN}custom${NC} - Define your own patterns"
    echo "  • Add custom regex patterns to the module"
    echo ""
}

# Function to show current customer config
show_customer_config() {
    local customer=$1
    echo -e "\n${BLUE}Current Configuration for $customer:${NC}"
    
    # Extract current config from main.tf
    if grep -q "\"$customer\"" "$ENV_DIR/main.tf"; then
        echo -e "${YELLOW}Found in Terraform config:${NC}"
        awk -v customer="$customer" '
            $0 ~ "\"" customer "\"" { found=1 }
            found && /sender_allowlist/ { 
                gsub(/.*sender_allowlist = \[/, "  Sender Allowlist: [")
                print
            }
            found && /regex_profile/ { 
                gsub(/.*regex_profile *= *"/, "  Regex Profile: ")
                gsub(/".*/, "")
                print
                found=0
            }
        ' "$ENV_DIR/main.tf"
    else
        echo -e "${RED}Customer not found in configuration${NC}"
        return 1
    fi
    
    # Show customer details from JSON if exists
    if [ -f "$PROJECT_ROOT/customers/${customer}.json" ]; then
        echo -e "\n${YELLOW}Customer Details:${NC}"
        echo "  Email: $(jq -r .email "$PROJECT_ROOT/customers/${customer}.json")"
        echo "  Created: $(jq -r .created "$PROJECT_ROOT/customers/${customer}.json")"
        echo "  Status: $(jq -r .status "$PROJECT_ROOT/customers/${customer}.json")"
    fi
}

# Function to update regex profile
update_regex_profile() {
    local customer=$1
    local new_profile=$2
    
    echo -e "\n${YELLOW}Updating regex profile for $customer to: $new_profile${NC}"
    
    # Update main.tf using sed
    sed -i.backup "/$customer.*{/,/}/ s/regex_profile.*=.*/      regex_profile    = \"$new_profile\"/" "$ENV_DIR/main.tf"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Updated regex profile${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update regex profile${NC}"
        return 1
    fi
}

# Function to update sender allowlist
update_sender_allowlist() {
    local customer=$1
    local new_senders=$2
    
    echo -e "\n${YELLOW}Updating sender allowlist for $customer${NC}"
    
    # Format the sender list for Terraform
    if [ "$new_senders" = "*" ]; then
        formatted_senders='["*"]'
    else
        # Convert comma-separated list to JSON array format
        formatted_senders=$(echo "$new_senders" | awk -F',' '{
            printf "["
            for(i=1; i<=NF; i++) {
                gsub(/^ +| +$/, "", $i)
                if(i>1) printf ", "
                printf "\"%s\"", $i
            }
            printf "]"
        }')
    fi
    
    # Update main.tf
    sed -i.backup "/$customer.*{/,/}/ s/sender_allowlist.*=.*/      sender_allowlist = $formatted_senders/" "$ENV_DIR/main.tf"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Updated sender allowlist${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update sender allowlist${NC}"
        return 1
    fi
}

# Function to add custom regex profile
add_custom_regex_profile() {
    local profile_name=$1
    
    echo -e "\n${YELLOW}To add a custom regex profile '$profile_name':${NC}"
    echo ""
    echo "Edit: $PROJECT_ROOT/modules/2fa_parser/main.tf"
    echo ""
    echo "Add to the regex_profiles local variable:"
    echo -e "${CYAN}"
    cat <<'EOF'
    custom_name = {
      patterns = [
        "your-regex-pattern-here",
        "another-pattern"
      ]
    }
EOF
    echo -e "${NC}"
    echo ""
    echo "Example patterns:"
    echo '  • "\\b([0-9]{6})\\b" - Any 6-digit number'
    echo '  • "(?i)code\\s*[:：]?\\s*([0-9]{4,8})" - Case-insensitive "code: 123456"'
    echo '  • "([A-Z0-9]{6})" - 6-character alphanumeric'
    echo ""
    read -p "Would you like to open the file in your editor? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-vi} "$PROJECT_ROOT/modules/2fa_parser/main.tf"
    fi
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}======================================"
        echo "  Customer Configuration Menu"
        echo -e "======================================${NC}"
        echo ""
        echo "1. View customer configuration"
        echo "2. Edit regex profile"
        echo "3. Edit sender allowlist"
        echo "4. View available regex profiles"
        echo "5. Add custom regex profile"
        echo "0. Exit"
        echo ""
        read -p "Choose an option: " option
        
        case $option in
            1)
                # View customer config
                echo -e "\n${YELLOW}Available customers:${NC}"
                for customer_file in "$PROJECT_ROOT"/customers/*.json; do
                    if [ -f "$customer_file" ]; then
                        customer=$(basename "$customer_file" .json)
                        echo "  • $customer"
                    fi
                done
                echo ""
                read -p "Customer name: " CUSTOMER_NAME
                show_customer_config "$CUSTOMER_NAME"
                ;;
            
            2)
                # Edit regex profile
                echo -e "\n${YELLOW}Edit Regex Profile${NC}"
                echo ""
                echo "Available customers:"
                for customer_file in "$PROJECT_ROOT"/customers/*.json; do
                    if [ -f "$customer_file" ]; then
                        customer=$(basename "$customer_file" .json)
                        echo "  • $customer"
                    fi
                done
                echo ""
                read -p "Customer name: " CUSTOMER_NAME
                
                show_customer_config "$CUSTOMER_NAME"
                show_regex_profiles
                
                echo ""
                read -p "New regex profile (standard/universal/alphanumeric/royalhealth/custom): " NEW_PROFILE
                
                if [[ "$NEW_PROFILE" =~ ^(standard|universal|alphanumeric|royalhealth)$ ]]; then
                    update_regex_profile "$CUSTOMER_NAME" "$NEW_PROFILE"
                    echo -e "\n${YELLOW}To apply changes:${NC}"
                    echo -e "${BLUE}cd $ENV_DIR && terraform apply${NC}"
                elif [ "$NEW_PROFILE" = "custom" ]; then
                    read -p "Custom profile name: " CUSTOM_NAME
                    add_custom_regex_profile "$CUSTOM_NAME"
                    echo -e "\n${YELLOW}After adding custom patterns, update the customer:${NC}"
                    echo "Run this script again and set profile to: $CUSTOM_NAME"
                else
                    echo -e "${RED}Invalid profile name${NC}"
                fi
                ;;
            
            3)
                # Edit sender allowlist
                echo -e "\n${YELLOW}Edit Sender Allowlist${NC}"
                echo ""
                echo "Available customers:"
                for customer_file in "$PROJECT_ROOT"/customers/*.json; do
                    if [ -f "$customer_file" ]; then
                        customer=$(basename "$customer_file" .json)
                        echo "  • $customer"
                    fi
                done
                echo ""
                read -p "Customer name: " CUSTOMER_NAME
                
                show_customer_config "$CUSTOMER_NAME"
                
                echo -e "\n${YELLOW}Enter new sender allowlist:${NC}"
                echo "  • Use '*' to accept from all senders"
                echo "  • Comma-separate multiple: sender1@domain.com,sender2@domain.com"
                echo "  • Use @domain.com to accept all from a domain"
                echo ""
                read -p "New allowlist: " NEW_SENDERS
                
                update_sender_allowlist "$CUSTOMER_NAME" "$NEW_SENDERS"
                echo -e "\n${YELLOW}To apply changes:${NC}"
                echo -e "${BLUE}cd $ENV_DIR && terraform apply${NC}"
                ;;
            
            4)
                # View regex profiles
                show_regex_profiles
                ;;
            
            5)
                # Add custom regex profile
                read -p "Custom profile name: " CUSTOM_NAME
                add_custom_regex_profile "$CUSTOM_NAME"
                ;;
            
            0)
                echo "Goodbye!"
                exit 0
                ;;
            
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# Check for direct command line usage
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [customer-name]"
    echo ""
    echo "Edit customer configuration for 2FA email parsing"
    echo ""
    echo "Options:"
    echo "  customer-name    Optional: Jump directly to editing this customer"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Configurations you can edit:"
    echo "  • Regex Profile: Choose parsing patterns (standard/universal/alphanumeric/custom)"
    echo "  • Sender Allowlist: Control which senders are accepted"
    exit 0
fi

if [ ! -z "$1" ]; then
    # Direct customer edit mode
    CUSTOMER_NAME="$1"
    show_customer_config "$CUSTOMER_NAME"
    echo ""
    echo "What would you like to edit?"
    echo "1. Regex profile"
    echo "2. Sender allowlist"
    read -p "Choice (1/2): " EDIT_CHOICE
    
    if [ "$EDIT_CHOICE" = "1" ]; then
        show_regex_profiles
        echo ""
        read -p "New regex profile: " NEW_PROFILE
        update_regex_profile "$CUSTOMER_NAME" "$NEW_PROFILE"
    elif [ "$EDIT_CHOICE" = "2" ]; then
        echo -e "\n${YELLOW}Enter new sender allowlist:${NC}"
        echo "  • Use '*' to accept all, or comma-separate multiple"
        read -p "New allowlist: " NEW_SENDERS
        update_sender_allowlist "$CUSTOMER_NAME" "$NEW_SENDERS"
    fi
    
    echo -e "\n${YELLOW}To apply changes:${NC}"
    echo -e "${BLUE}cd $ENV_DIR && terraform apply${NC}"
else
    # Interactive menu mode
    main_menu
fi
