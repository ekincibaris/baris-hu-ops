terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # Deliberately local state: this folder creates the bucket that holds every
  # other state file (chicken and egg). terraform.tfstate here is gitignored;
  # keep a copy somewhere safe or migrate it into the bucket afterwards
  # (see README "Bootstrap").
}
