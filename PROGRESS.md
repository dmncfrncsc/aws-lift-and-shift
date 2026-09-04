# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is **Project 1 of 5 planned portfolio projects** (+1 optional, GCP). Full roadmap, project
list, grouping rationale, and recommended sequence now live in the master prompt's "Portfolio
Plan" appendix (added 2026-09-04) — paste the master prompt alongside this file to see the full
context; not duplicated here to avoid two sources of truth.

## Current Phase
Phase 2 — Backend EC2s (in progress — Incident #2 fix implemented, not yet relaunch-tested)

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

### Phase 2 — Backend EC2s (in progress) 🔄
- **Userdata script location correction:** the actual userdata used for EC2 launches lives at
  `~/aws-lift-and-shift/userdata/` (outside the forked repo), NOT under `proton/userdata/` as
  earlier notes assumed. The scripts under `proton/vagrant/Automated_provisioning_*/mysql.sh`
  are the original Vagrant-provisioning scripts and are unrelated/unused for AWS EC2 userdata.
  Update any future references accordingly.
- userdata/memcache.sh, rabbitmq.sh — present locally, not yet reviewed for the git-clone issue
- IAM instance profile: vprofile-ssm-instance-profile (role: vprofile-ssm-role) — used by mc/rmq
- S3 Gateway Endpoint: vpce-0540d3b05281c8189 (free) — confirmed attached to main route table
  (rtb-08049511223df625b); confirmed private subnet uses main route table (no explicit association)
- Cleaned up accidental duplicate IAM role (vprofile-ec2-ssm-role) created in error this session
- vprofile-db: old instance (i-08b194932cee8902b) terminated, relaunched as i-0d66d67e5182ab83b,
  then **terminated again** as part of the Incident #2 fix (see below) — verified `terminated`
  via `describe-instances`. No vprofile-db instance currently exists.
- vprofile-mc (i-05681771c7c2a39a2) and vprofile-rmq (i-039c3b5c85abb9a11) — still TERMINATED.
  Their userdata scripts have NOT yet been checked for the same GitHub-dependency issue as mysql.sh.
- S3 bucket created: vprofile-artifacts-747336059892 (us-east-1, all public access blocked)
  - db/accountsdb.sql uploaded (3829 bytes) — replaces the git-clone dependency

## Incident #1 (resolved)
- Symptom: MariaDB, Memcached, RabbitMQ not installed after first launch
- Root cause: Private subnet had no internet route — yum couldn't reach Amazon Linux repos
- Fix: S3 Gateway Endpoint created — confirmed working (MariaDB installed successfully on relaunch)

## Incident #2 (fix implemented, not yet relaunch-tested)
- Symptom: mysql.sh's yum install succeeded, but schema import failed
- Root cause: script used `git clone https://github.com/.../proton.git` to fetch accountsdb.sql.
  GitHub is public internet — NOT covered by the S3 Gateway Endpoint (S3-only). Private subnet
  still has no route to the general internet.
- Fix — all steps below **verified complete via direct AWS CLI checks**, not assumed:
  1. ✅ `vprofile-db-role` created (2026-09-03T14:15:04Z) with:
     - `AmazonSSMManagedInstanceCore` (AWS managed policy) attached
     - Inline policy `db-s3-read`: `s3:GetObject` scoped to
       `arn:aws:s3:::vprofile-artifacts-747336059892/db/*` only — confirmed via
       `get-role-policy`, matches the least-privilege plan exactly (not `s3:*`, not
       whole-bucket ARN)
  2. ✅ `vprofile-db-instance-profile` created (2026-09-03T14:25:14Z), role attached — confirmed
     via `get-instance-profile`
  3. ✅ `~/aws-lift-and-shift/userdata/mysql.sh` edited — confirmed via grep: line 14 now reads
     `aws s3 cp s3://vprofile-artifacts-747336059892/db/accountsdb.sql /tmp/accountsdb.sql`,
     no `git clone` reference remains in the file
  4. ❌ **NOT yet done:** terminate-and-relaunch vprofile-db with the new instance profile +
     fixed mysql.sh, to prove the full fix end-to-end. The instance was terminated as part of
     cleanup but the relaunch (the actual test) has not happened yet.

## Current State
- **No EC2 instances running anywhere in the account** — confirmed via account-wide
  `describe-instances` filtered on `running` state, empty result. Nothing billable from
  compute right now.
- vprofile-db: TERMINATED — role, instance profile, and script fix are all in place; relaunch
  is the next actual step
- vprofile-mc, vprofile-rmq: TERMINATED — need relaunch, and their userdata scripts still need
  the same git-clone review mysql.sh got
- No ALB running

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
IAM role (db):              vprofile-db-role — CREATED, fully configured (see Incident #2)
IAM instance profile (db):  vprofile-db-instance-profile — CREATED
S3 bucket:        vprofile-artifacts-747336059892 (us-east-1, public access blocked)
  - db/accountsdb.sql
vprofile-db:      TERMINATED — no current instance ID; relaunch pending
vprofile-mc:      i-05681771c7c2a39a2 — TERMINATED, needs relaunch (new ID expected)
vprofile-rmq:     i-039c3b5c85abb9a11 — TERMINATED, needs relaunch (new ID expected)

## Key Decisions
- Dedicated VPC over default VPC (isolation, teaches networking fundamentals)
- One security group per service (least privilege, easier auditing)
- SSM Session Manager instead of bastion host (no extra EC2 cost, no open port 22)
- No NAT Gateway (saves ~$0.045/hr — SSM handles private EC2 access)
- S3 Gateway Endpoint instead of NAT Gateway for yum access (free vs $0.045/hr)
- No Route 53 hosted zone (saves $0.50/mo — will use ALB DNS directly)
- Private subnet in same AZ as pub-1a (minimizes cross-AZ data transfer)
- Pull deployment SQL artifact from S3 instead of git-cloning the app repo in userdata —
  avoids public internet dependency from private subnet, reuses existing S3 Gateway Endpoint,
  mirrors a legitimate production artifact-store pattern at portfolio scale
- Per-instance IAM roles when permission needs diverge — shared vprofile-ssm-role kept for
  mc/rmq (identical needs), separate vprofile-db-role for db (needs S3 read, they don't)
- Full migration tooling (Flyway/Liquibase) considered and rejected as scope creep for one
  static schema file — noted for README's "what I'd change for real production"

## Known Issues
- DB credentials hardcoded in mysql.sh (`admin123`) — inherited from original script, violates
  the "never hardcode credentials" rule. Needs an explicit decision later: fix via Secrets
  Manager/SSM Parameter Store, or acknowledge as a named simplification in the README.
- memcache.sh and rabbitmq.sh not yet reviewed for the same GitHub-dependency pattern found
  in mysql.sh — check before relaunching those two.
- Userdata scripts actually live at `~/aws-lift-and-shift/userdata/`, not `proton/userdata/` —
  earlier documentation had the wrong path; corrected above, worth double-checking no other
  notes still reference the old path.

## Next Step
Resume Incident #2 fix — role, instance profile, and script edit are done; only the proof step
remains:
1. Terminate-and-relaunch vprofile-db using `vprofile-db-instance-profile` and the corrected
   mysql.sh, to verify the full S3-based schema import works end-to-end (clean full-userdata
   test, per the original plan)
2. Verify schema import succeeded (check MariaDB tables via SSM session)
3. Review memcache.sh and rabbitmq.sh for the same git-clone/GitHub-dependency issue before
   relaunching those two
4. Once all three backend EC2s verified working, close out Phase 2 → Phase 3 (Tomcat)

## Remaining Phases
- Phase 2 remaining: relaunch/verify vprofile-db with the fix, review + relaunch mc/rmq
- Phase 3: Tomcat EC2, build .war, deploy via S3 (reuse vprofile-artifacts-747336059892,
  likely under an app/ prefix)
- Phase 4: ALB and target group
- Phase 5: Validation, documentation, cleanup

## Notes
NOTES.md is maintained incrementally at every checkpoint. No new concepts were introduced in
this shutdown-verification session — it was pure state confirmation (reading, not learning),
so no NOTES.md update needed for this checkpoint.
