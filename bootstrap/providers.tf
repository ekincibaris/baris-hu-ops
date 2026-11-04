provider "aws" {
  region              = var.region
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      Project   = "ops-baris"
      Component = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}
