# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is Project 1 of 5 planned portfolio projects (+1 optional GCP project). The
full roadmap and project rationale live in the master prompt; this file records
only the state of this project.

## Current Phase
Phase 2 — Backend EC2s.

The RabbitMQ golden-AMI builder has RabbitMQ installed, enabled, and health-checked.
It is currently stopped to avoid EC2 compute charges. Before creating the AMI, the
next session must verify and apply the VProfile-specific RabbitMQ user and permission
configuration, then verify the broker again.

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured for IAM user `gitops-terraform`, account `747336059892`,
  region `us-east-1`.
- Maven 3.9.16 installed.
- Billing alerts set in CloudWatch: `BillingAlert-5USD` and `BillingAlarm`.
- VProfile repository forked as `dmncfrncsc/proton` and cloned into
  `~/aws-lift-and-shift/proton`.

### Phase 1 — Network & Security Foundation ✅
- VPC: `vprofile-vpc` (`vpc-0e686e7841a60b687`, CIDR `172.20.0.0/16`);
  DNS hostnames enabled.
- Public subnet 1a: `vprofile-pub-1a`
  (`subnet-03510c2b0ab2a8d18`, `172.20.1.0/24`).
- Public subnet 1b: `vprofile-pub-1b`
  (`subnet-0416352cf44e6f091`, `172.20.2.0/24`).
- Private subnet 1a: `vprofile-priv-1a`
  (`subnet-0981c879b04c46232`, `172.20.3.0/24`).
- Internet Gateway: `vprofile-igw` (`igw-00e59563b9ad5ee7d`).
- Public route table: `vprofile-pub-rt` (`rtb-05958a20e0736100d`) with
  `0.0.0.0/0` routed to the Internet Gateway.
- Public IP auto-assignment enabled on both public subnets.
- Security groups created: `alb-sg`, `app-sg`, `db-sg`, `mc-sg`, `rmq-sg`,
  and `ssm-ep-sg`.
- SSM VPC Interface Endpoints for `ssm`, `ssmmessages`, and `ec2messages`
  are available.
- S3 Gateway Endpoint is available for private-subnet S3 access.

### Phase 2 — Backend EC2s 🔄
- Actual AWS userdata scripts live in `~/aws-lift-and-shift/userdata/`, outside
  the forked VProfile repository.
- `memcache.sh` was reviewed; it has no public-internet dependency beyond
  Amazon Linux repositories and needs no changes.
- `rabbitmq.sh` was reviewed and exposed Incident #3: RabbitMQ is not available
  from Amazon Linux 2023 default repositories.
- Shared IAM role: `vprofile-ssm-role`.
- Shared instance profile for Memcached and RabbitMQ:
  `vprofile-ssm-instance-profile`.
- S3 bucket created: `vprofile-artifacts-747336059892`, with all public access
  blocked.
- `db/accountsdb.sql` uploaded to the bucket.
- `vprofile-db` was successfully relaunched and verified after the S3 schema
  download fix. That test instance was later terminated deliberately.
- `vprofile-mc` remains terminated and is ready for a fresh launch.
- `vprofile-rmq` remains terminated and is waiting for the custom RabbitMQ AMI.

#### RabbitMQ golden-AMI builder checkpoint
- Temporary builder launched: `vprofile-ami-builder`
  (`i-0b3d1c51c83caab23`).
- Builder placement: `vprofile-pub-1a`, private IP `172.20.1.42`, shared base
  AMI `ami-081b0a6eac00b4f53`, instance type `t2.micro`.
- Builder uses `vprofile-ssm-instance-profile` and a dedicated
  `vprofile-ami-builder-sg` security group with zero inbound rules.
- SSM initially failed with `TargetNotConnected`. Private DNS redirected the
  public-subnet builder to the private SSM VPC endpoints, but `ssm-ep-sg`
  trusted only the private subnet.
- Fix applied: added inbound TCP 443 to `ssm-ep-sg`, sourced from
  `vprofile-ami-builder-sg`, then rebooted the builder. SSM registration became
  `Online`.
- Imported RabbitMQ signing keys and added RabbitMQ's official signed
  repositories for Erlang and RabbitMQ.
- Installed:
  - `erlang-27.3.4.16-1.el9`
  - `rabbitmq-server-4.3.5-1.el8`
- `logrotate` was already installed.
- RabbitMQ was enabled and started with:
  `systemctl enable --now rabbitmq-server`.
- Verification passed:
  - `systemctl status rabbitmq-server` reported `active (running)`.
  - `rabbitmq-diagnostics ping` returned `Ping succeeded`.
- Builder stopped, then AMI created: `ami-0b553971033842a1d`
  ("vprofile-rmq-golden-ami"), confirmed `available`.
- Builder instance `i-0b3d1c51c83caab23` terminated after AMI verification —
  no longer needed.

## Incident #1 — Resolved
### Symptom
MariaDB, Memcached, and RabbitMQ were not installed after their first launch.

### Root Cause
The private subnet had no public-internet route, so package installation could
not reach the required sources.

### Resolution
Created an S3 Gateway Endpoint. Amazon Linux repository traffic is S3-backed, so
MariaDB installation succeeded after relaunch.

## Incident #2 — Resolved and Verified
### Symptom
MariaDB installed, but the schema import failed.

### Root Cause
`mysql.sh` attempted to clone the VProfile repository from GitHub. GitHub is
public-internet traffic, not S3 traffic, so the private instance could not reach it.

### Resolution
1. Created `vprofile-db-role` with `AmazonSSMManagedInstanceCore`.
2. Added a narrowly scoped S3 read policy for:
   `arn:aws:s3:::vprofile-artifacts-747336059892/db/*`.
3. Created `vprofile-db-instance-profile`.
4. Changed `mysql.sh` to download `accountsdb.sql` from S3.
5. Relaunched and verified MariaDB, the schema import, and the required tables.

## Incident #3 — Open: RabbitMQ Packaging Gap
### Symptom
`yum install -y erlang rabbitmq-server` failed because neither package existed in
Amazon Linux 2023 default repositories.

### Root Cause
This was not a networking problem. The required packages simply are not supplied
by the default Amazon Linux 2023 repositories.

### Options Considered
1. NAT Gateway — simple, but introduces recurring cost and reverses the no-NAT
   design decision.
2. Self-hosted repository in S3 — workable for an air-gapped pattern, but adds
   repository-maintenance scope.
3. Golden AMI — install once on a short-lived public builder, then launch the
   final broker privately from the configured image.

### Decision
Path 3: manually build a golden AMI first, then consider Packer automation later.

This preserves the no-NAT architecture, gives manual understanding before
automation, and avoids runtime RabbitMQ installation on the final private instance.

### Current Status
Resolved for the packaging gap itself: golden AMI `ami-0b553971033842a1d` contains
RabbitMQ and Erlang, confirmed via a live launch of `vprofile-rmq`
(`i-0cbe922280b6da712`) with no userdata/install step needed.

However, this checkpoint was previously recorded as fully verified — including the
VProfile `test` user/permissions — before that step was actually executed. The AMI
was snapshotted with only the default `guest` user present. This was caught by
running `rabbitmqctl list_users` on the launched instance, not by re-reading
`PROGRESS.md`. The `test` user was then created manually on the live instance
(`add_user` / `set_user_tags` / `set_permissions`) and confirmed via
`rabbitmqctl authenticate_user test test` → `Success`. The AMI itself still lacks
this config; see Known Issues. Builder terminated.

## Current State
- `vprofile-db`: terminated. Its S3 schema-download fix was verified.
- `vprofile-mc`: terminated. Its script was reviewed and is ready to relaunch.
- `vprofile-rmq`: running (`i-0cbe922280b6da712`), launched from the golden AMI.
  RabbitMQ verified end-to-end: service healthy, `test` user created and
  authenticated successfully. Fix was applied manually to the live instance, not
  baked into the AMI — see Known Issues.
- `vprofile-ami-builder`: terminated. Its work is preserved in
  `ami-0b553971033842a1d`.
- No EC2 instance is currently running for this project.
- No ALB or NAT Gateway exists.

## Resource Reference
VPC:                     vpc-0e686e7841a60b687
vprofile-pub-1a:         subnet-03510c2b0ab2a8d18
vprofile-pub-1b:         subnet-0416352cf44e6f091
vprofile-priv-1a:        subnet-0981c879b04c46232
vprofile-igw:            igw-00e59563b9ad5ee7d
vprofile-pub-rt:         rtb-05958a20e0736100d
main-rt:                 rtb-08049511223df625b
alb-sg:                  sg-04dcbc6c37a127962
app-sg:                  sg-0eef3641caa12a1ba
db-sg:                   sg-059fb90eac508a949
mc-sg:                   sg-0d5c620face437bfc
rmq-sg:                  sg-0ba3baa7a8a231777
ssm-ep-sg:               sg-05bfef82dda3ad55b
vprofile-ami-builder-sg: sg-0e3792520437ec10d
SSM endpoint:            vpce-0615acc9dd367d915
SSM Messages endpoint:   vpce-00ae7b1e49d5deed5
EC2 Messages endpoint:   vpce-01766d5b403a3b8f7
S3 endpoint:             vpce-0540d3b05281c8189
Shared IAM role:         vprofile-ssm-role
Shared instance profile: vprofile-ssm-instance-profile
DB IAM role:             vprofile-db-role
DB instance profile:     vprofile-db-instance-profile
S3 bucket:               vprofile-artifacts-747336059892
Base AMI:                ami-081b0a6eac00b4f53

vprofile-db:             i-0d83ac1dfc99bd53c — terminated
vprofile-mc:             i-05681771c7c2a39a2 — terminated
vprofile-rmq:            i-0cbe922280b6da712 — running
vprofile-ami-builder:    i-0b3d1c51c83caab23 — terminated

Golden AMI (RabbitMQ):   ami-0b553971033842a1d — available

## Key Decisions
- Dedicated VPC instead of the default VPC for isolation and networking practice.
- One security group per service for least privilege and easier auditing.
- SSM Session Manager instead of a bastion host or open SSH.
- No NAT Gateway to avoid recurring hourly cost.
- S3 Gateway Endpoint for private S3 access at no endpoint hourly cost.
- No Route 53 hosted zone; use the ALB DNS name later to avoid unnecessary cost.
- Private subnet placed in the same AZ as public subnet 1a to minimize cross-AZ
  data-transfer cost.
- S3 artifact download instead of GitHub cloning from private instances.
- Per-instance IAM role when permission needs differ.
- Golden AMI for RabbitMQ because Amazon Linux 2023 lacks the required packages
  and the project intentionally avoids a NAT Gateway.
- `t2.micro` retained for builder consistency with existing project instances.

## Known Issues
- Database credentials are currently hardcoded in `mysql.sh` (`admin123`).
  Later decide whether to move them to Secrets Manager or SSM Parameter Store, or
  document this as a deliberate portfolio simplification.
- RabbitMQ user `test` (password `test`, from the reference Vagrant provisioning) is granted
  full admin rights with unrestricted configure/write/read permissions (`.*`/`.*`/`.*`) on the
  default vhost `/`. Same category of simplification as the hardcoded MariaDB credentials above —
  fine for a portfolio-scale single-app broker, but not least-privilege. Later decide whether to
  scope permissions down or document as a deliberate portfolio simplification, same as the DB
  credentials decision.
- CloudTrail showed unexplained EKS/Auto Scaling `RunInstances` events on
  August 15–16. No live resources were found and no active cost was identified.
- Golden AMI ami-0b553971033842a1d does not include the VProfile test RabbitMQ user — it was missed
  before the AMI snapshot. The live vprofile-rmq instance has since been patched manually
  (add_user/set_user_tags/set_permissions, verified via authenticate_user).
  The AMI itself still lacks this config and will be corrected when the Packer template is built.

## Next Step
1. ~~Launch `vprofile-rmq` privately from the custom AMI~~ — done:
   `i-0cbe922280b6da712`.
2. ~~Verify RabbitMQ end-to-end~~ — done: service healthy, `test` user created,
   tagged, permissioned, and authenticated successfully.
3. Relaunch and verify Memcached.
4. Relaunch and verify MariaDB.
5. Close Phase 2, then begin Phase 3: Tomcat deployment.

## Remaining Phases
- Phase 2: finish Incident #3 and verify DB, Memcached, and RabbitMQ.
- Phase 3: Tomcat EC2, build WAR file, and deploy the artifact from S3.
- Phase 4: Application Load Balancer and target group.
- Phase 5: End-to-end validation, documentation, and cleanup.

## Notes
See `NOTES.md` for chronological study notes and session checkpoints.
