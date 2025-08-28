variable "aws_profile" {
  type    = string
  default = "novoflow-dev"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "receipt_rule_set_name" {
  type    = string
  default = "inbound-auth-simple"
}

variable "receipt_rule_name" {
  type    = string
  default = "catch-all-to-s3"
}

variable "recipients" {
  type    = list(string)
  default = [] # Empty = catch all
}

variable "bucket_name" {
  type    = string
  default = "novoflow-ses-simple-dev-us-east-2"
}

variable "object_prefix" {
  type    = string
  default = "emails/"
}