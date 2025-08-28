output "s3_bucket_name" {
  value = aws_s3_bucket.inbound.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.inbound.arn
}

output "kms_key_id" {
  value = aws_kms_key.hipaa.id
}

output "kms_key_arn" {
  value = aws_kms_key.hipaa.arn
}

output "ses_rule_name" {
  value = aws_ses_receipt_rule.inbound_to_s3.name
}

output "ses_rule_set" {
  value = aws_ses_receipt_rule_set.this.rule_set_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.email_notifications.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.email_notifications.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.email_notifications.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
