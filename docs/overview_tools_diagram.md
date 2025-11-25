# NiFi CI/CD Project - Tools & Environment Overview

## 📋 Project Context

**Problem Statement**: Data pipelines are currently deployed manually across NiFi environments (Development, Test, Production). This process is time-consuming and error-prone.

**Objective**: Implement a CI/CD pipeline to automate the NiFi flow lifecycle management, reduce human errors, save time, and standardize environments.

---

## 🏗️ Three-Environment Architecture


![Environment Architecture Diagram](assets/environnement_diagram2.png)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPMENT ENVIRONMENT                             │
│                    (Flow Development & Unit Testing)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────────┐         ┌──────────────────┐                          │
│  │  NiFi Standalone │◄────────┤  NiFi Registry   │                          │
│  │                  │         │  (Version Ctrl)  │                          │
│  │  • Single Node   │         │                  │                          │
│  │  • Port: 8080    │         │  • Port: 18080   │                          │
│  │  • 4-8 GB RAM    │         │  • Git Backend   │                          │
│  │  • 2-4 CPU       │         └────────┬─────────┘                          │
│  └──────────────────┘                  │                                    │
│           │                            │                                    │
│           │                            ▼                                    │
│           │                  ┌──────────────────┐                           │
│           └─────────────────►│  PostgreSQL/     │                           │
│                              │  MySQL Database  │                           │
│                              │  (Test Data)     │                           │
│                              │  • Port: 5432    │                           │
│                              └──────────────────┘                           │
│                                       │                                     │
│  Resources: 4-8 GB RAM, 2-4 CPU      │                                     │
│  Purpose: Flow development, unit tests│                                     │
└───────────────────────────────────────┼─────────────────────────────────────┘
                                        │
                                        │ Git Push
                                        ▼
                              ┌──────────────────┐
                              │   GitHub Repo    │
                              │  (Source Truth)  │
                              └────────┬─────────┘
                                        │
                                        │ Webhook Trigger
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CI/CD PIPELINE (GitLab CI)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────┐            │
│  │ Validate │──►│   Test   │──►│  Deploy  │──►│   Verify     │            │
│  │  Flows   │   │  (pytest)│   │  to TEST │   │  Deployment  │            │
│  └──────────┘   └──────────┘   └──────────┘   └──────────────┘            │
│                                      │                                       │
│  Tools: Python, Docker, pytest       │ Automated                            │
└──────────────────────────────────────┼───────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TEST/UAT ENVIRONMENT                                  │
│            (Integration Testing & Functional Validation)                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        NiFi Cluster (2-3 Nodes)                       │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │   │
│  │  │  NiFi Node 1 │    │  NiFi Node 2 │    │  NiFi Node 3 │          │   │
│  │  │              │    │              │    │   (Optional) │          │   │
│  │  │  8-16 GB RAM │    │  8-16 GB RAM │    │  8-16 GB RAM │          │   │
│  │  │  Port: 8080  │    │  Port: 8080  │    │  Port: 8080  │          │   │
│  │  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘          │   │
│  │         │                    │                    │                  │   │
│  │         └────────────────────┴────────────────────┘                  │   │
│  │                              │                                       │   │
│  │                              │ Coordinated by                        │   │
│  │                              ▼                                       │   │
│  │                   ┌────────────────────┐                            │   │
│  │                   │  ZooKeeper Cluster │                            │   │
│  │                   │   (3 Nodes)        │                            │   │
│  │                   │  ┌────┐ ┌────┐    │                            │   │
│  │                   │  │ZK1 │ │ZK2 │    │                            │   │
│  │                   │  └────┘ └────┘    │                            │   │
│  │                   │     ┌────┐         │                            │   │
│  │                   │     │ZK3 │         │                            │   │
│  │                   │     └────┘         │                            │   │
│  │                   │  Port: 2181        │                            │   │
│  │                   └────────────────────┘                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌──────────────────┐         ┌──────────────────┐                          │
│  │  NiFi Registry   │         │  PostgreSQL/     │                          │
│  │  (Shared/Dedic.) │         │  MySQL Database  │                          │
│  │  Port: 18080     │         │  (Clone of Prod) │                          │
│  └──────────────────┘         │  Port: 5432      │                          │
│                                └──────────────────┘                          │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │              Monitoring Stack (Optional)                 │               │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐        │               │
│  │  │ Prometheus │  │  Grafana   │  │  ELK Stack │        │               │
│  │  └────────────┘  └────────────┘  └────────────┘        │               │
│  └──────────────────────────────────────────────────────────┘               │
│                                                                               │
│  Resources: 8-16 GB RAM per node                                             │
│  Purpose: Integration tests, performance validation, UAT                     │
└───────────────────────────────────────┬───────────────────────────────────────┘
                                        │
                                        │ Manual Approval
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION ENVIRONMENT                               │
│                    (Live Operations - High Availability)                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│                           ┌──────────────────┐                               │
│                           │  Load Balancer   │                               │
│                           │  (nginx/HAProxy) │                               │
│                           │  Port: 443       │                               │
│                           │  SSL Termination │                               │
│                           └────────┬─────────┘                               │
│                                    │                                         │
│                    ┌───────────────┼───────────────┐                        │
│                    │               │               │                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                   NiFi Cluster (3+ Nodes for HA)                     │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │   │
│  │  │  NiFi Node 1 │    │  NiFi Node 2 │    │  NiFi Node 3 │          │   │
│  │  │              │    │              │    │              │   + More  │   │
│  │  │ 16-32 GB RAM │    │ 16-32 GB RAM │    │ 16-32 GB RAM │          │   │
│  │  │  Port: 8443  │    │  Port: 8443  │    │  Port: 8443  │          │   │
│  │  │  (HTTPS)     │    │  (HTTPS)     │    │  (HTTPS)     │          │   │
│  │  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘          │   │
│  │         │                    │                    │                  │   │
│  │         └────────────────────┴────────────────────┘                  │   │
│  │                              │                                       │   │
│  │                              │ Coordinated by                        │   │
│  │                              ▼                                       │   │
│  │                   ┌────────────────────┐                            │   │
│  │                   │  ZooKeeper Cluster │                            │   │
│  │                   │    (3-5 Nodes)     │                            │   │
│  │                   │  ┌────┐ ┌────┐    │                            │   │
│  │                   │  │ZK1 │ │ZK2 │    │                            │   │
│  │                   │  └────┘ └────┘    │                            │   │
│  │                   │  ┌────┐ ┌────┐    │                            │   │
│  │                   │  │ZK3 │ │ZK4 │    │                            │   │
│  │                   │  └────┘ └────┘    │                            │   │
│  │                   │     ┌────┐         │                            │   │
│  │                   │     │ZK5 │         │                            │   │
│  │                   │     └────┘         │                            │   │
│  │                   │  Port: 2181        │                            │   │
│  │                   └────────────────────┘                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌──────────────────┐         ┌──────────────────┐                          │
│  │  NiFi Registry   │         │  PostgreSQL HA   │                          │
│  │  (Dedicated HA)  │         │  Cluster         │                          │
│  │  Port: 18443     │         │  Primary+Replica │                          │
│  │  (HTTPS)         │         │  Port: 5432      │                          │
│  └──────────────────┘         └──────────────────┘                          │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │                   Monitoring Stack (Required)            │               │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐        │               │
│  │  │ Prometheus │  │  Grafana   │  │  ELK Stack │        │               │
│  │  │    (HA)    │  │ Dashboard  │  │   Logs     │        │               │
│  │  └────────────┘  └────────────┘  └────────────┘        │               │
│  │                                                          │               │
│  │  ┌────────────┐  ┌────────────┐                        │               │
│  │  │ PagerDuty/ │  │  Backup &  │                        │               │
│  │  │ Alerting   │  │  Recovery  │                        │               │
│  │  └────────────┘  └────────────┘                        │               │
│  └──────────────────────────────────────────────────────────┘               │
│                                                                               │
│  ┌──────────────────┐                                                        │
│  │ HashiCorp Vault  │                                                        │
│  │ (Secrets Mgmt)   │                                                        │
│  │  Port: 8200      │                                                        │
│  └──────────────────┘                                                        │
│                                                                               │
│  Resources: 16-32 GB RAM per node                                            │
│  Purpose: Live operations, high availability, business-critical workloads    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Tools by Environment

### **1. Development Environment (DEV)**

| Component | Specification | Purpose | Why It Matters |
|-----------|--------------|---------|----------------|
| **NiFi Standalone** | • 1 Instance<br>• 4-8 GB RAM<br>• 2-4 CPU<br>• Port: 8080 (HTTP) | Flow development and unit testing workspace | **Cost-effective**: Single node sufficient for development<br>**Flexibility**: Developers can iterate quickly without cluster complexity |
| **NiFi Registry** | • Shared or dedicated<br>• Port: 18080<br>• Git backend | Version control for flows | **Version Control**: Every flow change tracked in Git<br>**Collaboration**: Multiple developers can work on different flows<br>**Audit Trail**: Complete history of who changed what and when |
| **PostgreSQL/MySQL** | • Single instance<br>• Port: 5432/3306<br>• Test/sample data | Development database | **Local Testing**: Developers can test database interactions<br>**Data Isolation**: Development data separate from production |
| **GitHub** | • Repository<br>• Webhooks configured | Source code management | **Single Source of Truth**: All code and flows stored centrally<br>**CI/CD Trigger**: Automated pipeline on code push |

**Resource Allocation**: 4-8 GB RAM, 2-4 CPU per instance  
**Security**: Basic authentication (single-user or LDAP)  
**Backup**: Not critical (development data)

---

### **2. Test/UAT Environment (TEST)**

| Component | Specification | Purpose | Why It Matters |
|-----------|--------------|---------|----------------|
| **NiFi Cluster** | • 2-3 Nodes<br>• 8-16 GB RAM each<br>• Port: 8080/8443<br>• Clustered mode | Integration testing and validation | **Realistic Testing**: Mimics production cluster behavior<br>**Load Testing**: Can validate performance under load<br>**Failover Testing**: Test high availability scenarios |
| **ZooKeeper Cluster** | • 3 Nodes<br>• Ports: 2181, 2888, 3888<br>• Quorum-based | Cluster coordination and leader election | **Cluster Management**: Coordinates NiFi nodes<br>**State Management**: Maintains cluster consistency<br>**Configuration Management**: Distributes config changes |
| **NiFi Registry** | • Shared with Prod or dedicated<br>• Port: 18080 | Version control (shared or isolated) | **Flow Promotion**: Flows tested here before production<br>**Rollback Capability**: Can revert to previous versions |
| **PostgreSQL/MySQL** | • Clone or subset of prod<br>• Port: 5432/3306<br>• Realistic data volume | Test database with production-like data | **Realistic Testing**: Tests with production data patterns<br>**Performance Validation**: Identifies bottlenecks before prod |
| **Monitoring Stack** (Optional) | • Prometheus<br>• Grafana<br>• ELK Stack | Performance monitoring and log analysis | **Early Detection**: Identify issues before production<br>**Performance Baseline**: Establish expected metrics |

**Resource Allocation**: 8-16 GB RAM per node  
**Security**: Moderate (SSL optional, basic auth)  
**Backup**: Daily backups recommended  
**Purpose**: Integration tests, UAT, performance testing

---

### **3. Production Environment (PROD)**

| Component | Specification | Purpose | Why It Matters |
|-----------|--------------|---------|----------------|
| **NiFi Cluster** | • 3+ Nodes (HA)<br>• 16-32 GB RAM each<br>• Port: 8443 (HTTPS only)<br>• SSL/TLS enabled | Live data processing with high availability | **Zero Downtime**: Node failures don't stop operations<br>**Scalability**: Add nodes to handle increased load<br>**Performance**: Distributed processing of high-volume data |
| **ZooKeeper Cluster** | • 3-5 Nodes<br>• Ports: 2181, 2888, 3888<br>• Production-grade quorum | Critical cluster coordination | **Reliability**: 5-node setup survives 2 node failures<br>**Split-Brain Prevention**: Quorum ensures consistency |
| **NiFi Registry** | • Dedicated HA setup<br>• Port: 18443 (HTTPS)<br>• High availability | Production flow versioning | **Business Continuity**: Critical component must be HA<br>**Disaster Recovery**: Can restore flows from registry |
| **Load Balancer** | • nginx or HAProxy<br>• Port: 443<br>• SSL termination<br>• Health checks | Traffic distribution and failover | **Single Entry Point**: Simplifies client configuration<br>**Automatic Failover**: Routes traffic away from failed nodes<br>**SSL Offload**: Centralizes certificate management |
| **PostgreSQL Cluster** | • Primary + Replicas<br>• Port: 5432<br>• Replication enabled<br>• Auto-failover | Production database with HA | **Data Durability**: Replicas protect against data loss<br>**Read Scaling**: Replicas handle read queries<br>**Automatic Recovery**: Failover without manual intervention |
| **Prometheus** | • High availability setup<br>• Scrape interval: 15s<br>• Retention: 30 days | Metrics collection and alerting | **Real-time Monitoring**: Immediate visibility into issues<br>**Trend Analysis**: Historical data for capacity planning<br>**Alerting**: Proactive notification of problems |
| **Grafana** | • Dashboards<br>• Multiple data sources<br>• Role-based access | Visualization and operational dashboards | **Operations Visibility**: Teams see system health at a glance<br>**Executive Reporting**: Business metrics visualization |
| **ELK Stack** | • Elasticsearch<br>• Logstash<br>• Kibana<br>• Centralized logging | Log aggregation and analysis | **Troubleshooting**: Quickly find root cause of issues<br>**Audit Trail**: Compliance and security logging<br>**Correlation**: Connect logs across all components |
| **HashiCorp Vault** | • Port: 8200<br>• HA setup<br>• Dynamic secrets | Secure secrets management | **Security**: No hardcoded passwords in code<br>**Rotation**: Automatic credential rotation<br>**Audit**: Complete access logs for compliance |
| **Backup System** | • Automated daily backups<br>• Off-site storage<br>• Restore procedures | Disaster recovery | **Business Continuity**: Recover from catastrophic failure<br>**Compliance**: Meet data retention requirements |
| **PagerDuty** | • On-call rotation<br>• Escalation policies<br>• Integration with alerts | Incident management | **Response Time**: Critical issues reach right person quickly<br>**Accountability**: Clear ownership of incidents |

**Resource Allocation**: 16-32 GB RAM per node  
**Security**: Maximum (HTTPS, mTLS, RBAC, secrets management)  
**Backup**: Real-time replication + daily snapshots  
**SLA**: 99.9% uptime target

---

## 🔄 CI/CD Pipeline Tools

### **GitLab CI / GitHub Actions**
**Purpose**: Automate deployment lifecycle

**Pipeline Stages**:
1. **Validate** - Syntax checking, standards compliance
2. **Test** - Unit and integration tests (pytest)
3. **Deploy-Dev** - Automatic deployment after code push
4. **Deploy-Test** - Automatic deployment after successful tests
5. **Deploy-Prod** - Manual approval gate + deployment

**Why Critical**: 
- Eliminates manual errors
- Reduces deployment time from hours to minutes
- Ensures consistency across environments
- Provides rollback capability

### **Python Deployment Scripts**
**Purpose**: Interact with NiFi REST API for automated deployments

**Key Scripts**:
- `deploy_nifi.py` - Main deployment orchestration
- `apply_parameters.py` - Environment-specific configuration
- `validate_flow.py` - Pre-deployment validation
- `backup_prod.py` - Pre-deployment backup

**Why Important**:
- Custom automation not available out-of-box
- Handles complex deployment logic
- Integrates with all other tools

### **Docker** (Optional)
**Purpose**: Containerization for portable deployments

**Usage**:
- Development environment consistency
- CI/CD pipeline execution
- Test environment isolation

---

## 📊 Comparison Table: Tools by Environment

| Tool/Component | DEV | TEST | PROD | Purpose |
|----------------|-----|------|------|---------|
| **NiFi** | Standalone (1 node) | Cluster (2-3 nodes) | Cluster (3+ nodes) | Data flow platform |
| **NiFi Registry** | Basic | Shared/Dedicated | Dedicated HA | Flow versioning |
| **ZooKeeper** | Not needed | 3 nodes | 3-5 nodes | Cluster coordination |
| **Database** | Single instance | Clone of prod | HA Cluster | Data persistence |
| **Load Balancer** | No | Optional | Required (nginx) | Traffic distribution |
| **Monitoring** | No | Optional | Required (Prom+Graf) | Observability |
| **Logging** | Local logs | Optional (ELK) | Required (ELK) | Troubleshooting |
| **Secrets Mgmt** | Plaintext config | Env variables | Vault | Security |
| **Backup** | No | Daily | Real-time + Daily | Disaster recovery |
| **SSL/TLS** | No | Optional | Required | Security |
| **Resources/Node** | 4-8 GB RAM | 8-16 GB RAM | 16-32 GB RAM | Performance |

---

## 💰 Cost vs. Capability Analysis

### **Development Environment**
- **Cost**: $ (Low)
- **Purpose**: Developer productivity
- **Uptime SLA**: None (business hours only)
- **Acceptable Downtime**: Hours to days

### **Test Environment**
- **Cost**: $$ (Medium)
- **Purpose**: Quality assurance, avoid prod issues
- **Uptime SLA**: 90% (best effort)
- **Acceptable Downtime**: Hours

### **Production Environment**
- **Cost**: $$$$ (High)
- **Purpose**: Business operations
- **Uptime SLA**: 99.9% (8.76 hours/year downtime)
- **Acceptable Downtime**: Minutes

**Investment Justification**:
- **Time Savings**: 90% reduction in deployment time
- **Error Reduction**: 85% fewer deployment issues
- **Business Continuity**: Production HA prevents costly outages

---

## 🔐 Security Considerations by Environment

### **Development**
- ✅ Basic authentication
- ✅ HTTP allowed
- ✅ Local file storage
- ❌ No encryption at rest
- ❌ No audit logging

### **Test**
- ✅ LDAP/SSO integration
- ✅ HTTPS optional
- ✅ Role-based access
- ✅ Basic audit logging
- ❌ Secrets in environment variables

### **Production**
- ✅ HTTPS only (TLS 1.3)
- ✅ Mutual TLS (mTLS)
- ✅ LDAP/SSO with MFA
- ✅ Granular RBAC
- ✅ HashiCorp Vault for secrets
- ✅ Encryption at rest
- ✅ Complete audit logging
- ✅ Security scanning
- ✅ Network segmentation

---

## 📈 Expected Benefits

### **Quantifiable Improvements**

| Metric | Before CI/CD | After CI/CD | Improvement |
|--------|-------------|-------------|-------------|
| **Deployment Time** | 4-6 hours | 15-30 minutes | 90% reduction |
| **Deployment Errors** | 20-30% | <5% | 85% reduction |
| **Environment Drift** | Frequent | Rare | Consistency achieved |
| **Rollback Time** | Hours-Days | Minutes | 95% reduction |
| **Audit Trail** | Manual docs | Automatic (Git) | 100% coverage |
| **Test Coverage** | Manual/Ad-hoc | Automated | Consistent |

### **Qualitative Benefits**
- ✅ **Developer Productivity**: Focus on flow logic, not deployment mechanics
- ✅ **Operations Confidence**: "Works in test = works in prod"
- ✅ **Compliance**: Complete audit trail for regulatory requirements
- ✅ **Disaster Recovery**: Rapid restoration from Registry + Git
- ✅ **Knowledge Sharing**: Infrastructure documented as code

---

## 🚀 Getting Started

### **Phase 1: Infrastructure Setup (Weeks 1-2)**
1. Provision servers/VMs for all three environments
2. Install NiFi on each environment
3. Install and configure NiFi Registry
4. Set up ZooKeeper clusters (Test & Prod)
5. Configure databases
6. Set up networking and firewalls

### **Phase 2: Configuration (Weeks 3-4)**
1. Create Parameter Contexts for each environment
2. Configure NiFi Registry → GitHub integration
3. Create Registry buckets (dev-flows, test-flows, prod-flows)
4. Set up authentication (LDAP for prod)
5. Deploy HashiCorp Vault (prod)

### **Phase 3: CI/CD Pipeline (Weeks 5-6)**
1. Create GitHub repository structure
2. Develop Python deployment scripts
3. Configure GitLab CI/CD pipeline
4. Create automated tests
5. Test full deployment flow: Dev → Test → Prod
6. Document rollback procedures

### **Phase 4: Monitoring (Week 7)**
1. Deploy Prometheus + Grafana
2. Configure alerting rules
3. Set up ELK stack for centralized logging
4. Create operational dashboards
5. Configure PagerDuty integration

### **Phase 5: Training & Handoff (Week 8)**
1. Document all procedures
2. Create runbooks for common scenarios
3. Train development and operations teams
4. Conduct disaster recovery drill
5. Go-live validation

---

## 📚 Documentation Deliverables

1. **Architecture Diagram** (this document)
2. **Deployment Guide** - Step-by-step deployment instructions
3. **Runbook** - Operational procedures for common tasks
4. **Disaster Recovery Plan** - Restoration procedures
5. **Troubleshooting Guide** - Common issues and solutions
6. **API Documentation** - NiFi REST API usage examples

---

## ✅ Success Criteria

- [ ] All three environments operational
- [ ] CI/CD pipeline successfully deploys from Dev → Test → Prod
- [ ] Monitoring dashboards showing all environments
- [ ] Zero manual configuration changes needed
- [ ] Rollback tested and documented
- [ ] Team trained on new process
- [ ] Documentation complete and reviewed

---

## 🔗 Key Tool Documentation

- **Apache NiFi**: https://nifi.apache.org/docs.html
- **NiFi Registry**: https://nifi.apache.org/docs/nifi-registry-docs/
- **Apache ZooKeeper**: https://zookeeper.apache.org/doc/
- **GitLab CI/CD**: https://docs.gitlab.com/ee/ci/
- **HashiCorp Vault**: https://www.vaultproject.io/docs
- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/

---

*Document Version: 1.0*  
*Last Updated: 25/11/2025*  
*Project: NiFi CI/CD Automation*  
*Owner: nifi-cicd-project Team*


