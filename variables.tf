variable "region" {
  description = "AWS region for SES receiving (and S3/KMS)."
  type        = string
  default     = "us-east-2"
}

variable "env" {
  description = "Environment tag (e.g., prod, staging)."
  type        = string
  default     = "prod"
}

variable "domain" {
  description = "SES verified subdomain used for receiving."
  type        = string
  default     = "auth.novoflow.io"
}

variable "receipt_rule_set_name" {
  description = "Existing SES receipt rule set name (must exist)."
  type        = string
  default     = "inbound-auth"
}

variable "receipt_rule_name" {
  description = "Name for the receipt rule to create."
  type        = string
  default     = "sanity-to-s3"
}

variable "recipients" {
  description = "Addresses this rule should match (exact). Use [\"sanity@auth.novoflow.io\"] or [\"auth.novoflow.io\"] to catch-all."
  type        = list(string)
  default     = ["sanity@auth.novoflow.io"]
}

variable "bucket_name" {
  description = "S3 bucket for inbound emails. Must be globally unique."
  type        = string
  default     = "novoflow-ses-inbound-prod-us-east-2"
}

variable "object_prefix" {
  description = "S3 key prefix for inbound email objects."
  type        = string
  default     = "inbound/"
}

variable "kms_alias" {
  description = "Alias for the CMK used to encrypt the bucket."
  type        = string
  default     = "alias/novoflow-inbound-prod"
}

variable "raw_retention_days" {
  description = "Days to keep raw inbound messages in S3."
  type        = number
  default     = 1
}
