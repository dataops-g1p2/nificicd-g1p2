terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.5.0"

  # Local backend for GitHub Actions workflow
  # State files will be stored in: workspaces/{environment}/terraform.tfstate
  backend "local" {
    # Path will be automatically set based on workspace
    # No need for backend-config files with local backend
  }
}