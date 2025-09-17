variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name used for tagging and resource names"
  type        = string
  default     = "dynamic-string-service"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "dev"
}

variable "ssm_parameter_name" {
  description = "Override for the SSM parameter name. If empty, a name will be derived."
  type        = string
  default     = ""
}

variable "dynamic_string_default" {
  description = "Default value for the dynamic string at first deploy. Changes are ignored by Terraform so you can update outside Terraform."
  type        = string
  default     = "Hello from Terraform"
}

locals {
  ssm_parameter_name  = var.ssm_parameter_name != "" ? var.ssm_parameter_name : "/${var.project_name}/${var.environment}/dynamic_string"
  lambda_function_name = "${var.project_name}-${var.environment}-renderer"
  log_group_name       = "/aws/lambda/${local.lambda_function_name}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
