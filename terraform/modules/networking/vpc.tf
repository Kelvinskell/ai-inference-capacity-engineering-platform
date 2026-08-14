# VPC for Kubernetes cluster with DNS enabled for service discovery.
resource "aws_vpc" "llm_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc-${var.environment}"
  })
}
