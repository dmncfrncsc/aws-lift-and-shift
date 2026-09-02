# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Current Phase
Phase 2 — Backend EC2s (next up)

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured (IAM user: gitops-terraform, account: 747336059892, region: us-east-1)
- Maven 3.9.16 installed
- Billing alerts set in CloudWatch (BillingAlert-5USD and BillingAlarm)
- VProfile repo forked (dmncfrncsc/proton) and cloned into ~/aws-lift-and-shift/proton
- userdata/ folder started with partial mysql.sh

### Phase 1 — Network & Security Foundation ✅
- VPC: vprofile-vpc (172.20.0.0/16) — vpc-0e686e7841a60b687
- DNS hostnames enabled on VPC
- Subnets:
  * vprofile-pub-1a — subnet-03510c2b0ab2a8d18 — 172.20.1.0/24 — us-east-1a (public)
  * vprofile-pub-1b — subnet-0416352cf44e6f091 — 172.20.2.0/24 — us-east-1b (public)
  * vprofile-priv-1a — subnet-0981c879b04c46232 — 172.20.3.0/24 — us-east-1a (private)
- Internet Gateway: vprofile-igw — igw-00e59563b9ad5ee7d
- Public route table: vprofile-pub-rt — rtb-05958a20e0736100d
  * Route: 0.0.0.0/0 → IGW
  * Associated with pub-1a and pub-1b
- Auto-assign public IP enabled on pub-1a and pub-1b
- Security groups:
  * vprofile-alb-sg  — sg-04dcbc6c37a127962 — port 80 from 0.0.0.0/0
  * vprofile-app-sg  — sg-0eef3641caa12a1ba — port 8080 from alb-sg
  * vprofile-db-sg   — sg-059fb90eac508a949 — port 3306 from app-sg
  * vprofile-mc-sg   — sg-0d5c620face437bfc — port 11211 from app-sg
  * vprofile-rmq-sg  — sg-0ba3baa7a8a231777 — port 5672 from app-sg
  * vprofile-ssm-ep-sg — sg-05bfef82dda3ad55b — port 443 from 172.20.3.0/24
- SSM VPC Endpoints (in priv-1a):
  * ssm endpoint      — vpce-0615acc9dd367d915
  * ssmmessages       — vpce-00ae7b1e49d5deed5
  * ec2messages       — vpce-01766d5b403a3b8f7

## Current State
Phase 1 fully complete. No EC2s running.
Only billable resources: 3 VPC endpoints (~$0.03/hr, ~$0.72/day).

## Cleanup If Stopping Long
aws ec2 delete-vpc-endpoints \
  --vpc-endpoint-ids vpce-0615acc9dd367d915 vpce-00ae7b1e49d5deed5 vpce-01766d5b403a3b8f7 \
  --region us-east-1

## Key Decisions
- Dedicated VPC over default VPC (network fundamentals, resource isolation)
- Separate security groups per service (least-privilege, easier auditing)
- SSM Session Manager over bastion host (no extra EC2, no port 22, IAM-controlled)
- VPC Endpoints over NAT Gateway (saves ~$0.045/hr, traffic stays in AWS network)
- Skipped Route 53 ($0.50/month) — using ALB DNS name directly
  * GoDaddy domain devopspro.xyz available — consider vprofile.devopspro.xyz in Phase 4
- Private subnet in same AZ as pub-1a (minimize cross-AZ data transfer costs)

## Teaching Notes (for future Claude sessions)
- Student has zero networking background — define every term from scratch
- Explain one idea at a time — no analogies unless simple explanation fails first
- Strip to basics before adding layers
- Before each command: student must understand it before running it
- Ask questions to verify understanding

## Planned Deliverables at Project End
- NOTES.md: lecture-style notes, simple definitions + real examples from what we built
- Architecture diagram highlighting all components

## Known Issues
- mysql.sh in userdata/ incomplete — missing DB creation, schema import, user setup
  Will complete in Phase 2

## Next Step
Phase 2 — Backend EC2s.
First: create IAM role with AmazonSSMManagedInstanceCore policy (needed before
launching EC2s so SSM Agent can communicate with SSM endpoints).
Then: launch MySQL, Memcache, RabbitMQ EC2s in priv-1a with that role attached.

## Remaining Phases
- Phase 2: IAM role for SSM + backend EC2s (MySQL, Memcache, RabbitMQ)
- Phase 3: Tomcat EC2, Maven build, .war deploy via S3
- Phase 4: ALB + target group (+ optional devopspro.xyz via GoDaddy)
- Phase 5: Validation, documentation, cleanup, NOTES.md
