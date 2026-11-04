terraform {
  # use_lockfile (S3-native state locking) needs Terraform 1.10+.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # Partial configuration: bucket comes from backend.hcl (gitignored), see
  # backend.hcl.example. Locking uses an S3 lock object; no DynamoDB table.
  backend "s3" {
    key          = "ops-baris-hu/prod/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
