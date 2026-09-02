# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Current Phase
Phase 1 — Network & Security Foundation ✅ COMPLETE
Phase 2 — Backend EC2s (not started)

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured (IAM user: gitops-terraform, account: 747336059892, region: us-east-1)
- Maven 3.9.16 installed
- Billing alerts set in CloudWatch (BillingAlert-5USD and BillingAlarm)
- VProfile repo forked (dmncfrncsc/proton) and cloned into ~/aws-lift-and-shift/proton
- userdata/ folder started with partial mysql.sh

### Phase 1 — Network & Security Foundation ✅
- VPC created: vprofile-vpc (172.20.0.0/16) — vpc-0e686e7841a60b687
- DNS hostnames enabled on VPC
- Three subnets created:
  * vprofile-pub-1a — subnet-03510c2b0ab2a8d18 — 172.20.1.0/24 — us-east-1a (public)
  * vprofile-pub-1b — subnet-0416352cf44e6f091 — 172.20.2.0/24 — us-east-1b (public)
  * vprofile-priv-1a — subnet-0981c879b04c46232 — 172.20.3.0/24 — us-east-1a (private)
- Internet Gateway created and attached: vprofile-igw — igw-00e59563b9ad5ee7d
- Public route table created: vprofile-pub-rt — rtb-05958a20e0736100d
  * Internet route added (0.0.0.0/0 → IGW)
  * Associated with both public subnets
- Auto-assign public IP enabled on pub-1a and pub-1b
- Five security groups created:
  * vprofile-alb-sg — sg-04dcbc6c37a127962 — port 80 from 0.0.0.0/0
  * vprofile-app-sg — sg-0eef3641caa12a1ba — port 8080 from alb-sg
  * vprofile-db-sg — sg-059fb90eac508a949 — port 3306 from app-sg
  * vprofile-mc-sg — sg-0d5c620face437bfc — port 11211 from app-sg
  * vprofile-rmq-sg — sg-0ba3baa7a8a231777 — port 5672 from app-sg
  * vprofile-ssm-ep-sg — sg-05bfef82dda3ad55b — port 443 from VPC CIDR (SSM endpoints)
- Three SSM VPC Interface Endpoints created (all available):
  * com.amazonaws.us-east-1.ssm — vpce-0615acc9dd367d915
  * com.amazonaws.us-east-1.ssmmessages — vpce-00ae7b1e49d5deed5
  * com.amazonaws.us-east-1.ec2messages — vpce-01766d5b403a3b8f7

### IAM Setup ✅
- Created IAM role: vprofile-ssm-role
  * Trust policy: ec2.amazonaws.com only
  * Attached policy: AmazonSSMManagedInstanceCore
- Created instance profile: vprofile-ssm-instance-profile
  * vprofile-ssm-role added to instance profile
  * Ready to attach to EC2 instances on launch

## Current State
Phase 1 fully complete. No EC2s or ALB running — no billable resources active.
SSM endpoints are Interface type and incur a small hourly charge (~$0.01/hr each,
~$0.03/hr total). Safe to leave running between sessions.

## Resource Reference
VPC:              vpc-0e686e7841a60b687  (172.20.0.0/16)
vprofile-pub-1a:  subnet-03510c2b0ab2a8d18  (172.20.1.0/24, us-east-1a)
vprofile-pub-1b:  subnet-0416352cf44e6f091  (172.20.2.0/24, us-east-1b)
vprofile-priv-1a: subnet-0981c879b04c46232  (172.20.3.0/24, us-east-1a)
vprofile-igw:     igw-00e59563b9ad5ee7d
vprofile-pub-rt:  rtb-05958a20e0736100d
vprofile-alb-sg:  sg-04dcbc6c37a127962
vprofile-app-sg:  sg-0eef3641caa12a1ba
vprofile-db-sg:   sg-059fb90eac508a949
vprofile-mc-sg:   sg-0d5c620face437bfc
vprofile-rmq-sg:  sg-0ba3baa7a8a231777
vprofile-ssm-ep-sg: sg-05bfef82dda3ad55b
ssm endpoint:       vpce-0615acc9dd367d915
ssmmessages endpoint: vpce-00ae7b1e49d5deed5
ec2messages endpoint: vpce-01766d5b403a3b8f7
vprofile-ssm-role: arn:aws:iam::747336059892:role/vprofile-ssm-role
vprofile-ssm-instance-profile: arn:aws:iam::747336059892:instance-profile/vprofile-ssm-instance-profile

## Key Decisions
- Dedicated VPC over default VPC (network isolation, teaches fundamentals)
- Separate security group per backend service (granular control, easier auditing)
- SSM Session Manager over bastion host (no public EC2 cost, no SSH key management,
  audit trail via CloudTrail, production-aligned practice)
- Skipped NAT Gateway (~$0.045/hr) — SSM endpoints serve our access needs
- Skipped Route 53 hosted zone ($0.50/month) — will use ALB DNS name directly
- Private subnet in same AZ as pub-1a to minimize cross-AZ data transfer costs
- NOTES.md will be written at project completion — lecture-style study notes
  covering all terms, concepts, and explanations accumulated during the build

## Known Issues
- mysql.sh in userdata/ is incomplete — missing DB creation, schema import,
  and user setup. Will complete in Phase 2.

## Next Step
Phase 2 — Launch backend EC2 instances (MySQL, Memcache, RabbitMQ) in
private subnet with vprofile-ssm-instance-profile attached. Start with
completing mysql.sh user-data script before launching any instances.

## Remaining Phases
- Phase 2: Launch backend EC2s (MySQL, Memcache, RabbitMQ) in private subnet
- Phase 3: Launch Tomcat EC2, build .war artifact, deploy via S3
- Phase 4: Application Load Balancer and target group
- Phase 5: Validation, documentation, cleanup
