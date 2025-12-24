# ==================================================
#  ROOT MAKEFILE: NiFi CI/CD Infrastructure Manager
# ==================================================

MAKEFLAGS += --no-print-directory

# Project settings
PROJECT_NAME := nificicd-g1p2

# Environment configuration
ENV ?= development

# Map environment aliases to actual workspace names
ifeq ($(ENV),dev)
WORKSPACE := development
else ifeq ($(ENV),stg)
WORKSPACE := staging
else ifeq ($(ENV),staging)
WORKSPACE := staging
else ifeq ($(ENV),prod)
WORKSPACE := production
else ifeq ($(ENV),production)
WORKSPACE := production
else ifeq ($(ENV),development)
WORKSPACE := development
else
WORKSPACE := $(ENV)
endif

ENV_FILE := .env.$(WORKSPACE)

# SSH Key Configuration
SSH_KEY_PATHS := $(HOME)/.ssh/deploy_key

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

help:
	@echo ""
	@echo "NiFi CI/CD Infrastructure Manager"
	@echo "=================================="
	@echo ""
	@echo "Usage: make <target> [ENV=<environment>]"
	@echo ""
	@echo "Environments:"
	@echo "  dev/development Azure development environment (default)"
	@echo "  staging         Azure staging environment"
	@echo "  prod/production Azure production environment"
	@echo ""
	@$(call print_section,"SETUP & CONFIGURATION")
	@echo "  setup-password              Generate NiFi password and keys for ENV"
	@echo "  validate-env                Validate environment configuration"
	@echo "  clean-generated-info        Clean generated info from env files"
	@echo "  echo-info-access            Show access info for environment"
	@echo "  health-check                Check environment health"
	@echo ""
	@$(call print_section,"VM DOCKER MANAGEMENT")
	@echo "  up                          Start NiFi services on VM"
	@echo "  down                        Stop NiFi services on VM"
	@echo "  restart                     Restart NiFi services on VM"
	@echo "  status                      Show container status on VM"
	@echo "  logs                        Tail all container logs"
	@echo "  logs-nifi                   Tail NiFi container logs"
	@echo "  logs-registry               Tail Registry container logs"
	@echo "  clean-volumes               Remove Docker volumes on VM"
	@echo "  prune                       Deep clean Docker resources on VM"
	@echo ""
	@$(call print_section,"NIFI REGISTRY SETUP")
	@echo "  setup-registry-buckets FLOW=<name>       Setup Registry with per-flow buckets"
	@echo "  setup-registry-default                   Setup Registry with single bucket"
	@echo "  registry-info                            Show registry information"
	@echo ""
	@$(call print_section,"FLOW MANAGEMENT - IMPORT (Local -> Registry)")
	@echo "  import-flows-auto                             Auto-import all flows to Registry"
	@echo "  import-flow FLOW=<name>                       Import specific flow"
	@echo "  import-flows-pattern PATTERN=<pattern>        Import flows matching PATTERN"
	@echo "  list-flows                                    List available flows"
	@echo ""
	@$(call print_section,"FLOW MANAGEMENT - EXPORT (Registry -> Local)")
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
	@echo "Examples:"
	@echo "  make setup-password ENV=dev                # Setup dev credentials"
	@echo "  make up ENV=staging                        # Start staging services"
	@echo "  make status ENV=prod                       # Check production status"
	@echo "  make setup-registry-buckets ENV=staging    # Setup staging registry"
	@echo "  make import-flows-auto ENV=prod            # Import flows to prod"
	@echo "  make import-flow FLOW=MyFlow ENV=dev       # Import specific flow"
	@echo "  make logs-nifi ENV=dev                     # View dev NiFi logs"
	@echo "  make echo-info-access ENV=dev              # Show dev environment info"
	@echo "  make ssh-dev                               # SSH to dev VM"
	@echo ""

define print_section
	@echo "------------------------------------------------------------"
	@echo "  $(1)"
	@echo "------------------------------------------------------------"
endef

# ==================================================
# ENVIRONMENT VALIDATION
# ==================================================
validate-env:
	@echo ""
	@echo "Validating $(WORKSPACE) environment..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[ERROR] $(ENV_FILE) not found"; \
		echo ""; \
		echo "Available environment files:"; \
		ls -1 .env.* 2>/dev/null | sed 's/^/  - /' || echo "  (none found)"; \
		echo ""; \
		echo "Create from template:"; \
		echo "  cp .env.template $(ENV_FILE)"; \
		echo ""; \
		echo "Or generate credentials:"; \
		echo "  make setup-password ENV=$(ENV)"; \
		exit 1; \
	fi
	@echo "[OK] Environment file exists: $(ENV_FILE)"
	@if grep -q "^NIFI_PASSWORD=$$" "$(ENV_FILE)" 2>/dev/null || ! grep -q "^NIFI_PASSWORD=" "$(ENV_FILE)" 2>/dev/null; then \
		echo "[WARNING] NIFI_PASSWORD not set"; \
		echo "  Run: make setup-password ENV=$(ENV)"; \
	else \
		echo "[OK] NIFI_PASSWORD configured"; \
	fi
	@if grep -q "^NIFI_SENSITIVE_PROPS_KEY=$$" "$(ENV_FILE)" 2>/dev/null || ! grep -q "^NIFI_SENSITIVE_PROPS_KEY=" "$(ENV_FILE)" 2>/dev/null; then \
		echo "[WARNING] NIFI_SENSITIVE_PROPS_KEY not set"; \
		echo "  Run: make setup-password ENV=$(ENV)"; \
	else \
		echo "[OK] NIFI_SENSITIVE_PROPS_KEY configured"; \
	fi
	@if [ ! -f "compose.$(WORKSPACE).yml" ]; then \
		echo "[WARNING] compose.$(WORKSPACE).yml not found"; \
		echo ""; \
		echo "Available compose files:"; \
		ls -1 compose.*.yml 2>/dev/null | sed 's/^/  - /' || echo "  (none found)"; \
	else \
		echo "[OK] Docker Compose file exists: compose.$(WORKSPACE).yml"; \
	fi
	@echo ""

# ==================================================
# SETUP & CONFIGURATION
# ==================================================
setup-password:
	@echo ""
	@echo "Generating credentials for $(WORKSPACE)..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[ERROR] $(ENV_FILE) not found"; \
		echo ""; \
		echo "Create it first:"; \
		echo "  cp .env.template $(ENV_FILE)"; \
		exit 1; \
	fi
	@PASS=$$(openssl rand -base64 16 | tr -d '=+/' | cut -c1-20); \
	KEY=$$(openssl rand -hex 12); \
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$(ENV_FILE)"; \
		sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$(ENV_FILE)"; \
	else \
		sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=$$PASS|" "$(ENV_FILE)"; \
		sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=$$KEY|" "$(ENV_FILE)"; \
	fi; \
	echo "[OK] Password: $$PASS"; \
	echo "[OK] Sensitive key: $$KEY"
	@echo ""
	@echo "Credentials saved to $(ENV_FILE)"
	@echo ""

clean-generated-info:
	@echo ""
	@echo "Cleaning generated info for $(WORKSPACE)..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[WARNING] $(ENV_FILE) not found"; \
		exit 1; \
	fi
	@if [ "$$(uname)" = "Darwin" ]; then \
		sed -i "" "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$(ENV_FILE)"; \
		sed -i "" "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$(ENV_FILE)"; \
		sed -i "" "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$(ENV_FILE)"; \
		sed -i "" "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$(ENV_FILE)"; \
		sed -i "" "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$(ENV_FILE)"; \
	else \
		sed -i "s|^NIFI_PASSWORD=.*|NIFI_PASSWORD=|" "$(ENV_FILE)"; \
		sed -i "s|^NIFI_SENSITIVE_PROPS_KEY=.*|NIFI_SENSITIVE_PROPS_KEY=|" "$(ENV_FILE)"; \
		sed -i "s|^PUBLIC_IP=.*|PUBLIC_IP=|" "$(ENV_FILE)"; \
		sed -i "s|^VM_PUBLIC_IP=.*|VM_PUBLIC_IP=|" "$(ENV_FILE)"; \
		sed -i "s|^NIFI_WEB_PROXY_HOST=.*|NIFI_WEB_PROXY_HOST=|" "$(ENV_FILE)"; \
	fi
	@echo "   [OK] Credentials cleared"
	@echo "   [OK] IP addresses cleared"
	@echo ""
	@echo "[OK] $(WORKSPACE) environment cleaned!"
	@echo ""
	@echo "To regenerate:"
	@echo "   make setup-password ENV=$(ENV)"
	@echo ""

echo-info-access:
	@echo ""
	@echo "========================================================"
	@echo "       NiFi CI/CD Environment Access Information"
	@echo "========================================================"
	@echo ""
	@if [ "$(WORKSPACE)" = "development" ]; then \
		echo "DEVELOPMENT ENVIRONMENT"; \
		echo "----------------------"; \
	elif [ "$(WORKSPACE)" = "staging" ]; then \
		echo "STAGING ENVIRONMENT"; \
		echo "------------------"; \
	elif [ "$(WORKSPACE)" = "production" ]; then \
		echo "PRODUCTION ENVIRONMENT"; \
		echo "---------------------"; \
	fi
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		echo "  Extracting info from running containers..."; \
		echo ""; \
		NIFI_CONTAINER=$$(sudo docker ps --filter "name=nifi" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -v registry | head -n1); \
		if [ -n "$$NIFI_CONTAINER" ]; then \
			VM_IP=$$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $$1}'); \
			NIFI_USER=$$(sudo docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_USERNAME=" | cut -d'=' -f2); \
			NIFI_PASS=$$(sudo docker exec $$NIFI_CONTAINER env 2>/dev/null | grep "^SINGLE_USER_CREDENTIALS_PASSWORD=" | cut -d'=' -f2); \
			echo "  NiFi UI:         https://$$VM_IP:8443/nifi"; \
			echo "  NiFi Registry:   http://$$VM_IP:18080/nifi-registry"; \
			echo "  NiFi Username:   $$NIFI_USER"; \
			echo "  NiFi Password:   $$NIFI_PASS"; \
			echo "  VM IP:           $$VM_IP"; \
			echo ""; \
			echo "  Container: $$NIFI_CONTAINER"; \
		else \
			echo "  [ERROR] No running NiFi containers found"; \
			echo ""; \
			echo "  Please start the NiFi services on this VM"; \
		fi; \
	else \
		echo "  [ERROR] Cannot retrieve information"; \
		echo "  Docker may not be running or requires sudo access"; \
		echo ""; \
		echo "  SSH to VM and run: make echo-info-access ENV=$(ENV)"; \
	fi
	@echo ""

health-check:
	@echo ""
	@echo "Health Check - $(WORKSPACE) Environment"
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		NIFI_RUNNING=$$(sudo docker ps --filter "name=nifi" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -v registry | head -n1); \
		REGISTRY_RUNNING=$$(sudo docker ps --filter "name=registry" --filter "status=running" --format "{{.Names}}" 2>/dev/null | head -n1); \
		VM_IP=$$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $$1}'); \
		if [ -n "$$NIFI_RUNNING" ]; then \
			echo "[OK] NiFi container running: $$NIFI_RUNNING"; \
			if curl -sf -k https://$$VM_IP:8443/nifi > /dev/null 2>&1; then \
				echo "[OK] NiFi web UI responding"; \
			else \
				echo "[WARNING] NiFi web UI not responding yet"; \
			fi; \
		else \
			echo "[ERROR] NiFi container not running"; \
		fi; \
		if [ -n "$$REGISTRY_RUNNING" ]; then \
			echo "[OK] Registry container running: $$REGISTRY_RUNNING"; \
			if curl -sf http://$$VM_IP:18080/nifi-registry > /dev/null 2>&1; then \
				echo "[OK] Registry API responding"; \
			else \
				echo "[WARNING] Registry API not responding yet"; \
			fi; \
		else \
			echo "[ERROR] Registry container not running"; \
		fi; \
	else \
		echo "[ERROR] Docker not accessible"; \
		echo "SSH to VM and run: make health-check ENV=$(ENV)"; \
	fi
	@echo ""

# ==================================================
# VM DOCKER MANAGEMENT
# ==================================================
up: validate-env
	@echo ""
	@echo "Starting NiFi services on $(WORKSPACE) VM..."
	@echo ""
	@if [ ! -f "compose.$(WORKSPACE).yml" ]; then \
		echo "[ERROR] compose.$(WORKSPACE).yml not found"; \
		echo ""; \
		echo "Available compose files:"; \
		ls -1 compose.*.yml 2>/dev/null | sed 's/^/  - /' || echo "  (none found)"; \
		exit 1; \
	fi
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		echo "  Running on VM - executing docker compose up..."; \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) up -d; \
		echo "  [OK] Containers started"; \
		echo ""; \
		echo "  Waiting for services to be ready..."; \
		sleep 45; \
		$(MAKE) health-check ENV=$(ENV); \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  To start services:"; \
		echo "    1. SSH to VM: make ssh-$(ENV)"; \
		echo "    2. Run: cd ~/nificicd-g1p2 && make up ENV=$(ENV)"; \
	fi
	@echo ""

down: validate-env
	@echo ""
	@echo "Stopping NiFi services on $(WORKSPACE) VM..."
	@echo ""
	@if [ ! -f "compose.$(WORKSPACE).yml" ]; then \
		echo "[ERROR] compose.$(WORKSPACE).yml not found"; \
		exit 1; \
	fi
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		echo "  Running on VM - executing docker compose down..."; \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) down; \
		echo "  [OK] Containers stopped"; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  To stop services:"; \
		echo "    1. SSH to VM: make ssh-$(ENV)"; \
		echo "    2. Run: cd ~/nificicd-g1p2 && make down ENV=$(ENV)"; \
	fi
	@echo ""

restart: down
	@sleep 2
	@$(MAKE) up ENV=$(ENV)

status: validate-env
	@echo ""
	@echo "Container Status - $(WORKSPACE)"
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) ps; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make status ENV=$(ENV)"; \
	fi
	@echo ""

logs: validate-env
	@echo ""
	@echo "Tailing all container logs - $(WORKSPACE) (Ctrl+C to exit)..."
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) logs -f --tail=100; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make logs ENV=$(ENV)"; \
	fi

logs-nifi: validate-env
	@echo ""
	@echo "Tailing NiFi logs - $(WORKSPACE) (Ctrl+C to exit)..."
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) logs -f --tail=100 nifi; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make logs-nifi ENV=$(ENV)"; \
	fi

logs-registry: validate-env
	@echo ""
	@echo "Tailing Registry logs - $(WORKSPACE) (Ctrl+C to exit)..."
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		sudo docker compose -f compose.$(WORKSPACE).yml --env-file $(ENV_FILE) logs -f --tail=100 nifi-registry; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make logs-registry ENV=$(ENV)"; \
	fi

clean-volumes:
	@echo ""
	@echo "Cleaning up NiFi Docker volumes on $(WORKSPACE) VM..."
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		echo "  [WARNING] This will remove all NiFi data volumes"; \
		echo ""; \
		printf "  Continue? [y/N]: "; \
		read confirm; \
		if [ "$${confirm}" = "y" ] || [ "$${confirm}" = "Y" ]; then \
			sudo docker volume rm nifi_conf_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_database_repository_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_flowfile_repository_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_content_repository_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_provenance_repository_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_nar_extensions_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_python_extensions_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_state_$(WORKSPACE) 2>/dev/null || true; \
			sudo docker volume rm nifi_logs_$(WORKSPACE) 2>/dev/null || true; \
			echo "  [OK] Cleanup complete"; \
		else \
			echo "  Cleanup cancelled"; \
		fi; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make clean-volumes ENV=$(ENV)"; \
	fi
	@echo ""

prune:
	@echo ""
	@echo "Deep cleaning Docker resources on $(WORKSPACE) VM..."
	@echo ""
	@if command -v docker >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then \
		echo "  [WARNING] This will remove:"; \
		echo "    - All stopped containers"; \
		echo "    - All unused networks"; \
		echo "    - All dangling images"; \
		echo ""; \
		printf "  Continue? [y/N]: "; \
		read confirm; \
		if [ "$${confirm}" = "y" ] || [ "$${confirm}" = "Y" ]; then \
			sudo docker system prune -f; \
			echo "  [OK] Docker system pruned"; \
		else \
			echo "  Prune cancelled"; \
		fi; \
	else \
		echo "  [ERROR] Not on VM or Docker not accessible"; \
		echo ""; \
		echo "  SSH to VM and run: make prune ENV=$(ENV)"; \
	fi
	@echo ""

# ==================================================
# REGISTRY SETUP
# ==================================================
setup-registry-default:
	@echo "Setting up NiFi Registry (default) for $(WORKSPACE)..."
	@export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/setup_nifi_registry.sh

setup-registry-buckets:
	@echo ""
	@$(call print_section,"Creating Flow-Specific Buckets - $(WORKSPACE)")
	@echo ""
	@if [ ! -f scripts/setup_nifi_registry.sh ]; then \
		echo "[ERROR] scripts/setup_nifi_registry.sh not found"; \
		exit 1; \
	fi
	@VM_IP=$$(grep '^VM_PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	if [ -z "$$VM_IP" ]; then \
		VM_IP=$$(grep '^PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	fi; \
	echo "Configuration:"; \
	echo "  - Environment: $(WORKSPACE)"; \
	echo "  - Registry URL: http://$$VM_IP:18080"; \
	echo "  - Flows Directory: ./flows"
	@if [ -n "$(FLOW)" ]; then \
		echo "  - Creating bucket for flow: $(FLOW)"; \
		if [ ! -f "./flows/$(FLOW).json" ]; then \
			echo "[ERROR] Flow file not found: ./flows/$(FLOW).json"; \
			exit 1; \
		fi; \
		bucket_name=$$(echo "$(FLOW)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$$//'); \
		echo "  - Bucket name: $$bucket_name"; \
		echo ""; \
		export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
		SKIP_DEFAULT_BUCKET=true SPECIFIC_FLOW="$(FLOW)" CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	elif [ -n "$(FLOWS)" ]; then \
		echo "  - Creating buckets for flows: $(FLOWS)"; \
		echo ""; \
		export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
		SKIP_DEFAULT_BUCKET=true SPECIFIC_FLOWS="$(FLOWS)" CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	else \
		echo "  - Creating buckets for all flows"; \
		echo ""; \
		export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
		SKIP_DEFAULT_BUCKET=true CREATE_PER_FLOW_BUCKETS=true bash scripts/setup_nifi_registry.sh; \
	fi
	@echo ""
	@echo "[OK] Flow buckets setup complete for $(WORKSPACE)!"
	@echo ""

registry-info:
	@echo ""
	@$(call print_section,"NiFi Registry Information - $(WORKSPACE)")
	@echo ""
	@VM_IP=$$(grep '^VM_PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	if [ -z "$$VM_IP" ]; then \
		VM_IP=$$(grep '^PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	fi; \
	REGISTRY_URL="http://$$VM_IP:18080"; \
	echo "Registry Status:"; \
	if curl -sf "$$REGISTRY_URL/nifi-registry" > /dev/null 2>&1; then \
		echo "  [OK] Registry is running"; \
		echo "  URL: $$REGISTRY_URL/nifi-registry"; \
	else \
		echo "  [ERROR] Registry is not accessible"; \
		echo "  URL: $$REGISTRY_URL/nifi-registry"; \
		echo "  Check if services are running or firewall rules"; \
	fi
	@echo ""
	@echo "Registry Buckets:"
	@VM_IP=$$(grep '^VM_PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	if [ -z "$$VM_IP" ]; then \
		VM_IP=$$(grep '^PUBLIC_IP=' $(ENV_FILE) | cut -d'=' -f2); \
	fi; \
	curl -s "http://$$VM_IP:18080/nifi-registry-api/buckets" 2>/dev/null | \
		jq -r '.[] | "  - \(.name) (ID: \(.identifier))"' 2>/dev/null || \
		echo "  [WARNING] Could not fetch buckets"
	@echo ""
	@echo "Available Flows:"
	@if [ -d "flows" ] && [ -n "$$(ls -A flows/*.json 2>/dev/null)" ]; then \
		ls -1 flows/*.json 2>/dev/null | while read file; do \
			name=$$(basename "$$file" .json); \
			echo "  - $$name"; \
		done; \
		total=$$(ls -1 flows/*.json 2>/dev/null | wc -l | tr -d ' '); \
		echo ""; \
		echo "  Total: $$total flow(s)"; \
	else \
		echo "  [WARNING] No flows found in flows/ directory"; \
	fi
	@echo ""

# ==================================================
# FLOW IMPORT
# ==================================================
import-flows-auto:
	@echo "Auto-importing flows to $(WORKSPACE)..."
	@export $$(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/auto_import_flows.sh

import-flow:
	@if [ -z "$(FLOW)" ]; then \
		echo "[ERROR] FLOW parameter required"; \
		echo ""; \
		echo "Usage: make import-flow FLOW=<flow-name> ENV=<env>"; \
		echo ""; \
		echo "Available flows:"; \
		ls -1 flows/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$$//' | sed 's/^/  - /' || echo "  (none)"; \
		exit 1; \
	fi
	@echo ""
	@echo "Importing flow: $(FLOW) to $(WORKSPACE)"
	@set -a && . ./$(ENV_FILE) && set +a && \
	export FLOW_NAME="$(FLOW)" && \
	bash scripts/auto_import_flows.sh

import-flows-pattern:
	@if [ -z "$(PATTERN)" ]; then \
		echo "[ERROR] PATTERN parameter required"; \
		echo ""; \
		echo "Usage: make import-flows-pattern PATTERN=<pattern> ENV=<env>"; \
		exit 1; \
	fi
	@echo "Importing flows matching: $(PATTERN) to $(WORKSPACE)"
	@set -a && . ./$(ENV_FILE) && set +a && \
	export FLOW_PATTERN="$(PATTERN)" && \
	bash scripts/auto_import_flows.sh

list-flows:
	@echo ""
	@$(call print_section,"Available NiFi Flows")
	@echo ""
	@if [ -d "flows" ] && [ -n "$$(ls -A flows/*.json 2>/dev/null)" ]; then \
		echo "Flows directory:"; \
		ls -1 flows/*.json 2>/dev/null | while read file; do \
			name=$$(basename "$$file" .json); \
			size=$$(du -h "$$file" | cut -f1); \
			echo "  - $$name ($$size)"; \
		done; \
		echo ""; \
		total=$$(ls -1 flows/*.json 2>/dev/null | wc -l | tr -d ' '); \
		echo "Total: $$total flow(s)"; \
	else \
		echo "[WARNING] No flows found in flows/ directory"; \
	fi
	@echo ""

# ==================================================
# FLOW EXPORT
# ==================================================
export-flow-from-registry:
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh

export-flows-from-registry:
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-all-flows-from-registry.sh

export-flow-with-commit: export-flows-from-registry
	@echo "Checking for changes..."
	@git add flows/
	@if ! git diff --cached --quiet; then \
		git commit -m "chore: update flow definitions from $(WORKSPACE) registry"; \
		echo "[OK] Changes committed"; \
	else \
		echo "No changes detected"; \
	fi

export-flow-by-id:
	@if [ -z "$(BUCKET_ID)" ] || [ -z "$(FLOW_ID)" ]; then \
		echo "[ERROR] BUCKET_ID and FLOW_ID required"; \
		echo "Usage: make export-flow-by-id BUCKET_ID=<id> FLOW_ID=<id> ENV=<env>"; \
		exit 1; \
	fi
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && \
	bash scripts/export-flow.sh --bucket-id $(BUCKET_ID) --flow-id $(FLOW_ID)

list-registry-buckets:
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh --list-buckets

list-registry-flows:
	@if [ -z "$(BUCKET_ID)" ]; then \
		export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh --list-flows; \
	else \
		export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh --list-flows --bucket-id $(BUCKET_ID); \
	fi

list-registry-versions:
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh --list-versions

show-registry-ids:
	@export $(cat $(ENV_FILE) | grep -v '^#' | xargs) && bash scripts/export-flow.sh --list-versions

# ==================================================
# SSH ACCESS
# ==================================================
ssh-dev:
	@echo "Connecting to Development VM..."
	@bash scripts/access-vm.sh development

ssh-staging:
	@echo "Connecting to Staging VM..."
	@bash scripts/access-vm.sh staging

ssh-prod:
	@echo "Connecting to Production VM..."
	@bash scripts/access-vm.sh production

# ==================================================
# BACKUP & RESTORE
# ==================================================
backup-flows:
	@echo "Creating flows backup..."
	@TIMESTAMP=$(date +%Y%m%d_%H%M%S); \
	BACKUP_DIR="flows/backups/$TIMESTAMP"; \
	mkdir -p "$BACKUP_DIR"; \
	cp flows/*.json "$BACKUP_DIR/" 2>/dev/null || true; \
	echo "[OK] Backup created: $BACKUP_DIR"

restore-flows:
	@echo ""
	@echo "Restoring ALL flows from ALL backups..."
	@echo ""
	@if [ ! -d "flows/backups" ]; then \
		echo "[ERROR] No backups directory found"; \
		exit 1; \
	fi; \
	TOTAL_BACKUPS=$(find flows/backups -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$TOTAL_BACKUPS" -eq 0 ]; then \
		echo "[WARNING] No backup JSON files found"; \
		exit 1; \
	fi; \
	echo "Backup Statistics:"; \
	BACKUP_DIRS=$(find flows/backups -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '); \
	echo "  - Total backup directories: $BACKUP_DIRS"; \
	echo "  - Total flow files: $TOTAL_BACKUPS"; \
	echo ""; \
	echo "Backup directories:"; \
	find flows/backups -mindepth 1 -maxdepth 1 -type d | sort -r | while read backup_dir; do \
		backup_name=$(basename "$backup_dir"); \
		flow_count=$(find "$backup_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
		echo "  - $backup_name ($flow_count flows)"; \
	done; \
	echo ""; \
	echo "[WARNING] This will:"; \
	echo "  1. Clear all existing flows in flows/"; \
	echo "  2. Copy ALL JSON files from ALL backup directories to flows/"; \
	echo "  3. Files with duplicate names will be overwritten by newer versions"; \
	echo ""; \
	printf "Continue with restoring ALL backups? [y/N]: "; \
	read confirm; \
	if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then \
		echo ""; \
		echo "Restore cancelled"; \
		exit 0; \
	fi; \
	echo ""; \
	echo "Step 1/2: Clearing current flows directory..."; \
	CURRENT_COUNT=$(find flows -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$CURRENT_COUNT" -gt 0 ]; then \
		rm -f flows/*.json 2>/dev/null || true; \
		echo "  [OK] Removed $CURRENT_COUNT existing flows"; \
	else \
		echo "  No existing flows to remove"; \
	fi; \
	echo ""; \
	echo "Step 2/2: Restoring all flows from backups..."; \
	find flows/backups -mindepth 1 -maxdepth 1 -type d | sort | while read backup_dir; do \
		backup_name=$(basename "$backup_dir"); \
		dir_flow_count=$(find "$backup_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$dir_flow_count" -gt 0 ]; then \
			cp "$backup_dir"/*.json flows/ 2>/dev/null || true; \
			echo "  - Copied $dir_flow_count flows from $backup_name"; \
		fi; \
	done; \
	FINAL_COUNT=$(find flows -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' '); \
	echo ""; \
	echo "[OK] Restore complete!"; \
	echo ""; \
	echo "Summary:"; \
	echo "  - Total backup files available: $TOTAL_BACKUPS"; \
	echo "  - Unique flows restored: $FINAL_COUNT"; \
	echo ""; \
	if [ "$FINAL_COUNT" -lt "$TOTAL_BACKUPS" ]; then \
		echo "Note: Duplicate filenames were merged (latest version kept)"; \
		echo ""; \
	fi