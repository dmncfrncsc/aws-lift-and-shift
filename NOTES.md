# NOTES.md — aws-lift-and-shift

Study notes, updated incrementally at each PROGRESS.md checkpoint. Organized
chronologically — one section per session. Starts from the checkpoint where
incremental notes began; does not backfill earlier sessions.

---

## Session — 2026-09-03 (IAM Roles, VPC Endpoints, SSM Troubleshooting)

**IAM Role vs IAM User**
A User has permanent credentials (access keys) — like your own house keys, valid
until someone revokes them. A Role has temporary, auto-rotating credentials issued
only while something is actively using it — like a hotel key card, expires on its
own. EC2 instances should always use roles, never a user's keys: if a role's
credentials leak, the exposure window is short; a leaked user key stays valid until
someone notices and revokes it.

**IAM Instance Profile**
EC2 can't attach a role directly — it attaches an Instance Profile, a thin wrapper
around the role. Almost always 1:1. This is legacy AWS API history; the console
hides it by auto-creating a same-named profile when you "attach a role" through the
UI, but the CLI makes you create it as a separate step.

**Shared vs. per-instance roles — the actual rule**
Share one role across instances only when their permission needs are genuinely
identical. The moment one instance needs something the others don't, it needs its
own role — bolting extra permissions onto a shared role grants them to instances
that never asked for it. Came up directly: vprofile-db needed S3 read for a schema
file; vprofile-mc and vprofile-rmq didn't, so db gets a separate role instead of
widening the shared one. Least privilege means scoping to what's actually needed,
not what's convenient.

**VPC Interface Endpoint (PrivateLink)**
A private network path from inside a VPC straight to one specific AWS service (like
SSM), never touching the public internet. ~$0.01/hr per Availability Zone per
endpoint, plus a small per-GB data charge. Needed 3 for full SSM Session Manager
function: ssm, ssmmessages, ec2messages.

**VPC Gateway Endpoint — different from Interface Endpoint**
Only exists for S3 and DynamoDB. Free. Works via route table entries rather than a
network interface — this is why checking which route table a subnet uses actually
matters (see below).

**Route tables: explicit association vs. the "main" table**
Every VPC has one default/main route table. Any subnet without an explicit
association to a different table automatically uses the main one. This project's
public subnets are explicitly tied to a custom route table; the private subnet was
never explicitly associated with anything, so it silently falls back to the main
table — which is where the S3 Gateway Endpoint was added, so it applies without any
extra step.

**userdata only runs once**
EC2 userdata scripts execute on first boot only, not on every start. If a script
fails partway, simply stopping and starting the same instance will NOT re-run it —
it comes back up in the same half-configured state. The only way to re-trigger
userdata is a fresh instance: terminate the broken one, launch a new one.

**S3 Gateway Endpoint =/= general internet access**
The endpoint only covers traffic to S3 specifically. Amazon Linux's yum repos
happen to be hosted on S3, so yum install worked through it — but git clone from
github.com is regular public internet traffic, unrelated to S3, and still fails
with no NAT Gateway. "Internet access" isn't one thing — different destinations
need different network paths.

**Production pattern vs. portfolio pattern for deploying files to instances**
Production teams decouple schema/config changes from instance bootstrap entirely,
using dedicated migration tools (Flyway, Liquibase) run as their own pipeline step.
For one static schema file, that's scope creep. Right middle ground: pull the file
from S3 (an internal, IAM-controlled store) instead of depending on the public
internet from a private instance — same underlying principle as production,
simplified to fit the scope.

**SSM Session Manager troubleshooting in Git Bash (two separate issues)**
1. systemctl status pipes through the less pager by default — q normally exits it.
2. Separately: Git Bash's terminal (MinTTY) doesn't behave like a real Windows
   console, so interactive programs (SSM's session-manager-plugin, same as Python's
   REPL) don't receive keystrokes without winpty in front of the command. If keys
   aren't registering at all — not even q — that's the winpty issue, not the pager.

**Diagnosing "is my local repo actually out of sync" before assuming it**
git fetch (pulls remote refs without merging) + git log HEAD..origin/master --oneline
(shows remote commits not yet local) + git status — run together, these confirm
whether local and remote have actually diverged, rather than guessing from a
possibly-stale web fetch.

**S3 bucket basics**
Bucket names are globally unique across all AWS accounts — appending your account
ID is a common way to guarantee uniqueness. New buckets default to private, but
explicitly setting all four public-access-block flags avoids relying on a default
that could change. Region matters for cost/architecture: an endpoint is regional
and only benefits buckets in the same region.

---

## Session — 2026-09-04 (Reference/Scaffold Apps in a DevOps Portfolio)

**Reference (scaffold) applications**
DevOps portfolios commonly deploy a pre-built sample app rather than one the
engineer wrote — the discipline is about infrastructure and operations, not
application development, so real DevOps engineers rarely write the apps they
deploy either. vprofile (Nginx/Tomcat/MySQL/Memcached/RabbitMQ) is exactly this:
an instructor-provided reference app, not self-written, and worth stating as such
in one sentence if asked. What actually gets evaluated — and what to pivot
to — is the infrastructure work: VPC design, IAM roles, SSM setup, the two real
incidents.

**winpty isn't just for Python**
Same MinTTY issue as the Python REPL — `aws ssm start-session` needed it too.
Symptom: connects fine, but keystrokes don't register (cursor just blinks).

**`file://` paramfiles can fail in Git Bash even when the file is fine**
`aws ec2 run-instances --user-data file://$HOME/.../mysql.sh` failed twice with
"No such file or directory" — even though `ls` and `cat` both proved the file
existed and was readable at that exact path. Root cause not fully pinned down
(likely Git Bash's path translation confusing the CLI's file loader). Fix:
skip `file://` entirely, use `--user-data "$(cat path/to/script)"` instead —
bash reads the file itself and hands the CLI the contents directly.

**A stale-looking file isn't always stale — check the source, not just the copy**
`/tmp/accountsdb.sql` on the relaunched `vprofile-db` showed a Sep 3 timestamp on
a Sep 4 instance, which looked like leftover/stale data. Checked the S3 object's
own `LastModified` (`aws s3api head-object`) — same Sep 3 timestamp, exactly.
`aws s3 cp` preserves the source object's timestamp rather than stamping download
time. Lesson: `cloud-init-output.log` (needs `sudo cat`) is the actual proof a
step ran on *this* boot — check the log, not just a file's timestamp, before
concluding something is stale.

**Not every missing package is a networking problem**
`rabbitmq.sh`'s `yum install erlang rabbitmq-server` will fail on relaunch —
confirmed via `sudo yum list available erlang rabbitmq-server` → "No matching
Packages to list", and `sudo dnf repolist all` showed no relevant disabled repo
to enable either. Unlike Incident #2 (right package, wrong network path), this
is a genuinely different problem: these packages simply aren't in Amazon Linux
2023's default repos at all, S3 endpoint or not. Different root cause needs a
different fix — added an internal S3-hosted yum repo (real production pattern
for air-gapped environments), rather than assuming the same fix as before would
apply.

**"What would we normally do here" is worth asking even mid-project**
Jumped straight into workaround options for the RabbitMQ packaging gap without
first asking whether a NAT Gateway (the actual common default) or a golden
AMI/Packer approach (arguably stronger practice) should be on the table too —
not just variations on the "no-NAT, S3-only" pattern already established
earlier in the project. Prior architecture decisions can accidentally narrow
later, unrelated decisions if not re-examined explicitly.

---

## Session — 2026-09-04 (cont'd — RabbitMQ Golden AMI Decision)

*From a parallel conversation on another account. Continues directly from the
"not every missing package is a networking problem" entry above — that session
initially approved the self-hosted S3 repo (Path 2), then reconsidered.*

**Golden AMI (custom AMI) — what it is and why**
An AMI is the template EC2 launches from — normally the stock Amazon Linux
image. A "golden AMI" is a custom one you build yourself: launch a base
instance, configure it exactly how you want (packages installed, services
enabled), then snapshot that configured instance into a new AMI. Anything
launched from it afterward starts already-configured — no userdata/bootstrap
step needed at launch. Trade-off vs. userdata: userdata reconfigures from
scratch on every fresh launch (slower boot, always current); a golden AMI boots
fast and consistently, but goes stale the moment the baked-in config needs to
change — it has to be rebuilt, not just re-run.

**Why golden AMI over the S3-repo path for Incident #3**
Both solve "erlang/rabbitmq-server aren't in Amazon Linux 2023's default repos,"
just at different layers: the S3-repo path (Path 2) fixes it at *install
time* — host a repo, sync and install at boot. Golden AMI (Path 3) fixes it at
*build time* — install once, bake into the image, no install step at boot at
all. Chosen reasoning: building the golden AMI manually first means the
eventual Packer template (which automates this same build) uses commands
already understood by hand, rather than being copied in blind — this project's
own "understand before automating" rule applied to the automation tool itself,
not just the app configuration.

**AMI creation: stopped vs. running instance**
`aws ec2 create-image` can technically target a live instance, but a *stopped*
instance gives a cleaner, more consistent snapshot — no risk of catching a file
mid-write or a service mid-transaction. Standard order: stop → create-image →
wait for the AMI to reach `available` → then terminate the source instance.

**t2 vs t3 instance families**
Both are "burstable performance" — cheap instances that bank CPU credits while
idle and spend them during short bursts, a good fit for light/intermittent
workloads like this project's EC2s. t3 is the newer generation: generally
better price/performance, and the one AWS steers new launches toward by
default now. t2 isn't deprecated, just older — no functional reason this
project needs one over the other. It became a live decision only because the
project had already standardized on `t2.micro` for every prior launch (db, mc,
rmq); picking `t3.micro` for just the new builder would be an unexplained
inconsistency without a stated reason. A good example of how a "minor" default
buried in a launch command can quietly turn into an architecture-consistency
question — worth catching before running the command, not after.
*Resolved: stayed on `t2.micro` for the builder, for exactly that consistency
reason.*

**A security group for an SSM-only instance needs zero inbound rules — not just no port 22**
Easy to think of "no bastion, no port 22" as the whole rule, but it goes
further: Session Manager works by the instance's SSM Agent dialing *out* to
AWS's SSM endpoints, nothing ever dials *in*. So the temp golden-AMI builder's
security group gets no inbound rules at all (not even a narrowed one) —
default outbound is all it needs. Same underlying reasoning as the VPC
Interface Endpoints from the 2026-09-03 session, just applied to the SG side
of the connection instead of the routing side.

---

## Session — 2026-09-04 (cont'd — RabbitMQ Builder Installation Checkpoint)

**Correction: Golden AMI replaced the earlier S3-repository idea**
A self-hosted S3 repository was considered for RabbitMQ, but it was not the final
implementation. This project chose a golden AMI instead: install RabbitMQ once on
a temporary public builder, then launch the final broker privately from the AMI.

**Private DNS can affect every subnet in a VPC**
Private DNS on an SSM interface endpoint redirects normal SSM lookups across the
whole VPC, not only the private subnet. *This project:* the public builder was
redirected to the private SSM endpoint, so `ssm-ep-sg` needed TCP 443 from
`vprofile-ami-builder-sg` before the SSM Agent could register.

**Package trust comes before installation**
A repository tells `dnf` where packages live; GPG keys let `dnf` verify that the
repository metadata and packages are trusted. *This project:* RabbitMQ signing
keys were accepted before installing Erlang 27.3.4.16 and RabbitMQ 4.3.5.

**Installed, enabled, and healthy are different states**
Installing puts software files on disk. Enabling means it will start after a boot.
A health check proves it is responding now. *This project:* `systemctl enable --now
rabbitmq-server` started and enabled the broker, then `rabbitmq-diagnostics ping`
returned `Ping succeeded`.

**Stopping the builder saves compute cost but does not create an AMI**
Stopping `i-0b3d1c51c83caab23` preserves its EBS disk and ends EC2 compute charges.
The instance is not yet a reusable AMI, and its EBS storage still has a small cost
until the builder is terminated after AMI creation and verification.

## Session — 2026-09-05 (RabbitMQ Golden AMI Finalized)

**`loopback_users` only matters for the `guest` account**
RabbitMQ's default config restricts the built-in `guest` user to localhost-only
connections. The Vagrant reference script disables this globally, but VProfile
never uses `guest` — it authenticates as its own `test` user, which has no such
restriction by default. *This project:* deliberately skipped the `loopback_users`
config change on the golden AMI since it wouldn't have changed anything for the
account we actually use — an explained omission, not a missed step.

**A golden AMI outlives the instance that built it**
Once `create-image` finishes, the resulting AMI is a fully independent resource —
terminating the source instance afterward doesn't affect it. *This project:*
builder `i-0b3d1c51c83caab23` was terminated right after AMI
`ami-0b553971033842a1d` reached `available`, with zero impact on the AMI itself.
"Verified" in PROGRESS.md isn't proof — check the actual resource. The golden AMI's 
write-up claimed the test RabbitMQ user was created and verified before the AMI snapshot. 
It wasn't — only guest existed on the launched instance. This project: 
caught via rabbitmqctl list_users on the newly launched vprofile-rmq, not by re-reading the docs. 
Lesson: documentation records an intended action; only re-checking the actual system confirms it happened.


**Bind address vs. security group — two different layers of the same problem**
Memcached defaults to binding only `127.0.0.1` (localhost) — nothing outside the
instance can reach it, even over the VPC network, until that's changed. *This
project:* `memcache.sh` uses `sed` to rewrite the bind address to `0.0.0.0`, then
`ss -tlnp | grep 11211` confirmed it was actually listening on `0.0.0.0:11211`
before trusting `systemctl status` alone — a service can report "active" while
still bound to localhost only. The bind address controls whether the service
*can* accept outside connections at all; the security group (`mc-sg`, port 11211
from `app-sg` only) controls *who's allowed to*. Memcached has no built-in
authentication, so the SG is the only real access boundary — standard for
Memcached, not a shortcut.

**"Running" isn't "verified" — same lesson, third time**
Same pattern as RabbitMQ: an EC2 instance reporting `running` only proves the OS
booted, not that userdata succeeded or the service works correctly. *This
project:* both Memcached and MariaDB relaunches were checked against
`cloud-init-output.log` for userdata errors, then service status, then an
actual functional check (`ss` for Memcached's listen address, `SHOW TABLES` for
MariaDB's schema import) — the same three-layer verification used for
RabbitMQ's `test` user.

**Scope-creep vs. a deliberate follow-up item**
Considered moving DB and RabbitMQ credentials to Secrets Manager/SSM Parameter
Store during this session, since both were already flagged as hardcoded-password
Known Issues. Decided against doing it mid-relaunch — it's real, separate work
(new secret, new IAM policy, script rewrite, new failure surface), not a small
aside, and bundling it into "verify the DB relaunch" would make it harder to
tell which part failed if something broke. Logged instead as a deliberate,
separately-scoped Phase 2 cleanup task — the point being that simplification
should be an explicit, tracked decision, not something silently deferred and
forgotten.

**Phase 2 closed — all three backend services verified simultaneously running**
`vprofile-rmq`, `vprofile-mc`, `vprofile-db` all running at once for the first
time in this project. Worth noting for cost awareness even though all are
`t2.micro` — first time observing what full backend-tier compute cost looks
like before Tomcat/ALB are added in later phases.

## Session — 2026-09-07 (Secrets Manager Migration — Networking Gap)

**IAM permission ≠ network reachability — two separate failure modes that look
similar at first**
Granting `secretsmanager:GetSecretValue` in IAM only controls *who's allowed to
ask*; it says nothing about *whether the request can physically reach the
service*. This project's db-role could legitimately call Secrets Manager
(confirmed by the policy being correctly scoped and present) but the private
subnet had no network path there at all — no NAT Gateway, no VPC endpoint for
that specific service. The failure mode is also different: an IAM denial fails
fast with a clear `AccessDenied` error; a missing network path just hangs
indefinitely with no error at all, until something (a timeout, or cloud-init
itself) gives up. Blinking cursor / hung command is itself a diagnostic signal
pointing toward network reachability, not permissions or syntax.

**Different AWS services need different VPC endpoints — S3's endpoint doesn't
cover Secrets Manager**
This project already had an S3 Gateway Endpoint (free, route-table-based) and
three SSM Interface Endpoints. Assuming "we have endpoints, we're fine" was
wrong — Secrets Manager is a distinct service with its own endpoint
(`com.amazonaws.us-east-1.secretsmanager`), same Interface-endpoint type and
cost profile as the SSM ones, but a completely separate resource. Every AWS
service reached privately needs its own endpoint (or a NAT Gateway covering
everything generally) — there's no "internet access" as a single on/off switch.

**Diagnosing a hang: isolate each layer instead of guessing**
When `get-secret-value` hung, the systematic approach was: (1) confirm IAM is
fine by testing a *different*, already-working call from the same role (S3
`cp`, which succeeded) — this isolates the problem to Secrets Manager
specifically, not the role generally; (2) confirm DNS resolves to the expected
private IP (`nslookup`) rather than a public one; (3) confirm the endpoint
itself is `available`, in the right subnet, with the right SG attached,
independent of trusting the create command's own echoed output; (4) confirm
security group rules in both directions (inbound on the endpoint's SG,
outbound on the client's SG). Each check ruled out one specific layer without
assuming the others were fine. Still open at end of session: raw TCP-level
connectivity and Network ACLs — the next two layers to check, since everything
checked so far came back clean.

**A "successful" AMI/instance launch doesn't mean userdata actually finished**
Same lesson as Phase 2, in a new form: the new vprofile-db instance reached
`running` and even progressed partway through its userdata (packages
installed, mariadb service created) before silently hanging on the Secrets
Manager call. `cloud-init-output.log` stopping mid-script, with no further
output, is the tell — not an error message, just an abrupt stop at the exact
line before the new (untested-at-the-time) code.

**Session paused near context/usage limit — mid-diagnosis, not mid-implementation**
Nothing destructive or half-applied is in flight: no resources were left in a
transitional state, the new db instance's incomplete userdata is a known,
documented, non-urgent issue (it can simply be relaunched once the network
issue is fixed). Safe to resume from PROGRESS.md's "Next Step" list without
replaying this session's diagnostic history.


## Session — 2026-09-07 (cont'd — Secrets Manager Root Cause Found & DB Migration Verified)

**Isolating "network path" from "AWS CLI's own request flow" as separate diagnostic layers**
After ruling out IAM, DNS, SG, and endpoint config in the prior session, this
session tested progressively higher layers: raw TCP connect (`/dev/tcp` to the
endpoint IP) succeeded instantly; a verbose `curl` completed a full TLS
handshake and got a real HTTP response (`404 UnknownOperationException` —
Secrets Manager's own expected reply to an unspecified action, not an error);
an IMDS credential check got an instant `401` (expected for IMDSv2 without a
token, but proves IMDS itself is reachable and fast). All four layers came
back clean — meaning the block wasn't in networking at all, it had to be in
timing/sequencing instead.

**Comparing timestamps confirmed a race, not a residual network fault**
Instance launch time (`06:10:18`) vs. Secrets Manager VPC endpoint creation
time (`06:21:28`) — an 11-minute gap, with the instance launched *first*.
Userdata runs once at boot, so it tried to reach an endpoint that plainly
didn't exist yet. This explains why every individual network check came back
fine when tested manually later: by the time anyone checks by hand, the race
is long over. Lesson: a "successful" endpoint creation later doesn't mean it
existed when something *earlier* tried to use it — check creation order, not
just current state, when a timing-sensitive dependency is involved.

**Fail-fast beats silent continuation, even for "it'll probably work" calls**
`mysql.sh` had no error check after the `DB_PASS=$(aws secretsmanager ...)`
line. When that call timed out, the script kept going anyway — running
`mysqladmin` with an effectively blank password, which cascaded into a much
more confusing downstream error (`Unknown database 'accounts'`) that looked
unrelated to its actual cause. Added an explicit `if [ -z "$DB_PASS" ]; then
exit 1; fi` check right after the fetch. Small change, meaningfully better
diagnosability if this ever happens again — the log would say exactly what
failed, immediately, instead of failing confusingly three steps later.

**DB-side Secrets Manager migration verified end-to-end**
New `vprofile-db` (`i-0c7f0a845aee0ea20`) launched after the endpoint existed;
`cloud-init-output.log` clean, `mariadb.service` active, `accounts` DB present
with all three expected tables, and login as `admin`/`admin123` succeeded —
confirming the Secrets Manager-fetched password actually matched what was
used to create the admin user. Both prior instances from this migration
(the stuck launch and the old pre-migration fallback) terminated after
verification, per the project's "verify before terminating a fallback" pattern
used earlier for RabbitMQ/Memcached too.

## Session — 2026-09-07 (cont'd — RabbitMQ AMI Rebuild, Cloudsmith URL Drift)

**Third-party repo-setup scripts can move their own URLs without warning**
The Cloudsmith setup scripts for both `rabbitmq-erlang` and `rabbitmq-server`
that worked during the original AMI build now 404 at their old URLs
(`public/rabbitmq/...`). The actual current location is a different namespace
entirely (`public/rabbitmq-dev/...`) — not a typo or a networking problem, an
upstream vendor change. *This project:* diagnosed via `curl -w
"%{http_code}"` instead of relying on the piped `curl | bash` one-liner, which
fails completely silently (`-f` suppresses the error body) when the URL 404s.
Worth remembering as an interview example of external dependency drift — a
frozen "it worked when I built this" script can go stale purely from a
vendor's side, with zero code change on this project's part.

**A script reporting "success" doesn't mean the thing it configured is usable**
Both Cloudsmith setup scripts printed their own "installed successfully" green
checkmark message, repo files were added, GPG keys imported — every visible
signal said it worked. `dnf install -y erlang rabbitmq-server` still failed
immediately after with "No match for argument" for both packages. Same
"reported ≠ verified" pattern as `cloud-init-output.log`/`systemctl status`
earlier in this project, now showing up in a third-party installer's own
self-reported status message, not just our own scripts. Diagnosis in
progress at end of session — checking `dnf repolist all` and directly listing
each repo's available packages next, rather than assuming the repo names or
package names guessed from the setup script's own naming convention.

## Session — 2026-09-07 (cont'd — RabbitMQ Node-Identity Pinning)

**RabbitMQ's node identity is hostname-derived, and that breaks golden AMIs**
RabbitMQ nodes identify themselves as `rabbit@<hostname>` by default. All
per-node data — including users — lives under a directory keyed to that name.
*This project:* the v3 golden AMI baked in a `test` user under
`rabbit@ip-172-20-1-52` (the builder's hostname). Every EC2 instance gets its
own unique hostname, so the next launch came up as a different node identity,
found no matching data directory, and silently initialized fresh — `test` was
simply gone, no error, just `guest` again.

**Fix: pin the node name explicitly, but that introduces a DNS-shaped requirement**
Setting `NODENAME=rabbit@vprofile-rmq` in `/etc/rabbitmq/rabbitmq-env.conf`
makes every instance from the AMI use the same fixed identity. But Erlang's
distribution layer actually resolves the node name's host part over the
network stack, even for a single, non-clustered node — pinning the name
without anything able to resolve it produced an `epmd_error ... nxdomain`
on startup. Fix: add `127.0.0.1 vprofile-rmq` to `/etc/hosts` before first
start, so the name resolves locally. This `/etc/hosts` entry is part of the
AMI snapshot too, so it carries to every future launch — correct, since we
only need loopback resolution, not real network identity.

**Lesson for golden AMIs generally**
Anything an application derives from machine identity at first run (hostname,
generated node names, machine IDs) is a landmine for golden AMIs — the value
gets baked in from the builder's identity, not the eventual instance's. Worth
checking for this class of issue before snapshotting, not after a failed
relaunch.

## Session — 2026-09-08 (cont'd — Phase 3 Tomcat Setup)

**WAR file (Web Application Archive)**
The compiled, deployable form of a Java web app — a zip file with a specific
structure that Tomcat knows how to unpack and serve. Built with `mvn package`.
*This project:* `vprofile-v2.war` built locally, uploaded to
`s3://vprofile-artifacts-747336059892/app/vprofile-v2.war`.

**WAR "explosion"**
Tomcat automatically unzips ("explodes") a `.war` file into a real folder on
first start. `ROOT.war` → `webapps/ROOT/`. Needed before we can write the
override `application.properties` into `webapps/ROOT/WEB-INF/classes/`.

**Spring Boot config override**
If an `application.properties` exists at `webapps/ROOT/WEB-INF/classes/`, it
overrides the one baked into the WAR at build time. *This project:* used to
inject real credentials (from Secrets Manager) and real backend IPs (from
describe-instances) without rebuilding the WAR.

**systemd service file**
A file that tells Linux how to manage a background process — how to start it,
stop it, restart it on crash, and when to launch it at boot. *This project:*
`/etc/systemd/system/tomcat.service` runs Tomcat as the non-root `tomcat` user,
restarts automatically on crash (`Restart=always`), and starts after the network
is up (`After=network.target`).

**`set -e` in bash scripts**
Makes the entire script exit immediately if any command fails — a blanket
fail-fast that catches errors at the actual failure point instead of letting
broken state cascade into confusing downstream errors. Applied to `tomcat.sh`.

## Session — 2026-09-08 (cont'd — Tomcat Script Finalized & Instance Launched)

**A missing shebang is an easy, silent mistake when copy-pasting scripts**
Manually stitching a script together in Notepad dropped the `#!/bin/bash` line entirely — the
script still looked complete and `bash -n` doesn't catch this (it's not a syntax error, just a
missing hint about which interpreter to use). *This project:* caught by asking to see the actual
saved file rather than trusting "I stitched it together" — same "verify the real file, not the
described one" principle already applied to PROGRESS.md edits.

**Two different "empty" cases for AWS CLI `--query` output**
A truly blank string and the literal text `"None"` are both possible "not found" results from
`describe-instances --query`, and they need separate checks (`-z "$VAR"` catches blank; `"$VAR" ==
"None"` catches the no-match case) — a single check misses one of them. *This project:* used for
all three backend IP lookups in `tomcat.sh`, filtered additionally by
`instance-state-name=running` so old terminated instances with the same Name tag can't match.

**Reference-script package names don't carry over between Linux distributions**
The Vagrant `tomcat.sh` used `java-17-openjdk` — correct for its original distro, but AL2023 only
ships Java as Amazon Corretto (`java-17-amazon-corretto`), confirmed via AWS's own Corretto docs
before trusting the reference script's naming. Same lesson as the Cloudsmith RabbitMQ URLs and the
AL2023 `dnf`-vs-package-availability gap — each reference script's assumptions get re-verified per
project, not copy-pasted on faith.

**"Trust but verify" caught nothing this time — and that's still worth confirming**
Re-checked `vprofile-app-role`, its instance profile, and `vprofile-app-sg` against live AWS state
before building on top of them, even though `PROGRESS.md` already recorded them as done. Unlike the
RabbitMQ `test`-user incident, this time the documented state matched reality exactly. Worth noting
that the verification habit doesn't only exist to catch drift — confirming *no* drift is also a
valid, useful outcome, not wasted effort.

## Session — 2026-09-08 (cont'd — Phase 3 Tomcat Boot Failures, Two New Endpoint Gaps)

**Every AWS service needs its own VPC endpoint — reinforced a third time**

First S3, then Secrets Manager, now the general EC2 API all turned out to need their own separate endpoint. This project: ec2messages (already present for SSM Session Manager) looked like it might cover general EC2 API calls (describe-instances) — it doesn't. Same name prefix, completely unrelated service. tomcat.sh's IP-lookup step needed a dedicated com.amazonaws.us-east-1.ec2 endpoint that never existed until this session.

**A security group built for one consumer doesn't automatically cover a new one**

vprofile-secretsmgr-ep-sg was created back when only db/rmq called Secrets Manager. When vprofile-app became a third caller in Phase 3, nothing updated that SG automatically — it silently blocked the new consumer with the exact same "connect timeout, no error message" symptom as a missing endpoint entirely. Lesson: adding a new consumer of an existing shared resource (endpoint, SG, IAM role) means re-checking whether that resource's access rules were scoped to the old set of consumers only.

**"Deployed" and "started successfully" are different claims for a WAR**

Tomcat's own log showed Deployment of web application archive [...] has finished — meaning the WAR was correctly exploded into ROOT/. But right above that same log block was SEVERE ... Context [] startup failed due to previous errors, caused by Spring failing to resolve ${jdbc.driverClassName} — an unfilled config placeholder. A 404 on curl didn't mean "nothing was deployed" like I first assumed from timestamps alone; it meant "deployed, but the app crashed on startup before it could serve anything." journalctl (Tomcat's systemd-captured output) was the log that actually showed this — catalina.out doesn't exist for a systemd-managed Tomcat; its stdout/stderr goes to the journal instead.

**Tomcat under systemd doesn't use catalina.out**

Expected Tomcat's traditional log file at $CATALINA_HOME/logs/catalina.out — it didn't exist. Under systemd, Tomcat's stdout/stderr is captured by the journal instead. sudo journalctl -u tomcat --no-pager is the correct way to see Tomcat's own startup/deployment messages when it's managed this way, not the log file.

## Session — 2026-09-08 (cont'd — Spring Placeholder Cascade Resolved)

**Spring resolves ALL `@Value` placeholders at startup, not lazily per feature**
A missing config key doesn't just break the feature that uses it — it fails the entire app's
context initialization, even for a feature this project never uses (Elasticsearch, a real
memcached standby). *This project:* three separate missing keys
(`jdbc.driverClassName`, `memcached.standBy.*`, `elasticsearch.*`) each independently crashed
Tomcat on startup, one revealed per restart, because Spring tries to wire every bean's
properties up front rather than only when that code path is hit. Useful diagnostic corollary:
once a startup log shows zero `SEVERE` entries, every `@Value` in the app resolved
successfully — a strong (not just circumstantial) signal that no more missing keys remain,
without needing to separately diff the source config.

**Reference-project config sometimes contains dead/unused blocks that still must be present**
VProfile's original `application.properties` includes an Elasticsearch block and a memcached
"standby" host, from features the reference app supports but this project's architecture never
implements. *This project:* rather than building a real ES cluster or a second Memcached
instance, the fix was adding the same dummy placeholder values the reference project itself
ships with (`elasticsearch.host=192.168.1.85`, `memcached.standBy.host=127.0.0.2`) — Spring only
needs the property to resolve to *something*, not to a reachable service, unless that feature
is actually exercised at runtime.

**A trimmed AL2023 install can lack tools you'd assume are always present**
Neither `unzip` nor `jar` was available on `vprofile-app` — `unzip` was deliberately removed
from `tomcat.sh` earlier as unused, and `java-17-amazon-corretto` turned out not to include the
full JDK's `jar` tool. *This project:* rather than installing either just for a one-off
verification read, judged the check unnecessary once the clean startup log already gave
equivalent proof (see placeholder-resolution note above) — a good example of stopping a
diagnostic path once its marginal value drops below its cost, rather than continuing on
momentum.

## Session — 2026-09-08 (cont'd — Phase 4 ALB)

**Target group is a separate resource from the load balancer, on purpose**
The ALB only knows "receive on port X, forward to target group Y" — it doesn't hold health-check
config or the list of instances itself. That separation is what lets one ALB route to multiple
target groups later (blue/green, path-based routing) without this project needing any of that
now. *This project:* `vprofile-app-tg` exists independently and briefly sat in an `unused` state
(`Target.NotInUse`) after registering `vprofile-app` but before a listener existed — expected,
not a bug: health checks only start once a listener actually attaches the target group to traffic.

**HEAD, GET, and POST can each get a different answer from the same URL**
`curl -I` sends a `HEAD` request. `/login` returned `405 Method Not Allowed, Allow: POST` for
both `HEAD` and an explicit `GET` — it's the form-submission endpoint, not the page that displays
the login form. Used `/` for the ALB health check instead, which had already proven itself with a
plain `200` back in Phase 3. Lesson: an endpoint's name (`/login`) doesn't tell you which HTTP
method it actually accepts — worth testing directly rather than assuming.

**A third Git-Bash-on-Windows path-translation gotcha: `MSYS_NO_PATHCONV`**
`--health-check-path /` was silently rewritten to `C:/Program Files/Git/` by Git Bash's MSYS
layer before AWS CLI ever saw it — same root cause family as the earlier `file://` userdata
issue (Git Bash assuming any Unix-looking path argument needs Windows translation, even when
it's just a plain string flag value). Fix: prefix the single command with `MSYS_NO_PATHCONV=1`,
scoped to that invocation only, rather than disabling path conversion globally (which could break
other commands that genuinely need it).

**`0.0.0.0/0` is correct here, not a shortcut**
Opening `alb-sg` to all inbound IPv4 on port 80 looks alarming in isolation, but it's the
intended design: the ALB is the one deliberately public-facing resource in this architecture,
and the actual access boundary is one layer further in — `app-sg` still only accepts port 8080
from `alb-sg` specifically, not from the internet. Public exposure is funneled through a single,
narrow, audited entry point rather than removed entirely (which isn't possible for a public
website anyway).

**`journalctl` without `-b` shows every boot's history, not just the current one**
Right after restarting `vprofile-app`, `journalctl -u tomcat | grep -i severe` returned several
old `SEVERE` entries — all timestamped hours earlier, from an interrupted boot during Phase 3's
Incident #5 troubleshooting. They weren't wrong, just stale: `journalctl -u tomcat -b` (current
boot only) came back empty, confirming the *current* startup was actually clean. Comparing
timestamps against `systemctl status`'s "Active since" line is one way to catch this; `-b` is the
more direct fix.

**End-to-end verification means checking the same fact two different ways**
`curl -I localhost:8080` (direct, from inside the instance) and
`curl -I http://vprofile-alb-...elb.amazonaws.com` (through the ALB, from outside) returned
identical `Content-Length: 7935` — that specific match is what actually proves the ALB is serving
real app content end-to-end, not just returning *some* `200` from a misconfigured default.
