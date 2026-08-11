output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.llm_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets."
  value       = aws_subnet.private_subnets[*].id
}

output "internet_gateway_id" {
  description = "Internet gateway ID."
  value       = aws_internet_gateway.llm_igw.id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = aws_nat_gateway.nat_gateways[*].id
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public_route_table.id
}

output "private_route_table_ids" {
  description = "Private route table IDs."
  value       = aws_route_table.private_route_tables[*].id
}
