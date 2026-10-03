variable "environment" {
  type    = string
  default = "tfdev"
}

variable "name_prefix" {
  type    = string
  default = "cicd-workshop"
}

locals {
  prefix = "${var.name_prefix}-${var.environment}"
}
