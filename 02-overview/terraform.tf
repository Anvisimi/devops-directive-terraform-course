# ------------------------------------------------------------------------------
# Terraform and provider configuration (no cloud resources created here).
# This file declares which Terraform CLI and provider versions this project uses.
# ------------------------------------------------------------------------------

terraform {
  # Declares which providers this project uses; Terraform downloads only these.
  required_providers {
    aws = {
      # Official AWS provider from Terraform Registry (registry.terraform.io/hashicorp/aws).
      source  = "hashicorp/aws"
      # ~> 5.92 = 5.92 or newer in the 5.x line, but not 6.0 (allows patches/minor, not major).
      version = "~> 5.92"
    }
  }

  # This config only runs with Terraform CLI 1.2 or newer; avoids surprises on old installs.
  required_version = ">= 1.2"
}
