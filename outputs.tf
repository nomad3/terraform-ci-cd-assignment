output "api_base_url" {
  description = "Base URL for the HTTP API. Open this URL to view the page."
  value       = try(aws_apigatewayv2_api.http_api[0].api_endpoint, null)
}

output "ssm_parameter_name" {
  description = "The SSM parameter name storing the dynamic string"
  value       = aws_ssm_parameter.dynamic_string.name
}

output "api_id" {
  description = "HTTP API ID (useful for LocalStack testing)"
  value       = try(aws_apigatewayv2_api.http_api[0].id, null)
}

output "lambda_function_name" {
  description = "Lambda function name for direct invocation (used in LocalStack tests)"
  value       = aws_lambda_function.renderer.function_name
}
