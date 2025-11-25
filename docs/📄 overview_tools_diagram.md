Tools & Environments Diagram Description (English Version)




This diagram illustrates the full lifecycle of how tools interact across the Development, Testing (UAT), and Production environments for the NiFi-based data pipeline project.

1. GitHub – Source Control & CI/CD Trigger

GitHub serves as the central platform where:

flow definitions exported from NiFi are versioned,

infrastructure and deployment configuration files are stored,

CI/CD workflows are triggered automatically.

Developers push changes to GitHub, which initiates automated build and deployment jobs.

2. NiFi Registry – Flow Versioning System

NiFi Registry stores and manages:

version history of NiFi flows,

metadata about flow changes,

synchronization between NiFi environments.

It acts as the version-controlled backend for flow management.

3. Docker – Build & Packaging Layer

Docker is used to:

build container images containing NiFi and NiFi Registry,

package flows, configurations, and scripts,

prepare artifacts for deployment.

These images become the basis for consistent deployments across environments.

4. Azure Container Registry (ACR) – Image Repository

ACR hosts and stores:

NiFi Docker images,

NiFi Registry images,

any custom processor bundles or required dependencies.

All downstream environments pull images from ACR to ensure consistency.

5. Testing / UAT Environment

The UAT environment retrieves Docker images from ACR and is used for:

validating functional behavior of flows,

testing integration between components,

ensuring stability before going live.

6. Production Environment

The Production environment pulls the same validated image from ACR. It provides:

secure deployment of NiFi,

stable execution of approved flows,

high reliability and controlled updates.

7. NiFi Runtime – Flow Execution Engine

Apache NiFi runs inside Docker containers and:

executes the data flows,

communicates with NiFi Registry to retrieve versioned flows,

processes real-time or batch data depending on flow design.

🔄 Overall Workflow Summary

Developer updates flow or code → pushes to GitHub

GitHub CI pipeline builds Docker images

Docker images pushed to Azure Container Registry

Testing environment pulls image → validation

Production environment pulls validated image → final deployment

This diagram represents a fully automated CI/CD workflow enabling consistent, secure, and scalable NiFi deployments across cloud environments.