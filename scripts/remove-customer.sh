#!/bin/bash
# Remove a client/tenant from the 2FA email pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "  Remove Client from 2FA Pipeline"
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

echo -e "\n${YELLOW}Current Configuration:${NC}"
echo "  Environment: $ENV"
echo "  SES Domain: $SES_DOMAIN"
echo ""

# List current clients
echo -e "${YELLOW}Current clients:${NC}"
if [ -d "docs/clients" ]; then
    for client_file in docs/clients/*.md; do
        if [ -f "$client_file" ]; then
            client=$(basename "$client_file" .md)
            email=$(grep "Email Address" "$client_file" | sed 's/.*`\(.*\)`.*/\1/')
            echo "  - $client ($email)"
        fi
    done
fi

# Get client to remove
echo ""
read -p "Client/Tenant name to remove: " CLIENT_NAME
CLIENT_NAME=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-')

# Check if client exists
if [ ! -f "docs/clients/${CLIENT_NAME}.md" ]; then
    echo -e "${RED}❌ Client $CLIENT_NAME not found${NC}"
    exit 1
fi

# Get client email
EMAIL_ADDRESS=$(grep "Email Address" "docs/clients/${CLIENT_NAME}.md" | sed 's/.*`\(.*\)`.*/\1/')

echo -e "\n${YELLOW}This will remove:${NC}"
echo "  Client: $CLIENT_NAME"
echo "  Email: $EMAIL_ADDRESS"
echo ""
echo -e "${RED}⚠️  Warning: This will also delete any stored 2FA codes for this client${NC}"
read -p "Remove this client? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

# Update Terraform configuration
echo -e "\n${YELLOW}Updating Terraform configuration...${NC}"
ENV_DIR="envs/$ENV"

# Backup current main.tf
cp "$ENV_DIR/main.tf" "$ENV_DIR/main.tf.backup"

# Remove tenant configuration
# This is tricky with sed, so we use a temporary file
awk -v client="$CLIENT_NAME" '
    BEGIN { in_client = 0 }
    /"'$CLIENT_NAME'" = {/ { in_client = 1; next }
    in_client && /^    }$/ { in_client = 0; next }
    !in_client { print }
' "$ENV_DIR/main.tf" > "$ENV_DIR/main.tf.tmp"
mv "$ENV_DIR/main.tf.tmp" "$ENV_DIR/main.tf"

# Remove email from recipients
sed -i.tmp "s/, \"$EMAIL_ADDRESS\"//g; s/\"$EMAIL_ADDRESS\", //g" "$ENV_DIR/terraform.tfvars"

# Clean up stored codes
echo -e "\n${YELLOW}Cleaning up stored codes...${NC}"
aws dynamodb scan \
    --table-name "2fa-codes-$ENV" \
    --filter-expression "tenant = :tenant" \
    --expression-attribute-values "{\":tenant\":{\"S\":\"$CLIENT_NAME\"}}" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --output json | jq -r '.Items[] | "\(.pk.S)|\(.sk.S)"' | while IFS='|' read -r pk sk; do
    
    echo "  Deleting code: $pk"
    aws dynamodb delete-item \
        --table-name "2fa-codes-$ENV" \
        --key "{\"pk\":{\"S\":\"$pk\"},\"sk\":{\"S\":\"$sk\"}}" \
        --region "$REGION" \
        --profile "$AWS_PROFILE"
done

# Apply changes
echo -e "\n${YELLOW}Creating Terraform plan...${NC}"
cd "$ENV_DIR"
terraform plan -target=module.ses_inbound.aws_ses_receipt_rule.inbound_to_s3 -target=module.twofa_parser -out=tfplan

echo -e "\n${YELLOW}Ready to apply!${NC}"
echo -e "Review the plan above. To apply, run:"
echo -e "${GREEN}cd $ENV_DIR && terraform apply tfplan${NC}"

# Archive client documentation
cd ../..
mkdir -p "docs/clients/archived"
mv "docs/clients/${CLIENT_NAME}.md" "docs/clients/archived/${CLIENT_NAME}-removed-$(date +%Y%m%d).md"

echo -e "\n${GREEN}✅ Client removed successfully!${NC}"
echo -e "\nClient documentation archived to: docs/clients/archived/"
echo -e "\nNext steps:"
echo -e "1. Apply changes: cd $ENV_DIR && terraform apply tfplan"
echo -e "2. The email $EMAIL_ADDRESS will no longer receive 2FA codes"
