# 2FA Email Pipeline Scripts

This directory contains operational scripts for managing the 2FA email pipeline infrastructure and customer provisioning.

## Initial Setup

### `setup-infrastructure.sh`
Sets up the base infrastructure for the 2FA email pipeline.

**What it does:**
- Validates prerequisites (Terraform, AWS CLI)
- Verifies SES domain
- Creates environment configuration
- Packages Lambda functions
- Initializes Terraform
- Creates deployment plan

**Usage:**
```bash
./scripts/setup-infrastructure.sh
```

**Required inputs:**
- AWS Profile name
- AWS Region (default: us-east-2)
- Environment name (default: dev)
- Verified SES domain

## Customer Provisioning

### `provision-customer.sh`
Provisions a dedicated email address and API access for a customer to receive forwarded 2FA emails.

**What it does:**
- Creates email address: `[customer]@auth.novoflow.io`
- Generates unique API key for customer
- Automatically provisions API key in API Gateway
- Associates key with usage plan for rate limiting
- Accepts 2FA emails from any sender
- Auto-extracts codes using universal regex patterns
- Creates customer documentation with working API examples

**Usage:**
```bash
./scripts/provision-customer.sh
```

**Example flow:**
```
Customer name: acme
→ Creates: acme@auth.novoflow.io
→ API Key: generated automatically
→ Ready to receive forwarded 2FA emails
```

### `test-api.sh` (NEW)
Tests the API Gateway endpoint for retrieving 2FA codes.

**What it does:**
- Calls the API Gateway endpoint with proper authentication
- Uses API key authentication (not AWS IAM)
- Returns the latest active code for a recipient
- Validates proper API response format

**Usage:**
```bash
# Test API for a customer email
./scripts/test-api.sh acme@auth.novoflow.io

# Interactive mode - lists available customers
./scripts/test-api.sh
```

**Note:** The deprecated `test-customer.sh` has been moved to `scripts/deprecated/` as it bypassed the API Gateway.

### `list-customers.sh`
Displays all provisioned customer email accounts and recent activity.

**What it displays:**
- All provisioned customers
- Email addresses and API keys
- Active/used code statistics
- Recent 2FA activity
- API endpoint information

**Usage:**
```bash
./scripts/list-customers.sh
```

### `remove-customer.sh` (optional)
Removes a customer email and cleans up their data.

**What it does:**
- Removes customer from Terraform config
- Deletes stored 2FA codes
- Archives customer documentation
- Updates SES recipients

**Usage:**
```bash
./scripts/remove-customer.sh
```

## Script Dependencies

All scripts require:
- `jq` for JSON processing
- `aws` CLI configured with appropriate credentials
- `terraform` for infrastructure management
- Write access to the project directory

## Typical Workflow

1. **Initial setup**:
   ```bash
   ./scripts/setup-infrastructure.sh
   cd envs/dev && terraform apply tfplan
   ```

2. **Provision first customer**:
   ```bash
   ./scripts/provision-customer.sh
   # Enter: walmart (automatically creates API key)
   cd envs/dev && terraform apply tfplan
   ./scripts/test-api.sh walmart@auth.novoflow.io
   ```

3. **Customer integration**:
   - Customer forwards 2FA emails to: `walmart@auth.novoflow.io`
   - Customer calls API with their API key to retrieve codes
   - Codes auto-expire after 15 minutes

4. **Regular operations**:
   ```bash
   # Check all customers
   ./scripts/list-customers.sh
   
   # Add new customer
   ./scripts/provision-customer.sh
   
   # Test specific customer API
   ./scripts/test-api.sh customer@auth.novoflow.io
   ```

## Customer API Usage

Once provisioned, customers can retrieve their 2FA codes:

```bash
curl -X POST https://ph8a9c26u5.execute-api.us-east-2.amazonaws.com/dev/codes \
  -H "Content-Type: application/json" \
  -H "x-api-key: <customer-api-key>" \
  -d '{"recipient": "customer@auth.novoflow.io"}'
```

Response:
```json
{
  "code": "123456",
  "recipient": "customer@auth.novoflow.io",
  "expiresAt": "2025-01-01T12:00:00Z"
}
```

## Configuration Files

Scripts create/modify these files:
- `envs/<env>/terraform.tfvars` - Terraform variables
- `envs/<env>/main.tf` - Terraform configuration
- `envs/<env>/setup-outputs.json` - Cached setup values
- `customers/<customer>.json` - Customer configuration
- `customers/<customer>-README.md` - Customer documentation



## Security Notes

- Each customer gets a unique API key
- API keys are automatically provisioned in API Gateway
- All AWS operations use named profiles
- Customer configurations stored locally
- No PHI stored in configuration files
- All data encrypted at rest and in transit
- HIPAA compliant infrastructure