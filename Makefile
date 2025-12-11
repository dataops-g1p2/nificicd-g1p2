# ============================================================================
# ROOT MAKEFILE: NiFi CI/CD Infrastructure Manager
# ============================================================================
# Manages local Docker environment and delegates infrastructure operations
# Location: ./Makefile
# Version: 2.0.0

MAKEFLAGS += --no-print-directory

# ============================================================================
# CONFIGURATION
# ============================================================================

# Project settings
PROJECT_NAME := nifi-cicd
DOCKER := docker compose

# Environment configuration
ENV ?= local
ENV_MAP_local := local
ENV_MAP_dev := development
ENV_MAP_development := development
ENV_MAP_staging := staging
ENV_MAP_prod := production
ENV_MAP_production := production

WORKSPACE := $(or $(ENV_MAP_$(ENV)),$(ENV))
ENV_FILE := $(if $(filter local,$(WORKSPACE)),.env,.env.$(WORKSPACE))

# SSH Key Configuration
SSH_KEY_PATHS := $(HOME)/.ssh/nifi_vm_key \
                 $(HOME)/.ssh/nifi_deploy_key \
                 $(HOME)/.ssh/id_rsa \
                 $(HOME)/.ssh/id_ed25519

# ============================================================================
# COLORS & FORMATTING
# ============================================================================

BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
CYAN := \033[0;36m
MAGENTA := \033[0;35m
BOLD := \033[1m
NC := \033[0m

# Box drawing characters
BOX_H := ═
BOX_V := ║
BOX_TL := ╔
BOX_TR := ╗
BOX_BL := ╚
BOX_BR := ╝
BOX_VR := ╠
BOX_VL := ╣
BOX_HU := ╩
BOX_HD := ╦

# Symbols
CHECK := ✓
CROSS := ✗
ARROW := →
BULLET := •
WARNING := ⚠
INFO := ℹ
ROCKET := 🚀
WRENCH := 🔧
LOCK := 🔒
KEY := 🔑
PACKAGE := 📦
CHART := 📊
CLOUD := ☁
LAPTOP := 💻

# ============================================================================
# PHONY TARGETS
# ============================================================================

.PHONY: help \
        setup-password setup-passwords clean-generated-info clean-generated-info-all \
        echo-info-access echo-info-access-all validate-env \
        up down restart status logs logs-nifi logs-registry clean-volumes prune \
        setup-registry setup-registry-buckets setup-registry-default registry-info \
        import-flows-auto import-flow import-flows-pattern list-flows \
        export-flow-from-registry export-flows-from-registry export-flow-with-commit \
        export-flow-by-id list-registry-buckets list-registry-flows list-registry-versions \
        show-registry-ids \
        ssh-dev ssh-staging ssh-prod \
        health-check health-check-all \
        backup-flows restore-flows

.DEFAULT_GOAL := help

# ============================================================================
# HELP TARGET
# ============================================================================
help:
	@echo ""
	@echo "$(BOX_TL)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_TR)"
	@echo "$(BOX_V)    $(BOLD)NiFi CI/CD Infrastructure Manager$(NC)             $(BOX_V)"
	@echo "$(BOX_BL)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_H)$(BOX_BR)"
	@echo ""
	@echo "$(CYAN)$(BOLD)Usage:$(NC) make <target> [ENV=<environment>]"
	@echo ""
	@echo "$(YELLOW)$(BOLD)Environments:$(NC)"
	@echo "  $(LAPTOP) local           Local Docker environment (default)"
	@echo "  $(WRENCH) dev/development Azure development environment"
	@echo "  🎭 staging          Azure staging environment"
	@echo "  $(ROCKET) prod/production Azure production environment"
	@echo ""
	@$(call print_section,"SETUP & CONFIGURATION")
	@echo "  setup-password              Generate NiFi password and keys for ENV"
	@echo "  setup-passwords             Generate passwords for all environments"
	@echo "  validate-env                Validate environment configuration"
	@echo "  clean-generated-info        Clean generated info from env files"
	@echo "  clean-generated-info-all    Clean all environments"
	@echo "  echo-info-access            Show access info for environment"
	@echo "  echo-info-access-all        Show access info for all environments"
	@echo ""
	@$(call print_section,"LOCAL DOCKER ENVIRONMENT")
	@echo "  up                          Start local NiFi environment"
	@echo "  down                        Stop local NiFi environment"
	@echo "  restart                     Restart local NiFi environment"
	@echo "  status                      Show container status"
	@echo "  logs                        Tail all container logs"
	@echo "  logs-nifi                   Tail NiFi container logs"
	@echo "  logs-registry               Tail Registry container logs"
	@echo "  clean-volumes               Remove Docker volumes"
	@echo "  prune                       Deep clean Docker resources"
	@echo "  health-check                Check local environment health"
	@echo ""
	@$(call print_section,"NIFI REGISTRY SETUP")
	@echo "  setup-registry-buckets      Setup Registry with per-flow buckets"
	@echo "  setup-registry-default      Setup Registry with single bucket"
	@echo "  registry-info               Show registry information"
	@echo ""
	@$(call print_section,"FLOW MANAGEMENT - IMPORT (Local → Registry)")
	@echo "  import-flows-auto           Auto-import all flows to Registry"
	@echo "  import-flow FLOW=<name>     Import specific flow"
	@echo "  import-flows-pattern        Import flows matching PATTERN"
	@echo "  list-flows                  List available flows"
	@echo ""
	@$(call print_section,"FLOW MANAGEMENT - EXPORT (Registry → Local)")
	@echo "  export-flow-from-registry   Export single flow (interactive)"
	@echo "  export-flows-from-registry  Export all flows from Registry"
	@echo "  export-flow-with-commit     Export all flows and commit to Git"
	@echo "  export-flow-by-id           Export by BUCKET_ID and FLOW_ID"
	@echo ""
	@$(call print_section,"REGISTRY INSPECTION")
	@echo "  list-registry-buckets       List all Registry buckets"
	@echo "  list-registry-flows         List flows in bucket"
	@echo "  list-registry-versions      List all flow versions"
	@echo "  show-registry-ids           Show all bucket and flow IDs"
	@echo ""
	@$(call print_section,"SSH ACCESS TO VMs")
	@echo "  ssh-dev                     SSH to development VM"
	@echo "  ssh-staging                 SSH to staging VM"
	@echo "  ssh-prod                    SSH to production VM"
	@echo ""
	@$(call print_section,"BACKUP & RESTORE")
	@echo "  backup-flows                Backup flows directory"
	@echo "  restore-flows               Restore flows from backup"
	@echo ""
	@echo "$(CYAN)$(BOLD)Examples:$(NC)"
	@echo "  make up                                    # Start local environment"
	@echo "  make setup-registry-buckets                # Setup registry"
	@echo "  make import-flows-auto                     # Import all flows"
	@echo "  make import-flow FLOW=MyFlow               # Import specific flow"
	@echo "  make echo-info-access ENV=dev              # Show dev environment info"
	@echo "  make ssh-dev                               # SSH to dev VM"
	@echo ""

define print_section   # Helper function to print section headers
	@echo "$(GREEN)$(BOLD)────────────────────────────────────────────────────────$(NC)"
	@echo "$(GREEN)$(BOLD)  $(1)$(NC)"
	@echo "$(GREEN)$(BOLD)────────────────────────────────────────────────────────$(NC)"
endef
# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================
validate-env:
	@echo ""
	@echo "$(BLUE)$(INFO) Validating $(WORKSPACE) environment...$(NC)"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "$(RED)$(CROSS) $(ENV_FILE) not found$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Create from template:$(NC)"; \
		echo "  cp .env.template $(ENV_FILE)"; \
		exit 1; \
	fi
	@echo "$(GREEN)$(CHECK) Environment file exists: $(ENV_FILE)$(NC)"
	@if grep -q "^NIFI_PASSWORD=$$" "$(ENV_FILE)" 2>/dev/null; then \
		echo "$(YELLOW)$(WARNING) NIFI_PASSWORD not set$(NC)"; \
	else \
		echo "$(GREEN)$(CHECK) NIFI_PASSWORD configured$(NC)"; \
	fi
	@if grep -q "^NIFI_SENSITIVE_PROPS_KEY=$$" "$(ENV_FILE)" 2>/dev/null; then \
		echo "$(YELLOW)$(WARNING) NIFI_SENSITIVE_PROPS_KEY not set$(NC)"; \
	else \
		echo "$(GREEN)$(CHECK) NIFI_SENSITIVE_PROPS_KEY configured$(NC)"; \
	fi
	@echo ""

# ============================================================================
# SETUP & CONFIGURATION
# ============================================================================
setup-password: validate-env
	@echo ""
	@echo "$(BLUE)$(KEY) Generating credentials for $(WORKSPACE)...$(NC)"
	@echo ""
	@PASS=$$(openssl rand -base64 16 | tr -d '=+/' | cut -c1-20); \
	KEY=$$(openssl rand -hex 12); \
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$(ENV_FILE)"; \
		sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$(ENV_FILE)"; \
	else \
		sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$(ENV_FILE)"; \
		sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$(ENV_FILE)"; \
	fi; \
	echo "$(GREEN)$(CHECK) Password: $$PASS$(NC)"; \
	echo "$(GREEN)$(CHECK) Sensitive key: $$KEY$(NC)"
	@echo ""
	@echo "$(CYAN)$(INFO) Credentials saved to $(ENV_FILE)$(NC)"
	@echo ""

setup-passwords:
	@for env in local development staging production; do \
		$(MAKE) setup-password ENV=$$env; \
	done
	@echo "$(GREEN)$(BOLD)$(CHECK) All environments configured!$(NC)"
	@echo ""

clean-generated-info:
	@echo ""
	@echo "$(BLUE)🧹 Cleaning generated info for $(WORKSPACE)...$(NC)"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "$(YELLOW)$(WARNING) $(ENV_FILE) not found$(NC)"; \
		exit 1; \
	fi
	@if [ "$$(uname)" = "Darwin" ]; then \
		sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$(ENV_FILE)"; \
		sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$(ENV_FILE)"; \
		if [ "$(WORKSPACE)" != "local" ]; then \
			sed -i "" "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$(ENV_FILE)"; \
			sed -i "" "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$(ENV_FILE)"; \
			sed -i "" "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$(ENV_FILE)"; \
		fi; \
	else \
		sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$(ENV_FILE)"; \
		sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$(ENV_FILE)"; \
		if [ "$(WORKSPACE)" != "local" ]; then \
			sed -i "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$(ENV_FILE)"; \
			sed -i "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$(ENV_FILE)"; \
			sed -i "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$(ENV_FILE)"; \
		fi; \
	fi
	@echo "   $(GREEN)$(CHECK) Credentials cleared$(NC)"
	@if [ "$(WORKSPACE)" != "local" ]; then \
		echo "   $(GREEN)$(CHECK) IP addresses cleared$(NC)"; \
	fi
	@echo ""
	@echo "$(GREEN)$(CHECK) $(WORKSPACE) environment cleaned!$(NC)"
	@echo ""
	@echo "$(CYAN)💡 To regenerate:$(NC)"
	@echo "   make setup-password ENV=$(ENV)"
	@echo ""

clean-generated-info-all:
	@for env in local development staging production; do \
		$(MAKE) clean-generated-info ENV=$$env; \
	done

echo-info-access:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════╗"
	@echo "║       NiFi CI/CD Environment Access Information           ║"
	@echo "╚═══════════════════════════════════════════════════════════╝"
	@echo ""
	@if [ "$(WORKSPACE)" = "local" ]; then \
		echo "┌──────────────────────┐"; \
		echo "│ 🏠 LOCAL ENVIRONMENT │"; \
		echo "└──────────────────────┘"; \
		if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then \
			NIFI_CONTAINER=$$(docker ps --filter "name=nifi" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -v registry | head -n1); \
			REGISTRY_CONTAINER=$$(docker ps --filter "name=registry" --filter "status=running" --format "{{.Names}}" 2>/dev/null | head -n1); \
			if [ -n "$$NIFI_CONTAINER" ]; then \
				NIFI_USER=$$(docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_USERNAME=" | cut -d'=' -f2); \
				NIFI_PASS=$$(docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_PASSWORD=" | cut -d'=' -f2); \
				ENV_PASS=$$(grep "^NIFI_PASSWORD=" .env 2>/dev/null | cut -d'=' -f2); \
				echo "  $(BLUE)👤 Username:        $(CYAN)$$NIFI_USER$(NC)"; \
				echo "  $(BLUE)🔑 Password:        $(CYAN)$$NIFI_PASS$(NC)"; \
				echo "  $(BLUE)📊 NiFi UI:         $(GREEN)https://localhost:8443/nifi$(NC)"; \
				echo "  $(BLUE)📦 NiFi Registry:   $(GREEN)http://localhost:18080/nifi-registry$(NC)"; \
				if [ -n "$$ENV_PASS" ] && [ "$$NIFI_PASS" != "$$ENV_PASS" ]; then \
					echo ""; \
					echo "  $(YELLOW)⚠️  WARNING: .env password differs from running container$(NC)"; \
					echo "  $(CYAN)💡 Run 'make restart' to apply new password$(NC)"; \
				fi; \
			else \
				echo "  $(YELLOW)⚠️ No running containers found$(NC)"; \
				echo ""; \
				echo "  Run: make up"; \
			fi; \
		else \
			echo "  $(YELLOW)⚠️ Docker not running$(NC)"; \
			echo ""; \
			echo "  Run: make up"; \
		fi; \
	else \
		if [ "$(WORKSPACE)" = "development" ]; then \
			echo "┌─────────────────────────────┐"; \
			echo "│ 🔧 DEVELOPMENT ENVIRONMENT  │"; \
			echo "└─────────────────────────────┘"; \
		elif [ "$(WORKSPACE)" = "staging" ]; then \
			echo "┌────────────────────────┐"; \
			echo "│ 🎭 STAGING ENVIRONMENT │"; \
			echo "└────────────────────────┘"; \
		elif [ "$(WORKSPACE)" = "production" ]; then \
			echo "┌───────────────────────────┐"; \
			echo "│ 🚀 PRODUCTION ENVIRONMENT │"; \
			echo "└───────────────────────────┘"; \
		fi; \
		\
		if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
			echo "  $(BLUE)🔍 Extracting info from running containers...$(NC)"; \
			echo ""; \
			NIFI_CONTAINER=$$(sudo docker ps --filter "name=nifi" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -v registry | head -n1); \
			REGISTRY_CONTAINER=$$(sudo docker ps --filter "name=registry" --filter "status=running" --format "{{.Names}}" 2>/dev/null | head -n1); \
			if [ -n "$$NIFI_CONTAINER" ]; then \
				VM_IP=$$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $$1}'); \
				NIFI_USER=$$(sudo docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_USERNAME=" | cut -d'=' -f2); \
				NIFI_PASS=$$(sudo docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_PASSWORD=" | cut -d'=' -f2); \
				echo "  $(BLUE)📊 NiFi UI:         $(GREEN)https://$$VM_IP:8443/nifi$(NC)"; \
				if [ -n "$$REGISTRY_CONTAINER" ]; then \
					echo "  $(BLUE)📦 NiFi Registry:   $(GREEN)http://$$VM_IP:18080/nifi-registry$(NC)"; \
				fi; \
				echo "  $(BLUE)👤 NiFi Username:   $(CYAN)$$NIFI_USER$(NC)"; \
				echo "  $(BLUE)🔑 NiFi Password:   $(CYAN)$$NIFI_PASS$(NC)"; \
				echo "  $(BLUE)🌐 VM IP:           $(CYAN)$$VM_IP$(NC)"; \
				echo ""; \
				echo "  $(CYAN)💡 Container: $$NIFI_CONTAINER$(NC)"; \
			else \
				echo "  $(RED)❌ No running NiFi containers found$(NC)"; \
				echo ""; \
				echo "  $(CYAN)Check deployment status:$(NC)"; \
				echo "    sudo docker ps -a"; \
				echo "    sudo docker logs <container-name>"; \
			fi; \
		elif command -v gh >/dev/null 2>&1; then \
			echo "  $(BLUE)🔍 Fetching info from GitHub Actions...$(NC)"; \
			echo ""; \
			REPO=$$(git config --get remote.origin.url | sed 's/.*github.com[:/]\(.*\)\.git/\1/' 2>/dev/null); \
			if [ -z "$$REPO" ]; then \
				echo "  $(RED)❌ Cannot determine GitHub repository$(NC)"; \
			else \
				WORKFLOW_RUN=$$(gh run list --workflow=deploy-$(WORKSPACE).yml --limit 1 --json conclusion,databaseId,status,displayTitle 2>/dev/null | jq -r '.[0] // empty'); \
				if [ -n "$$WORKFLOW_RUN" ]; then \
					RUN_ID=$$(echo "$$WORKFLOW_RUN" | jq -r '.databaseId'); \
					STATUS=$$(echo "$$WORKFLOW_RUN" | jq -r '.status'); \
					CONCLUSION=$$(echo "$$WORKFLOW_RUN" | jq -r '.conclusion // "in_progress"'); \
					if [ "$$CONCLUSION" = "success" ]; then \
						echo "  $(GREEN)✅ Last deployment: successful$(NC)"; \
						echo ""; \
						LOGS=$$(gh run view $$RUN_ID --log 2>/dev/null | grep -A 5 "DEPLOYMENT SUCCESSFUL" | tail -5); \
						if [ -n "$$LOGS" ]; then \
							VM_IP=$$(echo "$$LOGS" | grep "NiFi UI:" | sed 's/.*https:\/\/\([^:]*\):.*/\1/' | head -n1); \
							if [ -n "$$VM_IP" ]; then \
								echo "  $(BLUE)📊 NiFi UI:         $(GREEN)https://$$VM_IP:8443/nifi$(NC)"; \
								echo "  $(BLUE)📦 NiFi Registry:   $(GREEN)http://$$VM_IP:18080/nifi-registry$(NC)"; \
								echo "  $(BLUE)🌐 VM IP:           $(CYAN)$$VM_IP$(NC)"; \
								echo ""; \
								echo "  $(YELLOW)⚠️  Credentials are stored in GitHub Secrets$(NC)"; \
								echo "  $(CYAN)💡 View deployment logs: gh run view $$RUN_ID$(NC)"; \
							else \
								echo "  $(YELLOW)⚠️  Could not extract VM IP from logs$(NC)"; \
								echo "  $(CYAN)💡 View full logs: gh run view $$RUN_ID$(NC)"; \
							fi; \
						else \
							echo "  $(YELLOW)⚠️  Could not fetch deployment logs$(NC)"; \
							echo "  $(CYAN)💡 View logs: gh run view $$RUN_ID$(NC)"; \
						fi; \
					else \
						echo "  $(YELLOW)⚠️  Last deployment status: $$CONCLUSION$(NC)"; \
						echo "  $(CYAN)💡 View logs: gh run view $$RUN_ID$(NC)"; \
					fi; \
				else \
					echo "  $(YELLOW)⚠️  No deployment runs found for $(WORKSPACE)$(NC)"; \
					echo ""; \
					echo "  $(CYAN)Deploy with: git push origin develop$(NC)"; \
				fi; \
			fi; \
		else \
			echo "  $(RED)❌ Cannot retrieve information$(NC)"; \
			echo ""; \
			echo "  $(CYAN)Install GitHub CLI to view deployment info:$(NC)"; \
			echo "    brew install gh  # macOS"; \
			echo "    sudo apt install gh  # Ubuntu/Debian"; \
			echo ""; \
			echo "  $(CYAN)Or SSH to VM and run:$(NC)"; \
			echo "    make echo-info-access ENV=$(ENV)"; \
		fi; \
	fi
	@echo ""

echo-info-access-all:
	@$(MAKE) echo-info-access WORKSPACE=development ENV=development
	@$(MAKE) echo-info-access WORKSPACE=staging ENV=staging
	@$(MAKE) echo-info-access WORKSPACE=production ENV=production

# ============================================================================
# LOCAL DOCKER ENVIRONMENT
# ============================================================================
up:
	@echo "$(BLUE)$(ROCKET) Starting local NiFi environment...$(NC)"
	@$(DOCKER) -f compose.local.yml up -d
	@echo "$(GREEN)$(CHECK) Containers started$(NC)"
	@echo ""
	@echo "$(CYAN)Waiting for services to be ready...$(NC)"
	@sleep 30
	@$(MAKE) health-check

down:
	@echo "$(BLUE)🛑 Stopping local NiFi environment...$(NC)"
	@$(DOCKER) -f compose.local.yml down
	@echo "$(GREEN)$(CHECK) Containers stopped$(NC)"

restart: down
	@sleep 2
	@$(MAKE) up

status:
	@echo ""
	@echo "$(BLUE)$(CHART) Container Status:$(NC)"
	@echo ""
	@$(DOCKER) -f compose.local.yml ps
	@echo ""

logs:
	@echo "$(CYAN)$(INFO) Tailing all container logs (Ctrl+C to exit)...$(NC)"
	@$(DOCKER) -f compose.local.yml logs -f --tail=100

logs-nifi:
	@echo "$(CYAN)$(INFO) Tailing NiFi logs (Ctrl+C to exit)...$(NC)"
	@$(DOCKER) -f compose.local.yml logs -f --tail=100 nifi

logs-registry:
	@echo "$(CYAN)$(INFO) Tailing Registry logs (Ctrl+C to exit)...$(NC)"
	@$(DOCKER) -f compose.local.yml logs -f --tail=100 nifi-registry

clean-volumes:
	@echo "$(YELLOW)🧹 Cleaning Docker volumes...$(NC)"
	@docker volume rm $(PROJECT_NAME)_nifi_conf 2>/dev/null || true
	@docker volume rm $(PROJECT_NAME)_nifi_registry_git 2>/dev/null || true
	@echo "$(GREEN)$(CHECK) Volumes removed$(NC)"

prune:
	@echo "$(YELLOW)$(WARNING) This will remove all stopped containers, unused networks, and dangling images$(NC)"
	@echo -n "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@docker system prune -f
	@echo "$(GREEN)$(CHECK) Docker system pruned$(NC)"

health-check:
	@echo ""
	@echo "$(BLUE)🏥 Health Check - Local Environment$(NC)"
	@echo ""
	@NIFI_RUNNING=$$(docker ps --filter "name=nifi" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -v registry | head -n1); \
	REGISTRY_RUNNING=$$(docker ps --filter "name=registry" --filter "status=running" --format "{{.Names}}" 2>/dev/null | head -n1); \
	if [ -n "$$NIFI_RUNNING" ]; then \
		echo "$(GREEN)$(CHECK) NiFi container running: $$NIFI_RUNNING$(NC)"; \
		if curl -sf -k https://localhost:8443/nifi > /dev/null 2>&1; then \
			echo "$(GREEN)$(CHECK) NiFi web UI responding$(NC)"; \
		else \
			echo "$(YELLOW)$(WARNING) NiFi web UI not responding yet$(NC)"; \
		fi; \
	else \
		echo "$(RED)$(CROSS) NiFi container not running$(NC)"; \
	fi; \
	if [ -n "$$REGISTRY_RUNNING" ]; then \
		echo "$(GREEN)$(CHECK) Registry container running: $$REGISTRY_RUNNING$(NC)"; \
		if curl -sf http://localhost:18080/nifi-registry > /dev/null 2>&1; then \
			echo "$(GREEN)$(CHECK) Registry API responding$(NC)"; \
		else \
			echo "$(YELLOW)$(WARNING) Registry API not responding yet$(NC)"; \
		fi; \
	else \
		echo "$(RED)$(CROSS) Registry container not running$(NC)"; \
	fi
	@echo ""

# ============================================================================
# REGISTRY SETUP
# ============================================================================
setup-registry-default:
	@echo "$(BLUE)$(PACKAGE) Setting up NiFi Registry (default)...$(NC)"
	@bash scripts/setup_nifi_registry.sh

setup-registry-buckets:
	@echo ""
	@$(call print_section,"Creating Flow-Specific Buckets")
	@echo ""
	@if [ ! -f scripts/setup_nifi_registry.sh ]; then \
		echo "$(RED)$(CROSS) scripts/setup_nifi_registry.sh not found$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)$(INFO) Configuration:$(NC)"
	@echo "  $(BULLET) Registry URL: http://localhost:18080"
	@echo "  $(BULLET) Flows Directory: ./flows"
	@if [ -n "$(FLOW)" ]; then \
		echo "  $(BULLET) Creating bucket for flow: $(FLOW)"; \
		if [ ! -f "./flows/$(FLOW).json" ]; then \
			echo "$(RED)$(CROSS) Flow file not found: ./flows/$(FLOW).json$(NC)"; \
			exit 1; \
		fi; \
		bucket_name=$$(echo "$(FLOW)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$$//'); \
		echo "  $(BULLET) Bucket name: $$bucket_name"; \
		echo ""; \
		SKIP_DEFAULT_BUCKET=true SPECIFIC_FLOW="$(FLOW)" CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	elif [ -n "$(FLOWS)" ]; then \
		echo "  $(BULLET) Creating buckets for flows: $(FLOWS)"; \
		for flow in $$(echo "$(FLOWS)" | tr ',' ' '); do \
			if [ ! -f "./flows/$$flow.json" ]; then \
				echo "$(YELLOW)$(WARN) Flow file not found: ./flows/$$flow.json (will skip)$(NC)"; \
			fi; \
		done; \
		echo ""; \
		SKIP_DEFAULT_BUCKET=true SPECIFIC_FLOWS="$(FLOWS)" CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	else \
		echo "  $(BULLET) Creating buckets for all flows"; \
		echo ""; \
		SKIP_DEFAULT_BUCKET=true CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	fi
	@echo ""
	@echo "$(GREEN)$(CHECK) Flow buckets setup complete!$(NC)"
	@echo ""

setup-registry-buckets-help:
	@echo ""
	@echo "$(CYAN)NiFi Registry Bucket Setup - Usage$(NC)"
	@echo ""
	@echo "$(YELLOW)Note: Run 'make setup-registry-default' first to create the default bucket$(NC)"
	@echo ""
	@echo "Create buckets for all flows:"
	@echo "  $(GREEN)make setup-registry-buckets$(NC)"
	@echo ""
	@echo "Create bucket for a specific flow:"
	@echo "  $(GREEN)make setup-registry-buckets FLOW=MyFlow$(NC)"
	@echo ""
	@echo "Create buckets for multiple flows (comma-separated):"
	@echo "  $(GREEN)make setup-registry-buckets FLOWS=Flow1,Flow2,Flow3$(NC)"
	@echo ""
	@echo "Complete setup workflow:"
	@echo "  $(GREEN)make setup-registry-default$(NC)         # Create default bucket"
	@echo "  $(GREEN)make setup-registry-buckets$(NC)         # Create flow-specific buckets"
	@echo ""

registry-info:
	@echo ""
	@$(call print_section,"NiFi Registry Information")
	@echo ""
	@echo "$(CYAN)$(CHART) Registry Status:$(NC)"
	@if curl -sf "http://localhost:18080/nifi-registry" > /dev/null 2>&1; then \
		echo "  $(GREEN)$(CHECK) Registry is running$(NC)"; \
		echo "  $(BLUE)🔗 URL: http://localhost:18080/nifi-registry$(NC)"; \
	else \
		echo "  $(RED)$(CROSS) Registry is not running$(NC)"; \
		echo "  $(YELLOW)💡 Start with: make up$(NC)"; \
	fi
	@echo ""
	@echo "$(CYAN)$(PACKAGE) Registry Buckets:$(NC)"
	@curl -s "http://localhost:18080/nifi-registry-api/buckets" 2>/dev/null | \
		jq -r '.[] | "  $(BULLET) \(.name) (ID: \(.identifier))"' 2>/dev/null || \
		echo "  $(YELLOW)$(WARNING) Could not fetch buckets$(NC)"
	@echo ""
	@echo "$(CYAN)📂 Available Flows:$(NC)"
	@if [ -d "flows" ] && [ -n "$$(ls -A flows/*.json 2>/dev/null)" ]; then \
		ls -1 flows/*.json 2>/dev/null | while read file; do \
			name=$$(basename "$$file" .json); \
			echo "  $(GREEN)$(BULLET)$(NC) $$name"; \
		done; \
		total=$$(ls -1 flows/*.json 2>/dev/null | wc -l | tr -d ' '); \
		echo ""; \
		echo "  $(BLUE)Total: $$total flow(s)$(NC)"; \
	else \
		echo "  $(YELLOW)$(WARNING) No flows found in flows/ directory$(NC)"; \
	fi
	@echo ""

# ============================================================================
# FLOW IMPORT
# ============================================================================
import-flows-auto:
	@echo "$(BLUE)$(PACKAGE) Auto-importing flows...$(NC)"
	@export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/auto_import_flows.sh

import-flow:
	@if [ -z "$(FLOW)" ]; then \
		echo "$(RED)$(CROSS) FLOW parameter required$(NC)"; \
		echo ""; \
		echo "Usage: make import-flow FLOW=<flow-name>"; \
		echo ""; \
		echo "Available flows:"; \
		ls -1 flows/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$$//' | sed 's/^/  $(BULLET) /' || echo "  (none)"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(BLUE)$(PACKAGE) Importing flow: $(FLOW)$(NC)"
	@export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
	export FLOW_NAME="$(FLOW)" && \
	bash scripts/auto_import_flows.sh

import-flows-pattern:
	@if [ -z "$(PATTERN)" ]; then \
		echo "$(RED)$(CROSS) PATTERN parameter required$(NC)"; \
		echo ""; \
		echo "Usage: make import-flows-pattern PATTERN=<pattern>"; \
		exit 1; \
	fi
	@echo "$(BLUE)$(PACKAGE) Importing flows matching: $(PATTERN)$(NC)"
	@export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
	export FLOW_PATTERN="$(PATTERN)" && \
	bash scripts/auto_import_flows.sh

list-flows:
	@echo ""
	@$(call print_section,"Available NiFi Flows")
	@echo ""
	@if [ -d "flows" ] && [ -n "$$(ls -A flows/*.json 2>/dev/null)" ]; then \
		echo "$(CYAN)📂 Flows directory:$(NC)"; \
		ls -1 flows/*.json 2>/dev/null | while read file; do \
			name=$$(basename "$$file" .json); \
			size=$$(du -h "$$file" | cut -f1); \
			echo "  $(GREEN)$(BULLET)$(NC) $$name $(YELLOW)($$size)$(NC)"; \
		done; \
		echo ""; \
		total=$$(ls -1 flows/*.json 2>/dev/null | wc -l | tr -d ' '); \
		echo "$(BLUE)Total: $$total flow(s)$(NC)"; \
	else \
		echo "$(YELLOW)$(WARNING) No flows found in flows/ directory$(NC)"; \
	fi
	@echo ""

# ============================================================================
# FLOW EXPORT
# ============================================================================
export-flow-from-registry:
	@bash scripts/export-flow.sh

export-flows-from-registry:
	@bash scripts/export-all-flows-from-registry.sh

export-flow-with-commit: export-flows-from-registry
	@echo "$(BLUE)📝 Checking for changes...$(NC)"
	@git add flows/
	@if ! git diff --cached --quiet; then \
		git commit -m "chore: update flow definitions from registry"; \
		echo "$(GREEN)$(CHECK) Changes committed$(NC)"; \
	else \
		echo "$(CYAN)$(INFO) No changes detected$(NC)"; \
	fi

export-flow-by-id:
	@if [ -z "$(BUCKET_ID)" ] || [ -z "$(FLOW_ID)" ]; then \
		echo "$(RED)$(CROSS) BUCKET_ID and FLOW_ID required$(NC)"; \
		echo "Usage: make export-flow-by-id BUCKET_ID=<id> FLOW_ID=<id>"; \
		exit 1; \
	fi
	@bash scripts/export-flow.sh --bucket-id $(BUCKET_ID) --flow-id $(FLOW_ID)

list-registry-buckets:
	@bash scripts/export-flow.sh --list-buckets

list-registry-flows:
	@if [ -z "$(BUCKET_ID)" ]; then \
		bash scripts/export-flow.sh --list-flows; \
	else \
		bash scripts/export-flow.sh --list-flows --bucket-id $(BUCKET_ID); \
	fi

list-registry-versions:
	@bash scripts/export-flow.sh --list-versions

show-registry-ids:
	@bash scripts/export-flow.sh --list-versions

# ============================================================================
# SSH ACCESS
# ============================================================================
ssh-dev:
	@echo "$(BLUE)🔌 Connecting to Development VM...$(NC)"
	@bash scripts/access-vm.sh development

ssh-staging:
	@echo "$(BLUE)🔌 Connecting to Staging VM...$(NC)"
	@bash scripts/access-vm.sh staging

ssh-prod:
	@echo "$(BLUE)🔌 Connecting to Production VM...$(NC)"
	@bash scripts/access-vm.sh production

# ============================================================================
# BACKUP & RESTORE
# ============================================================================
backup-flows:
	@echo "$(BLUE)💾 Creating flows backup...$(NC)"
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	BACKUP_DIR="flows/backups/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	cp flows/*.json "$$BACKUP_DIR/" 2>/dev/null || true; \
	echo "$(GREEN)$(CHECK) Backup created: $$BACKUP_DIR$(NC)"

restore-flows:
	@echo ""
	@echo "$(BLUE)📥 Restoring ALL flows from ALL backups...$(NC)"
	@echo ""
	@if [ ! -d "flows/backups" ]; then \
		echo "$(RED)$(CROSS) No backups directory found$(NC)"; \
		echo ""; \
		exit 1; \
	fi; \
	TOTAL_BACKUPS=$$(find flows/backups -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$TOTAL_BACKUPS" -eq 0 ]; then \
		echo "$(YELLOW)$(WARNING) No backup JSON files found$(NC)"; \
		echo ""; \
		exit 1; \
	fi; \
	echo "$(CYAN)📊 Backup Statistics:$(NC)"; \
	BACKUP_DIRS=$$(find flows/backups -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '); \
	echo "  $(BULLET) Total backup directories: $$BACKUP_DIRS"; \
	echo "  $(BULLET) Total flow files: $$TOTAL_BACKUPS"; \
	echo ""; \
	echo "$(CYAN)📂 Backup directories:$(NC)"; \
	find flows/backups -mindepth 1 -maxdepth 1 -type d | sort -r | while read backup_dir; do \
		backup_name=$$(basename "$$backup_dir"); \
		flow_count=$$(find "$$backup_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
		backup_date=$$(echo "$$backup_name" | sed 's/_/ /'); \
		echo "  $(GREEN)$(BULLET)$(NC) $$backup_date $(YELLOW)($$flow_count flows)$(NC)"; \
	done; \
	echo ""; \
	echo "$(YELLOW)$(WARNING) This will:$(NC)"; \
	echo "  1. Clear all existing flows in flows/"; \
	echo "  2. Copy ALL JSON files from ALL backup directories to flows/"; \
	echo "  3. Files with duplicate names will be overwritten by newer versions"; \
	echo ""; \
	printf "$(CYAN)Continue with restoring ALL backups? [y/N]: $(NC)"; \
	read confirm; \
	if [ "$${confirm}" != "y" ] && [ "$${confirm}" != "Y" ]; then \
		echo ""; \
		echo "$(CYAN)$(INFO) Restore cancelled$(NC)"; \
		echo ""; \
		exit 0; \
	fi; \
	echo ""; \
	echo "$(BLUE)📦 Step 1/2: Clearing current flows directory...$(NC)"; \
	CURRENT_COUNT=$$(find flows -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$CURRENT_COUNT" -gt 0 ]; then \
		rm -f flows/*.json 2>/dev/null || true; \
		echo "  $(GREEN)$(CHECK) Removed $$CURRENT_COUNT existing flows$(NC)"; \
	else \
		echo "  $(CYAN)$(INFO) No existing flows to remove$(NC)"; \
	fi; \
	echo ""; \
	echo "$(BLUE)📦 Step 2/2: Restoring all flows from backups...$(NC)"; \
	find flows/backups -mindepth 1 -maxdepth 1 -type d | sort | while read backup_dir; do \
		backup_name=$$(basename "$$backup_dir"); \
		dir_flow_count=$$(find "$$backup_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$$dir_flow_count" -gt 0 ]; then \
			cp "$$backup_dir"/*.json flows/ 2>/dev/null || true; \
			echo "  $(GREEN)$(BULLET)$(NC) Copied $$dir_flow_count flows from $$backup_name"; \
		fi; \
	done; \
	FINAL_COUNT=$$(find flows -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	echo ""; \
	echo "$(GREEN)$(CHECK) Restore complete!$(NC)"; \
	echo ""; \
	echo "$(CYAN)📊 Summary:$(NC)"; \
	echo "  $(BULLET) Total backup files available: $$TOTAL_BACKUPS"; \
	echo "  $(BULLET) Unique flows restored: $$FINAL_COUNT"; \
	echo ""; \
	if [ "$$FINAL_COUNT" -lt "$$TOTAL_BACKUPS" ]; then \
		echo "$(CYAN)$(INFO) Note: Duplicate filenames were merged (latest version kept)$(NC)"; \
		echo ""; \
	fi