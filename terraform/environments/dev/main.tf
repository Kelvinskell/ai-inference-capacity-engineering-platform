# Create networking resources
module "networking" {
  source = "../../modules/networking"

  name_prefix          = var.name_prefix
  cluster_name         = var.cluster_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_gateway_mode     = var.nat_gateway_mode
  tags                 = var.tags
}

# S3 Model storage
module "s3" {
  source = "../../modules/s3-model-storage"

  bucket_name   = "${var.name_prefix}-models-${var.environment}-${var.aws_account_id}"
  force_destroy = true
  tags          = var.tags
}

# Create EKS Control plane
module "eks" {
  source = "../../modules/eks"

  name_prefix           = var.name_prefix
  cluster_name          = var.cluster_name
  model_bucket_arn      = module.s3.bucket_arn
  environment           = var.environment
  kubernetes_version    = var.kubernetes_version
  vpc_id                = module.networking.vpc_id
  vpc_cidr              = var.vpc_cidr
  private_subnet_ids    = module.networking.private_subnet_ids
  endpoint_access_mode  = var.endpoint_access_mode
  authentication_mode   = var.authentication_mode
  access_principal_arns = var.access_principal_arns
  tags                  = var.tags
}

# Create Custom Gpu Node resources
# Create custom GPU NodeClass and NodePools
module "gpu_node" {
  source = "../../modules/gpu-node"

  node_role_name        = module.eks.node_role_name
  private_subnet_ids    = module.networking.private_subnet_ids
  node_security_group_id = module.eks.cluster_primary_security_group_id
}