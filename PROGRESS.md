# PROGRESS.md — aws-lift-and-shift (Project 1)

## Project
Lift-and-shift migration of the VProfile Java application onto AWS infrastructure.
Replacing five local Vagrant VMs with equivalent AWS resources.

## Portfolio Context
This is Project 1 of 5 planned portfolio projects (+1 optional GCP project). The
full roadmap and project rationale live in the master prompt; this file records
only the state of this project.

## Current Phase
Phase 5 (validation, documentation, cleanup) — IN PROGRESS. Phase 4 (ALB) is COMPLETE and
verified as described below. The four EC2 instances (`vprofile-db`, `vprofile-mc`, `vprofile-rmq`
v4, and `vprofile-app`) were confirmed `stopped` via `describe-instances` this session. Phase 5
docs `docs/incidents.md` (7-incident engineering log) and `docs/decisions.md` (11-entry ADR-lite
log) are still not independently verified in the correct portfolio repository. The initial
Phase 5 architecture approach is agreed: two Mermaid diagrams (network/security and request-flow).
Remaining Phase 5 work: verify the correct repo/docs state, add/verify the architecture diagrams,
Course Coverage Matrix, cleanup/ALB shutdown, and README last (synthesizing the other docs).

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

## Incident #4 — Resolved: Two Missing VPC Endpoints Blocked Tomcat Bootstrap

### Symptom

vprofile-app's userdata (tomcat.sh) failed twice on relaunch: first with Connect timeout calling Secrets Manager, then (after that fix) with Connect timeout calling the EC2 API.

### Root Cause

Two separate missing private network paths, same underlying pattern as the earlier Secrets Manager migration issue — every AWS service needs its own dedicated VPC endpoint; none is covered by another.

vprofile-secretsmgr-ep-sg only allowed inbound 443 from db-sg/rmq-sg — never updated when app-sg became a new consumer of that endpoint in Phase 3.

No VPC endpoint existed at all for the general EC2 API (com.amazonaws.us-east-1.ec2) — ec2messages (already present) is a narrow, unrelated service used only internally by the SSM Agent, not a substitute for the EC2 API that tomcat.sh's describe-instances IP-lookup step needs.

### Resolution

Added inbound rule to vprofile-secretsmgr-ep-sg (sg-0b61cd7e69844f147): TCP 443 from app-sg (sg-0eef3641caa12a1ba).

Created new dedicated SG vprofile-ec2api-ep-sg (sg-01faa4745a8953e2f) with inbound TCP 443 from app-sg.

Created new VPC Interface Endpoint for the EC2 API: vpce-0a24fd33ba9bbb006, in subnet-0981c879b04c46232, using the new SG. PrivateDnsEnabled: true.

Terminated and relaunched vprofile-app twice total this session (i-00f0024c88e4f5a58 → i-0334bc9422966f1c2 → i-00e2cb29243a3fb05, the last being current). userdata now completes cleanly with no scripts-user failure warning.

## Incident #5 — Resolved: Three Missing Spring Config Placeholders Crashed Tomcat on Startup

### Symptom
Tomcat itself was healthy (`systemctl status` → active, clean deploy log), but the app failed
to start, and `curl -I localhost:8080` returned 404. `journalctl -u tomcat` showed
`Could not resolve placeholder 'jdbc.driverClassName'` — resolved and restarted, then hit the
same error for `memcached.standBy.host`, resolved and restarted, then hit it again for
`elasticsearch.host`. Three cascading failures, one per restart.

### Root Cause
`tomcat.sh`'s config-override heredoc (the block that writes real values into
`webapps/ROOT/WEB-INF/classes/application.properties`) was incomplete relative to what the
WAR's Spring context actually requires at startup. It wrote `jdbc.url`/`username`/`password`,
`memcached.active.*`, and all four `rabbitmq.*` keys, but omitted `jdbc.driverClassName`,
the `memcached.standBy.*` pair, and the full `elasticsearch.*` block (host/port/cluster/node)
— all present in the reference project's original config but dropped somewhere during this
project's script adaptation. Spring resolves every `@Value` placeholder across all beans at
context startup (not lazily per-request), so any missing key fails the whole app immediately,
even for features this project doesn't use — Elasticsearch and a real memcached standby were
never part of this architecture and still aren't; the app just needs *some* value present for
each key. Confirmed the reference project's own defaults for these missing keys via multiple
independent write-ups of the same instructor-provided reference app (all matching this
project's other values — `db01`/`admin`/`admin123`/`test`/`test` — exactly, so a reliable
cross-check).

### Resolution
1. Diagnosed by reading `journalctl -u tomcat` (not `catalina.out`, which doesn't exist under
systemd) after each restart — one new missing placeholder revealed per cycle.
2. Manually patched the live override file on `vprofile-app` via SSM (`sed -i`) for each of the
three missing blocks, restarting Tomcat and re-checking after each, confirming `curl -I`
finally returned `200` with all three fixes applied.
3. Ported the same three additions into `tomcat.sh`'s heredoc so future relaunches don't repeat
this — committed as `fix(tomcat): add missing jdbc.driverClassName, memcached standby, and
elasticsearch placeholders`.
4. Deliberately did not pursue extracting the WAR's original bundled `application.properties`
for a byte-for-byte diff (blocked by `unzip`/`jar` both being unavailable on this trimmed
AL2023 Corretto install) — judged unnecessary since Spring's fail-fast startup behavior means
any remaining missing key would have already surfaced in the same journal log, the same way
these three did.

## Current State
- `vprofile-mc` (`i-0ea6c857a80a4e02d`) — restarted after being stopped since Phase 2, re-verified
  2026-09-08: `systemctl status memcached` → `active (running)`, `ss -tlnp | grep 11211` confirmed
  listening on `0.0.0.0:11211` (bind-address fix survived the stop/start cycle, no drift).
  Subsequently stopped at session end — see below.
- `vprofile-db` (`i-0c7f0a845aee0ea20`), `vprofile-rmq` v4 (`i-083381cc68958e4eb`), and
  `vprofile-mc` (`i-0ea6c857a80a4e02d`) — all three stopped, confirmed via `describe-instances`
  at the end of the 2026-09-08 (cont'd) session. All show `State.Name: stopped`.
- Both prior `vprofile-db` instances from this migration are terminated:
  `i-01ae6e334e08de812` (the stuck/broken launch) and `i-0d5f4c4b3a689042a`
  (the old pre-migration fallback, kept until the new one was verified, now
  superseded).
- RabbitMQ golden AMI rebuild: COMPLETE. v3 attempt (ami-0bae99fa0907e01c5) succeeded at installing RabbitMQ/Erlang via correct *.rabbitmq.com repos (Cloudsmith repos were dead — see Known Issues), but the launched instance couldn't authenticate the baked-in test user. Root cause: RabbitMQ's node identity (rabbit@<hostname>) is hostname-derived, and each EC2 instance gets a unique hostname, so the builder's node identity never matched any future launch — the test user existed but under an unreachable node name. Fixed by pinning NODENAME=rabbit@vprofile-rmq in /etc/rabbitmq/rabbitmq-env.conf on a fresh builder (i-0379cf9a62cddf462), which required adding a 127.0.0.1 vprofile-rmq entry to /etc/hosts first (Erlang's distribution layer does a real DNS-style lookup on the node name even for single-node/non-clustered use). test user created and verified under the pinned name; snapshotted as ami-041192a7315e5625c (v4). New vprofile-rmq (i-083381cc68958e4eb) launched from v4 and verified end-to-end on 2026-09-07: `systemctl status rabbitmq-server` active/running, `rabbitmq-diagnostics ping` succeeded (addressing `rabbit@vprofile-rmq` by name), `rabbitmqctl authenticate_user test test` succeeded with zero manual patching, and `rabbitmqctl eval 'node().'` confirmed `rabbit@vprofile-rmq` on a genuinely fresh instance. AMI-level fix confirmed working, not just the manually-patched original instance.

  v3 builder (`i-0a63d61b202949913`) and both prior vprofile-rmq instances (`i-0cbe922280b6da712` original, `i-086ef927045148b72` v3-launch) are terminated.

### Phase 3 — In Progress
- IAM: `vprofile-app-role` created with four policies (SSM baseline, scoped S3
  read `app/*`, scoped Secrets Manager read for db + rmq secrets, and
  account-wide read-only `ec2:DescribeInstances`). `vprofile-app-instance-profile`
  created and attached. All verified via `get-role-policy` and
  `get-instance-profile`.
- WAR built locally via `mvn clean package` → `target/vprofile-v2.war` (83MB).
  Uploaded to `s3://vprofile-artifacts-747336059892/app/vprofile-v2.war`.
  Verified via `head-object`.
- `vprofile-app-sg` (`sg-0eef3641caa12a1ba`) verified — already has correct
  inbound rule (TCP 8080 from `alb-sg`). No changes needed.
- Reviewed Vagrant `tomcat.sh` from forked repo — used as reference for Tomcat
  installation approach (version 10.1.26, Java 17, systemd service definition,
  ROOT.war deployment pattern, and the commented-out `application.properties`
  override which confirms our override approach).
- `tomcat.sh` fully written (4 parts: install, systemd service, secrets+IP lookup, WAR deploy).
  Fixes applied during review: added missing `#!/bin/bash` shebang (dropped during Notepad
  copy/paste), corrected `CATALINA_BASE` typo from Vagrant reference script, added `rsync` to
  the dnf install line (not guaranteed present on base AL2023 AMI), removed unused `wget`/`unzip`,
  reordered WAR-deploy ROOT cleanup to stop-tomcat-then-remove (was remove-then-stop; worked
  either way on Linux but stop-first is the standard/expected order).
- Verified `java-17-amazon-corretto` is the correct AL2023 package name (not `java-17-openjdk`,
  which was the Vagrant reference script's naming — doesn't exist on AL2023, confirmed via
  AWS docs: AL2023's only Java distribution is Corretto).
- Tomcat installed via `aws s3 cp` (S3-staged tarball), not `wget` to `archive.apache.org` —
  same fix pattern as Incident #2, since the private subnet has no path to the public internet.
  Tarball uploaded manually to `s3://vprofile-artifacts-747336059892/app/apache-tomcat-10.1.26.tar.gz`.
- Re-verified `vprofile-app-role` / `vprofile-app-instance-profile` / `vprofile-app-sg` against
  live AWS state (not just trusting the earlier PROGRESS.md record): `AmazonSSMManagedInstanceCore`
  attached as managed policy; `app-s3-read` scoped to `app/*` only; `app-secrets-read` scoped to
  exactly the two db/rmq secret ARNs; `app-ec2-describe` correctly unscoped (`DescribeInstances`
  doesn't support resource-level restriction — expected, not a gap). SG confirmed: TCP 8080
  inbound from `alb-sg` only. No drift found this time.
- Verified `ami-081b0a6eac00b4f53` is a genuine AWS-published AL2023 AMI (OwnerId
  `137112412989`, alias `amazon`) before reusing it for Tomcat.
- EC2 instance launched: `vprofile-app` (`i-00f0024c88e4f5a58`) — full spec in EC2 table and
  Current Phase. Launched via `--user-data "$(cat ~/aws-lift-and-shift/userdata/tomcat.sh)"`
  (not `file://` — known Git Bash issue from 2026-09-04 session). State was `pending` at launch;
  NOT yet confirmed `running` or functional — next session must verify before assuming success.

### Phase 4 — Application Load Balancer ✅
- `alb-sg` (`sg-04dcbc6c37a127962`) already had the correct inbound rule (TCP 80 from
  `0.0.0.0/0`) pre-provisioned from Phase 1 — discovered when `authorize-security-group-ingress`
  returned `InvalidPermission.Duplicate`. Verified via `describe-security-groups`: exactly one
  rule, matching what Phase 4 needed. No change made.
- Verified health-check path before configuring anything: `curl -I localhost:8080/login`
  returned `405 Method Not Allowed` (POST-only, it's the form-submission endpoint, not a page).
  Used `/` instead, which had already returned a clean `200` in Phase 3 verification.
- Target group created: `vprofile-app-tg`
  (`arn:aws:elasticloadbalancing:us-east-1:747336059892:targetgroup/vprofile-app-tg/810a9f8873f9910b`) —
  HTTP, port 8080, target type `instance`, health check path `/`, matcher `200`.
- `vprofile-app` (`i-00e2cb29243a3fb05`) registered as a target on port 8080. Initially showed
  `unused` (`Target.NotInUse`) since no listener existed yet — expected, not an error.
- ALB created: `vprofile-alb`
  (`arn:aws:elasticloadbalancing:us-east-1:747336059892:loadbalancer/app/vprofile-alb/0be0c8202f2798af`) —
  internet-facing, spans both public subnets (`subnet-03510c2b0ab2a8d18` / `subnet-0416352cf44e6f091`),
  `alb-sg` attached. DNS name: `vprofile-alb-932338318.us-east-1.elb.amazonaws.com`.
- Listener created: HTTP:80 → forward to `vprofile-app-tg`. Once attached, target health flipped
  from `unused` to `healthy`.
- End-to-end verification: `curl -I http://vprofile-alb-932338318.us-east-1.elb.amazonaws.com`
  returned `200`, `Content-Length: 7935` — identical to the direct `localhost:8080` response,
  confirming real app content is flowing through the full ALB → target group → app path.
- No HTTPS/ACM — named simplification (no custom domain to validate a cert against). To be
  called out explicitly in the README as a production gap, not a silent omission.
- Before this phase's implementation, all four instances (`vprofile-db`, `vprofile-mc`,
  `vprofile-rmq`, `vprofile-app`) were restarted from their previously-stopped state (private
  IPs unchanged, confirmed via `describe-instances`) and re-verified healthy — `vprofile-app`'s
  `journalctl -u tomcat -b` showed zero `SEVERE` entries on the current boot (old `SEVERE` entries
  from an earlier boot today were still present in full `journalctl` history but correctly
  excluded by `-b`).

## Secrets Manager Migration
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
| `vprofile-ec2api-ep-sg` | `sg-01faa4745a8953e2f` |

### VPC Endpoints
| Endpoint | ID |
|---|---|
| SSM | `vpce-0615acc9dd367d915` |
| SSM Messages | `vpce-00ae7b1e49d5deed5` |
| EC2 Messages | `vpce-01766d5b403a3b8f7` |
| S3 (Gateway) | `vpce-0540d3b05281c8189` |
| Secrets Manager | `vpce-0ebdbcb485fe2ea67` |
| EC2 API | `vpce-0a24fd33ba9bbb006` |

### IAM Roles / Instance Profiles
| Role | Instance Profile |
|---|---|
| `vprofile-ssm-role` (shared) | `vprofile-ssm-instance-profile` (shared) |
| `vprofile-db-role` | `vprofile-db-instance-profile` |
| `vprofile-rmq-role` (new) | `vprofile-rmq-instance-profile` (new) |
| `vprofile-app-role` | `vprofile-app-instance-profile` |

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

### Load Balancing
| Resource | ARN / Value |
|---|---|
| Target group (`vprofile-app-tg`) | `arn:aws:elasticloadbalancing:us-east-1:747336059892:targetgroup/vprofile-app-tg/810a9f8873f9910b` |
| ALB (`vprofile-alb`) | `arn:aws:elasticloadbalancing:us-east-1:747336059892:loadbalancer/app/vprofile-alb/0be0c8202f2798af` |
| ALB DNS name | `vprofile-alb-932338318.us-east-1.elb.amazonaws.com` |

### EC2 Instances (current state)
| Instance | Instance ID | Status |
|---|---|---|
| `vprofile-db` | `i-0c7f0a845aee0ea20` | stopped — verified via `describe-instances` in Phase 5 session |
| `vprofile-mc` | `i-0ea6c857a80a4e02d` | stopped — verified via `describe-instances` in Phase 5 session |
| `vprofile-rmq` (v4) | `i-083381cc68958e4eb` | stopped — verified via `describe-instances` in Phase 5 session |
| `vprofile-rmq-builder-v3` | `i-0a63d61b202949913` | terminated |
| `vprofile-rmq-builder-v4` | `i-0379cf9a62cddf462` | terminated |
| `vprofile-rmq` (v3 launch, superseded) | `i-086ef927045148b72` | terminated |
| `vprofile-rmq` (original golden AMI) | `i-0cbe922280b6da712` | terminated |
| `vprofile-app` | `i-00e2cb29243a3fb05` | stopped — verified via `describe-instances` in Phase 5 session |

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
- Phase 3 service discovery: Tomcat's userdata (`tomcat.sh`) looks up the
  current private IPs of `vprofile-db`, `vprofile-mc`, and `vprofile-rmq` at
  boot via `aws ec2 describe-instances`, filtered by each instance's `Name`
  tag — rather than hardcoding private IPs, which would break on any future
  relaunch of those instances (already happened multiple times this project).
  Real best practice for this problem is DNS-based service discovery (a
  Route 53 private hosted zone, or AWS Cloud Map) — deliberately not used
  here because Route 53 was already excluded from this project's architecture
  for cost/scope reasons (see the existing "No Route 53 hosted zone" decision
  above), and reversing that just for this would need its own justification.
  Trade-off accepted: `vprofile-app-role` needs `ec2:DescribeInstances`, which
  (unlike the S3/Secrets Manager policies on this role) can't be scoped to
  specific instance ARNs — it's read-only but account-wide. **README must
  state this explicitly as a named simplification with the production
  alternative (Route 53 / Cloud Map) called out** — do not let this read as
  if dynamic tag lookup were the real-world answer.

## Known Issues
- (Resolved 2026-09-07) Database credentials migrated from hardcoded `admin123` in `mysql.sh`
  to Secrets Manager (`vprofile/db/admin-password`). See Secrets Manager Migration section.
- RabbitMQ user `test` (password `test`, from the reference Vagrant provisioning)
  is granted full admin rights with unrestricted configure/write/read permissions
  (`.*`/`.*`/`.*`) on the default vhost `/`. Same category of simplification as
  the hardcoded MariaDB credentials above — fine for a portfolio-scale single-app
  broker, but not least-privilege. Same planned follow-up as the DB credentials
  above.
- CloudTrail showed unexplained EKS/Auto Scaling `RunInstances` events on
  August 15–16. No live resources were found and no active cost was identified.
- (Resolved 2026-09-07) Golden AMI `ami-0b553971033842a1d` (v1) was missing the
  VProfile `test` RabbitMQ user at snapshot time. Superseded by v4
  (`ami-041192a7315e5625c`), which bakes in a working `test` user under a
  pinned node identity (`rabbit@vprofile-rmq`) — confirmed on a fresh launch
  with zero manual patching. See "RabbitMQ Node-Identity Pinning" in NOTES.md
  for the root cause (hostname-derived node identity breaks golden AMIs unless
  pinned).
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

- Tomcat service discovery trade-off (`ec2:DescribeInstances` vs Route 53 / Cloud Map,
  and README TODO) — see Key Decisions — Phase 3 service discovery for full rationale.
- Git Bash / MSYS path auto-translation: `--health-check-path /` was silently rewritten to
  `C:/Program Files/Git/` before reaching the AWS CLI, causing a confusing `ValidationError`.
  Fix: prefix the command with `MSYS_NO_PATHCONV=1` (scoped to that one invocation). Same family
  of issue as the earlier `file://` userdata problem — a third documented Git-Bash-on-Windows gotcha.

## Next Step
1. Verify the correct outer portfolio repo (`~/aws-lift-and-shift`) state: confirm `docs/incidents.md`
   and `docs/decisions.md` exist and are committed (`git -C ~/aws-lift-and-shift status`,
   `git -C ~/aws-lift-and-shift log --oneline -5`, and `ls ~/aws-lift-and-shift/docs/`).
2. Continue Phase 5 architecture documentation using the agreed two-diagram approach: network/security
   architecture and request-flow/application architecture (Mermaid). Verify the diagrams render cleanly
   before committing them.
3. Build the Course Coverage Matrix after the architecture documentation, then complete the README last.
4. The four EC2 instances are now confirmed `stopped`. ALB (`vprofile-alb`) was left active/billing
   this session — no change made. Revisit deletion after the Phase 5 documentation is complete
   (approval-gated, destructive-ish action).

## Remaining Phases
- Phase 3: Tomcat EC2 — COMPLETE. `vprofile-app` verified serving the app on port 8080.
- Phase 4: Application Load Balancer and target group — COMPLETE. `vprofile-alb` verified
  serving the app end-to-end.
- Phase 5: End-to-end validation, documentation, and cleanup — IN PROGRESS.

## Notes
See `NOTES.md` for chronological study notes and session checkpoints.