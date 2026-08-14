terraform {
  backend "s3" {
    bucket       = "ai-inference-tfstate-euw1"
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
