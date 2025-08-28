output "dynamodb_table_name" {
  value       = aws_dynamodb_table.codes.name
  description = "DynamoDB table name for 2FA codes"
}

output "parser_lambda_arn" {
  value       = aws_lambda_function.parser.arn
  description = "ARN of the parser Lambda function"
}

output "lookup_lambda_arn" {
  value       = aws_lambda_function.lookup.arn
  description = "ARN of the lookup Lambda function"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.lookup.invoke_url
  description = "API Gateway URL for lookups"
}

output "dlq_url" {
  value       = aws_sqs_queue.dlq.url
  description = "DLQ URL for failed parse attempts"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.lookup.id
  description = "API Gateway ID"
}
