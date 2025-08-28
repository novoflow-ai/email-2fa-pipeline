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

# Function to display regex pattern examples
show_regex_examples() {
    echo -e "\n${BLUE}Common Regex Pattern Examples:${NC}"
    echo ""
    echo -e "${CYAN}Exact match patterns:${NC}"
    echo '  • "(?<=code )\\d{6}" - Matches 6 digits after "code " (e.g., "code 123456")'
    echo '  • "(?<=Use verification code )\\d{6}" - Royal Health format'
    echo '  • "(?<=OTP: )\\d{6}" - Matches 6 digits after "OTP: "'
    echo ""
    echo -e "${CYAN}Flexible patterns:${NC}"
    echo '  • "(?i)code\\s*[:：]?\\s*(\\d{6})" - Case-insensitive, optional colon/space'
    echo '  • "verification code\\s+(\\d{4,8})" - 4-8 digits after "verification code"'
    echo '  • "(\\d{6})\\s*is your.*code" - "123456 is your verification code"'
    echo ""
    echo -e "${CYAN}Fallback patterns:${NC}"
    echo '  • "\\b(\\d{6})\\b" - Any standalone 6-digit number'
    echo '  • "\\b(\\d{4,8})\\b" - Any standalone 4-8 digit number'
    echo ""
    echo -e "${YELLOW}Note: Patterns are tried in order. Put specific patterns first.${NC}"
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
            found && /regex_patterns/ { 
                gsub(/.*regex_patterns *= *\[/, "  Regex Patterns: [")
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

# Function to update regex patterns
update_regex_patterns() {
    local customer=$1
    shift
    local patterns=("$@")
    
    echo -e "\n${YELLOW}Updating regex patterns for $customer${NC}"
    
    # Build the patterns array string
    local patterns_str="["
    local first=true
    for pattern in "${patterns[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            patterns_str+=", "
        fi
        # Escape backslashes for sed
        escaped_pattern=$(echo "$pattern" | sed 's/\\/\\\\/g')
        patterns_str+="\"$escaped_pattern\""
    done
    patterns_str+="]"
    
    # Update main.tf using sed
    sed -i.backup "/$customer.*{/,/}/ s/regex_patterns.*=.*/      regex_patterns   = $patterns_str/" "$ENV_DIR/main.tf"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Updated regex patterns${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update regex patterns${NC}"
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

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}======================================"
        echo "  Customer Configuration Menu"
        echo -e "======================================${NC}"
        echo ""
        echo "1. View customer configuration"
        echo "2. Edit regex patterns"
        echo "3. Edit sender allowlist"
        echo "4. View regex pattern examples"
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
                # Edit regex patterns
                echo -e "\n${YELLOW}Edit Regex Patterns${NC}"
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
                show_regex_examples
                
                echo ""
                echo -e "${YELLOW}Enter regex patterns (one per line, empty line to finish):${NC}"
                echo -e "${CYAN}Example: (?<=code )\\d{6}${NC}"
                echo ""
                
                patterns=()
                while true; do
                    read -p "Pattern ${#patterns[@]}: " pattern
                    if [ -z "$pattern" ]; then
                        break
                    fi
                    patterns+=("$pattern")
                done
                
                if [ ${#patterns[@]} -gt 0 ]; then
                    update_regex_patterns "$CUSTOMER_NAME" "${patterns[@]}"
                    echo -e "\n${YELLOW}To apply changes:${NC}"
                    echo -e "${BLUE}cd $ENV_DIR && terraform apply${NC}"
                else
                    echo -e "${RED}No patterns entered${NC}"
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
                # View regex pattern examples
                show_regex_examples
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
    echo "  • Regex Patterns: Custom regex patterns for parsing 2FA codes"
    echo "  • Sender Allowlist: Control which senders are accepted"
    exit 0
fi

if [ ! -z "$1" ]; then
    # Direct customer edit mode
    CUSTOMER_NAME="$1"
    show_customer_config "$CUSTOMER_NAME"
    echo ""
    echo "What would you like to edit?"
    echo "1. Regex patterns"
    echo "2. Sender allowlist"
    read -p "Choice (1/2): " EDIT_CHOICE
    
    if [ "$EDIT_CHOICE" = "1" ]; then
        show_regex_examples
        echo ""
        echo -e "${YELLOW}Enter regex patterns (one per line, empty line to finish):${NC}"
        echo -e "${CYAN}Example: (?<=code )\\d{6}${NC}"
        echo ""
        
        patterns=()
        while true; do
            read -p "Pattern ${#patterns[@]}: " pattern
            if [ -z "$pattern" ]; then
                break
            fi
            patterns+=("$pattern")
        done
        
        if [ ${#patterns[@]} -gt 0 ]; then
            update_regex_patterns "$CUSTOMER_NAME" "${patterns[@]}"
        else
            echo -e "${RED}No patterns entered${NC}"
        fi
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
