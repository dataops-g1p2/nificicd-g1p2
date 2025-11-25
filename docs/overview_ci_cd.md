# CI/CD Overview for NiFi Pipelines

## Context

NiFi data pipelines are currently built directly in the NiFi UI by one or more data engineers. This allows for highly efficient and well-structured transformations.  

However, a key challenge remains: **how to move these Flows to production in a controlled and structured way**?  

NiFi does not natively provide a way to "package" a set of Flows and move them through a Dev Ã¢â€ â€™ Test Ã¢â€ â€™ Prod workflow. Deployments are therefore manual, which introduces several issues:  

- Risk of human errors when migrating Flows between environments.  
- Difficulty maintaining traceability and change history.  
- Potential environment inconsistencies that can compromise testing reliability.  

## CI/CD Objectives

Implementing a CI/CD pipeline for NiFi aims to:  

1. **Automate deployments**  
   - Minimize manual interventions and ensure safe production releases.  

2. **Standardize environments**  
   - Ensure that Development, Test, and Production environments use the same Flow versions and configurations.  

3. **Version Flows and ensure traceability**  
   - Each persisted Flow is versioned via the NiFi Registry, allowing rollback to previous versions if necessary.  
   - Using a Git repository as the persistence layer provides a clear and auditable history of changes.  

4. **Introduce a structured Dev Ã¢â€ â€™ Test Ã¢â€ â€™ Prod workflow**  
   - Each Flow passes through environments in a controlled manner, with automated validation and testing.  

## Key NiFi Registry Concepts

The NiFi Registry introduces an abstraction layer that manages Flows independently of their underlying storage:  

- **Bucket**: a container for multiple Flows. Can represent an environment, a business unit, or a NiFi instance.  
- **Flow**: a pipeline persisted in the Registry.  
- **Version**: each Flow is versioned, allowing reference and deployment of a specific version.  

Thus, a Bucket contains multiple Flows, and each Flow may have multiple Versions.

## CI/CD Pipeline Overview

![Environment Architecture Diagram](../assets/proomotion_flows_env.png)

### How It Works

- Developed Flows are **persisted in a Git repository via the NiFi Registry**.  
- NiFi communicates with the Registry using a **REST API**, ensuring synchronization of Flows and the ability to retrieve a specific version for each environment.  
- The CI/CD pipeline automates deployment and validation, ensuring a **repeatable, safe, and traceable path to production**.  

This setup provides **reliability, traceability, and automation**, fully addressing the critical needs of production environments.


