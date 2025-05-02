provider "aws" {
  region = var.aws_region
  default_tags {
    tags = merge({
      terraform   = "true"
      owner       = var.owner
      environment = var.environment
      stack       = var.stack
      team        = var.team
    }, var.additional_tags)
  }
}

