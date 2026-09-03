# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Current Phase
Phase 2 — Backend EC2s (not started)

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured (IAM user: gitops-terraform, account: 747336059892, region: us-east-1)
- Maven 3.9.16 installed
- Billing alerts set in CloudWatch (BillingAlert-5USD and BillingAlarm)
- VProfile repo forked (dmncfrncsc/proton) and cloned into ~/aws-lift-and-shift/proton
- userdata/ folder started with partial mysql.sh

### Phase 1 — Network & Security Foundation ✅
- VPC: vprofile-vpc (172.20.0.0/16) — vpc-0e686e7841a60b687, DNS hostnames enabled
- Subnets:
  * vprofile-pub-1a — subnet-03510c2b0ab2a8d18 — 172.20.1.0/24 — us-east-1a
  * vprofile-pub-1b — subnet-0416352cf44e6f091 — 172.20.2.0/24 — us-east-1b
  * vprofile-priv-1a — subnet-0981c879b04c46232 — 172.20.3.0/24 — us-east-1a
- Internet Gateway: vprofile-igw — igw-00e59563b9ad5ee7d
- Public route table: vprofile-pub-rt — rtb-05958a20e0736100d
  * 0.0.0.0/0 → IGW, associated with both public subnets
- Auto-assign public IP enabled on pub-1a and pub-1b
- Security groups:
  * vprofile-alb-sg   — sg-04dcbc6c37a127962 — port 80 from 0.0.0.0/0
  * vprofile-app-sg   — sg-0eef3641caa12a1ba — port 8080 from alb-sg
  * vprofile-db-sg    — sg-059fb90eac508a949 — port 3306 from app-sg
  * vprofile-mc-sg    — sg-0d5c620face437bfc — port 11211 from app-sg
  * vprofile-rmq-sg   — sg-0ba3baa7a8a231777 — port 5672 from app-sg
  * vprofile-ssm-ep-sg — sg-05bfef82dda3ad55b — port 443 from VPC CIDR
- SSM VPC Endpoints (all in priv-1a, all using ssm-ep-sg, all available):
  * SSM          — vpce-0615acc9dd367d915
  * SSM Messages — vpce-00ae7b1e49d5deed5
  * EC2 Messages — vpce-01766d5b403a3b8f7

## Current State
Phase 1 fully verified. No EC2s or ALB running. No billable resources active.

## Next Step
Phase 2 — Launch backend EC2s (MySQL, Memcache, RabbitMQ) in private subnet.
First task: complete mysql.sh userdata script, then write memcache.sh and rabbitmq.sh.

## Remaining Phases
- Phase 2: Backend EC2s (MySQL, Memcache, RabbitMQ) — userdata scripts + launch
- Phase 3: Tomcat EC2, build .war, deploy via S3
- Phase 4: Application Load Balancer and target group
- Phase 5: Validation, documentation, cleanup

## Resource Reference
VPC:              vpc-0e686e7841a60b687 (172.20.0.0/16)
vprofile-pub-1a:  subnet-03510c2b0ab2a8d18
vprofile-pub-1b:  subnet-0416352cf44e6f091
vprofile-priv-1a: subnet-0981c879b04c46232
vprofile-igw:     igw-00e59563b9ad5ee7d
vprofile-pub-rt:  rtb-05958a20e0736100d
alb-sg:           sg-04dcbc6c37a127962
app-sg:           sg-0eef3641caa12a1ba
db-sg:            sg-059fb90eac508a949
mc-sg:            sg-0d5c620face437bfc
rmq-sg:           sg-0ba3baa7a8a231777
ssm-ep-sg:        sg-05bfef82dda3ad55b

## Key Decisions
- Dedicated VPC over default VPC (isolation, teaches networking fundamentals)
- One security group per service (least privilege, easier auditing)
- SSM Session Manager instead of bastion host (no extra EC2 cost, no open port 22)
- No NAT Gateway (saves ~$0.045/hr — SSM handles private EC2 access)
- No Route 53 hosted zone (saves $0.50/mo — will use ALB DNS directly)
- Private subnet in same AZ as pub-1a (minimizes cross-AZ data transfer)
