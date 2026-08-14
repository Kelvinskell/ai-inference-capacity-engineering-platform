# Elastic IPs for NAT gateways (one per AZ or shared single, based on nat_gateway_mode).
resource "aws_eip" "nat_eips" {
  count = local.nat_count

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}-${var.environment}"
  })
}

# NAT gateways to enable private subnet egress without public IPs.
resource "aws_nat_gateway" "nat_gateways" {
  count = local.nat_count

  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-${count.index + 1}-${var.environment}"
  })

  depends_on = [aws_internet_gateway.llm_igw]
}
