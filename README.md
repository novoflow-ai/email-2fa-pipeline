## Email 2FA Inbound Pipeline (Phase‑1)

This repository provisions a single, minimal SES inbound pipeline for catching 2FA emails and landing them safely in S3, with basic observability via SNS→SQS.

### What this stack creates
- KMS CMK and alias for S3 encryption
- S3 bucket for raw MIME with:
  - Versioning, ownership controls, and public access blocks
  - Default SSE‑KMS (CMK), Bucket Keys enabled
  - Lifecycle rule to expire `inbound/` objects after 1 day
  - Bucket policy: deny non‑TLS; allow SES PutObject/PutObjectAcl to the prefix
- SNS topic for SES inbound events + topic policy allowing SES to publish
- SQS queue subscribed to the topic (encrypted with the CMK)
- SES receipt rule:
  - Action 1: SNS publish (includes MIME if ≤150KB)
  - Action 2: S3 write to the landing bucket/prefix
- Safe AES256↔KMS flip during rule updates (explained below)

### Variables you’ll likely override
- `region` (default `us-east-2`)
- `env` (e.g., `prod`, `staging`)
- `bucket_name` (must be globally unique)
- `receipt_rule_set_name` and `receipt_rule_name` (must exist and/or match your SES setup)
- `recipients` (e.g., `["sanity@auth.novoflow.io"]`)
- `object_prefix` (default `inbound/`)

### Usage
```bash
terraform init -upgrade
terraform validate
terraform plan \
  -var='region=us-east-2' \
  -var='env=prod' \
  -var='bucket_name=YOUR-GLOBAL-UNIQUE-BUCKET' \
  -var='receipt_rule_set_name=inbound-auth' \
  -var='receipt_rule_name=sanity-to-s3' \
  -var='recipients=["sanity@auth.novoflow.io"]'
terraform apply -auto-approve
```

### KMS/SES “test PUT” issue and our workaround
When you create or update a SES receipt rule with an S3 action, SES performs a small “test PUT” to the target bucket. If the bucket enforces SSE‑KMS and KMS permissions/policy lines aren’t perfectly aligned, this test write can fail with AccessDenied/KMS errors. Symptoms include:
- “Could not write to S3 bucket” in SES
- S3 AccessDenied or KMS AccessDenied errors during rule updates

To make this safe and reliable, this stack temporarily flips the bucket’s default encryption to AES256 immediately before the rule change and flips back to your CMK immediately after:
- `null_resource.flip_to_aes_before_ses_rule` sets AES256 and is explicitly referenced in the SES rule `depends_on` so SES waits for this flip.
- `null_resource.flip_back_to_kms_after_ses_rule` depends on the SES rule and restores SSE‑KMS (with Bucket Keys) right after the rule succeeds.

Result: your final state remains SSE‑KMS with your CMK, but the transient SES test write never touches KMS.

### Common pitfalls and how to fix
- Region mismatch:
  - Ensure `var.region` matches your SES receiving region for the rule set.
- Wrong rule set or inactive set:
  - `var.receipt_rule_set_name` must refer to an existing set, and that set must be active in the SES console.
- Recipients don’t match:
  - `recipients` must include the exact address or domain you’re testing.
- Bucket policy SourceArn/SourceAccount mismatch:
  - `local.source_arn` is built from your region, account, rule set name, and rule name. If any of these don’t match what SES actually uses, S3 denies the write. Double‑check both names and region.
- AWS CLI not installed on the apply runner:
  - The AES/KMS flip uses `aws s3api put-bucket-encryption`. Install the AWS CLI and ensure the identity has `s3:PutBucketEncryption`.

### Testing the flow
1) Apply the stack. Confirm `terraform validate` is green and `terraform apply` succeeds.
2) Send an email to one of the `recipients` (e.g., `sanity@auth.novoflow.io`).
3) Check:
   - S3: object appears under `inbound/`
   - SQS: message arrives (from the SNS subscription)

### Outputs
- `s3_bucket_name` – landing bucket name
- `kms_key_arn` – CMK used for SSE‑KMS
- `ses_rule_name` / `ses_rule_set` – SES identifiers
- `ses_events_topic_arn` – SNS topic for inbound events
- `ses_events_queue_url` / `ses_events_queue_arn` – SQS subscription details

### Commit hygiene
- Commit `.terraform.lock.hcl` for reproducible provider versions.
- Do not commit `.terraform/` (already in `.gitignore`).
