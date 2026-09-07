# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is Project 1 of 5 planned portfolio projects (+1 optional GCP project). The
full roadmap and project rationale live in the master prompt; this file records
only the state of this project.

## Current Phase
Phase 2 cleanup — Secrets Manager migration — IN PROGRESS (blocked on networking issue).
Not yet in Phase 3.

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

### Phase 2 — Backend EC2s ✅
- Actual AWS userdata scripts live in `~/aws-lift-and-shift/userdata/`, outside
  the forked VProfile repository.
- Shared IAM role: `vprofile-ssm-role`.
- Shared instance profile for Memcached and RabbitMQ:
  `vprofile-ssm-instance-profile`.
- S3 bucket created: `vprofile-artifacts-747336059892`, with all public access
  blocked.
- `db/accountsdb.sql` uploaded to the bucket.

#### RabbitMQ — verified ✅
- Launched from golden AMI `ami-0b553971033842a1d` into
  `subnet-0981c879b04c46232` (private), using `rmq-sg` (`sg-0ba3baa7a8a231777`)
  and `vprofile-ssm-instance-profile`. No userdata needed.
- Instance: `vprofile-rmq` (`i-0cbe922280b6da712`), running.
- `systemctl status rabbitmq-server` → `active (running)`.
- `rabbitmq-diagnostics ping` → `Ping succeeded`.
- The golden AMI was snapshotted with only the default `guest` user present —
  the VProfile `test` user was never actually created before the AMI build,
  despite being previously (incorrectly) recorded as done. Caught via
  `rabbitmqctl list_users` on this launched instance, not by re-reading
  `PROGRESS.md`.
- Fix applied manually on the live instance:
  `add_user test test` → `set_user_tags test administrator` →
  `set_permissions -p / test ".*" ".*" ".*"`.
- Verified: `rabbitmqctl authenticate_user test test` → `Success`.
- The AMI itself still lacks this config — see Known Issues.

#### Memcached — verified ✅
- Launched from base AMI `ami-081b0a6eac00b4f53` into
  `subnet-0981c879b04c46232` (private), using `mc-sg` (`sg-0d5c620face437bfc`)
  and `vprofile-ssm-instance-profile`.
- Instance: `vprofile-mc` (`i-0ea6c857a80a4e02d`), running.
- `userdata/memcache.sh` ran cleanly (confirmed via `cloud-init-output.log`,
  no errors).
- `systemctl status memcached` → `active (running)`.
- `ss -tlnp | grep 11211` confirmed listening on `0.0.0.0:11211` (not
  `127.0.0.1`), confirming the userdata's bind-address fix
  (`sed -i 's/127.0.0.1/0.0.0.0/g' /etc/sysconfig/memcached`) took effect.
- `mc-sg` restricts port 11211 to `app-sg` only — this SG rule is the actual
  security boundary, since Memcached itself has no built-in authentication.

#### MariaDB — verified ✅
- Launched from base AMI `ami-081b0a6eac00b4f53` into
  `subnet-0981c879b04c46232` (private), using `db-sg` (`sg-059fb90eac508a949`)
  and the dedicated `vprofile-db-instance-profile` (not the shared SSM
  profile — this instance alone needs S3 read access for the schema file).
- Instance: `vprofile-db` (`i-0d5f4c4b3a689042a`), running.
- `userdata/mysql.sh` ran cleanly (confirmed via `cloud-init-output.log`,
  no errors); this is the Incident #2-fixed version using S3 download instead
  of GitHub clone.
- `systemctl status mariadb` → `active (running)`.
- `mysql -u admin -padmin123 -e "SHOW DATABASES; USE accounts; SHOW TABLES;"`
  confirmed the `accounts` database exists with tables `role`, `user`,
  `user_role` — the actual schema-import step that failed in Incident #2 is
  now confirmed working on this fresh launch.

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
5. Relaunched and verified MariaDB, the schema import, and the required tables
   (confirmed again on the current `vprofile-db` instance).

## Incident #3 — Resolved: RabbitMQ Packaging Gap
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
- Old instances `vprofile-db` (i-0d5f4c4b3a689042a), `vprofile-mc` (i-0ea6c857a80a4e02d),
  `vprofile-rmq` (i-0cbe922280b6da712) are all STOPPED. This happened on 2026-09-05
  (confirmed via CloudTrail), NOT during this session, and was previously undocumented —
  PROGRESS.md incorrectly still said "running." Cause of the Sep 5 stop events not yet
  investigated; low priority since instances are intact and easily restartable.
- NEW `vprofile-db` instance launched this session: i-01ae6e334e08de812, running,
  using updated mysql.sh with Secrets Manager integration. **However, its userdata
  is STUCK/incomplete** — cloud-init hung indefinitely on the `aws secretsmanager
  get-secret-value` call (see Known Issues). MariaDB/schema setup did NOT complete.
  Do not treat this instance as verified/working yet.
- RabbitMQ golden AMI rebuild: NOT STARTED. Blocked behind resolving the Secrets
  Manager connectivity issue first, since the rebuild will hit the same problem.

## Secrets Manager Migration (in progress this session)
- Two secrets created, values unchanged from before (deliberate — chose to relocate
  credentials, not rotate them):
  - `vprofile/db/admin-password` (value: admin123)
    ARN: arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/db/admin-password-9mjRxL
  - `vprofile/rmq/test-password` (value: test)
    ARN: arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/rmq/test-password-onPKEB
- New IAM role + instance profile: `vprofile-rmq-role` / `vprofile-rmq-instance-profile`
  (RabbitMQ previously had no dedicated role — rode on the shared SSM profile). Has
  AmazonSSMManagedInstanceCore + inline policy `vprofile-rmq-secret-read` (scoped to
  its own secret ARN only).
- `vprofile-db-role` (existing) got new inline policy `vprofile-db-secret-read`
  (scoped to its own secret ARN only), alongside its existing `db-s3-read` policy.
- `userdata/mysql.sh` updated: fetches DB_PASS from Secrets Manager at boot instead
  of hardcoding admin123. All mysql/mysqladmin calls now use $DB_PASS.
- `userdata/rabbitmq.sh` rewritten: this file is NOT live userdata (RabbitMQ uses a
  golden-AMI pattern, no boot-time script runs). Rewritten as an accurate build-reference
  doc for the next AMI rebuild — removed the actually-nonfunctional `yum install
  erlang rabbitmq-server` line (fails per Incident #3), added a header clarifying its
  real purpose, and updated `add_user` to pull RMQ_PASS from Secrets Manager.
- ADR-lite decision (not yet written to a formal decision log, capture here for now):
  chose Secrets Manager over Parameter Store despite near-zero cost difference (~$1/mo),
  because Secrets Manager is the correct category fit for credentials (vs. Parameter
  Store's config-focused design) even though rotation — its main differentiator — isn't
  used yet. Kept current password values as-is rather than rotating, since Option A
  (full clean relaunch) made rotation low-risk but out of today's approved scope.


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

vprofile-db:             i-0d5f4c4b3a689042a — running
vprofile-mc:             i-0ea6c857a80a4e02d — running
vprofile-rmq:            i-0cbe922280b6da712 — running
vprofile-ami-builder:    i-0b3d1c51c83caab23 — terminated

Golden AMI (RabbitMQ):   ami-0b553971033842a1d — available

DB:  arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/db/admin-password-9mjRxL
RMQ: arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/rmq/test-password-onPKEB

vprofile-secretsmgr-ep-sg:  sg-0b61cd7e69844f147
Secrets Manager endpoint:   vpce-0ebdbcb485fe2ea67
vprofile-rmq-role:          (new)
vprofile-rmq-instance-profile: (new)
vprofile-db (NEW, unverified): i-01ae6e334e08de812 — running, userdata incomplete
vprofile-db (OLD):           i-0d5f4c4b3a689042a — stopped, do not terminate yet
vprofile-mc:                 i-0ea6c857a80a4e02d — stopped
vprofile-rmq (OLD):          i-0cbe922280b6da712 — stopped

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
- `t2.micro` retained across all instances for consistency.
- Deferred Secrets Manager / SSM Parameter Store migration for DB and RabbitMQ
  credentials rather than folding it into this relaunch — treated as a
  deliberate, separately-scoped Phase 2 cleanup task rather than scope creep
  into an already-proven relaunch.

## Known Issues
- Database credentials are currently hardcoded in `mysql.sh` (`admin123`).
  Flagged as a deliberate portfolio simplification for now; planned follow-up:
  migrate to Secrets Manager or SSM Parameter Store as a Phase 2 cleanup task.
- RabbitMQ user `test` (password `test`, from the reference Vagrant provisioning) is granted
  full admin rights with unrestricted configure/write/read permissions (`.*`/`.*`/`.*`) on the
  default vhost `/`. Same category of simplification as the hardcoded MariaDB credentials above —
  fine for a portfolio-scale single-app broker, but not least-privilege. Same planned follow-up
  as the DB credentials above.
- CloudTrail showed unexplained EKS/Auto Scaling `RunInstances` events on
  August 15–16. No live resources were found and no active cost was identified.
- Golden AMI ami-0b553971033842a1d does not include the VProfile test RabbitMQ user — it was missed
  before the AMI snapshot. The live vprofile-rmq instance has since been patched manually
  (add_user/set_user_tags/set_permissions, verified via authenticate_user).
  The AMI itself still lacks this config and will be corrected when the Packer template is built.
- **BLOCKING**: Private-subnet instances (db, and future rmq) cannot reach AWS
  Secrets Manager despite: correct IAM (confirmed working — S3 fetch from the same
  role succeeds), a newly-created Secrets Manager VPC Interface Endpoint
  (`vpce-0ebdbcb485fe2ea67`, state `available`, private DNS enabled, correct subnet
  `subnet-0981c879b04c46232`), a new security group (`vprofile-secretsmgr-ep-sg`,
  `sg-0b61cd7e69844f147`) with inbound 443 from both `db-sg` and `rmq-sg`, and
  confirmed wide-open egress on `db-sg`. DNS resolves `secretsmanager.us-east-1
  .amazonaws.com` correctly to the endpoint's private IP (172.20.3.127, in-VPC).
  `timeout 10 aws secretsmanager get-secret-value ...` still times out (exit 124)
  from inside the vprofile-db instance (i-01ae6e334e08de812) even after the endpoint
  was created and confirmed available.
  **Ruled out so far:** IAM/permissions (S3 works via same role), DNS resolution
  (resolves correctly to private IP), endpoint placement (correct subnet/SG),
  db-sg egress (wide open, default).
  **Not yet checked:** raw TCP connectivity to the endpoint IP on 443 (bypassing
  DNS/SDK entirely, via /dev/tcp), and Network ACLs on the private subnet (NACLs
  are stateless and subnet-level — a return-traffic block there would produce
  exactly this "connects but times out" symptom). These are the next two things
  to check when resuming.
- New `vprofile-db` instance (i-01ae6e334e08de812) has an incomplete/stuck userdata
  run — MariaDB installed but user/password/schema setup did not complete. Will
  need re-verification (or a fresh relaunch) once the connectivity issue is fixed.


## Next Step (updated)
1. Diagnose remaining Secrets Manager connectivity gap: raw TCP test
   (`/dev/tcp/172.20.3.127/443`) from vprofile-db, then check Network ACLs on
   `subnet-0981c879b04c46232`.
2. Once fixed: re-verify new vprofile-db (i-01ae6e334e08de812) end-to-end
   (mariadb service, schema import, admin user auth via fetched secret).
3. Terminate OLD vprofile-db (i-0d5f4c4b3a689042a) once new one is verified.
4. Rebuild RabbitMQ golden AMI with updated rabbitmq.sh steps (Secrets Manager
   version) — this was the original reason for touching RabbitMQ at all.
5. Terminate old vprofile-rmq, launch new one from new AMI, verify.
6. Decide what to do with vprofile-mc — currently stopped with no relaunch
   planned; likely just needs a restart (no script changes were made for
   Memcached in this session).
7. THEN resume original Phase 3 (Tomcat) plan.



## Remaining Phases
- Phase 3: Tomcat EC2, build WAR file, and deploy the artifact from S3.
- Phase 4: Application Load Balancer and target group.
- Phase 5: End-to-end validation, documentation, and cleanup.

## Notes
See `NOTES.md` for chronological study notes and session checkpoints.