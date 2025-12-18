# Complete NiFi CI/CD Testing Guide

## Prerequisites

Before starting, verify that you have:
```bash
# Check Docker
docker --version
docker compose version

# Check necessary tools
make --version
jq --version
curl --version
openssl version
```

## Complete Testing Steps

### **Phase 1: Initial Configuration**

#### 1.1 Display help
```bash
make help
# Verify that all commands are listed correctly
```

#### 1.2 Validate environment
```bash
make validate-env
# Check if .env file exists
# If file doesn't exist, it will show you how to create it
```

#### 1.3 Create environment files (if necessary)
```bash
# If you don't have .env file
cp .env.template .env
cp .env.template .env.development
cp .env.template .env.staging
cp .env.template .env.production
```

#### 1.4 Generate passwords
```bash
# For local environment
make setup-password

# For all environments at once
make setup-passwords

# Verify passwords are generated in .env files
cat .env | grep NIFI_PASSWORD
cat .env | grep NIFI_SENSITIVE_PROPS_KEY
```

---

### **Phase 2: Local Docker Environment**

#### 2.1 Start environment
```bash
make up
# NiFi and Registry containers should start
# Wait approximately 30 seconds for initialization
```

#### 2.2 Check status
```bash
make status
# Containers should be "Up" with their ports

docker ps
# Manually verify containers are running
```

#### 2.3 Check service health
```bash
make health-check
# NiFi UI should respond (https://localhost:8443/nifi)
# Registry should respond (http://localhost:18080/nifi-registry)
```

#### 2.4 Access connection information
```bash
make echo-info-access
# Display username, password and URLs
# Verify info matches container info
```

#### 2.5 View logs
```bash
# Logs from all containers
make logs
# Ctrl+C to stop

# NiFi logs only
make logs-nifi

# Registry logs only
make logs-registry
```

#### 2.6 Test web interface
```bash
# Open in browser
open https://localhost:8443/nifi
# or
xdg-open https://localhost:8443/nifi

# Login with credentials displayed by echo-info-access
```

---

### **Phase 3: Registry Configuration**

#### 3.1 Registry setup (default bucket)
```bash
make setup-registry-default
# Create "default" bucket in Registry
```

#### 3.2 Check Registry information
```bash
make registry-info
# Display created buckets
# List available flows in flows/
```

#### 3.3 Access Registry interface
```bash
# Open in browser
open http://localhost:18080/nifi-registry
# or
xdg-open http://localhost:18080/nifi-registry

# Verify buckets are visible in UI
# Explore Registry interface
```

#### 3.4 Setup with per-flow buckets (optional)
```bash
# For all flows
make setup-registry-buckets

# For specific flow
make setup-registry-buckets FLOW=MyFlow

# For multiple flows
make setup-registry-buckets FLOWS=Flow1,Flow2,Flow3
```

#### 3.5 List Registry buckets
```bash
make list-registry-buckets
# Display all created buckets
```

---

### **Phase 3.5: UI Configuration - Link NiFi to Registry (CRITICAL)**

> **MANDATORY STEP**: Do this once per environment before any commit to Registry

#### 3.5.1 Open NiFi interface
```bash
# URL will be displayed by this command
make echo-info-access

# Open in browser
open https://localhost:8443/nifi
# or
xdg-open https://localhost:8443/nifi
```

#### 3.5.2 Login to NiFi
- **Username**: Displayed by `make echo-info-access`
- **Password**: Displayed by `make echo-info-access`
- Accept self-signed certificate in browser

#### 3.5.3 Configure Registry Client in NiFi UI

##### Step 1: Access settings
1. Click on **☰** (hamburger) menu at top right
2. Select **Controller Settings**
3. Click on **Registry Clients** tab

##### Step 2: Add Registry Client
1. Click on **➕ Add Registry Client** button (plus symbol)
2. A configuration window opens

##### Step 3: Fill in information

| Field | Value | Description |
|-------|--------|-------------|
| **Name** | `nifi-registry` | Registry client name |
| **URL** | `http://nifi-registry:18080` | Internal Docker URL (local) |
| **Description** | `Central NiFi Registry` | Optional description |

**For remote environments (dev/staging/prod)**:
```
URL for dev:     http://<VM_DEV_IP>:18080
URL for staging: http://<VM_STAGING_IP>:18080
URL for prod:    http://<VM_PROD_IP>:18080
```

##### Step 4: Save
- Click on **Apply** or **Save**
- Window closes

#### 3.5.4 Verify connection

##### Visual validation
1. Registry `nifi-registry` should appear in list
2. **Status**: Should show green icon or "Connected"
3. No red error message

##### Connection test
```bash
# From terminal, verify Registry responds
curl -s http://localhost:18080/nifi-registry-api/buckets | jq '.'

# Should return list of buckets
```

##### Troubleshooting connection error

**Problem: "Unable to connect to Registry"**
```bash
# Verify Registry is started
make health-check

# Check Registry logs
make logs-registry

# Restart if necessary
make restart
```

**Problem: "Incorrect URL"**
- For local environment: use `http://nifi-registry:18080`
- For remote environment: use VM public IP


---

### **Phase 3.6: Complete UI Workflow Test**

> **Objective**: Create a flow in NiFi and commit it to Registry

#### 3.6.1 Create test Process Group

##### In NiFi interface (https://localhost:8443/nifi)

1. **Drag-and-drop** **Process Group** icon on canvas
2. **Name** the Process Group: `TestFlow-Demo`
3. **Double-click** on Process Group to enter it

#### 3.6.2 Add test components

##### Create simple flow:
1. **Add GenerateFlowFile processor**:
   - Drag & drop Processor icon
   - Search "GenerateFlowFile"
   - Configure: Schedule = 10 sec

2. **Add LogAttribute processor**:
   - Connect GenerateFlowFile → LogAttribute
   - Configure: Auto-terminate all relationships

3. **Start processors**:
   - Select both processors
   - Right click → Start
   - Verify no red bulletin appears

#### 3.6.3 Version the Flow (Commit to Registry)

##### Step 1: Exit Process Group
- Click on "NiFi Flow" in breadcrumb at top

##### Step 2: Start versioning
1. **Right click** on Process Group `TestFlow-Demo`
2. Select **Version** → **Start version control**

##### Step 3: Commit configuration

A "Save Flow Version" window appears:

| Field | Value |
|-------|--------|
| **Registry** | `nifi-registry` (configured before) |
| **Bucket** | `default` (or choose specific bucket) |
| **Flow Name** | `TestFlow-Demo` |
| **Flow Description** | `Test flow for validation` |
| **Comments** | `Initial commit - testing registry integration` |

##### Step 4: Save
- Click on **Save**
- A green icon should appear on Process Group

#### 3.6.4 Verify in Registry UI

##### Access Registry
```bash
open http://localhost:18080/nifi-registry
```

##### Visual validation
1. Go to **Buckets** → `default`
2. Flow **TestFlow-Demo** should appear
3. Click on it to see:
   - Version: 1
   - Comment: "Initial commit..."
   - Creation date

#### 3.6.5 Make second commit (versioning test)

##### In NiFi UI
1. **Enter** Process Group `TestFlow-Demo`
2. **Modify** something:
   - Add new processor (e.g., UpdateAttribute)
   - Or modify a parameter
3. **Exit** Process Group

##### Commit changes
1. **Right click** on Process Group
2. **Version** → **Commit local changes**
3. Fill in:
   - **Comments**: `Added UpdateAttribute processor`
4. **Save**

##### Verify in Registry
```bash
# Via CLI
make list-registry-versions

# Via Registry UI
# See that TestFlow-Demo now has 2 versions
```
---

### **Phase 4: Flow Management**

#### 4.1 List available flows
```bash
make list-flows
# List all flows/
```

#### 4.2 Import flows to Registry

```bash
# Automatic import of all flows
make import-flows-auto

# Import specific flow
make import-flow FLOW=MyFlow

# Import with pattern
make import-flows-pattern PATTERN=prod*
```

#### 4.3 Verify flows in Registry
```bash
# List flows in buckets
make list-registry-flows

# See all IDs (buckets + flows + versions)
make show-registry-ids

# List versions
make list-registry-versions
```

#### 4.4 Export flows from Registry

```bash
# Interactive export of one flow
make export-flow-from-registry

# Export all flows
make export-flows-from-registry

# Export by specific ID
make export-flow-by-id BUCKET_ID=xxx FLOW_ID=yyy
```

---

### **Phase 5: Environment Management**

#### 5.1 Restart environment
```bash
make restart
# Stop and restart all containers
```

#### 5.2 Stop environment
```bash
make down
# Stop all containers
```

#### 5.3 Clean volumes (Delete data)
```bash
make clean-volumes
# Remove Docker volumes (data lost)
```

#### 5.4 Complete cleanup (Dangerous)
```bash
make prune
# Clean entire Docker system
# Confirm with 'y'
```

---

### **Phase 6: Multi-Environments**

#### 6.1 Validate specific environment
```bash
make validate-env ENV=dev
make validate-env ENV=staging
make validate-env ENV=prod
```

#### 6.2 Display access info for each environment
```bash
make echo-info-access ENV=dev
make echo-info-access ENV=staging
make echo-info-access ENV=prod

# Or all at once
make echo-info-access-all
```

#### 6.3 Clean generated info
```bash
# For one environment
make clean-generated-info ENV=dev

# For all
make clean-generated-info-all
```

---

### **Phase 7: SSH Access to VMs (Cloud Environments)**

```bash
# SSH connection to different environments
make ssh-dev
make ssh-staging
make ssh-prod

# Requires SSH keys to be configured
```
---

## Validation Checklist

### Basic Commands
- `make help` displays all commands
- `make validate-env` verifies configuration
- `make setup-password` generates credentials

### Local Docker
- `make up` starts containers
- `make status` shows active containers
- `make health-check` confirms everything works
- `make logs` displays logs
- `make down` stops containers

### Registry
- `make setup-registry-default` creates bucket
- `make registry-info` displays info
- `make list-registry-buckets` lists buckets
- **Registry UI accessible** (http://localhost:18080/nifi-registry)
- **Buckets visible in Registry UI**

### Flows
- `make list-flows` lists local flows
- `make import-flows-auto` imports to Registry
- `make export-flows-from-registry` exports from Registry
- `make list-registry-flows` lists Registry flows


### Multi-env
- `make echo-info-access ENV=dev` works
- `make clean-generated-info ENV=dev` cleans
- `make setup-passwords` configures all envs

---