output "s3_bucket_name" {
  value = aws_s3_bucket.inbound.bucket
}
output "kms_key_arn" {
  value = aws_kms_key.inbound.arn
}
output "ses_rule_name" {
  value = aws_ses_receipt_rule.inbound_to_s3.name
}
output "ses_rule_set" {
  value = var.receipt_rule_set_name
}

output "ses_events_topic_arn" {
  value = aws_sns_topic.ses_inbound_events.arn
}

output "ses_events_queue_url" {
  value = aws_sqs_queue.ses_inbound_events.id
}

output "ses_events_queue_arn" {
  value = aws_sqs_queue.ses_inbound_events.arn
}
