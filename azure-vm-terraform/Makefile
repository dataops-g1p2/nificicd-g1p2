# ========================================================================
# TERRAFORM MAKEFILE: Azure VM Infrastructure with Proper State Isolation
# ========================================================================
# Location: azure-vm-terraform/Makefile

MAKEFLAGS += --no-print-directory

# Environment mapping
ENV ?= development
ENV_MAP_dev := development
ENV_MAP_development := development

WORKSPACE := $(or $(ENV_MAP_$(ENV)),$(ENV))

# Paths
TFVARS_FILE := $(WORKSPACE).tfvars
BACKEND_CONFIG := backend-configs/$(WORKSPACE).tfbackend
ROOT_DIR := $(shell pwd)/..
ENV_FILE := $(ROOT_DIR)/.env.$(WORKSPACE)

.DEFAULT_GOAL := help

.PHONY: help init validate plan apply destroy output state update-secrets remove-secrets clean

help:
	@echo ""
	@echo "┌─────────────────────────────────────────────────────┐"
	@echo "|  Terraform Infrastructure Manager (State Isolated)  |"
	@echo "└─────────────────────────────────────────────────────┘"
	@echo ""
	@echo "Usage: make [target] ENV=<environment>"
	@echo ""
	@echo "📦 SINGLE ENVIRONMENT OPERATIONS"
	@echo "  init              Initialize Terraform for environment"
	@echo "  validate          Validate Terraform configuration"
	@echo "  plan              Show execution plan"
	@echo "  apply             Apply infrastructure changes"
	@echo "  destroy           Destroy infrastructure"
	@echo "  output            Show outputs"
	@echo "  state             Show state list"
	@echo ""
	@echo "🔐 SECRETS MANAGEMENT"
	@echo "  update-secrets         Update GitHub secrets (ENV required)"
	@echo "  remove-secrets         Remove GitHub secrets (ENV required)"
	@echo ""
	@echo "🧹 MAINTENANCE"
	@echo "  clean                  Clean Terraform cache (ENV required)"
	@echo ""

init:
	@echo ""
	@echo "┌─────────────────────────────────────────┐"
	@echo "| Initializing - $(WORKSPACE) Environment |"
	@echo "└─────────────────────────────────────────┘"
	@echo ""
	@if [ ! -f "$(TFVARS_FILE)" ]; then \
		echo "❌ $(TFVARS_FILE) not found"; \
		exit 1; \
	fi
	@if [ ! -f "$(BACKEND_CONFIG)" ]; then \
		echo "❌ $(BACKEND_CONFIG) not found"; \
		exit 1; \
	fi
	@mkdir -p workspaces/$(WORKSPACE)
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG)
	@echo ""
	@echo "✅ Initialized $(WORKSPACE)"
	@echo ""

validate:
	@echo ""
	@echo "┌─────────────────────────────────────────┐"
	@echo "| Validating - $(WORKSPACE) Environment   |"
	@echo "└─────────────────────────────────────────┘"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform validate
	@echo ""
	@echo "✅ Configuration valid for $(WORKSPACE)"
	@echo ""

plan:
	@echo ""
	@echo "┌──────────────────────────────────────┐"
	@echo "| Planning - $(WORKSPACE) Environment  |"
	@echo "└──────────────────────────────────────┘"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform plan -var-file=$(TFVARS_FILE)
	@echo ""

apply:
	@echo ""
	@echo "┌──────────────────────────────────────┐"
	@echo "| Applying - $(WORKSPACE) Environment  |"
	@echo "└──────────────────────────────────────┘"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform apply -var-file=$(TFVARS_FILE) -auto-approve
	@echo ""
	@$(MAKE) sync-outputs
	@echo ""
	@echo "✅ Infrastructure deployed for $(WORKSPACE)"
	@echo ""

destroy:
	@echo ""
	@echo "⚠️  WARNING: Destroying $(WORKSPACE) environment"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform destroy -var-file=$(TFVARS_FILE) -auto-approve
	@echo "✅ $(WORKSPACE) destroyed"
	@echo ""

output:
	@echo ""
	@echo "📤 Outputs for $(WORKSPACE):"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform output
	@echo ""

state:
	@echo ""
	@echo "📋 State for $(WORKSPACE):"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform state list || echo "⚠️  No state found"
	@echo ""

update-secrets:
	@echo ""
	@echo "🔐 Updating GitHub secrets for $(WORKSPACE)..."
	@bash ../scripts/setup_nifi_github_secrets.sh $(WORKSPACE) --from-env --with-terraform
	@echo ""

remove-secrets:
	@echo ""
	@echo "🗑️  Removing GitHub secrets for $(WORKSPACE)..."
	@bash ../scripts/remove_github_secrets.sh $(WORKSPACE) --remove
	@echo ""

clean:
	@echo "🧹 Cleaning $(WORKSPACE)..."
	@rm -rf .terraform .terraform.lock.hcl *.tfplan
	@rm -rf workspaces/*/terraform.tfstate*
	@echo "✅ Cleaned"
	@echo ""