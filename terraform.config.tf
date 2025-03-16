terraform {
  backend "s3" {
    bucket = "codegenitor-iac"
    key    = "terraform/terraform.tfstate"
    region = "us-east-1"
  }
}