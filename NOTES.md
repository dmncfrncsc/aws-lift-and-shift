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
