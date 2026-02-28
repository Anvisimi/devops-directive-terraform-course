terraform {
  backend "remote" {
    organization = "devops-directive"

    workspaces {
      name = "devops-directive-terraform-course"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}
