variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket containing email objects"
  type        = string
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN for email notifications"
  type        = string
}

variable "code_ttl_minutes" {
  description = "TTL for 2FA codes in minutes"
  type        = number
  default     = 15
}

variable "tenant_configs" {
  description = "Tenant configurations for parsing 2FA emails"
  type = map(object({
    sender_allowlist = list(string)
    regex_patterns   = optional(list(string))
    webhook_url      = optional(string)
    webhook_secret   = optional(string)
  }))
  default = {
    # Example tenant config
    # "acme" = {
    #   sender_allowlist = ["noreply@acme.com", "2fa@acme.com"]
    #   regex_patterns   = ["(?<=code )\\d{6}", "verification code\\s+(\\d{6})"]
    #   webhook_url      = "https://internal.acme.com/2fa-webhook"
    #   webhook_secret   = "secret-key"
    # }
  }
}

variable "enable_webhooks" {
  description = "Enable webhook notifications"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
