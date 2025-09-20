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

variable "use_localstack" {
  description = "If true, point AWS provider endpoints to LocalStack"
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "use_secure_string" {
  description = "If true, store the SSM parameter as SecureString"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for SecureString encryption. If empty and use_secure_string=true, a CMK will be created and used."
  type        = string
  default     = ""
}

variable "kms_key_deletion_days" {
  description = "KMS key deletion window in days for the created CMK"
  type        = number
  default     = 7
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 3
}

variable "lambda_memory_mb" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for the Lambda function (-1 disables reservation)"
  type        = number
  default     = -1
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 400
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
