# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Current Phase
Phase 1 — Network & Security Foundation (nearly complete)

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured (IAM user: gitops-terraform, account: 747336059892, region: us-east-1)
- Maven 3.9.16 installed
- Billing alerts set in CloudWatch (BillingAlert-5USD and BillingAlarm)
- VProfile repo forked (dmncfrncsc/proton) and cloned into ~/aws-lift-and-shift/proton
- userdata/ folder started with partial mysql.sh

### Phase 1 — Network & Security Foundation (partial) ✅
- VPC created: vprofile-vpc (172.20.0.0/16) — vpc-0e686e7841a60b687
- DNS hostnames enabled on VPC
- Three subnets created:
  - vprofile-pub-1a — subnet-03510c2b0ab2a8d18 — 172.20.1.0/24 — us-east-1a (public)
  - vprofile-pub-1b — subnet-0416352cf44e6f091 — 172.20.2.0/24 — us-east-1b (public)
  - vprofile-priv-1a — subnet-0981c879b04c46232 — 172.20.3.0/24 — us-east-1a (private)
- Internet Gateway created and attached: vprofile-igw — igw-00e59563b9ad5ee7d
- Public route table created: vprofile-pub-rt — rtb-05958a20e0736100d
  - Internet route added (0.0.0.0/0 → IGW)
  - Associated with both public subnets
- Auto-assign public IP enabled on pub-1a and pub-1b
- Five security groups created with inbound rules:
  - vprofile-alb-sg — sg-04dcbc6c37a127962 — port 80 from internet (0.0.0.0/0)
  - vprofile-app-sg — sg-0eef3641caa12a1ba — port 8080 from alb-sg
  - vprofile-db-sg  — sg-059fb90eac508a949 — port 3306 from app-sg
  - vprofile-mc-sg  — sg-0d5c620face437bfc — port 11211 from app-sg
  - vprofile-rmq-sg — sg-0ba3baa7a8a231777 — port 5672 from app-sg

## Current State
All network infrastructure is in place. No EC2s or ALB running — no billable
resources active. Safe to leave overnight.

## Resource Reference
VPC: vpc-0e686e7841a60b687 (172.20.0.0/16)
vprofile-pub-1a: subnet-03510c2b0ab2a8d18
vprofile-pub-1b: subnet-0416352cf44e6f091
vprofile-priv-1a: subnet-0981c879b04c46232
vprofile-igw: igw-00e59563b9ad5ee7d
vprofile-pub-rt: rtb-05958a20e0736100d
vprofile-alb-sg: sg-04dcbc6c37a127962
vprofile-app-sg: sg-0eef3641caa12a1ba
vprofile-db-sg: sg-059fb90eac508a949
vprofile-mc-sg: sg-0d5c620face437bfc
vprofile-rmq-sg: sg-0ba3baa7a8a231777


## Key Decisions
- Used dedicated VPC instead of default VPC (teaches network fundamentals,
  isolates project resources)
- Separate security groups per backend service (production best practice —
  granular control, easier auditing and troubleshooting)
- Skipped NAT Gateway (cost: ~$0.045/hr) — will use SSM Session Manager
  to connect to private EC2s instead
- Skipped Route 53 hosted zone ($0.50/month) — will use ALB DNS name directly
- Private subnet in same AZ as pub-1a to minimize cross-AZ data transfer costs

## Known Issues
- mysql.sh in userdata/ is incomplete — missing DB creation, schema import,
  and user setup. Will complete in Phase 2.

## Next Step
Resume Phase 1 — add SSM Session Manager access (allows connecting to
private EC2s without a bastion host). Then Phase 1 is complete.
After that: generate PROGRESS.md update and move to Phase 2 — Backend EC2s.

## Remaining Phases
- Phase 1 remaining: SSM Session Manager access
- Phase 2: Launch backend EC2s (MySQL, Memcache, RabbitMQ) in private subnet
- Phase 3: Launch Tomcat EC2, build .war, deploy via S3
- Phase 4: Application Load Balancer and target group
- Phase 5: Validation, documentation, cleanup

## Master Prompt Updates (carry these into new chats)
Rule 3 additions:
- Define every term on first use (what it is, problem it solves, why it matters)
- Before each command, prompt student to understand it before running.
  Every command run is a command understood, not just copied.
Rule 8 addition:
- Default to production-level best practices always. Never simplify without
  flagging the trade-off and getting student approval. Simplification is
  opt-in, not opt-out.
