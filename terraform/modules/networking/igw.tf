# Internet gateway for public subnet egress.
resource "aws_internet_gateway" "llm_igw" {
  vpc_id = aws_vpc.llm_vpc.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw-${var.environment}"
  })
}