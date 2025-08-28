terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws  = { source = "hashicorp/aws",  version = ">= 5.50" }
    null = { source = "hashicorp/null", version = ">= 3.2.2" }
  }
}
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}


