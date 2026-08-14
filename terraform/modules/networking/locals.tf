# Derive computed values from input variables.
data "aws_availability_zones" "available_azs" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available_azs.names, 0, var.az_count)
  nat_count    = var.nat_gateway_mode == "ha" ? var.az_count : 1

  common_tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}
