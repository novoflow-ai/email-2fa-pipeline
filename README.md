# 2FA Email Pipeline (HIPAA-Compliant)

A serverless AWS pipeline for capturing and extracting 2FA codes from forwarded emails, built with HIPAA compliance and healthcare systems in mind.

## 🎯 Overview

This pipeline automatically:
1. Receives forwarded 2FA emails via AWS SES
2. Extracts verification codes using customizable regex patterns
3. Stores codes temporarily (15-minute TTL)
4. Provides secure API access for code retrieval
5. Ensures one-time use with automatic expiration

## 🏗️ Architecture

```
Email → SES → S3 → Lambda (Parser) → DynamoDB
                     ↓
                API Gateway → Lambda (Lookup) → DynamoDB
```

### Components
- **AWS SES**: Receives emails at dedicated addresses
- **S3**: Stores raw emails with encryption
- **Lambda Parser**: Extracts codes from emails
- **DynamoDB**: Temporary code storage with TTL
- **API Gateway**: RESTful endpoint for code retrieval
- **CloudWatch**: Monitoring and alerts

## 🔒 Security & Compliance

### HIPAA Compliance
- ✅ Encryption at rest (S3, DynamoDB, SQS)
- ✅ Encryption in transit (TLS required)
- ✅ Short data retention (15-minute TTL)
- ✅ Audit logging via CloudWatch
- ✅ PHI tagging on all resources
- ✅ One-time code usage

### Access Control
- Customer-specific email addresses
- Unique API keys per customer
- Application-level sender whitelisting
- Internal-only API access

## 🚀 Quick Start

### Prerequisites
- AWS Account with SES access
- Terraform >= 1.0
- AWS CLI configured
- Verified SES domain

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/your-org/email_2fa_pipeline.git
cd email_2fa_pipeline
```

2. **Run setup**
```bash
./scripts/setup-infrastructure.sh
```

3. **Deploy infrastructure**
```bash
cd envs/dev
terraform apply tfplan
```

4. **Request SES production access** (removes sender restrictions)
```bash
./scripts/request-production-access.sh
```

## 📧 Customer Management

### Provision a new customer
```bash
./scripts/provision-customer.sh
# Enter: customer-name (e.g., "acme")
# Creates: acme@auth.yourdomain.com
```

### Test customer integration
```bash
./scripts/test-customer.sh customer-name
```

### List customers
```bash
./scripts/list-customers.sh
```

### Manage sender whitelists
```bash
./scripts/manage-senders.sh
```

## 🔌 API Usage

### Retrieve 2FA Code
```bash
curl -X POST https://your-api-gateway-url/codes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: customer-api-key" \
  -d '{"recipient": "customer@auth.yourdomain.com"}'
```

### Response
```json
{
  "code": "123456",
  "recipient": "customer@auth.yourdomain.com",
  "expiresAt": "2024-01-01T12:15:00.000Z"
}
```

## 📁 Project Structure

```
email_2fa_pipeline/
├── modules/
│   ├── ses_inbound_hipaa/    # SES → S3 pipeline
│   └── 2fa_parser/            # Lambda functions & API
├── envs/
│   └── dev/                   # Environment configuration
├── scripts/
│   ├── setup-infrastructure.sh
│   ├── provision-customer.sh
│   ├── test-customer.sh
│   ├── list-customers.sh
│   ├── manage-senders.sh
│   └── request-production-access.sh
└── README.md
```

## ⚙️ Configuration

### Tenant Configuration (envs/dev/main.tf)
```hcl
tenant_configs = {
  "customer-name" = {
    sender_allowlist = ["sender@service.com"]  # or ["*"] for all
    regex_profile    = "universal"
  }
}
```

### Regex Profiles
- `universal`: Matches most common 2FA formats
- `standard`: Basic 6-digit code extraction
- Custom profiles can be added in `modules/2fa_parser/main.tf`

## 🔍 Monitoring

- **CloudWatch Logs**: All Lambda executions
- **CloudWatch Metrics**: Code processing, API calls
- **CloudWatch Alarms**: No codes received, parser errors
- **Dead Letter Queue**: Failed message processing

## 🚨 Troubleshooting

### SES Sandbox Mode
If emails aren't being received:
1. Check SES sandbox status: `./scripts/manage-senders.sh`
2. Request production access: `./scripts/request-production-access.sh`

### Code Not Found
1. Check sender is whitelisted for customer
2. Verify regex pattern matches code format
3. Check CloudWatch logs for parser errors

### API Authentication Failed
1. Verify API key is correct
2. Check customer is provisioned
3. Ensure API Gateway is deployed

## 📝 License

[Your License Here]

## 🤝 Contributing

[Your Contributing Guidelines]

## 📞 Support

For issues or questions:
- Email: founders@novoflow.io
- Phone: +1 6284448155