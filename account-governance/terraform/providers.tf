terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }

  # Supply bucket/key/region through -backend-config. Do not use local state for
  # production governance, or the ephemeral CI runner would lose ownership.
  backend "s3" {}
}

provider "aws" {
  region              = var.control_region
  allowed_account_ids = [var.governance_account_id]
  # Real AWS credentials come from the normal credential chain/OIDC, never the
  # LocalStack provider or the dummy credentials in the other project.
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "account-governance"
    }
  }
}
