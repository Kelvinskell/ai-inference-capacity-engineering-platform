# Public subnets for NAT gateways and load balancers.
resource "aws_subnet" "public_subnets" {
  count = var.az_count

  vpc_id                  = aws_vpc.llm_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = "${var.name_prefix}-public-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/elb" = "1"
  })
}

# Private subnets for EKS control plane and worker nodes.
resource "aws_subnet" "private_subnets" {
  count = var.az_count

  vpc_id            = aws_vpc.llm_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.selected_azs[count.index]

  tags = merge(local.common_tags, {
    Name                              = "${var.name_prefix}-private-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  })
}
