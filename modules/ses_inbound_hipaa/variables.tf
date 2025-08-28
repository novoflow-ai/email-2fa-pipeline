variable "region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "object_prefix" {
  description = "S3 prefix for emails"
  type        = string
  default     = "emails/"
}

variable "receipt_rule_set_name" {
  description = "SES rule set name"
  type        = string
}

variable "receipt_rule_name" {
  description = "SES rule name"
  type        = string
}

variable "recipients" {
  description = "Email addresses to catch"
  type        = list(string)
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "retention_days" {
  description = "Days to retain emails (HIPAA requires 6 years minimum for some records)"
  type        = number
  default     = 2190 # 6 years
}

variable "enable_s3_logging" {
  description = "Enable S3 access logging"
  type        = bool
  default     = true
}

variable "logging_bucket" {
  description = "Bucket for S3 access logs (must already exist)"
  type        = string
  default     = ""
}
