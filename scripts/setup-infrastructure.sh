#!/bin/bash
# Initial infrastructure setup script for 2FA Email Pipeline
# This script should be run once to set up the base infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="us-east-2"
DEFAULT_ENV="dev"

echo "======================================"
echo "  2FA Email Pipeline Setup"
echo "======================================"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install Terraform first.${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"

# Get user input
echo -e "\n${YELLOW}Configuration${NC}"
read -p "AWS Profile name: " AWS_PROFILE
read -p "AWS Region [$DEFAULT_REGION]: " REGION
REGION=${REGION:-$DEFAULT_REGION}
read -p "Environment name [$DEFAULT_ENV]: " ENV
ENV=${ENV:-$DEFAULT_ENV}
read -p "Your verified SES domain (e.g., auth.yourdomain.com): " SES_DOMAIN

# Validate SES domain
echo -e "\n${YELLOW}Validating SES domain...${NC}"
if aws ses get-identity-verification-attributes \
    --identities "$SES_DOMAIN" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --output json | grep -q "Success"; then
    echo -e "${GREEN}✓ SES domain verified${NC}"
else
    echo -e "${RED}❌ SES domain not verified. Please verify $SES_DOMAIN in SES first.${NC}"
    exit 1
fi

# Generate bucket name
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
BUCKET_NAME="ses-2fa-hipaa-${ENV}-${REGION}-${ACCOUNT_ID}"

echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo "  AWS Profile: $AWS_PROFILE"
echo "  Region: $REGION"
echo "  Environment: $ENV"
echo "  SES Domain: $SES_DOMAIN"
echo "  S3 Bucket: $BUCKET_NAME"
echo ""
read -p "Continue with setup? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

# Get project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Create environment directory
ENV_DIR="$PROJECT_ROOT/envs/$ENV"
if [ ! -d "$ENV_DIR" ]; then
    echo -e "\n${YELLOW}Creating environment directory...${NC}"
    mkdir -p "$ENV_DIR"
    
    # Copy example files
    if [ -d "$PROJECT_ROOT/envs/dev" ] && [ "$ENV" != "dev" ]; then
        cp "$PROJECT_ROOT/envs/dev"/*.tf "$ENV_DIR/"
        cp "$PROJECT_ROOT/envs/dev/terraform.tfvars.example" "$ENV_DIR/"
    fi
fi

# Create terraform.tfvars
echo -e "\n${YELLOW}Creating terraform.tfvars...${NC}"
cat > "$ENV_DIR/terraform.tfvars" <<EOF
# AWS Configuration
aws_profile = "$AWS_PROFILE"
region      = "$REGION"
env         = "$ENV"

# SES Configuration
receipt_rule_set_name = "inbound-auth-hipaa-$ENV"
receipt_rule_name     = "2fa-emails-hipaa-$ENV"

# Accept all emails to the domain
recipients = ["$SES_DOMAIN"]

# S3 Configuration
bucket_name   = "$BUCKET_NAME"
object_prefix = "emails/"
EOF

echo -e "${GREEN}✓ Configuration created${NC}"

# Package Lambda functions
echo -e "\n${YELLOW}Packaging Lambda functions...${NC}"
cd "$PROJECT_ROOT/modules/2fa_parser"
./package-lambda.sh
cd "$PROJECT_ROOT"

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
cd "$ENV_DIR"
terraform init

# Create plan
echo -e "\n${YELLOW}Creating Terraform plan...${NC}"
terraform plan -out=tfplan

# Apply
echo -e "\n${YELLOW}Ready to deploy!${NC}"
echo -e "Review the plan above. To deploy, run:"
echo -e "${GREEN}cd envs/$ENV && terraform apply tfplan${NC}"

# Save outputs for later use
cat > "$ENV_DIR/setup-outputs.json" <<EOF
{
  "aws_profile": "$AWS_PROFILE",
  "region": "$REGION",
  "env": "$ENV",
  "ses_domain": "$SES_DOMAIN",
  "bucket_name": "$BUCKET_NAME",
  "account_id": "$ACCOUNT_ID"
}
EOF

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo -e "\nNext steps:"
echo -e "1. Deploy: cd envs/$ENV && terraform apply tfplan"
echo -e "2. Test: aws ses send-email --from test@$SES_DOMAIN --to test@$SES_DOMAIN --subject 'Test' --text 'Your code is: 123456' --region $REGION --profile $AWS_PROFILE"
echo -e "3. Add customers: ./scripts/provision-customer.sh"
