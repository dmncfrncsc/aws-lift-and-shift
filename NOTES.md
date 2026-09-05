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
