# ========================================================================
# TERRAFORM MAKEFILE: Azure VM Infrastructure with Proper State Isolation
# ========================================================================
# Location: azure-vm-terraform/Makefile

MAKEFLAGS += --no-print-directory

# Environment mapping
ENV ?= development
ENV_MAP_dev := development
ENV_MAP_development := development
ENV_MAP_staging := staging
ENV_MAP_prod := production
ENV_MAP_production := production

WORKSPACE := $(or $(ENV_MAP_$(ENV)),$(ENV))

# Valid workspaces
VALID_WORKSPACES := development staging production

# Paths
TFVARS_FILE := $(WORKSPACE).tfvars
BACKEND_CONFIG := backend-configs/$(WORKSPACE).tfbackend
ROOT_DIR := $(shell pwd)/..
ENV_FILE := $(ROOT_DIR)/.env.$(WORKSPACE)

.DEFAULT_GOAL := help

.PHONY: help init validate plan apply destroy output state \
        init-all validate-all plan-all apply-all destroy-all output-all state-all \
        update-secrets update-secrets-all check-secrets \
        clean clean-all diagnose

help:
	@echo ""
	@echo "┌────────────────────────────────────────────────────┐"
	@echo "|  Terraform Infrastructure Manager (State Isolated) |"
	@echo "└────────────────────────────────────────────────────┘"
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
	@echo "🔄 ALL ENVIRONMENTS OPERATIONS"
	@echo "  init-all          Initialize all environments"
	@echo "  validate-all      Validate all configurations"
	@echo "  plan-all          Plan all environments"
	@echo "  apply-all         Deploy all environments (isolated)"
	@echo "  destroy-all       Destroy all environments"
	@echo "  output-all        Show all outputs"
	@echo "  state-all         Show all states"
	@echo ""
	@echo "🔐 SECRETS MANAGEMENT"
	@echo "  update-secrets         Update GitHub secrets (ENV required)"
	@echo "  update-secrets-all     Update all GitHub secrets"
	@echo "  check-secrets          Check GitHub secrets status"
	@echo ""
	@echo "🧹 MAINTENANCE"
	@echo "  clean                  Clean Terraform cache (ENV required)"
	@echo "  clean-all              Clean all caches"
	@echo "  diagnose               Run diagnostics"
	@echo ""
	@echo "🌍 Valid Environments: development, staging, production"
	@echo ""
	@echo "💡 Example Usage:"
	@echo "  make init ENV=development     # Initialize development"
	@echo "  make apply ENV=staging        # Deploy staging"
	@echo "  make apply-all                # Deploy all (isolated)"
	@echo ""

# =============================================================================
#  INITIALIZATION
# =============================================================================
init:
	@echo ""
	@echo "──────────────────────────────────────────"
	@echo "  Initializing - $(WORKSPACE) Environment "
	@echo "──────────────────────────────────────────"
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

init-all:
	@echo ""
	@echo "╔════════════════════════════════╗"
	@echo "║ Initializing All Environments  ║"
	@echo "╚════════════════════════════════╝"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		echo "🔄 Initializing $$env..."; \
		$(MAKE) init ENV=$$env || exit 1; \
	done
	@echo "✅ All environments initialized!"
	@echo ""

# =============================================================================
#  VALIDATION
# =============================================================================
validate:
	@echo ""
	@echo "──────────────────────────────────────────"
	@echo "  Validating - $(WORKSPACE) Environment"
	@echo "──────────────────────────────────────────"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform validate
	@echo ""
	@echo "✅ Configuration valid for $(WORKSPACE)"
	@echo ""

validate-all:
	@echo ""
	@echo "╔══════════════════════════════╗"
	@echo "║ Validating All Environments  ║"
	@echo "╚══════════════════════════════╝"
	@echo ""
	@ERRORS=0; \
	for env in $(VALID_WORKSPACES); do \
		echo "Validating $$env..."; \
		if $(MAKE) validate ENV=$$env; then \
			echo "✅ $$env valid"; \
		else \
			echo "❌ $$env validation failed"; \
			ERRORS=$$((ERRORS + 1)); \
		fi; \
		echo ""; \
	done; \
	if [ $$ERRORS -gt 0 ]; then \
		echo "❌ Validation failed for $$ERRORS environment(s)"; \
		exit 1; \
	fi
	@echo "✅ All environments validated"
	@echo ""

# =============================================================================
#  PLANNING
# =============================================================================
plan:
	@echo ""
	@echo "────────────────────────────────────────"
	@echo "  Planning - $(WORKSPACE) Environment"
	@echo "────────────────────────────────────────"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform plan -var-file=$(TFVARS_FILE)
	@echo ""

plan-all:
	@echo ""
	@echo "╔═══════════════════════════╗"
	@echo "║ Planning All Environments ║"
	@echo "╚═══════════════════════════╝"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		$(MAKE) plan ENV=$$env; \
		sleep 2; \
	done
	@echo "✅ All plans generated"
	@echo ""

# =============================================================================
#  APPLY
# =============================================================================
apply:
	@echo ""
	@echo "───────────────────────────────────────"
	@echo " Applying - $(WORKSPACE) Environment   "
	@echo "───────────────────────────────────────"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform apply -var-file=$(TFVARS_FILE)
	@echo ""
	@$(MAKE) sync-outputs
	@echo ""
	@echo "✅ Infrastructure deployed for $(WORKSPACE)"
	@echo ""

apply-all:
	@echo ""
	@echo "╔════════════════════════════════════════════════════╗"
	@echo "║     🚀 Deploying ALL Environments (Isolated)       ║"
	@echo "╚════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Each environment has its own state file:"
	@echo "  • workspaces/development/terraform.tfstate"
	@echo "  • workspaces/staging/terraform.tfstate"
	@echo "  • workspaces/production/terraform.tfstate"
	@echo ""
	@read -p "Continue? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "❌ Cancelled"; \
		exit 1; \
	fi
	@FAILED_ENVS=""; \
	APPLIED_COUNT=0; \
	for env in $(VALID_WORKSPACES); do \
		echo ""; \
		echo "────────────────────────"; \
		echo "  Applying $$env...     "; \
		echo "────────────────────────"; \
		if $(MAKE) apply ENV=$$env; then \
			echo "✅ $$env deployed successfully"; \
			APPLIED_COUNT=$$((APPLIED_COUNT + 1)); \
		else \
			FAILED_ENVS="$$FAILED_ENVS $$env"; \
			echo "❌ $$env deployment failed"; \
		fi; \
		if [ "$$env" != "production" ]; then \
			echo "⏳ Waiting 30 seconds..."; \
			sleep 30; \
		fi; \
	done; \
	echo ""; \
	echo "📊 Deployment Summary: $$APPLIED_COUNT/3 successful"; \
	if [ -n "$$FAILED_ENVS" ]; then \
		echo "❌ Failed:$$FAILED_ENVS"; \
		exit 1; \
	else \
		echo "🎉 All environments deployed!"; \
	fi
	@echo ""

# =============================================================================
#  DESTROY
# =============================================================================
destroy:
	@echo ""
	@echo "⚠️  WARNING: Destroying $(WORKSPACE) environment"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform destroy -var-file=$(TFVARS_FILE) -auto-approve
	@echo "✅ $(WORKSPACE) destroyed"
	@echo ""

destroy-all:
	@echo ""
	@echo "⚠️  WARNING: This will destroy ALL environments"
	@echo ""
	@read -p "Type 'destroy-all-environments' to confirm: " confirm; \
	if [ "$$confirm" = "destroy-all-environments" ]; then \
		for env in production staging development; do \
			echo ""; \
			echo "⚠️ Destroying $$env..."; \
			$(MAKE) destroy ENV=$$env; \
		done; \
		echo "✅ All destroyed"; \
	else \
		echo "❌ Cancelled"; \
	fi
	@echo ""

# =============================================================================
#  OUTPUT & STATE
# =============================================================================
output:
	@echo ""
	@echo "📤 Outputs for $(WORKSPACE):"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform output
	@echo ""

output-all:
	@echo ""
	@echo "╔════════════════════════════╗"
	@echo "║ Outputs - All Environments ║"
	@echo "╚════════════════════════════╝"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		echo "───────────────────────────"; \
		echo " $$env Environment         "; \
		echo "───────────────────────────"; \
		$(MAKE) output ENV=$$env; \
	done

state:
	@echo ""
	@echo "📋 State for $(WORKSPACE):"
	@echo ""
	@terraform init -reconfigure -backend-config=$(BACKEND_CONFIG) > /dev/null 2>&1
	@terraform state list || echo "⚠️  No state found"
	@echo ""

state-all:
	@echo ""
	@echo "╔═══════════════════════════╗"
	@echo "║ State - All Environments  ║"
	@echo "╚═══════════════════════════╝"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		echo "───────────────────────────"; \
		echo " $$env Environment         "; \
		echo "───────────────────────────"; \
		$(MAKE) state ENV=$$env; \
	done

# =============================================================================
#  OUTPUT SYNCHRONIZATION
# =============================================================================
sync-outputs:
	@echo "🔄 Syncing outputs to $(ENV_FILE)..."
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "⚠️  $(ENV_FILE) not found - skipping"; \
		exit 0; \
	fi
	@VM_IP=$$(terraform output -raw vm_public_ip 2>/dev/null || echo ""); \
	if [ -n "$$VM_IP" ] && [ "$$VM_IP" != "" ]; then \
		sed -i.bak "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=$$VM_IP|" "$(ENV_FILE)" 2>/dev/null || \
		sed -i '' "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=$$VM_IP|" "$(ENV_FILE)" 2>/dev/null; \
		echo "  ✅ VM_PUBLIC_IP updated: $$VM_IP"; \
		rm -f "$(ENV_FILE).bak"; \
	fi

# =============================================================================
#  GITHUB SECRETS
# =============================================================================
update-secrets:
	@echo ""
	@echo "🔐 Updating GitHub secrets for $(WORKSPACE)..."
	@bash ../scripts/setup_nifi_github_secrets.sh $(WORKSPACE) --from-env --with-terraform
	@echo ""

update-secrets-all:
	@echo ""
	@echo "╔════════════════════════════════════╗"
	@echo "║ Updating GitHub Secrets - All Envs ║"
	@echo "╚════════════════════════════════════╝"
	@echo ""
	@bash ../scripts/setup_nifi_github_secrets.sh all --from-env --with-terraform
	@echo ""

check-secrets:
	@echo ""
	@echo "📋 GitHub Secrets Status:"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		echo "$$env:"; \
		gh secret list --env $$env 2>/dev/null || echo "  No secrets"; \
		echo ""; \
	done

remove-secrets:
	@echo ""
	@echo "🗑️  Removing GitHub secrets for $(WORKSPACE)..."
	@bash ../scripts/remove_github_secrets.sh $(WORKSPACE) --remove
	@echo ""

remove-secrets-all:
	@echo ""
	@echo "╔═════════════════════════════════════╗"
	@echo "║ Removing GitHub Secrets - All Envs  ║"
	@echo "╚═════════════════════════════════════╝"
	@echo ""
	@bash ../scripts/remove_github_secrets.sh all --remove
	@echo ""
# =============================================================================
#  CLEANUP
# =============================================================================
clean:
	@echo "🧹 Cleaning $(WORKSPACE)..."
	@rm -rf .terraform .terraform.lock.hcl *.tfplan
	@rm -rf workspaces/*/terraform.tfstate*
	@echo "✅ Cleaned"
	@echo ""

clean-all:
	@echo "🧹 Cleaning all..."
	@rm -rf .terraform .terraform.lock.hcl *.tfplan
	@rm -rf workspaces/*/terraform.tfstate*
	@echo "✅ All cleaned"
	@echo ""

# =============================================================================
#  DIAGNOSTICS
# =============================================================================
diagnose:
	@echo ""
	@echo "╔═══════════════════════╗"
	@echo "║ Terraform Diagnostics ║"
	@echo "╚═══════════════════════╝"
	@echo ""
	@for env in $(VALID_WORKSPACES); do \
		echo "Environment: $$env"; \
		echo "  Backend: backend-configs/$$env.tfbackend"; \
		if [ -f "backend-configs/$$env.tfbackend" ]; then \
			echo "  ✅ Backend config exists"; \
			cat "backend-configs/$$env.tfbackend" | sed 's/^/    /'; \
		fi; \
		echo "  State: workspaces/$$env/terraform.tfstate"; \
		if [ -f "workspaces/$$env/terraform.tfstate" ]; then \
			RESOURCES=$$(grep -c '"type":' "workspaces/$$env/terraform.tfstate" 2>/dev/null || echo "0"); \
			echo "  ✅ State exists ($$RESOURCES resources)"; \
		else \
			echo "  ⚠️  No state file"; \
		fi; \
		echo ""; \
	done
	@echo "✅ Diagnostic complete"
	@echo ""