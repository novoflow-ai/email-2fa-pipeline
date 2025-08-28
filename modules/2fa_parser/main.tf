data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  
  # Common regex patterns for 2FA codes
  regex_profiles = {
    standard = {
      patterns = [
        "(?:code|token|pin)\\s*[:：]?\\s*([0-9]{4,8})",
        "verification code\\s*[:：]?\\s*([0-9]{4,8})",
        "([0-9]{4,8})\\s*is your.*code"
      ]
    }
    universal = {
      patterns = [
        "(?i)(?:verification code|code|OTP|2FA|token|pin)\\s*[:：]?\\s*([0-9]{4,8})",
        "([0-9]{4,8})\\s*is your.*(?:code|OTP|token)",
        "(?i)(?:authentication|security|access)\\s*code\\s*[:：]?\\s*([0-9]{4,8})",
        "(?i)passcode\\s*[:：]?\\s*([0-9]{4,8})",
        "\\b([0-9]{6})\\b"  # Fallback: any standalone 6-digit number
      ]
    }
    alphanumeric = {
      patterns = [
        "(?:code|token)\\s*[:：]?\\s*([A-Z0-9]{4,8})",
        "verification code\\s*[:：]?\\s*([A-Z0-9]{4,8})"
      ]
    }
    royalhealth = {
      patterns = [
        "(?i)Use verification code\\s+([0-9]{4,8})",  # Royal Health specific format
        "(?i)verification code\\s+([0-9]{4,8})",       # General verification code
        "(?i)(?:code|OTP|2FA|token|pin)\\s*[:：]?\\s*([0-9]{4,8})",  # Common patterns
        "\\b([0-9]{6})\\b"  # Fallback: any standalone 6-digit number
      ]
    }
  }
}

# DynamoDB table for storing 2FA codes
resource "aws_dynamodb_table" "codes" {
  name         = "2fa-codes-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"  # tenant#correlationId
  range_key    = "sk"  # receivedAt timestamp

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "tenant"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # TTL to auto-delete expired codes
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  # HIPAA: Enable encryption at rest
  server_side_encryption {
    enabled = true
  }

  # HIPAA: Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Global secondary index for tenant queries
  global_secondary_index {
    name            = "tenant-status-index"
    hash_key        = "tenant"
    range_key       = "status"
    projection_type = "ALL"
  }

  tags = {
    Name        = "2fa-codes-${var.env}"
    Environment = var.env
    PHI         = "true"   # May contain PHI in correlation data
    Compliance  = "HIPAA"
  }
}

# Lambda execution role
resource "aws_iam_role" "parser_lambda" {
  name = "2fa-parser-lambda-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}



# Lambda policy
resource "aws_iam_role_policy" "parser_lambda" {
  name = "2fa-parser-lambda-policy"
  role = aws_iam_role.parser_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}"
      },

      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.codes.arn,
          "${aws_dynamodb_table.codes.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "2FA-Parser"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# Lambda function for parsing emails
resource "aws_lambda_function" "parser" {
  filename         = "${path.module}/lambda/parser.zip"
  function_name    = "2fa-parser-${var.env}"
  role            = aws_iam_role.parser_lambda.arn
  handler         = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/parser.zip")
  runtime         = "nodejs16.x"
  timeout         = 60
  memory_size     = 256

  environment {
    variables = {
      DYNAMODB_TABLE   = aws_dynamodb_table.codes.name
      CODE_TTL_MINUTES = var.code_ttl_minutes
      TENANT_CONFIGS   = jsonencode(var.tenant_configs)
      REGEX_PROFILES   = jsonencode(local.regex_profiles)
      ENABLE_WEBHOOKS  = var.enable_webhooks
      S3_BUCKET        = var.s3_bucket_name
      ENVIRONMENT      = var.env
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tags = {
    Name        = "2fa-parser-${var.env}"
    Environment = var.env
  }
}

# DLQ for failed parsing attempts
resource "aws_sqs_queue" "dlq" {
  name                      = "2fa-parser-dlq-${var.env}"
  message_retention_seconds = 1209600  # 14 days
  
  # HIPAA: Enable encryption
  kms_master_key_id = "alias/aws/sqs"

  tags = {
    Name        = "2fa-parser-dlq-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${aws_lambda_function.parser.function_name}"
  retention_in_days = var.log_retention_days
  
  # HIPAA: Logs are encrypted by default with CloudWatch Logs service key
  # To use custom KMS key, create one and reference it here

  tags = {
    Name        = "2fa-parser-logs-${var.env}"
    Environment = var.env
    PHI         = "true"
    Compliance  = "HIPAA"
  }
}

# Note: We're using EventBridge schedule instead of SQS trigger
# The S3 scanner runs every minute to process new emails

# API Gateway for internal lookups
resource "aws_api_gateway_rest_api" "lookup" {
  name        = "2fa-lookup-${var.env}"
  description = "Internal API for 2FA code lookups"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway resource
resource "aws_api_gateway_resource" "codes" {
  rest_api_id = aws_api_gateway_rest_api.lookup.id
  parent_id   = aws_api_gateway_rest_api.lookup.root_resource_id
  path_part   = "codes"
}

# API Gateway method
resource "aws_api_gateway_method" "get_code" {
  rest_api_id      = aws_api_gateway_rest_api.lookup.id
  resource_id      = aws_api_gateway_resource.codes.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

# Lambda for API lookups
resource "aws_lambda_function" "lookup" {
  filename         = "${path.module}/lambda/lookup.zip"
  function_name    = "2fa-lookup-${var.env}"
  role            = aws_iam_role.lookup_lambda.arn
  handler         = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/lookup.zip")
  runtime         = "nodejs16.x"
  timeout         = 10
  memory_size     = 128

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.codes.name
    }
  }

  tags = {
    Name        = "2fa-lookup-${var.env}"
    Environment = var.env
  }
}

# Lambda execution role for lookup
resource "aws_iam_role" "lookup_lambda" {
  name = "2fa-lookup-lambda-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda policy for lookup
resource "aws_iam_role_policy" "lookup_lambda" {
  name = "2fa-lookup-lambda-policy"
  role = aws_iam_role.lookup_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.codes.arn,
          "${aws_dynamodb_table.codes.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "2FA-Lookup"
          }
        }
      }
    ]
  })
}

# API Gateway integration
resource "aws_api_gateway_integration" "lookup" {
  rest_api_id = aws_api_gateway_rest_api.lookup.id
  resource_id = aws_api_gateway_resource.codes.id
  http_method = aws_api_gateway_method.get_code.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.lookup.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lookup.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lookup.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "lookup" {
  rest_api_id = aws_api_gateway_rest_api.lookup.id

  triggers = {
    # Force new deployment when method configuration changes
    method_auth = jsonencode({
      authorization    = aws_api_gateway_method.get_code.authorization
      api_key_required = aws_api_gateway_method.get_code.api_key_required
    })
    # Redeploy when integration changes
    integration_hash = sha256(jsonencode(aws_api_gateway_integration.lookup))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.get_code,
    aws_api_gateway_integration.lookup
  ]
}

# API Gateway stage
resource "aws_api_gateway_stage" "lookup" {
  deployment_id = aws_api_gateway_deployment.lookup.id
  rest_api_id   = aws_api_gateway_rest_api.lookup.id
  stage_name    = var.env
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "no_codes_received" {
  alarm_name          = "2fa-no-codes-received-${var.env}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CodesReceived"
  namespace           = "2FA-Parser"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "No 2FA codes received in the last 10 minutes"
  treat_missing_data  = "breaching"

  dimensions = {
    Environment = var.env
  }
}

resource "aws_cloudwatch_metric_alarm" "parser_errors" {
  alarm_name          = "2fa-parser-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ParseErrors"
  namespace           = "2FA-Parser"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "High number of parser errors"

  dimensions = {
    Environment = var.env
  }
}

# S3 Event Notification for immediate processing
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parser.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.s3_bucket_name}"
}

# S3 bucket notification
resource "aws_s3_bucket_notification" "email_notifications" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.parser.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "emails/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
