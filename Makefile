# ============================================================================
# ROOT MAKEFILE: NiFi CI/CD Infrastructure Manager
# ============================================================================
# Manages local Docker environment and delegates infrastructure operations
# Location: ./Makefile

MAKEFLAGS += --no-print-directory

# Environment configuration
ENV ?= local
PROJECT_NAME := nifi_cicd_project
DOCKER := docker compose
TF_MAKEFILE := azure-vm-terraform/Makefile

# Environment mapping
ENV_MAP_local := local
ENV_MAP_dev := development
ENV_MAP_development := development

WORKSPACE := $(or $(ENV_MAP_$(ENV)),$(ENV))
ENV_FILE := $(if $(filter local,$(WORKSPACE)),.env,.env.$(WORKSPACE))

# SSH Key Configuration
SSH_KEY_PATH := $(HOME)/.ssh/id_rsa

-include .env
export

.DEFAULT_GOAL := help

.PHONY: 

help:
	@echo ""
	@echo "┌───────────────────────────────────┐"
	@echo "| NiFi CI/CD Infrastructure Manager |"
	@echo "└───────────────────────────────────┘"
	@echo ""
	@echo "Usage: make [target] [ENV=environment]"
	@echo ""
	@echo "🔧 SETUP & CLEANUP PASSWORDS"
	@echo "  setup-password ENV=         Generate and set password for specified ENV"
	@echo "  clean-generated-info ENV=   Clean generated info for specified ENV"
	@echo ""
	@echo "🐳 LOCAL DOCKER OPERATIONS"
	@echo "  up                         Start local Docker NiFi environment"
	@echo "  down                       Stop local Docker NiFi environment"
	@echo "  restart                    Restart local Docker NiFi environment"
	@echo "  status                     Show status of local Docker containers"
	@echo "  logs                       Tail logs of all local Docker containers"
	@echo "  logs-nifi                  Tail logs of local NiFi container"
	@echo "  logs-registry              Tail logs of local NiFi Registry container"
	@echo "  clean-volumes              Clean local Docker volumes (data)"
	@echo ""
	@echo "🔌 SSH ACCESS TO REMOTE VMs"
	@echo "  ssh-dev                    SSH into Development VM"
	@echo "  ssh-test-dev               Test SSH connection to Development VM"
	@echo "  ssh-logs-dev               View NiFi logs on Development VM"
	@echo "  ssh-status-dev             Check container status on Development VM"
	@echo ""
	@echo "☁️  TERRAFORM OPERATIONS"
	@echo "  tf-init                    Initialize Terraform workspace"
	@echo "  tf-validate                Validate Terraform configuration"
	@echo "  tf-plan                    Show execution plan"
	@echo "  tf-apply                   Apply infrastructure changes"
	@echo "  tf-destroy                 Destroy infrastructure"
	@echo "  tf-output                  Show outputs"
	@echo "  tf-state                   Show state list"
	@echo ""
	@echo "🔒 SECRETS MANAGEMENT"
	@echo "  sync-secrets ENV=dev       Sync secrets for specified ENV"
	@echo ""
	@echo "🔐 CREDENTIALS MANAGEMENT"
	@echo "  echo  ENV=dev              Show NiFi access information (encrypted passwords)"
	@echo ""


setup-password:
	@echo ""
	@echo "🔐 Generating password for $(WORKSPACE)..."
	@echo ""
	@FILE=".env.$(WORKSPACE)"; \
	if [ "$(WORKSPACE)" = "local" ]; then FILE=".env"; fi; \
	if [ ! -f "$$FILE" ]; then echo "❌ $$FILE not found"; exit 1; fi; \
	PASS=$$(openssl rand -base64 32); \
	KEY=$$(openssl rand -hex 12); \
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$$FILE"; \
		sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$$FILE"; \
	else \
		sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$$FILE"; \
		sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$$FILE"; \
	fi; \
	echo "✅ Password: $$PASS"; \
	echo "✅ Sensitive key: $$KEY"
	@echo ""

clean-generated-info:
	@if [ "$(ENV)" = "local" ]; then \
		echo ""; \
		echo "🧹 Cleaning generated info for LOCAL environment..."; \
		echo ""; \
		FILE=".env"; \
		if [ ! -f "$$FILE" ]; then \
			echo "⚠️  $$FILE not found"; \
			exit 1; \
		fi; \
		if [ "$$(uname)" = "Darwin" ]; then \
			sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$$FILE"; \
			sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$$FILE"; \
		else \
			sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$$FILE"; \
			sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$$FILE"; \
		fi; \
		echo "   ✅ NIFI_PASSWORD cleared"; \
		echo "   ✅ NIFI_SENSITIVE_PROPS_KEY cleared"; \
		echo ""; \
		echo "✅ Local environment cleaned!"; \
	else \
		echo ""; \
		echo "🧹 Cleaning generated info for $(WORKSPACE) environment..."; \
		echo ""; \
		FILE=".env.$(WORKSPACE)"; \
		if [ ! -f "$$FILE" ]; then \
			echo "⚠️  $$FILE not found"; \
			exit 1; \
		fi; \
		if [ "$$(uname)" = "Darwin" ]; then \
			sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$$FILE"; \
			sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$$FILE"; \
			sed -i "" "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$$FILE"; \
			sed -i "" "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$$FILE"; \
			sed -i "" "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$$FILE"; \
		else \
			sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$$FILE"; \
			sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$$FILE"; \
			sed -i "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$$FILE"; \
			sed -i "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$$FILE"; \
			sed -i "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$$FILE"; \
		fi; \
		echo "   ✅ NIFI_PASSWORD cleared"; \
		echo "   ✅ NIFI_SENSITIVE_PROPS_KEY cleared"; \
		echo "   ✅ PUBLIC_IP cleared"; \
		echo "   ✅ VM_PUBLIC_IP cleared"; \
		echo "   ✅ NIFI_WEB_PROXY_HOST cleared"; \
		echo ""; \
		echo "✅ $(WORKSPACE) environment cleaned!"; \
	fi
	@echo ""
	@echo "💡 To regenerate:"
	@echo "   Passwords: make setup-password ENV=$(ENV)"
	@if [ "$(ENV)" != "local" ]; then \
		echo "   IPs: make tf-output ENV=$(ENV)"; \
	fi
	@echo ""

echo:
	@echo ""
	@echo "╔═════════════════════════════════════════════╗"
	@echo "║  NiFi CI/CD Environment Access Information  ║"
	@echo "╚═════════════════════════════════════════════╝"
	@echo ""
	@if [ "$(WORKSPACE)" = "local" ]; then \
		echo "┌───────────────────────┐"; \
		echo "│ 🏠 LOCAL ENVIRONMENT  │"; \
		echo "└───────────────────────┘"; \
		if [ -f .env ]; then \
			ENV_FILE='.env'; \
			USER=$$(grep "^NIFI_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			PASS=$$(grep "^NIFI_PASSWORD=" $$ENV_FILE | cut -d'=' -f2-); \
			echo "  📊 NiFi UI:         https://localhost:8443/nifi"; \
			echo "  📦 NiFi Registry:   http://localhost:18080/nifi-registry"; \
			echo "  👤 Username:        $$USER"; \
			echo "  🔑 Password:        $$PASS"; \
		else \
			echo "  ⚠️  .env file not found - run 'make setup-passwords'"; \
		fi; \
	elif [ "$(WORKSPACE)" = "development" ]; then \
		echo "┌─────────────────────────────┐"; \
		echo "│ 🔧 DEVELOPMENT ENVIRONMENT  │"; \
		echo "└─────────────────────────────┘"; \
		if [ -f .env.development ]; then \
			ENV_FILE='.env.development'; \
			IP=$$(grep "^VM_PUBLIC_IP=" $$ENV_FILE | cut -d'=' -f2-); \
			USER=$$(grep "^NIFI_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			PASS=$$(grep "^NIFI_PASSWORD=" $$ENV_FILE | cut -d'=' -f2-); \
			VMUSER=$$(grep "^VM_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			if [ -n "$$IP" ] && [ "$$IP" != "" ]; then \
				echo "  📊 NiFi UI:         https://$$IP:8443/nifi"; \
				echo "  📦 NiFi Registry:   http://$$IP:18080/nifi-registry"; \
				echo "  👤 NiFi Username:   $$USER"; \
				echo "  🔑 NiFi Password:   $$PASS"; \
				echo "  🌐 VM IP:           $$IP"; \
				echo "  💻 SSH:             ssh -i $(SSH_KEY_PATH) azureuser@$$IP"; \
				echo "  🚀 Quick SSH:       make ssh-dev"; \
			else \
				echo "  ⚠️  VM not deployed - run 'make tf-apply ENV=development'"; \
			fi; \
		else \
			echo "  ⚠️  .env.development not found"; \
		fi; \
	elif [ "$(WORKSPACE)" = "staging" ]; then \
		echo "┌─────────────────────────┐"; \
		echo "│ 🎭 STAGING ENVIRONMENT  │"; \
		echo "└─────────────────────────┘"; \
		if [ -f .env.staging ]; then \
			ENV_FILE='.env.staging'; \
			IP=$$(grep "^VM_PUBLIC_IP=" $$ENV_FILE | cut -d'=' -f2-); \
			USER=$$(grep "^NIFI_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			PASS=$$(grep "^NIFI_PASSWORD=" $$ENV_FILE | cut -d'=' -f2-); \
			VMUSER=$$(grep "^VM_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			if [ -n "$$IP" ] && [ "$$IP" != "" ]; then \
				echo "  📊 NiFi UI:         https://$$IP:8443/nifi"; \
				echo "  📦 NiFi Registry:   http://$$IP:18080/nifi-registry"; \
				echo "  👤 NiFi Username:   $$USER"; \
				echo "  🔑 NiFi Password:   $$PASS"; \
				echo "  🌐 VM IP:           $$IP"; \
				echo "  💻 SSH:             ssh -i $(SSH_KEY_PATH) azureuser@$$IP"; \
				echo "  🚀 Quick SSH:       make ssh-staging"; \
			else \
				echo "  ⚠️  VM not deployed - run 'make tf-apply ENV=staging'"; \
			fi; \
		else \
			echo "  ⚠️  .env.staging not found"; \
		fi; \
	elif [ "$(WORKSPACE)" = "production" ]; then \
		echo "┌────────────────────────────┐"; \
		echo "│ 🚀 PRODUCTION ENVIRONMENT  │"; \
		echo "└────────────────────────────┘"; \
		if [ -f .env.production ]; then \
			ENV_FILE='.env.production'; \
			IP=$$(grep "^VM_PUBLIC_IP=" $$ENV_FILE | cut -d'=' -f2-); \
			USER=$$(grep "^NIFI_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			PASS=$$(grep "^NIFI_PASSWORD=" $$ENV_FILE | cut -d'=' -f2-); \
			VMUSER=$$(grep "^VM_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
			if [ -n "$$IP" ] && [ "$$IP" != "" ]; then \
				echo "  📊 NiFi UI:         https://$$IP:8443/nifi"; \
				echo "  📦 NiFi Registry:   http://$$IP:18080/nifi-registry"; \
				echo "  👤 NiFi Username:   $$USER"; \
				echo "  🔑 NiFi Password:   $$PASS"; \
				echo "  🌐 VM IP:           $$IP"; \
				echo "  💻 SSH:             ssh -i $(SSH_KEY_PATH) azureuser@$$IP"; \
				echo "  🚀 Quick SSH:       make ssh-prod"; \
			else \
				echo "  ⚠️  VM not deployed - run 'make tf-apply ENV=production'"; \
			fi; \
		else \
			echo "  ⚠️  .env.production not found"; \
		fi; \
	fi
	@echo ""

up:
	@$(DOCKER) -f compose.local.yml up -d
down:
	@$(DOCKER) -f compose.local.yml down
restart: down up
status:
	@$(DOCKER) -f compose.local.yml ps
logs:
	@$(DOCKER) -f compose.local.yml logs -f --tail=100
logs-nifi:
	@$(DOCKER) -f compose.local.yml logs -f --tail=100 nifi
logs-registry:
	@$(DOCKER) -f compose.local.yml logs -f --tail=100 nifi-registry	
clean-volumes:
	@echo "🧹 Cleaning up..."
	@docker volume rm $(PROJECT_NAME)_nifi_registry_database
	@docker volume rm $(PROJECT_NAME)_nifi_registry_flow_storage
	@docker volume rm $(PROJECT_NAME)_nifi_database_repository
	@docker volume rm $(PROJECT_NAME)_nifi_flowfile_repository
	@docker volume rm $(PROJECT_NAME)_nifi_content_repository
	@docker volume rm $(PROJECT_NAME)_nifi_provenance_repository
	@docker volume rm $(PROJECT_NAME)_nifi_nar_extensions
	@docker volume rm $(PROJECT_NAME)_nifi_python_extensions
	@docker volume rm $(PROJECT_NAME)_nifi_conf
	@docker volume rm $(PROJECT_NAME)_nifi_state
	@docker volume rm $(PROJECT_NAME)_nifi_logs
	@echo "✅ Cleanup complete."

define get_vm_info
	$(eval ENV_FILE := .env.$(1))
	$(eval VM_IP := $(shell grep "^VM_PUBLIC_IP=" $(ENV_FILE) 2>/dev/null | cut -d'=' -f2))
	$(eval VM_USER := $(shell grep "^VM_USERNAME=" $(ENV_FILE) 2>/dev/null | cut -d'=' -f2 || echo "azureuser"))
endef
ssh-dev:
	@$(call get_vm_info,development)
	@if [ -z "$(VM_IP)" ]; then \
		echo "❌ VM_PUBLIC_IP not found in .env.development"; \
		echo "   Run: make tf-output ENV=development"; \
		exit 1; \
	fi
	@echo "🔐 Connecting to Development VM..."
	@echo "   IP: $(VM_IP)"
	@echo "   User: $(VM_USER)"
	@echo ""
	@ssh -i $(SSH_KEY_PATH) -o StrictHostKeyChecking=no $(VM_USER)@$(VM_IP)

ssh-test-dev:
	@$(call get_vm_info,development)
	@if [ -z "$(VM_IP)" ]; then \
		echo "❌ VM_PUBLIC_IP not found in .env.development"; \
		exit 1; \
	fi
	@echo "🧪 Testing SSH connection to Development VM..."
	@echo "   IP: $(VM_IP)"
	@if ssh -i $(SSH_KEY_PATH) -o StrictHostKeyChecking=no -o ConnectTimeout=5 $(VM_USER)@$(VM_IP) "echo 'Connection successful!'" 2>/dev/null; then \
		echo "✅ SSH connection working"; \
	else \
		echo "❌ SSH connection failed"; \
		echo "   Check: 1) VM is running  2) SSH key is deployed  3) Firewall allows SSH"; \
		exit 1; \
	fi

ssh-logs-dev:
	@$(call get_vm_info,development)
	@if [ -z "$(VM_IP)" ]; then \
		echo "❌ VM_PUBLIC_IP not found in .env.development"; \
		exit 1; \
	fi
	@echo "📋 Viewing NiFi logs on Development VM..."
	@ssh -i $(SSH_KEY_PATH) -o StrictHostKeyChecking=no $(VM_USER)@$(VM_IP) \
		"cd ~/nifi-cicd && docker compose -f compose.development.yml logs -f --tail=100 nifi"

ssh-status-dev:
	@$(call get_vm_info,development)
	@if [ -z "$(VM_IP)" ]; then \
		echo "❌ VM_PUBLIC_IP not found in .env.development"; \
		exit 1; \
	fi
	@echo "📊 Container status on Development VM:"
	@echo ""
	@ssh -i $(SSH_KEY_PATH) -o StrictHostKeyChecking=no $(VM_USER)@$(VM_IP) \
		"cd ~/nifi-cicd && docker compose -f compose.development.yml ps"

tf-init:
	@$(MAKE) -C azure-vm-terraform init ENV=$(ENV)

tf-validate:
	@$(MAKE) -C azure-vm-terraform validate ENV=$(ENV)

tf-plan:
	@$(MAKE) -C azure-vm-terraform plan ENV=$(ENV)

tf-apply:
	@$(MAKE) -C azure-vm-terraform apply ENV=$(ENV)

tf-destroy:
	@$(MAKE) -C azure-vm-terraform destroy ENV=$(ENV)

tf-output:
	@$(MAKE) -C azure-vm-terraform output ENV=$(ENV)

tf-state:
	@$(MAKE) -C azure-vm-terraform state ENV=$(ENV)
tf-clean:
	@$(MAKE) -C azure-vm-terraform clean ENV=$(ENV)


tf-update-secrets:
	@$(MAKE) -C azure-vm-terraform update-secrets ENV=$(ENV)
tf-check-secrets:
	@$(MAKE) -C azure-vm-terraform check-secrets

tf-remove-secrets:
	@$(MAKE) -C azure-vm-terraform remove-secrets ENV=$(ENV)

sync-secrets:
	@if [ "$(ENV)" = "local" ]; then \
		echo "❌ Secrets sync not applicable for local environment"; \
		exit 1; \
	fi
	@echo ""
	@echo "🔄 Syncing secrets for $(WORKSPACE) environment..."
	@bash ./scripts/setup_nifi_github_secrets.sh $(WORKSPACE) --from-env --with-terraform
	@echo ""
	@echo "✅ Secrets synchronized for $(WORKSPACE)!"
	@echo ""

health-check:
	@echo "🏥 Health Check - $(WORKSPACE)"
	@echo ""
	@if [ "$(WORKSPACE)" = "local" ]; then \
		if $(DOCKER) ps | grep -q nifi; then \
			echo "✅ NiFi container running"; \
			curl -k -s https://localhost:8443/nifi > /dev/null 2>&1 && \
				echo "✅ NiFi accessible" || echo "❌ NiFi not responding"; \
		else \
			echo "❌ NiFi not running"; \
		fi; \
		if $(DOCKER) ps | grep -q nifi-registry; then \
			echo "✅ Registry container running"; \
			curl -s http://localhost:18080/nifi-registry > /dev/null 2>&1 && \
				echo "✅ Registry accessible" || echo "❌ Registry not responding"; \
		else \
			echo "❌ Registry not running"; \
		fi; \
	else \
		VM_IP=$$(grep "^VM_PUBLIC_IP=" .env.$(WORKSPACE) 2>/dev/null | cut -d'=' -f2); \
		if [ -z "$$VM_IP" ]; then \
			echo "❌ VM_PUBLIC_IP not set. Run 'make tf-output ENV=$(WORKSPACE)'"; \
			exit 1; \
		fi; \
		echo "VM IP: $$VM_IP"; \
		ping -c 1 -W 2 $$VM_IP > /dev/null 2>&1 && \
			echo "✅ VM reachable" || echo "❌ VM not responding"; \
		curl -k -s --connect-timeout 5 https://$$VM_IP:8443/nifi > /dev/null 2>&1 && \
			echo "✅ NiFi accessible" || echo "❌ NiFi not responding"; \
		curl -s --connect-timeout 5 http://$$VM_IP:18080/nifi-registry > /dev/null 2>&1 && \
			echo "✅ Registry accessible" || echo "❌ Registry not responding"; \
	fi
	@echo ""

check-env:
	@echo "Environment: $(WORKSPACE)"
	@echo "   File: $(ENV_FILE)"
	@echo ""
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "❌ Environment file not found"; \
		exit 1; \
	fi
	@for var in NIFI_USERNAME NIFI_PASSWORD NIFI_SENSITIVE_PROPS_KEY; do \
		grep -q "^$$var=" $(ENV_FILE) && echo "✅ $$var" || echo "❌ $$var missing"; \
	done
	@echo ""

diagnose:
	@echo ""
	@echo "╔════════════════════════╗"
	@echo "║ Full Diagnostic Report ║"
	@echo "╚════════════════════════╝"
	@echo ""
	@echo "Delegating to Terraform Makefile..."
	@$(MAKE) -C azure-vm-terraform diagnose
	@echo ""