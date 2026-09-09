# PROGRESS.md — iac-terraform-ansible (Project 2)

## Project

Infrastructure-as-Code implementation of the VProfile stack using **Terraform** (infrastructure provisioning) and **Ansible** (configuration management).

Automates the same VPC, EC2, IAM, and service configuration built manually in **Project 1 (`aws-lift-and-shift`)**, replacing approximately 40 manual AWS CLI commands and userdata scripts with declarative, reproducible code.

---

## Portfolio Context

This is **Project 2 of 5** planned portfolio projects.

Portfolio sequence:

- ✅ Project 1 — `aws-lift-and-shift` (CLOSED)
- 🟢 Project 2 — `iac-terraform-ansible` (CURRENT)
- Project 3 — `cicd-pipeline-vprofile`
- Project 4 — `aws-paas-migration`
- Project 5 — `k8s-gitops-vprofile`

The full roadmap and project rationale live in the master portfolio prompt. This file records only the implementation state of Project 2.

---

## Current Phase

**Phase 1 — Terraform Foundation: NOT YET STARTED**

Planning and architecture decisions are approved. No AWS infrastructure has been provisioned yet.

---

## Project Baseline

Project 2 intentionally reproduces the **verified architecture from Project 1** before introducing Infrastructure-as-Code improvements.

The goal is **feature parity first, automation second**:

- Same networking architecture.
- Same IAM model.
- Same four application services.
- Same Secrets Manager integration.
- Same security group boundaries.

Architectural improvements (modules, remote state, ALB, Interface VPC Endpoints, Route 53, etc.) are treated as later enhancements rather than changing the baseline implementation.

---

## Key Decisions

### Infrastructure Decisions

- Terraform provisions AWS infrastructure.
- Ansible configures operating systems and application services.
- No userdata scripts for service installation; configuration happens through Ansible roles after instance creation.
- Local Terraform state (`terraform.tfstate`) for portfolio simplicity; S3 remote backend documented later as the production alternative.
- Flat Terraform files first; modular refactor deferred until fundamentals are complete.
- Project 1 EC2 instances will be terminated instead of imported into Terraform state.
- No ALB or Interface VPC Endpoints during Phase 1 scope.

### Security Decisions

- Reuse Project 1 Secrets Manager secrets:
  - `vprofile/db/admin-password`
  - `vprofile/rmq/test-password`
- No hardcoded credentials committed to the repository.
- Maintain the same least-privilege IAM model established in Project 1.

### Engineering Process Decisions

**Verification-first rule (carried forward from Project 1):**

> Nothing is marked **COMPLETE** until verified against live AWS state or successful tool output.

Implementation alone is not completion. Verification evidence is recorded before updating `PROGRESS.md`.

---

## Completed Work

*No implementation work completed yet.*

Phase 1 begins with repository setup and Terraform networking.

---

## Implementation Phases

| Phase | Focus | Deliverables |
|-------|-------|--------------|
| Phase 1 | Terraform networking & IAM | VPC, subnets, route tables, Internet Gateway, security groups, IAM roles, successful `terraform validate` and `terraform plan`. |
| Phase 2 | Terraform EC2 infrastructure | MariaDB, Memcached, RabbitMQ, Tomcat instances defined in Terraform. |
| Phase 3 | Terraform apply & verification | Infrastructure created, AWS state verified against Terraform state. |
| Phase 4 | Ansible roles | Roles for MariaDB, Memcached, RabbitMQ, and Tomcat. |
| Phase 5 | Ansible execution & idempotency | Successful playbook execution and zero-change second run verification. |
| Phase 6 | Reproducibility & documentation | Destroy → recreate → verify test, README, architecture, decisions, incidents, and course coverage documentation. |

---

## Resource Reference

*Populated as Terraform provisions resources.*

### Networking

*(To be populated during Phase 1.)*

### Security Groups

*(To be populated during Phase 1.)*

### IAM Roles / Instance Profiles

*(To be populated during Phase 1.)*

### EC2 Instances

*(To be populated during Phase 2.)*

### Secrets

Reused from Project 1.

---

## Known Decisions

- Terraform state stored locally and ignored by Git.
- `.terraform/`, `terraform.tfstate`, `terraform.tfstate.backup`, and plan files excluded via `.gitignore`.
- Ansible control node is the local Windows Git Bash environment.
- Secrets fetched dynamically from AWS Secrets Manager during Ansible runtime.
- Infrastructure mirrors Project 1 unless a documented architectural improvement is intentionally introduced.

---

## Known Issues

None.

Phase 1 has not started.

---

## Definition of Done

### Terraform

- [ ] Terraform files written.
- [ ] `terraform fmt` produces clean formatting.
- [ ] `terraform validate` succeeds.
- [ ] `terraform plan` reviewed with expected resources only.
- [ ] `terraform apply` provisions infrastructure successfully.
- [ ] AWS infrastructure matches Terraform state.

### Ansible

- [ ] Roles created for Tomcat, MariaDB, Memcached, RabbitMQ.
- [ ] Inventory configured.
- [ ] Playbook executes successfully.
- [ ] Second execution is idempotent (zero changes).

### Verification

- [ ] All four services healthy.
- [ ] Application reachable.
- [ ] Destroy → recreate → verify reproducibility test completed.

### Documentation

- [ ] `README.md`
- [ ] `architecture.md`
- [ ] `decisions.md`
- [ ] `incidents.md`
- [ ] `course-coverage.md`
- [ ] `PROGRESS.md` finalized.

### Repository

- [ ] Clean Conventional Commit history.
- [ ] No secrets committed.
- [ ] End-to-end reproducible workflow with minimal manual steps.

---

## Repository Status

- [ ] GitHub repository `iac-terraform-ansible` created.
- [ ] Local repository initialized.
- [ ] Directory structure created (`terraform/`, `ansible/`, `docs/`).
- [ ] `.gitignore` configured.
- [ ] Initial commit pushed.

---

## Next Step

### Phase 1 — Terraform Foundation

1. Create GitHub repository `iac-terraform-ansible`.
2. Clone into the DevOps workspace on **G:**.
3. Initialize repository structure.
4. Configure `.gitignore`.
5. Write Terraform networking files:
   - `main.tf`
   - `variables.tf`
   - `outputs.tf`
   - `security_groups.tf`
   - `iam.tf`
6. Run `terraform fmt`, `terraform validate`, and `terraform plan`.

**No `terraform apply` until the initial plan has been reviewed.**

---

## Assumptions

- Project 1 (`aws-lift-and-shift`) is fully completed and archived.
- AWS CLI configured for IAM user `gitops-terraform`.
- AWS Region: `us-east-1`.
- AWS Account: `747336059892`.
- Terraform installed locally (`terraform -v`).
- Ansible installed locally (`ansible --version`).
- Git Bash is the primary shell environment.

### Verified Project 1 AWS State (2026-09-09)

Confirmed via live AWS CLI queries before Project 2 infrastructure work began:

- All 4 Project 1 EC2 instances (`vprofile-mc`, `vprofile-db`, `vprofile-rmq`, `vprofile-app`) — **terminated**. Associated EBS volumes released on termination.
- Project 1 VPC `vprofile-vpc` (`vpc-0e686e7841a60b687`, CIDR `172.20.0.0/16`) — **still exists**. Project 2's Terraform-managed VPC must use a non-overlapping CIDR (`10.0.0.0/16` selected).
- Project 1 ALB and all 5 VPC Interface Endpoints — confirmed already deleted (matches Project 1 README). Only the free S3 Gateway Endpoint (`vpce-0540d3b05281c8189`) remains.
- Project 1 S3 bucket and 2 Secrets Manager secrets (`vprofile/db/admin-password`, `vprofile/rmq/test-password`) — still exist and are intentionally reused by Project 2 (see Security Decisions above).
- No orphaned Elastic IPs found.
- Default VPC (`vpc-0a0efac60df5e3724`, `172.31.0.0/16`) also present in-account; not used by either project but noted to avoid future CIDR confusion.

---

## Notes

See `NOTES.md` for chronological study notes and session checkpoints.
