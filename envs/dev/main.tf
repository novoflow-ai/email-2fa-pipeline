module "ses_inbound" {
  source = "../../modules/ses_inbound_hipaa"

  region  = var.region
  env     = var.env

  receipt_rule_set_name = var.receipt_rule_set_name
  receipt_rule_name     = var.receipt_rule_name
  recipients            = var.recipients

  bucket_name   = var.bucket_name
  object_prefix = var.object_prefix
  
  # HIPAA settings
  kms_deletion_window = 30
  retention_days      = 365  # 1 year for dev (prod should be 2190 - 6 years)
  enable_s3_logging   = false  # We'll enable this when we have a logging bucket
}

# 2FA Parser service
module "twofa_parser" {
  source = "../../modules/2fa_parser"

  env            = var.env
  region         = var.region
  s3_bucket_name = module.ses_inbound.s3_bucket_name
  sqs_queue_arn  = module.ses_inbound.sqs_queue_arn
  
  # Configure tenant parsing rules
  tenant_configs = {
    "ermi" = {
      sender_allowlist = ["*"]
      regex_patterns   = [
        "(?<=Use verification code )\\d{6}",           # Royal Health exact format
        "(?<=verification code )\\d{6}",               # Generic verification code
        "(?i)verification\\s*code\\s+(\\d{6})",        # Flexible with potential whitespace
        "(?<=code )\\d{6}",                            # Simple code pattern
        "\\b1[0-9]{5}\\b"                              # Fallback: 6-digit number starting with 1
      ]
    }
  }
}

output "s3_bucket_name" { value = module.ses_inbound.s3_bucket_name }
output "s3_bucket_arn"  { value = module.ses_inbound.s3_bucket_arn }
output "kms_key_id"     { value = module.ses_inbound.kms_key_id }
output "kms_key_arn"    { value = module.ses_inbound.kms_key_arn }
output "ses_rule_name"  { value = module.ses_inbound.ses_rule_name }
output "ses_rule_set"   { value = module.ses_inbound.ses_rule_set }
output "sns_topic_arn"  { value = module.ses_inbound.sns_topic_arn }
output "sqs_queue_url"  { value = module.ses_inbound.sqs_queue_url }
output "sqs_queue_arn"  { value = module.ses_inbound.sqs_queue_arn }
output "dlq_url"        { value = module.ses_inbound.dlq_url }
output "dlq_arn"        { value = module.ses_inbound.dlq_arn }

# 2FA Parser outputs
output "twofa_api_url"     { value = module.twofa_parser.api_gateway_url }
output "twofa_table_name"  { value = module.twofa_parser.dynamodb_table_name }
output "twofa_parser_dlq"  { value = module.twofa_parser.dlq_url }
