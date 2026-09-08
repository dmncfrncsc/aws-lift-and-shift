# Engineering Incident Log — aws-lift-and-shift

Real incidents encountered while building this project, in the order they occurred. Each
entry reflects what actually happened and how it was diagnosed and fixed — nothing here is
a hypothetical or invented scenario. Kept separate from `PROGRESS.md` (project state) and
`NOTES.md` (concept notes); this file exists specifically to show diagnostic process.

---

## Incident 1 — Backend Services Failed to Install (No Internet Path from Private Subnet)

**Symptom**
MariaDB, Memcached, and RabbitMQ were not installed after their EC2 instances first booted.

**Diagnosis**
Checked `cloud-init-output.log` on the affected instances — package installation was
failing, not silently skipping.

**Root Cause**
The private subnet had no route to the public internet (no NAT Gateway, by design — see
ADR log). Amazon Linux's package manager couldn't reach any repository at all.

**Fix**
Created an S3 Gateway Endpoint. Amazon Linux's default repositories are S3-hosted, so this
restored package installation without adding a NAT Gateway.

**Prevention**
Recognized as a general pattern for the rest of the project: any private-subnet AWS service
call needs its own explicit network path (VPC endpoint or NAT), never assumed. This exact
lesson recurred three more times (Incidents 4, and the separate Secrets Manager and EC2 API
endpoint gaps) — each time for a *different* AWS service, confirming there's no single
"internet access" switch to flip.

---

## Incident 2 — Database Schema Import Failed (GitHub Is Not S3)

**Symptom**
MariaDB installed successfully, but the schema import step failed.

**Diagnosis**
`mysql.sh` was cloning the VProfile repository directly from GitHub to pull the schema
file — a plain `git clone` to a public-internet host.

**Root Cause**
The S3 Gateway Endpoint from Incident 1 only covers S3 traffic. GitHub is unrelated public
internet traffic and remained unreachable from the private subnet.

**Fix**
1. Uploaded `accountsdb.sql` to the project's own S3 bucket.
2. Created a dedicated IAM role (`vprofile-db-role`) with S3 read access scoped to
   `vprofile-artifacts-747336059892/db/*` only.
3. Changed `mysql.sh` to `aws s3 cp` the file instead of `git clone`.
4. Relaunched and verified the schema imported correctly.

**Prevention**
Established a standing rule for the rest of the project: any artifact needed during
userdata gets pre-staged to S3 first, never fetched from the open internet. Applied later
to the Tomcat tarball and the app WAR file as well.

---

## Incident 3 — RabbitMQ Packages Unavailable on Amazon Linux 2023

**Symptom**
`dnf install erlang rabbitmq-server` failed — the packages don't exist in Amazon Linux
2023's default repositories at all.

**Diagnosis**
Confirmed via `dnf list available` (no matching packages) and `dnf repolist all` (no
disabled repo to simply re-enable). This ruled out a networking cause — the earlier
S3-endpoint fix didn't apply here, because the problem wasn't reachability, it was that the
packages are genuinely absent from AL2023's repos.

**Root Cause**
Amazon Linux 2023's default package set doesn't ship Erlang or RabbitMQ.

**Options Considered**
1. NAT Gateway — reverses an already-approved architecture decision, adds recurring cost.
2. Self-hosted S3 repository — workable, but adds ongoing repo-maintenance scope.
3. Golden AMI — install once on a temporary public builder instance, snapshot it, launch
   the final broker privately from that image with no install step at boot.

**Fix**
Chose the golden AMI path. Built a temporary EC2 instance in a public subnet (zero inbound
security group rules — SSM Session Manager only needs outbound), installed and verified
RabbitMQ/Erlang manually first, then ran `aws ec2 create-image` and terminated the builder
once the AMI reached `available`.

**Prevention**
This decision also set up the project's "understand manually before automating" principle
for a second time (after the Terraform-vs-CLI approach) — the golden AMI was built by hand
before considering any Packer automation, so the eventual automation would use commands
already understood, not commands copied in blind.

---

## Incident 4 — Two Missing VPC Endpoints Blocked Tomcat Bootstrap

**Symptom**
`vprofile-app`'s userdata (`tomcat.sh`) failed twice on relaunch: first with a connect
timeout calling Secrets Manager, then — after that fix — a connect timeout calling the EC2
API.

**Diagnosis**
A hanging command with no error message is itself a signal pointing toward a missing
network path rather than a permissions or syntax problem (an IAM denial fails fast with a
clear error; a missing route just hangs). Checked each layer in turn: the Secrets Manager
endpoint's security group, then whether any endpoint existed at all for the general EC2 API.

**Root Cause**
Two separate gaps:
1. `vprofile-secretsmgr-ep-sg` only allowed inbound 443 from `db-sg`/`rmq-sg` — it was never
   updated when `app-sg` became a third consumer of that same endpoint in Phase 3.
2. No VPC endpoint existed for the general EC2 API (`com.amazonaws.us-east-1.ec2`) at all.
   `ec2messages` (already present for SSM) looks similarly named but is a narrow, unrelated
   service used only by the SSM Agent — not a substitute for `describe-instances` calls.

**Fix**
1. Added an inbound rule to `vprofile-secretsmgr-ep-sg` for TCP 443 from `app-sg`.
2. Created a new SG (`vprofile-ec2api-ep-sg`) and a new VPC Interface Endpoint for the EC2
   API, then relaunched `vprofile-app`.

**Prevention**
Reinforced, for the third time, that every AWS service needs its own dedicated VPC
endpoint — and specifically, that adding a *new consumer* to an existing shared resource
(an endpoint, a security group, a role) requires re-checking whether that resource's rules
were scoped only to the old set of consumers.

---

## Incident 5 — Three Missing Spring Config Placeholders Crashed Tomcat on Startup

**Symptom**
Tomcat itself reported healthy (`systemctl status` active, clean deployment log), but
`curl -I localhost:8080` returned `404`. `journalctl -u tomcat` showed
`Could not resolve placeholder 'jdbc.driverClassName'`.

**Diagnosis**
Fixed that key, restarted, hit the identical failure pattern for `memcached.standBy.host`,
fixed and restarted again, then hit it a third time for `elasticsearch.host`. Recognized
this as Spring resolving every `@Value` placeholder across all beans at startup — not
lazily per feature — so any missing key fails the entire app immediately, even for features
this project doesn't use.

**Root Cause**
`tomcat.sh`'s config-override step wrote the real values this project actually needs
(`jdbc.url`, `jdbc.username`, `jdbc.password`, active Memcached, all four RabbitMQ keys) but
omitted three keys the reference app's Spring context still requires to exist —
`jdbc.driverClassName`, the unused `memcached.standBy.*` pair, and the unused
`elasticsearch.*` block — all dropped somewhere during the script's adaptation from the
original Vagrant reference.

**Fix**
1. Diagnosed via `journalctl -u tomcat` (not `catalina.out`, which doesn't exist under
   systemd) after each restart, revealing one missing key per cycle.
2. Patched the live instance directly via SSM for each key, restarting and re-verifying
   after each, using the reference project's own documented default values for the two
   genuinely-unused blocks — Spring only needs *something* present, not a reachable service.
3. Ported all three fixes into `tomcat.sh` so future relaunches don't repeat this.

**Prevention**
Once a startup log shows zero `SEVERE` entries, that's a strong signal every placeholder
resolved successfully — useful as a stopping condition without needing a byte-for-byte diff
against the WAR's original bundled config (which wasn't possible here anyway, since neither
`unzip` nor `jar` was available on this trimmed AL2023/Corretto install).

---

## Incident 6 — RabbitMQ Vendor Repository URLs Moved Without Warning

**Symptom**
Rebuilding the RabbitMQ golden AMI (v3), the Cloudsmith setup scripts for both
`rabbitmq-erlang` and `rabbitmq-server` — which had worked during the original build — now
404'd at their old URLs.

**Diagnosis**
The setup scripts are normally run as `curl | bash`, which fails silently on a 404 (`-f`
suppresses the error body, and the script prints its own "installed successfully" message
regardless). Switched to `curl -w "%{http_code}"` directly against the URLs to see the real
HTTP status instead of trusting the piped installer's own reported outcome.

**Root Cause**
Cloudsmith had moved both repositories to a different URL namespace
(`public/rabbitmq-dev/...` instead of the old `public/rabbitmq/...`) — an upstream vendor
change, not anything wrong with this project's script.

**Fix**
Updated the repo URLs to the current namespace. Confirmed the setup scripts installed
cleanly afterward.

**Prevention**
A frozen "it worked when I built this" script can go stale purely from a third party's
side, with zero code change on the project's part — and a script's own self-reported
success message is not proof of anything, the same "reported ≠ verified" lesson that showed
up earlier with `cloud-init-output.log` and `systemctl status`.

---

## Incident 7 — RabbitMQ Golden AMI Lost Its Baked-In User on Every New Launch

**Symptom**
The golden AMI was believed to include a working VProfile `test` RabbitMQ user. Every fresh
instance launched from it came up with only the default `guest` user — `test` was simply
gone, with no error.

**Diagnosis**
Checked `rabbitmqctl list_users` directly on a newly launched instance rather than trusting
`PROGRESS.md`'s existing "verified" note — which turned out to be inaccurate; the user had
never actually been created and confirmed before the original AMI snapshot.

**Root Cause**
RabbitMQ identifies each node as `rabbit@<hostname>`, and all of its per-node data —
including users — lives under a directory keyed to that name. Every EC2 instance gets a
unique auto-generated hostname, so each new launch came up as a different node identity,
found no matching data directory, and silently initialized fresh.

**Fix**
1. Set `NODENAME=rabbit@vprofile-rmq` in `/etc/rabbitmq/rabbitmq-env.conf` on a new builder,
   pinning every future launch to the same fixed node identity.
2. This alone produced an `epmd_error ... nxdomain` on startup, because Erlang's
   distribution layer does a real hostname resolution on the node name even for a single,
   non-clustered node. Added `127.0.0.1 vprofile-rmq` to `/etc/hosts` on the builder so the
   name resolves locally — this entry is baked into the AMI too, so it carries to every
   future launch.
3. Created and verified the `test` user under the pinned name, snapshotted as AMI v4, and
   confirmed a fresh launch from v4 authenticated successfully with zero manual patching.

**Prevention**
General lesson for golden AMIs: anything an application derives from machine identity at
first run (hostname, generated node names, machine IDs) is a landmine, because the value
gets baked in from the *builder's* identity, not the eventual instance's. Worth checking for
this class of problem before snapshotting, not after a failed relaunch.
