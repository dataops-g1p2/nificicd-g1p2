variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID"
  sensitive   = true
}

variable "azure_location" {
  type        = string
  description = "Azure region for resources"
  default     = "francecentral"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  default     = "rg-nifi_cicd_project-dev"
}

variable "environment" {
  type        = string
  description = "Environment name (fixed to development)"
  default     = "development"
}

variable "vm_size" {
  type        = string
  description = "Azure VM size"
  default     = "Standard_B2s_v2"  # 2 vCPUs, 8 GB RAM
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key file"
  default     = "~/.ssh/id_rsa.pub"
}

variable "nifi_username" {
  type        = string
  description = "NiFi admin username"
  default     = "admin"
}

variable "nifi_password" {
  type        = string
  description = "NiFi admin password"
  sensitive   = true
  default     = "49e9eda8ef1c33c39f6dc418535751a8"
}

variable "nifi_sensitive_key" {
  type        = string
  description = "NiFi sensitive properties key"
  sensitive   = true
  default     = "1163ebb9600df80eb74f30ca"
}