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
Phase 2 — Backend EC2s (db verified end-to-end, Incident #2 closed; mc script clean; rmq
blocked on Incident #3 — decision made, not yet implemented). **db's actual running/terminated
status needs re-verification before anything else — see Current State.**

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

### Phase 2 continued
- **vprofile-db relaunched and fully verified** (i-0d83ac1dfc99bd53c, 172.20.3.9): Incident #2
  fix confirmed end-to-end via cloud-init-output.log (S3 download logged at this boot),
  systemctl status (MariaDB active), and SHOW TABLES (accounts.role/user/user_role present).
  Incident #2 is closed.
- **memcache.sh reviewed** — clean, no internet dependency beyond yum (S3-backed repos), no
  changes needed. Not yet relaunched.
- **rabbitmq.sh reviewed** — found a NEW, different blocker (see Incident #3 below). Not a
  repeat of Incident #2's root cause.

## Incident #1 (resolved)
- Symptom: MariaDB, Memcached, RabbitMQ not installed after first launch
- Root cause: Private subnet had no internet route — yum couldn't reach Amazon Linux repos
- Fix: S3 Gateway Endpoint created — confirmed working (MariaDB installed successfully on relaunch)

## Incident #2 (RESOLVED — verified end-to-end)
- Symptom: mysql.sh's yum install succeeded, but schema import failed
- Root cause: script used `git clone https://github.com/.../proton.git` to fetch accountsdb.sql.
  GitHub is public internet — NOT covered by the S3 Gateway Endpoint (S3-only). Private subnet
  still has no route to the general internet.
- Fix — all steps verified complete via direct AWS CLI checks/diagnostics, not assumed:
  1. ✅ `vprofile-db-role` created (2026-09-03T14:15:04Z) with:
     - `AmazonSSMManagedInstanceCore` (AWS managed policy) attached
     - Inline policy `db-s3-read`: `s3:GetObject` scoped to
       `arn:aws:s3:::vprofile-artifacts-747336059892/db/*` only
  2. ✅ `vprofile-db-instance-profile` created (2026-09-03T14:25:14Z), role attached
  3. ✅ `~/aws-lift-and-shift/userdata/mysql.sh` edited — line 14 now reads
     `aws s3 cp s3://vprofile-artifacts-747336059892/db/accountsdb.sql /tmp/accountsdb.sql`,
     no `git clone` reference remains
  4. ✅ **Relaunched and verified end-to-end** — instance i-0d83ac1dfc99bd53c (172.20.3.9),
     launched with vprofile-db-instance-profile and the corrected mysql.sh. Verified via
     cloud-init-output.log (S3 download logged as run on *this* boot), `systemctl status`
     (MariaDB active), and `SHOW TABLES` (accounts.role/user/user_role all present).
     Incident #2 is closed.
- Note: this instance was subsequently targeted for termination at the end of the session —
  see **Current State** for why that's flagged unconfirmed.

## Incident #3 (open — decision made, not yet implemented)
- Symptom (predicted, verified via diagnostics before relaunching): `yum install -y erlang
  rabbitmq-server` in rabbitmq.sh will fail — confirmed via `yum list available` (no matching
  packages) and `dnf repolist all` (no relevant disabled repo) on the AMI.
- Root cause: unlike Incident #2 (right package, wrong network path), these packages are
  simply not in Amazon Linux 2023's default repos at all — needs an additional repo, not just
  a different fetch method.
- Options considered: (1) NAT Gateway — simplest/most standard, reverses earlier no-NAT
  decision, small ongoing cost; (2) self-hosted yum repo in S3 (build on a temp public
  instance, upload with createrepo_c, sync down via existing S3 Gateway Endpoint) — keeps
  no-NAT architecture consistent, more setup, legitimate air-gapped-environment pattern;
  (3) golden AMI via Packer — arguably strongest practice, bakes RabbitMQ in at build time,
  sidesteps runtime internet dependency entirely, introduces a new tool/concept.
- **Decision: Path 2 (self-hosted S3 repo) — approved, not yet implemented.**
- Not yet started: temp public EC2 instance to download+package erlang/rabbitmq-server+deps,
  createrepo_c, upload to s3://vprofile-artifacts-747336059892/rabbitmq-repo/, terminate temp
  instance, edit rabbitmq.sh to sync from S3 + install from local repo, relaunch vprofile-rmq.

## Current State
- **vprofile-db: status uncertain — verify before acting on it.** This session relaunched db
  as i-0d83ac1dfc99bd53c (172.20.3.9) and verified it end-to-end (Incident #2 closed). At the
  end of the session you said "yes please" to terminating it, and the command
  (`aws ec2 terminate-instances --instance-ids i-0d83ac1dfc99bd53c`) was given — but the
  conversation cut off before the output confirming it actually ran was pasted back. **Run a
  read-only `describe-instances` check on that instance ID first thing next session** before
  assuming either running or terminated.
- vprofile-mc, vprofile-rmq: TERMINATED. mc script reviewed and confirmed clean — ready to
  relaunch as-is whenever. rmq is blocked on Incident #3 (Path 2) implementation before it can
  relaunch.
- No ALB, no NAT Gateway, no temporary instances running.

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
vprofile-db:      i-0d83ac1dfc99bd53c (172.20.3.9) — relaunched + verified end-to-end
                  (Incident #2 closed); termination requested at session end, NOT confirmed —
                  re-verify before trusting either state
vprofile-mc:      i-05681771c7c2a39a2 — TERMINATED, needs relaunch (new ID expected); script
                  reviewed and clean
vprofile-rmq:     i-039c3b5c85abb9a11 — TERMINATED, needs relaunch (new ID expected); blocked
                  on Incident #3 implementation

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
- RabbitMQ packaging gap (Incident #3): chose self-hosted S3 yum repo over NAT Gateway or
  golden AMI/Packer — keeps the no-NAT architecture consistent; see Incident #3 for the full
  trade-off analysis

## Known Issues
- DB credentials hardcoded in mysql.sh (`admin123`) — inherited from original script, violates
  the "never hardcode credentials" rule. Needs an explicit decision later: fix via Secrets
  Manager/SSM Parameter Store, or acknowledge as a named simplification in the README.
- ~~memcache.sh and rabbitmq.sh not yet reviewed for the same GitHub-dependency pattern~~ —
  **resolved this session**: memcache.sh reviewed and clean; rabbitmq.sh surfaced a different,
  unrelated blocker, tracked as Incident #3.
- Userdata scripts actually live at `~/aws-lift-and-shift/userdata/`, not `proton/userdata/` —
  earlier documentation had the wrong path; corrected above, worth double-checking no other
  notes still reference the old path.
- Unexplained CloudTrail RunInstances events from EKS/AutoScaling on Aug 15-16 — no live
  resources found (checked: no EKS clusters, no ASGs, no running/pending instances anywhere),
  so not currently costing money, but origin still unexplained. Worth a closer look eventually,
  deliberately deprioritized this session since nothing is actively billing.

## Next Step
0. **State check (read-only, do this first):** confirm whether vprofile-db
   (i-0d83ac1dfc99bd53c) actually terminated, since last session ended before that was
   confirmed:
   `aws ec2 describe-instances --filters "Name=tag:Name,Values=vprofile-db" --query
   "Reservations[].Instances[].[InstanceId,State.Name]" --output table`

Then implement Incident #3 Path 2:
1. Launch temporary public EC2 instance (billable, short-lived — needs approval)
2. Enable appropriate upstream repo (EPEL or RabbitMQ official) on that temp instance only
3. `dnf download --resolve` erlang + rabbitmq-server + dependencies
4. `createrepo_c` over the downloaded packages to build valid repo metadata
5. Upload resulting repo folder to S3 (rabbitmq-repo/ prefix)
6. Terminate temp instance
7. Edit rabbitmq.sh: sync repo from S3, add local .repo file, install from it
8. Relaunch vprofile-rmq, verify end-to-end (same pattern as db: cloud-init log,
   systemctl status, functional check)
9. Relaunch vprofile-mc (script already reviewed, no changes needed)
10. If vprofile-db turns out to still be running, decide whether to leave it or restart it —
    either way, the relaunch is now a known-good, already-verified process
11. Once db/mc/rmq all verified running → close Phase 2 → Phase 3 (Tomcat)

## Remaining Phases
- Phase 2 remaining: re-verify vprofile-db's actual state, implement Incident #3 (Path 2) to
  unblock rmq, then relaunch mc + rmq and verify both end-to-end
- Phase 3: Tomcat EC2, build .war, deploy via S3 (reuse vprofile-artifacts-747336059892,
  likely under an app/ prefix)
- Phase 4: ALB and target group
- Phase 5: Validation, documentation, cleanup

## Notes
NOTES.md updated this session — new entries: winpty applies to `aws ssm start-session` too,
`file://` paramfiles failing in Git Bash, checking a file's actual boot-time provenance vs. its
timestamp, diagnosing a genuinely-missing package vs. a networking problem, and asking what the
field's default approach is before narrowing to project-established patterns.
