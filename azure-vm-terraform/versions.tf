terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.5.0"

  backend "local" {
    # Path will be set via backend config file per environment
    # e.g., terraform init -backend-config=backend-configs/development.tfbackend
  }
}
