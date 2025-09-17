output "api_base_url" {
  description = "Base URL for the HTTP API. Open this URL to view the page."
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "ssm_parameter_name" {
  description = "The SSM parameter name storing the dynamic string"
  value       = aws_ssm_parameter.dynamic_string.name
}
