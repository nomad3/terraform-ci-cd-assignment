terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigatewayv2 = var.localstack_endpoint
      cloudwatch   = var.localstack_endpoint
      lambda       = var.localstack_endpoint
      logs         = var.localstack_endpoint
      ssm          = var.localstack_endpoint
      iam          = var.localstack_endpoint
      sts          = var.localstack_endpoint
    }
  }
}
