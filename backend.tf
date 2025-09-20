terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-euw2"
    key            = "dynamic-string-service/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks-euw2"
    encrypt        = true
  }
}
