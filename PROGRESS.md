# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is Project 1 of 5 planned portfolio projects (+1 optional GCP project). The
full roadmap and project rationale live in the master prompt; this file records
only the state of this project.

## Current Phase
Phase 2 cleanup — Secrets Manager migration — DB side COMPLETE and verified.
RabbitMQ golden AMI rebuild IN PROGRESS — v4 AMI built with corrected node-name pinning, new instance launched, verification pending at session end.

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
- Public subnet 1a: `vprofile-pub-1a` (`subnet-03510c2b0ab2a8d18`, `172.20.1.0/24`).
- Public subnet 1b: `vprofile-pub-1b` (`subnet-0416352cf44e6f091`, `172.20.2.0/24`).
- Private subnet 1a: `vprofile-priv-1a` (`subnet-0981c879b04c46232`, `172.20.3.0/24`).
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
- Shared instance profile for Memcached and RabbitMQ: `vprofile-ssm-instance-profile`.
- S3 bucket created: `vprofile-artifacts-747336059892`, with all public access blocked.
- `db/accountsdb.sql` uploaded to the bucket.

#### RabbitMQ — verified ✅
- Launched from golden AMI `ami-0b553971033842a1d` into `subnet-0981c879b04c46232`
  (private), using `rmq-sg` (`sg-0ba3baa7a8a231777`) and `vprofile-ssm-instance-profile`.
  No userdata needed.
- Instance: `vprofile-rmq` (`i-0cbe922280b6da712`).
- `systemctl status rabbitmq-server` → `active (running)`.
- `rabbitmq-diagnostics ping` → `Ping succeeded`.
- The golden AMI was snapshotted with only the default `guest` user present — the
  VProfile `test` user was never actually created before the AMI build, despite
  being previously (incorrectly) recorded as done. Caught via `rabbitmqctl
  list_users` on this launched instance, not by re-reading `PROGRESS.md`.
- Fix applied manually on the live instance:
  `add_user test test` → `set_user_tags test administrator` →
  `set_permissions -p / test ".*" ".*" ".*"`.
- Verified: `rabbitmqctl authenticate_user test test` → `Success`.
- The AMI itself still lacks this config — see Known Issues.

#### Memcached — verified ✅
- Launched from base AMI `ami-081b0a6eac00b4f53` into `subnet-0981c879b04c46232`
  (private), using `mc-sg` (`sg-0d5c620face437bfc`) and `vprofile-ssm-instance-profile`.
- Instance: `vprofile-mc` (`i-0ea6c857a80a4e02d`).
- `userdata/memcache.sh` ran cleanly (confirmed via `cloud-init-output.log`, no errors).
- `systemctl status memcached` → `active (running)`.
- `ss -tlnp | grep 11211` confirmed listening on `0.0.0.0:11211` (not `127.0.0.1`),
  confirming the userdata's bind-address fix
  (`sed -i 's/127.0.0.1/0.0.0.0/g' /etc/sysconfig/memcached`) took effect.
- `mc-sg` restricts port 11211 to `app-sg` only — this SG rule is the actual
  security boundary, since Memcached itself has no built-in authentication.

#### MariaDB — verified ✅
- Launched from base AMI `ami-081b0a6eac00b4f53` into `subnet-0981c879b04c46232`
  (private), using `db-sg` (`sg-059fb90eac508a949`) and the dedicated
  `vprofile-db-instance-profile` (not the shared SSM profile — this instance
  alone needs S3 read access for the schema file).
- Instance: `vprofile-db` (`i-0d5f4c4b3a689042a`).
- `userdata/mysql.sh` ran cleanly (confirmed via `cloud-init-output.log`, no errors);
  this is the Incident #2-fixed version using S3 download instead of GitHub clone.
- `systemctl status mariadb` → `active (running)`.
- `mysql -u admin -padmin123 -e "SHOW DATABASES; USE accounts; SHOW TABLES;"`
  confirmed the `accounts` database exists with tables `role`, `user`,
  `user_role` — the actual schema-import step that failed in Incident #2 is
  now confirmed working on this fresh launch.

*(Note: the three instances above are the original Phase 2 launches. See*
*"Current State" below — all three were later stopped, and `vprofile-db`*
*was relaunched during the Secrets Manager migration.)*

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

## Incident #3 — Resolved: RabbitMQ Packaging Gap
### Symptom
`yum install -y erlang rabbitmq-server` failed because neither package existed in
Amazon Linux 2023 default repositories.

### Root Cause
Not a networking problem — the required packages simply are not supplied by the
default Amazon Linux 2023 repositories.

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

### Resolution
Golden AMI `ami-0b553971033842a1d` contains RabbitMQ and Erlang, confirmed via a
live launch of `vprofile-rmq` (`i-0cbe922280b6da712`) with no userdata/install
step needed. Builder instance terminated.

This checkpoint was previously recorded as fully verified — including the
VProfile `test` user/permissions — before that step was actually executed (see
the RabbitMQ note above and Known Issues for the AMI-level gap and its fix).

## Current State
- `vprofile-mc` (`i-0ea6c857a80a4e02d`) and `vprofile-rmq` (`i-0cbe922280b6da712`)
  remain **STOPPED**, unchanged this session.
- `vprofile-db` is now `i-0c7f0a845aee0ea20` — **launched and fully verified this
  session** (2026-09-07). Root cause of the prior blocking issue found and fixed
  (see "Secrets Manager Migration" below); service, schema, and admin auth all
  confirmed working end-to-end.
- Both prior `vprofile-db` instances from this migration are terminated:
  `i-01ae6e334e08de812` (the stuck/broken launch) and `i-0d5f4c4b3a689042a`
  (the old pre-migration fallback, kept until the new one was verified, now
  superseded).
- RabbitMQ golden AMI rebuild: v3 attempt (ami-0bae99fa0907e01c5) succeeded at installing RabbitMQ/Erlang via correct *.rabbitmq.com repos (Cloudsmith repos were dead — see Known Issues), but the launched instance couldn't authenticate the baked-in test user. Root cause: RabbitMQ's node identity (rabbit@<hostname>) is hostname-derived, and each EC2 instance gets a unique hostname, so the builder's node identity never matched any future launch — the test user existed but under an unreachable node name. Fixed by pinning NODENAME=rabbit@vprofile-rmq in /etc/rabbitmq/rabbitmq-env.conf on a fresh builder (i-0379cf9a62cddf462), which required adding a 127.0.0.1 vprofile-rmq entry to /etc/hosts first (Erlang's distribution layer does a real DNS-style lookup on the node name even for single-node/non-clustered use). test user created and verified under the pinned name; snapshotted as ami-041192a7315e5625c (v4). New vprofile-rmq (i-083381cc68958e4eb) launched from v4 — verification not yet run before session end.

  v3 builder (i-0379cf9a62cddf462... wait, that's v4's builder — v3's was i-0a63d61b202949913) and both prior vprofile-rmq instances (i-0cbe922280b6da712 original, i-086ef927045148b72 v3-launch) are terminated.

## Secrets Manager Migration (in progress this session)
- Two secrets created, values unchanged from before (deliberate — chose to
  relocate credentials, not rotate them):
  - `vprofile/db/admin-password` (value: admin123)
    ARN: `arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/db/admin-password-9mjRxL`
  - `vprofile/rmq/test-password` (value: test)
    ARN: `arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/rmq/test-password-onPKEB`
- New IAM role + instance profile: `vprofile-rmq-role` / `vprofile-rmq-instance-profile`
  (RabbitMQ previously had no dedicated role — rode on the shared SSM profile). Has
  `AmazonSSMManagedInstanceCore` + inline policy `vprofile-rmq-secret-read` (scoped
  to its own secret ARN only).
- `vprofile-db-role` (existing) got new inline policy `vprofile-db-secret-read`
  (scoped to its own secret ARN only), alongside its existing `db-s3-read` policy.
- `userdata/mysql.sh` updated: fetches `DB_PASS` from Secrets Manager at boot
  instead of hardcoding `admin123`. All mysql/mysqladmin calls now use `$DB_PASS`.
- `userdata/rabbitmq.sh` rewritten: this file is NOT live userdata (RabbitMQ uses
  a golden-AMI pattern, no boot-time script runs). Rewritten as an accurate
  build-reference doc for the next AMI rebuild — removed the actually-nonfunctional
  `yum install erlang rabbitmq-server` line (fails per Incident #3), added a header
  clarifying its real purpose, and updated `add_user` to pull `RMQ_PASS` from
  Secrets Manager.
- ADR-lite decision (not yet written to a formal decision log, captured here for
  now): chose Secrets Manager over Parameter Store despite near-zero cost
  difference (~$1/mo), because Secrets Manager is the correct category fit for
  credentials (vs. Parameter Store's config-focused design) even though rotation
  — its main differentiator — isn't used yet. Kept current password values as-is
  rather than rotating, since Option A (full clean relaunch) made rotation
  low-risk but out of today's approved scope.

### Root Cause Found and Resolved (2026-09-07)
The "BLOCKING" connectivity issue from the prior session was not a persistent
networking/IAM/SG problem — every one of those layers was independently
confirmed working (raw TCP connect to the endpoint IP succeeded instantly, a
verbose curl completed a full TLS handshake and got a real HTTP response from
Secrets Manager, IMDS responded normally). The actual cause was sequencing:
the Secrets Manager VPC endpoint (`vpce-0ebdbcb485fe2ea67`) was created at
`06:21:28`, but the failed `vprofile-db` instance (`i-01ae6e334e08de812`) had
already launched at `06:10:18` — 11 minutes earlier. Its userdata tried to
call Secrets Manager before the endpoint existed at all, which produced a
`Connect timeout` (confirmed in `cloud-init-output.log`), not an error the
script handled — it silently continued and later failed with
`ERROR 1049: Unknown database 'accounts'` as a downstream symptom.

**Fix applied:**
1. Terminated the broken instance (`i-01ae6e334e08de812`) — userdata doesn't
   re-run on restart, so a fresh launch was required.
2. Hardened `userdata/mysql.sh`: added a fail-fast check immediately after the
   `DB_PASS` fetch — if the secret comes back empty, the script now exits
   immediately with a clear `FATAL` message instead of continuing with a
   blank password and failing confusingly downstream.
3. Relaunched `vprofile-db` as `i-0c7f0a845aee0ea20`, now that the endpoint
   exists. Verified end-to-end: `cloud-init-output.log` clean (no FATAL, no
   timeout), `mariadb.service` active, `accounts` database present with
   `role`/`user`/`user_role` tables, and `admin`/`admin123` login succeeded —
   confirming the Secrets Manager fetch itself worked correctly this time.
4. Terminated the old pre-migration fallback instance (`i-0d5f4c4b3a689042a`)
   now that the new one is verified.

## Resource Reference

### Networking
| Resource | ID |
|---|---|
| VPC (`vprofile-vpc`) | `vpc-0e686e7841a60b687` |
| Public subnet 1a (`vprofile-pub-1a`) | `subnet-03510c2b0ab2a8d18` |
| Public subnet 1b (`vprofile-pub-1b`) | `subnet-0416352cf44e6f091` |
| Private subnet 1a (`vprofile-priv-1a`) | `subnet-0981c879b04c46232` |
| Internet Gateway (`vprofile-igw`) | `igw-00e59563b9ad5ee7d` |
| Public route table (`vprofile-pub-rt`) | `rtb-05958a20e0736100d` |
| Main route table | `rtb-08049511223df625b` |

### Security Groups
| Name | ID |
|---|---|
| `alb-sg` | `sg-04dcbc6c37a127962` |
| `app-sg` | `sg-0eef3641caa12a1ba` |
| `db-sg` | `sg-059fb90eac508a949` |
| `mc-sg` | `sg-0d5c620face437bfc` |
| `rmq-sg` | `sg-0ba3baa7a8a231777` |
| `ssm-ep-sg` | `sg-05bfef82dda3ad55b` |
| `vprofile-ami-builder-sg` | `sg-0e3792520437ec10d` |
| `vprofile-secretsmgr-ep-sg` | `sg-0b61cd7e69844f147` |

### VPC Endpoints
| Endpoint | ID |
|---|---|
| SSM | `vpce-0615acc9dd367d915` |
| SSM Messages | `vpce-00ae7b1e49d5deed5` |
| EC2 Messages | `vpce-01766d5b403a3b8f7` |
| S3 (Gateway) | `vpce-0540d3b05281c8189` |
| Secrets Manager | `vpce-0ebdbcb485fe2ea67` |

### IAM Roles / Instance Profiles
| Role | Instance Profile |
|---|---|
| `vprofile-ssm-role` (shared) | `vprofile-ssm-instance-profile` (shared) |
| `vprofile-db-role` | `vprofile-db-instance-profile` |
| `vprofile-rmq-role` (new) | `vprofile-rmq-instance-profile` (new) |

### Storage & AMIs
| Resource | ID |
|---|---|
| S3 bucket | `vprofile-artifacts-747336059892` |
| Base AMI | `ami-081b0a6eac00b4f53` |
| Golden AMI (RabbitMQ v3, superseded) | `ami-0bae99fa0907e01c5` — superseded/unused |
| Golden AMI (RabbitMQ v4, node-name pinned) | `ami-041192a7315e5625c` — available, in use |

### Secrets
| Secret | ARN |
|---|---|
| DB admin password | `arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/db/admin-password-9mjRxL` |
| RMQ test password | `arn:aws:secretsmanager:us-east-1:747336059892:secret:vprofile/rmq/test-password-onPKEB` |

### EC2 Instances (current state)
| Instance | Instance ID | Status |
|---|---|---|
| `vprofile-db` | `i-0c7f0a845aee0ea20` | running, verified ✅ |
| `vprofile-mc` | `i-0ea6c857a80a4e02d` | stopped |
| `vprofile-rmq` (v4) | `i-083381cc68958e4eb` | running — verification pending |
| `vprofile-rmq-builder-v3` | `i-0a63d61b202949913` | terminated |
| `vprofile-rmq-builder-v4` | `i-0379cf9a62cddf462` | terminated |
| `vprofile-rmq` (v3 launch, superseded) | `i-086ef927045148b72` | terminated |
| `vprofile-rmq` (original golden AMI) | `i-0cbe922280b6da712` | terminated |

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
- RabbitMQ user `test` (password `test`, from the reference Vagrant provisioning)
  is granted full admin rights with unrestricted configure/write/read permissions
  (`.*`/`.*`/`.*`) on the default vhost `/`. Same category of simplification as
  the hardcoded MariaDB credentials above — fine for a portfolio-scale single-app
  broker, but not least-privilege. Same planned follow-up as the DB credentials
  above.
- CloudTrail showed unexplained EKS/Auto Scaling `RunInstances` events on
  August 15–16. No live resources were found and no active cost was identified.
- Golden AMI `ami-0b553971033842a1d` does not include the VProfile `test`
  RabbitMQ user — it was missed before the AMI snapshot. The live `vprofile-rmq`
  instance has since been patched manually (add_user/set_user_tags/
  set_permissions, verified via `authenticate_user`). The AMI itself still lacks
  this config and will be corrected when the Packer template is built.
- (Resolved 2026-09-07) Secrets Manager connectivity was blocked purely by
  launch-order sequencing (instance launched before the VPC endpoint existed),
  not a persistent networking/IAM issue. See "Secrets Manager Migration" above
  for full root cause and fix. `mysql.sh` now fails fast instead of silently
  continuing if the secret fetch fails — worth applying the same pattern to
  `rabbitmq.sh` during the upcoming AMI rebuild.
- Cloudsmith moved both RabbitMQ repo namespaces from `public/rabbitmq/...` to
  `public/rabbitmq-dev/...` at some point after the original AMI build (old
  URLs now return 404, confirmed via `curl -w "%{http_code}"`; new URLs return
  200). If `rabbitmq.sh` still references the old `public/rabbitmq/...` URLs,
  it needs updating to `public/rabbitmq-dev/...` during this rebuild. Both
  repos now install successfully under the new URLs, but `dnf install` still
  can't find the packages afterward — see Current State; root cause not yet
  found.

## Next Step
1. Verify new vprofile-rmq (i-083381cc68958e4eb, from ami-041192a7315e5625c) end-to-end: systemctl status rabbitmq-server, rabbitmq-diagnostics ping, rabbitmqctl authenticate_user test test, and rabbitmqctl eval 'node().' (confirm it prints rabbit@vprofile-rmq on a genuinely fresh instance, not just the builder). Commands were issued but output not yet captured.
2. If verified clean with zero manual patching: RabbitMQ golden AMI work is DONE. Update Known Issues to remove the "test user missing from AMI" entry (superseded) and add the node-name-pinning lesson.
3. Decide what to do with vprofile-mc (i-0ea6c857a80a4e02d) — still stopped, no changes needed, likely just needs restart + re-verification.
4. THEN resume Phase 3 (Tomcat).

## Remaining Phases
- Phase 3: Tomcat EC2, build WAR file, and deploy the artifact from S3.
- Phase 4: Application Load Balancer and target group.
- Phase 5: End-to-end validation, documentation, and cleanup.

## Notes
See `NOTES.md` for chronological study notes and session checkpoints.