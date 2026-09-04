# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is **Project 1 of 5 planned portfolio projects** (+1 optional, GCP). Full roadmap, project
list, grouping rationale, and recommended sequence live in the master prompt's "Portfolio Plan"
appendix — paste the master prompt alongside this file to see the full context; not duplicated
here to avoid two sources of truth.

## Current Phase
Phase 2 — Backend EC2s. Golden AMI builder (Incident #3, Path 3) launched and running.
Next: connect via SSM, install erlang + rabbitmq-server.

## Completed Work

### Phase 0 — Prerequisites & Safety Setup ✅
- AWS CLI configured (IAM user: gitops-terraform, account: 747336059892, region: us-east-1)
- Maven 3.9.16 installed
- Billing alerts set in CloudWatch (BillingAlert-5USD and BillingAlarm)
- VProfile repo forked (dmncfrncsc/proton) and cloned into ~/aws-lift-and-shift/proton

### Phase 1 — Network & Security Foundation ✅
- VPC: vprofile-vpc (172.20.0.0/16) — vpc-0e686e7841a60b687, DNS hostnames enabled
- Subnets:
  * vprofile-pub-1a — subnet-03510c2b0ab2a8d18 — 172.20.1.0/24 — us-east-1a
  * vprofile-pub-1b — subnet-0416352cf44e6f091 — 172.20.2.0/24 — us-east-1b
  * vprofile-priv-1a — subnet-0981c879b04c46232 — 172.20.3.0/24 — us-east-1a
- Internet Gateway: vprofile-igw — igw-00e59563b9ad5ee7d
- Public route table: vprofile-pub-rt — rtb-05958a20e0736100d (0.0.0.0/0 → IGW, both public subnets)
- Auto-assign public IP enabled on pub-1a and pub-1b
- Security groups: alb-sg, app-sg, db-sg, mc-sg, rmq-sg, ssm-ep-sg (see Resource Reference)
- SSM VPC Interface Endpoints (ssm, ssmmessages, ec2messages) — all available

### Phase 2 — Backend EC2s 🔄
- **Userdata script location correction:** the actual userdata used for EC2 launches lives at
  `~/aws-lift-and-shift/userdata/` (outside the forked repo), NOT under `proton/userdata/` as
  earlier notes assumed. The scripts under `proton/vagrant/Automated_provisioning_*/mysql.sh`
  are the original Vagrant-provisioning scripts and are unrelated/unused for AWS EC2 userdata.
- userdata/memcache.sh, rabbitmq.sh — present locally, reviewed (see below)
- IAM instance profile: vprofile-ssm-instance-profile (role: vprofile-ssm-role) — used by mc/rmq
- S3 Gateway Endpoint: vpce-0540d3b05281c8189 (free) — confirmed attached to main route table
  (rtb-08049511223df625b); confirmed private subnet uses main route table (no explicit association)
- Cleaned up accidental duplicate IAM role (vprofile-ec2-ssm-role) created in error this session
- S3 bucket created: vprofile-artifacts-747336059892 (us-east-1, all public access blocked)
  - db/accountsdb.sql uploaded (3829 bytes) — replaces the git-clone dependency
- **vprofile-db relaunched and fully verified** (i-0d83ac1dfc99bd53c, 172.20.3.9): Incident #2
  fix confirmed end-to-end via cloud-init-output.log (S3 download logged at this boot),
  systemctl status (MariaDB active), and SHOW TABLES (accounts.role/user/user_role present).
  Incident #2 is closed.
- **memcache.sh reviewed** — clean, no internet dependency beyond yum (S3-backed repos), no
  changes needed. Not yet relaunched.
- **rabbitmq.sh reviewed** — surfaced Incident #3 (see below).
- **db state re-verified**: confirmed `terminated` via read-only `describe-instances`. The
  termination command from the previous session did go through — no vprofile-db instance
  currently exists.

## Incident #1 (resolved)
- Symptom: MariaDB, Memcached, RabbitMQ not installed after first launch
- Root cause: Private subnet had no internet route — yum couldn't reach Amazon Linux repos
- Fix: S3 Gateway Endpoint created — confirmed working (MariaDB installed successfully on relaunch)

## Incident #2 (RESOLVED — verified end-to-end)
- Symptom: mysql.sh's yum install succeeded, but schema import failed
- Root cause: script used `git clone https://github.com/.../proton.git` to fetch accountsdb.sql.
  GitHub is public internet — NOT covered by the S3 Gateway Endpoint (S3-only).
- Fix — verified end-to-end:
  1. `vprofile-db-role` created with `AmazonSSMManagedInstanceCore` + inline policy `db-s3-read`
     (`s3:GetObject` scoped to `arn:aws:s3:::vprofile-artifacts-747336059892/db/*` only)
  2. `vprofile-db-instance-profile` created, role attached
  3. `mysql.sh` line 14 changed to `aws s3 cp s3://.../db/accountsdb.sql /tmp/accountsdb.sql`
  4. Relaunched and verified end-to-end on i-0d83ac1dfc99bd53c. Incident #2 is closed.
- That instance was subsequently terminated (see db state re-verification above) — the fix
  itself remains verified good; relaunching db again is just re-running a known-good process.

## Incident #3 (open — execution in progress)
- Symptom: `yum install -y erlang rabbitmq-server` in rabbitmq.sh fails — confirmed via
  `yum list available` (no matching packages) and `dnf repolist all` (no relevant disabled
  repo) on the AMI.
- Root cause: unlike Incident #2 (right package, wrong network path), these packages simply
  aren't in Amazon Linux 2023's default repos at all — needs an additional package source, not
  just a different fetch method.
- Options considered: (1) NAT Gateway — simplest, reverses the no-NAT decision, small ongoing
  cost; (2) self-hosted yum repo in S3 — keeps no-NAT architecture consistent, legitimate
  air-gapped-environment pattern; (3) golden AMI (Packer later) — bakes RabbitMQ in at build
  time, sidesteps runtime internet dependency entirely.
- **Decision: Path 3 — golden AMI, built manually first, Packer template as a later automation
  step. Confirmed.** (Originally approved as Path 2 self-hosted S3 repo, revisited and switched
  mid-project.) Reasoning: building the golden AMI manually first means the eventual Packer
  template uses commands already understood by hand — this project's own "understand before
  automating" principle applied to the automation tool itself, not just the app configuration.
- Plan (nothing executed yet):
  1. Launch temp public EC2 instance (billable, short-lived) — SSM only, no SSH
  2. Connect via SSM, manually install + configure erlang and rabbitmq-server, start/enable
     the service, verify it's running
  3. **Stop** the instance (not terminate) — AMI creation is cleaner from a stopped instance
  4. Create AMI from it (`aws ec2 create-image`) — the actual "golden image" artifact
  5. Terminate the temp instance once the AMI is confirmed `available`
  6. Launch vprofile-rmq in the private subnet from the new custom AMI (no userdata needed —
     RabbitMQ is already baked in)
  7. Verify vprofile-rmq end-to-end (cloud-init log, systemctl status, functional check)
    
- **Execution started:** Temp builder instance i-0b3d1c51c83caab23 — RUNNING (launched
  vprofile-pub-1a, base AMI ami-081b0a6eac00b4f53, t2.micro, vprofile-ssm-instance-profile,
  public IP). New SG: vprofile-ami-builder-sg — sg-0e3792520437ec10d — zero inbound rules.
  Not yet done: connect via SSM, install/configure erlang + rabbitmq-server, verify service,
  stop instance, create AMI, terminate builder, relaunch vprofile-rmq from new AMI.
  
- **Launch parameters for the temp builder — confirmed, ready to execute:**
  | Parameter | Choice | Why |
  |---|---|---|
  | Subnet | vprofile-pub-1a | Needs a public IP to reach EPEL/RabbitMQ's repos — deliberate exception to the private-by-default pattern; the AMI and relaunched rmq end up private again |
  | AMI | ami-081b0a6eac00b4f53 | Same base image used for db/mc/rmq — one golden AMI lineage, not two |
  | Instance type | t2.micro | Confirmed — consistency with every other instance in the project |
  | IAM instance profile | vprofile-ssm-instance-profile (existing) | SSM access without opening port 22; doesn't need db's S3-read permission since this instance never touches the S3 bucket |
  | Security group | New, zero inbound rules, default outbound | SSM connects outbound only — no inbound rule is needed at all, not just no port 22. Dedicated SG keeps "one SG per service" intact and makes cleanup unambiguous |

## Current State
- **vprofile-db: confirmed TERMINATED** (i-0d83ac1dfc99bd53c). Incident #2 fix verified good —
  relaunching is a known-good, already-proven process whenever we get to it.
- **vprofile-mc: TERMINATED.** Script reviewed and confirmed clean — ready to relaunch as-is.
- **vprofile-rmq: TERMINATED.** Blocked on Incident #3 (Path 3, golden AMI) — builder instance
  launched and running (see vprofile-ami-builder above); install/verify erlang+rabbitmq-server
  not yet done.
- vprofile-ami-builder (i-0b3d1c51c83caab23): RUNNING — billable, temporary, delete after AMI
  creation confirmed available

## Resource Reference
VPC:              vpc-0e686e7841a60b687 (172.20.0.0/16)
vprofile-pub-1a:  subnet-03510c2b0ab2a8d18
vprofile-pub-1b:  subnet-0416352cf44e6f091
vprofile-priv-1a: subnet-0981c879b04c46232
vprofile-igw:     igw-00e59563b9ad5ee7d
vprofile-pub-rt:  rtb-05958a20e0736100d
main-rt:          rtb-08049511223df625b (private subnet uses this — Main: True, no explicit assoc)
alb-sg:           sg-04dcbc6c37a127962
app-sg:           sg-0eef3641caa12a1ba
db-sg:            sg-059fb90eac508a949
mc-sg:            sg-0d5c620face437bfc
rmq-sg:           sg-0ba3baa7a8a231777
ssm-ep-sg:        sg-05bfef82dda3ad55b
SSM endpoint:     vpce-0615acc9dd367d915
SSM Messages:     vpce-00ae7b1e49d5deed5
EC2 Messages:     vpce-01766d5b403a3b8f7
S3 endpoint:      vpce-0540d3b05281c8189
IAM role (shared, mc/rmq): vprofile-ssm-role
IAM instance profile (shared): vprofile-ssm-instance-profile
IAM role (db):              vprofile-db-role
IAM instance profile (db):  vprofile-db-instance-profile
S3 bucket:        vprofile-artifacts-747336059892 (us-east-1, public access blocked)
  - db/accountsdb.sql
Base AMI (reused project-wide): ami-081b0a6eac00b4f53
vprofile-db:      i-0d83ac1dfc99bd53c — TERMINATED (confirmed); Incident #2 fix verified good,
                  needs relaunch
vprofile-mc:      i-05681771c7c2a39a2 — TERMINATED, needs relaunch; script reviewed and clean
vprofile-rmq:     i-039c3b5c85abb9a11 — TERMINATED, needs relaunch; blocked on Incident #3
                  (Path 3 confirmed, launch parameters set, execution not started)

## Key Decisions
- Dedicated VPC over default VPC (isolation, teaches networking fundamentals)
- One security group per service (least privilege, easier auditing)
- SSM Session Manager instead of bastion host (no extra EC2 cost, no open port 22)
- No NAT Gateway (saves ~$0.045/hr — SSM handles private EC2 access)
- S3 Gateway Endpoint instead of NAT Gateway for yum access (free vs $0.045/hr)
- No Route 53 hosted zone (saves $0.50/mo — will use ALB DNS directly)
- Private subnet in same AZ as pub-1a (minimizes cross-AZ data transfer)
- Pull deployment SQL artifact from S3 instead of git-cloning the app repo in userdata
- Per-instance IAM roles when permission needs diverge — shared vprofile-ssm-role kept for
  mc/rmq (identical needs), separate vprofile-db-role for db (needs S3 read, they don't)
- Full migration tooling (Flyway/Liquibase) considered and rejected as scope creep for one
  static schema file — noted for README's "what I'd change for real production"
- **RabbitMQ packaging gap (Incident #3) — confirmed:** switched from the self-hosted S3 yum
  repo (Path 2) to a golden AMI (Path 3), built manually before any Packer automation, reusing
  the project's existing base AMI. Reasoning captured in Incident #3 above — good ADR-lite
  candidate for the README later.
- **Golden-AMI builder instance type: t2.micro** — chosen over t3.micro purely for consistency
  with every other instance in the project (db, mc, rmq have all used t2.micro); no functional
  requirement pulled this toward either family specifically.

## Known Issues
- DB credentials hardcoded in mysql.sh (`admin123`) — inherited from original script, violates
  the "never hardcode credentials" rule. Needs an explicit decision later: fix via Secrets
  Manager/SSM Parameter Store, or acknowledge as a named simplification in the README.
- Unexplained CloudTrail RunInstances events from EKS/AutoScaling on Aug 15-16 — no live
  resources found, not currently costing money, origin still unexplained. Deliberately
  deprioritized, nothing actively billing.

## Next Step
1. Connect via SSM, manually install + configure erlang/rabbitmq-server, verify service running.
2.  Stop the temp instance (not terminate) for clean AMI creation.
3. Create the custom AMI (`aws ec2 create-image`), wait for `available`.
4. Terminate the temp instance once the AMI is confirmed available.
5. Relaunch vprofile-rmq in the private subnet from the new custom AMI (no userdata needed).
6. Verify vprofile-rmq end-to-end (cloud-init log, systemctl status, functional check).
7. Relaunch vprofile-mc (script already reviewed, no changes needed) and verify.
8. Relaunch vprofile-db (known-good Incident #2 process) and verify.
9. Once db/mc/rmq are all verified running → close Phase 2 → Phase 3 (Tomcat).
10. *(Later, optional)* Wrap the manual golden-AMI steps in a Packer template — the original
    motivation for choosing Path 3 over Path 2; a natural fit as a Phase 2 addendum or folded
    into Project 2's Terraform/Ansible scope discussion.

## Remaining Phases
- Phase 2 remaining: implement Incident #3 (Path 3), then relaunch db + mc + rmq and verify
  all three end-to-end
- Phase 3: Tomcat EC2, build .war, deploy via S3 (reuse vprofile-artifacts-747336059892,
  likely under an app/ prefix)
- Phase 4: ALB and target group
- Phase 5: Validation, documentation, cleanup

## Notes
See NOTES.md for this session's entries: golden AMI concept, stopped-vs-running AMI creation,
t2 vs t3 instance families, and why an SSM-managed instance needs zero inbound security-group
rules.
