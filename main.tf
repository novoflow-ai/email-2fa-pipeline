data "aws_caller_identity" "this" {}

locals {
  account_id = data.aws_caller_identity.this.account_id
  region     = var.region
  source_arn = "arn:aws:ses:${local.region}:${local.account_id}:receipt-rule-set/${var.receipt_rule_set_name}:receipt-rule/${var.receipt_rule_name}"
  bucket_arn = "arn:aws:s3:::${var.bucket_name}"
  bucket_all = "${local.bucket_arn}/*"
}

# -------------------- KMS (CMK) --------------------
resource "aws_kms_key" "inbound" {
  description             = "CMK for SES inbound (${var.env})"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  # Keep this policy simple and robust: let S3 in this account+region use the key via service
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowS3ViaServiceForThisAccountAndRegion"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*",
          "kms:DescribeKey", "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
            "kms:ViaService"    = "s3.${local.region}.amazonaws.com"
          }
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      }
    ]
  })

  tags = {
    project = "novoflow-email-2fa"
    env     = var.env
    phi     = "true"
  }
}

resource "aws_kms_alias" "inbound" {
  name          = var.kms_alias
  target_key_id = aws_kms_key.inbound.key_id
}

# -------------------- S3 bucket --------------------
resource "aws_s3_bucket" "inbound" {
  bucket = var.bucket_name
  tags = {
    project = "novoflow-email-2fa"
    env     = var.env
    phi     = "true"
  }
}

resource "aws_s3_bucket_versioning" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "inbound" {
  bucket                  = aws_s3_bucket.inbound.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.inbound.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  rule {
    id     = "expire-raw-inbound-${var.raw_retention_days}d"
    status = "Enabled"
    filter {
      prefix = var.object_prefix
    }
    expiration {
      days = var.raw_retention_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.inbound]
}

# Bucket policy:
# - Deny non-TLS
# - Allow SES service to PutObject *and* PutObjectAcl to inbound/* scoped to your Account and this specific Rule SourceArn
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
        Resource  = [local.bucket_arn, local.bucket_all]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AllowSESPutsAndAcl"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource  = "${local.bucket_arn}/${var.object_prefix}*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
            "AWS:SourceArn"     = local.source_arn
          }
        }
      }
    ]
  })
  depends_on = [
    aws_s3_bucket_ownership_controls.inbound,
    aws_s3_bucket_public_access_block.inbound
  ]
}

# -------------------- SNS topic for inbound events --------------------
resource "aws_sns_topic" "ses_inbound_events" {
  name = "ses-inbound-events-${var.env}"
}

resource "aws_sns_topic_policy" "allow_ses_publish" {
  arn = aws_sns_topic.ses_inbound_events.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowSESPublish",
      Effect    = "Allow",
      Principal = { Service = "ses.amazonaws.com" },
      Action    = "sns:Publish",
      Resource  = aws_sns_topic.ses_inbound_events.arn,
      Condition = {
        StringEquals = {
          "AWS:SourceAccount" = local.account_id
        },
        StringLike = {
          "AWS:SourceArn" = local.source_arn
        }
      }
    }]
  })
}

# -------------------- SQS (encrypted) and subscription --------------------
resource "aws_sqs_queue" "ses_inbound_events" {
  name                              = "ses-inbound-events-${var.env}"
  kms_master_key_id                 = aws_kms_key.inbound.arn
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = 86400
  visibility_timeout_seconds        = 30
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.ses_inbound_events.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowSNSSend",
      Effect    = "Allow",
      Principal = { Service = "sns.amazonaws.com" },
      Action    = "sqs:SendMessage",
      Resource  = aws_sqs_queue.ses_inbound_events.arn,
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_sns_topic.ses_inbound_events.arn },
        StringEquals = { "AWS:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "topic_to_sqs" {
  topic_arn = aws_sns_topic.ses_inbound_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.ses_inbound_events.arn
}

# -------------------- SES receipt rule --------------------
# Assumes the rule set already exists. Set 'recipients' to your mailbox (e.g., ["sanity@auth.novoflow.io"]).
resource "aws_ses_receipt_rule" "inbound_to_s3" {
  name          = var.receipt_rule_name
  rule_set_name = var.receipt_rule_set_name
  enabled       = true
  recipients    = var.recipients
  tls_policy    = "Require"
  scan_enabled  = false

  # 1) SNS action for observability (includes MIME if <=150KB)
  sns_action {
    position  = 1
    topic_arn = aws_sns_topic.ses_inbound_events.arn
    encoding  = "UTF-8"
  }

  # 2) S3 action (existing landing bucket)
  s3_action {
    position          = 2
    bucket_name       = aws_s3_bucket.inbound.bucket
    object_key_prefix = var.object_prefix
    kms_key_arn       = aws_kms_key.inbound.arn
  }

  depends_on = [
    aws_s3_bucket_policy.inbound,
    aws_s3_bucket_server_side_encryption_configuration.inbound,
    null_resource.flip_to_aes_before_ses_rule,
    aws_sns_topic_policy.allow_ses_publish,
    aws_sqs_queue_policy.allow_sns
  ]
}

# --- Flip bucket to AES256 right before SES rule create/update ---
resource "null_resource" "flip_to_aes_before_ses_rule" {
  triggers = {
    rule_name   = var.receipt_rule_name
    bucket_name = aws_s3_bucket.inbound.bucket
    region      = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail
      echo "[pre] Setting bucket SSE to AES256 so SES test write cannot fail on KMS"
      aws --region ${var.region} s3api put-bucket-encryption \
        --bucket ${aws_s3_bucket.inbound.bucket} \
        --server-side-encryption-configuration '{
          "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
        }'
      echo "[pre] Done"
    EOT
  }
}

# --- Flip bucket back to KMS immediately after SES rule succeeds ---
resource "null_resource" "flip_back_to_kms_after_ses_rule" {
  depends_on = [aws_ses_receipt_rule.inbound_to_s3]

  triggers = {
    key_arn = aws_kms_key.inbound.arn
    bucket  = aws_s3_bucket.inbound.bucket
    region  = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail
      echo "[post] Restoring bucket SSE to KMS (${aws_kms_key.inbound.arn})"
      aws --region ${var.region} s3api put-bucket-encryption \
        --bucket ${aws_s3_bucket.inbound.bucket} \
        --server-side-encryption-configuration '{
          "Rules":[{"ApplyServerSideEncryptionByDefault":{
            "SSEAlgorithm":"aws:kms",
            "KMSMasterKeyID":"${aws_kms_key.inbound.arn}"
          }}]
        }'
      aws --region ${var.region} s3api put-bucket-encryption \
        --bucket ${aws_s3_bucket.inbound.bucket} \
        --server-side-encryption-configuration '{
          "Rules":[{"ApplyServerSideEncryptionByDefault":{
            "SSEAlgorithm":"aws:kms",
            "KMSMasterKeyID":"${aws_kms_key.inbound.arn}"
          },
          "BucketKeyEnabled":true}]
        }'
      echo "[post] Done"
    EOT
  }
}