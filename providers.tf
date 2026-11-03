terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Makes the self-signed certificate for HTTPS on the load balancer
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Absolute path, so the laptop and the pipeline runner use the SAME state file.
  # A relative path resolves differently depending on the folder Terraform runs in.
  backend "local" {
    path = "C:/tfstate/innovatech-cs1-dev.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}