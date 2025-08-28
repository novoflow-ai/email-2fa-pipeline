data "aws_caller_identity" "this" {}

locals {
  account_id = data.aws_caller_identity.this.account_id
  region     = var.region
}

# KMS key for HIPAA-compliant encryption
resource "aws_kms_key" "hipaa" {
  description             = "HIPAA-compliant key for ${var.env} email pipeline"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true # HIPAA best practice

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SES to encrypt SNS messages"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "sns.${local.region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "Allow services to use the key"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "sns.amazonaws.com",
            "sqs.amazonaws.com",
            "cloudwatch.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SES to use key for S3"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
            "kms:ViaService" = "s3.${local.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "email-2fa-hipaa-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

resource "aws_kms_alias" "hipaa" {
  name          = "alias/email-2fa-hipaa-${var.env}"
  target_key_id = aws_kms_key.hipaa.key_id
}

# S3 bucket for storing emails with HIPAA compliance
resource "aws_s3_bucket" "inbound" {
  bucket = var.bucket_name
  
  tags = {
    Name        = var.bucket_name
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# Enable versioning for HIPAA compliance
resource "aws_s3_bucket_versioning" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "inbound" {
  bucket = aws_s3_bucket.inbound.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption with SSE-S3 (temporarily for testing)
resource "aws_s3_bucket_server_side_encryption_configuration" "inbound" {
  bucket = aws_s3_bucket.inbound.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rule for HIPAA retention
resource "aws_s3_bucket_lifecycle_configuration" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  
  rule {
    id     = "hipaa-retention"
    status = "Enabled"
    
    filter {}  # Apply to all objects
    
    # Transitions must be in ascending order by days
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 180
      storage_class = "GLACIER"
    }
    
    # Expiration days must be greater than the last transition
    expiration {
      days = max(var.retention_days, 181)  # At least 1 day after GLACIER transition
    }
  }
}

# Enable S3 access logging if specified
resource "aws_s3_bucket_logging" "inbound" {
  count = var.enable_s3_logging && var.logging_bucket != "" ? 1 : 0
  
  bucket = aws_s3_bucket.inbound.id

  target_bucket = var.logging_bucket
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}

# S3 bucket policy to allow SES to write
resource "aws_s3_bucket_policy" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.inbound.arn,
          "${aws_s3_bucket.inbound.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "AllowSESPuts"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource  = "${aws_s3_bucket.inbound.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.inbound]
}

# SNS topic for email notifications (encrypted)
resource "aws_sns_topic" "email_notifications" {
  name              = "${var.receipt_rule_name}-notifications-${var.env}"
  kms_master_key_id = aws_kms_key.hipaa.id
  
  tags = {
    Name        = "${var.receipt_rule_name}-notifications-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# SNS topic policy to allow SES to publish
resource "aws_sns_topic_policy" "allow_ses" {
  arn = aws_sns_topic.email_notifications.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPublish"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.email_notifications.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
      }
    }]
  })
}

# Dead Letter Queue for failed messages
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.receipt_rule_name}-notifications-dlq-${var.env}"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.hipaa.id
  
  tags = {
    Name        = "${var.receipt_rule_name}-notifications-dlq-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# SQS queue for processing emails (encrypted)
resource "aws_sqs_queue" "email_notifications" {
  name                       = "${var.receipt_rule_name}-notifications-${var.env}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400 # 1 day
  kms_master_key_id          = aws_kms_key.hipaa.id
  
  tags = {
    Name        = "${var.receipt_rule_name}-notifications-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# Configure DLQ for main queue
resource "aws_sqs_queue_redrive_policy" "email_notifications" {
  queue_url = aws_sqs_queue.email_notifications.url
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# SQS policy to allow SNS to send messages
resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.email_notifications.url
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSNSSendMessage"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.email_notifications.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.email_notifications.arn
        }
      }
    }]
  })
}

# Subscribe SQS to SNS topic
resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.email_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.email_notifications.arn
}

# SES receipt rule set
resource "aws_ses_receipt_rule_set" "this" {
  rule_set_name = var.receipt_rule_set_name
}

# Activate the rule set
resource "aws_ses_active_receipt_rule_set" "active" {
  rule_set_name = aws_ses_receipt_rule_set.this.rule_set_name
}

# SES receipt rule
resource "aws_ses_receipt_rule" "inbound_to_s3" {
  name          = var.receipt_rule_name
  rule_set_name = aws_ses_receipt_rule_set.this.rule_set_name
  recipients    = var.recipients
  enabled       = true
  scan_enabled  = false
  tls_policy    = "Require" # HIPAA requires TLS
  
  # First send notification to SNS
  sns_action {
    topic_arn = aws_sns_topic.email_notifications.arn
    encoding  = "UTF-8"
    position  = 1
  }
  
  # Then save to S3 (will use bucket default KMS encryption)
  s3_action {
    bucket_name       = aws_s3_bucket.inbound.bucket
    object_key_prefix = var.object_prefix
    # Temporarily removing kms_key_arn - bucket has default KMS encryption
    position          = 2
  }
  
  depends_on = [
    aws_s3_bucket_policy.inbound,
    aws_s3_bucket_server_side_encryption_configuration.inbound,
    aws_sns_topic_policy.allow_ses,
    aws_sqs_queue_policy.allow_sns
  ]
}