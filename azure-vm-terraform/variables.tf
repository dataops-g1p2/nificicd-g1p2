variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "francecentral"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "vm_name" {
  description = "Virtual machine name"
  type        = string
}

variable "vm_size" {
  description = "Virtual machine size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "nifi"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}