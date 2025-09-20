data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.use_secure_string && var.kms_key_arn != "" ? var.kms_key_arn : (length(aws_kms_key.ssm) > 0 ? aws_kms_key.ssm[0].arn : null)
  tags              = local.tags
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-${var.environment}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-policy"
  description = "Allow Lambda to read SSM parameter and write logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}:*"
      },
      {
        Sid    = "ReadDynamicStringParameter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_parameter_name}"
      }
    ]
  })

  tags = local.tags
}

# Extra policy only when SecureString is enabled
resource "aws_iam_policy" "kms_decrypt" {
  count       = var.use_secure_string ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kms-decrypt"
  description = "Allow Lambda to decrypt SecureString parameters"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "KMSDecryptForSSM",
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_kms_attach" {
  count      = var.use_secure_string ? 1 : 0
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.kms_decrypt[0].arn
}

# Optional KMS key for SecureString when user did not provide one
resource "aws_kms_key" "ssm" {
  count                   = var.use_secure_string && var.kms_key_arn == "" ? 1 : 0
  description             = "CMK for SecureString parameter"
  deletion_window_in_days = var.kms_key_deletion_days
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "ssm" {
  count         = var.use_secure_string && var.kms_key_arn == "" ? 1 : 0
  name          = "alias/${var.project_name}-${var.environment}-ssm"
  target_key_id = aws_kms_key.ssm[0].id
}

# Update SSM parameter to always use encryption when enabled
resource "aws_ssm_parameter" "dynamic_string" {
  name        = local.ssm_parameter_name
  description = "Dynamic string used by Lambda to render HTML"
  type        = var.use_secure_string ? "SecureString" : "String"
  value       = var.dynamic_string_default
  tier        = "Standard"
  key_id      = var.use_secure_string ? (var.kms_key_arn != "" ? var.kms_key_arn : (length(aws_kms_key.ssm) > 0 ? aws_kms_key.ssm[0].arn : null)) : null
  tags        = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_lambda_function" "renderer" {
  function_name    = local.lambda_function_name
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_mb
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      PARAM_NAME     = local.ssm_parameter_name
      DEFAULT_STRING = var.dynamic_string_default
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  tags      = local.tags
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_apigatewayv2_api" "http_api" {
  count         = var.use_localstack ? 0 : 1
  name          = "${var.project_name}-${var.environment}-http-api"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  count                  = var.use_localstack ? 0 : 1
  api_id                 = aws_apigatewayv2_api.http_api[0].id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  payload_format_version = "2.0"
  integration_uri        = aws_lambda_function.renderer.invoke_arn
}

# Route root path to the Lambda
resource "aws_apigatewayv2_route" "root" {
  count     = var.use_localstack ? 0 : 1
  api_id    = aws_apigatewayv2_api.http_api[0].id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[0].id}"
  authorization_type = "NONE"
}

# API Gateway access logs (encrypted)
resource "aws_cloudwatch_log_group" "api_gw" {
  count             = var.use_localstack ? 0 : 1
  name              = "/aws/apigateway/${var.project_name}-${var.environment}-http"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.use_secure_string && var.kms_key_arn != "" ? var.kms_key_arn : (length(aws_kms_key.ssm) > 0 ? aws_kms_key.ssm[0].arn : null)
  tags              = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  count       = var.use_localstack ? 0 : 1
  api_id      = aws_apigatewayv2_api.http_api[0].id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw[0].arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationStatus = "$context.integrationStatus"
      errorMessage      = "$context.error.message"
    })
  }
}

resource "aws_lambda_permission" "allow_apigw" {
  count         = var.use_localstack ? 0 : 1
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.renderer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:${data.aws_partition.current.partition}:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.http_api[0].id}/*/*/*"
}

# Dead Letter Queue for Lambda (optional simple SQS)
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.project_name}-${var.environment}-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = var.use_secure_string && var.kms_key_arn != "" ? var.kms_key_arn : (length(aws_kms_key.ssm) > 0 ? aws_kms_key.ssm[0].arn : null)
  tags                      = local.tags
}

# IAM updates: allow Lambda to send to DLQ
resource "aws_iam_policy" "lambda_dlq_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-dlq"
  description = "Allow Lambda to send messages to DLQ"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "SQSSend",
        Effect: "Allow",
        Action: ["sqs:SendMessage"],
        Resource: aws_sqs_queue.lambda_dlq.arn
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_dlq_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dlq_policy.arn
}

# Basic CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.renderer.function_name
  }

  tags = local.tags
}
