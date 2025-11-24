# Makefile for NiFi CI/CD Infrastructure Management
MAKEFLAGS += --no-print-directory

# Environment configuration
ENV ?= local
PROJECT_NAME := nifi_cicd_projet     # Change this to your desired project name
DOCKER := docker compose
TF_MAKEFILE := azure-vm-terraform/Makefile

# Environment mapping
ENV_MAP_local := local
ENV_MAP_dev := development
ENV_MAP_development := development
ENV_MAP_staging := staging
ENV_MAP_prod := production
ENV_MAP_production := production

WORKSPACE := $(or $(ENV_MAP_$(ENV)),$(ENV))
ENV_FILE := $(if $(filter local,$(WORKSPACE)),.env,.env.$(WORKSPACE))

ALL_ENVS := local development staging production
REMOTE_ENVS := development staging production

.PHONY: help setup-password setup-passwords clean-generated-info clean-generated-info-all echo up down restart status logs logs-nifi logs-registry clean-volumes

help:
	@echo ""
	@echo "┌────────────────────────────────────────────────────────┐"
	@echo "|           NiFi CI/CD Infrastructure Management         |"
	@echo "└────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "Usage: make [target] [ENV=environment]"
	@echo ""
	@echo "🔐 PASSWORD & CONFIG MANAGEMENT"
	@echo "  setup-password             Generate password for specified env"
	@echo "  setup-passwords            Generate passwords for all envs"
	@echo "  clean-generated-info       Clean generated info for specified env"
	@echo "  clean-generated-info-all   Clean generated info for all envs"
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


setup-passwords:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║          Generating Passwords for All Environments            ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@$(MAKE) setup-password ENV=local
	@$(MAKE) setup-password ENV=development
	@$(MAKE) setup-password ENV=staging
	@$(MAKE) setup-password ENV=production
	@echo "✅ All environment passwords generated!"
	@echo ""
	@echo "💡 Don't forget to:"
	@echo "   1. Update GitHub secrets: make update-secrets-all"
	@echo "   2. Restart NiFi containers if running"
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

clean-generated-info-all:
	@echo ""
	@echo "╔═════════════════════════════════════════════════════════╗"
	@echo "║      Removing Generated Info from All Environments      ║"
	@echo "╚═════════════════════════════════════════════════════════╝"
	@echo ""
	@read -p "⚠️  This will clear passwords and Terraform-generated IPs. Continue? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "❌ Cancelled"; \
		exit 0; \
	fi
	@echo ""
	@$(MAKE) clean-generated-info ENV=local
	@$(MAKE) clean-generated-info ENV=development
	@$(MAKE) clean-generated-info ENV=staging
	@$(MAKE) clean-generated-info ENV=production
	@echo ""
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║      ✅ All Environments Cleaned Successfully!       ║"
	@echo "╚══════════════════════════════════════════════════════╝"
	@echo ""
	@echo "💡 To regenerate:"
	@echo "   Passwords: make setup-passwords"
	@echo "   IPs:       make tf-output-all"
	@echo ""

echo:
	@echo ""
	@echo "╔═════════════════════════════════════════════════════════════╗"
	@echo "║          NiFi CI/CD Environment Access Information          ║"
	@echo "╚═════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "┌───────────────────────┐"
	@echo "│ 🏠 LOCAL ENVIRONMENT  │"
	@echo "└───────────────────────┘"
	@if [ -f .env ]; then \
		ENV_FILE='.env'; \
		USER=$$(grep "^NIFI_USERNAME=" $$ENV_FILE | cut -d'=' -f2-); \
		PASS=$$(grep "^NIFI_PASSWORD=" $$ENV_FILE | cut -d'=' -f2-); \
		echo "  📊 NiFi UI:         https://localhost:8443/nifi"; \
		echo "  📦 NiFi Registry:   http://localhost:18080/nifi-registry"; \
		echo "  👤 Username:        $$USER"; \
		echo "  🔑 Password:        $$PASS"; \
	else \
		echo "  ⚠️  .env file not found - run 'make setup-passwords'"; \
	fi
	@echo ""

	
up:
	@$(DOCKER) -f compose.local.yml up -d
down:
	@$(DOCKER) -f compose.local.yml down
restart:
	@$(DOCKER) -f compose.local.yml restart
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

