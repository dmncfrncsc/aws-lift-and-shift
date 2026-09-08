# ADR-lite Decision Log — aws-lift-and-shift

Lightweight architecture decision records for this project. Each entry covers a decision
that was genuinely deliberated with real alternatives on the table — not every small config
choice gets one. Numbered in roughly the order the decisions were made.

---

## ADR-001: Dedicated VPC Instead of the Default VPC

**Context**
AWS accounts come with a default VPC pre-configured and ready to use immediately.

**Alternatives Considered**
1. Use the account's default VPC.
2. Build a dedicated VPC from scratch.

**Trade-offs**
The default VPC is faster to start with and requires no networking design. A dedicated VPC
takes longer to set up but forces hands-on practice with subnets, route tables, and gateways
— exactly the skills this project exists to demonstrate.

**Decision**
Built a dedicated VPC (`172.20.0.0/16`) with explicit public and private subnets. For a
learning-and-portfolio project, using the default VPC would have skipped the actual
networking design work being evaluated.

---

## ADR-002: No NAT Gateway

**Context**
The private subnet needs some way to let instances reach AWS services and package
repositories without being directly internet-exposed. A NAT Gateway is the standard
production answer.

**Alternatives Considered**
1. NAT Gateway — full outbound internet access from the private subnet.
2. VPC Endpoints per service (Gateway endpoint for S3, Interface endpoints for everything
   else needed) — private AWS-only paths, no general internet access.

**Trade-offs**
A NAT Gateway is the field's default and requires zero per-service configuration, but costs
roughly $32–35/month plus data processing charges, and provides *general* internet access
that this project doesn't actually need — every private-subnet dependency turned out to be
either an AWS service (S3, Secrets Manager, EC2 API, SSM) or something that could be
pre-staged to S3.
VPC Endpoints are free (Gateway) or cheap (~$0.01/hr per Interface endpoint per AZ), and
narrower — but each new AWS service dependency needs its own endpoint added explicitly, and
this was genuinely easy to miss (see Incidents 1, 4, and the earlier Secrets Manager
networking gap — three separate times a missing endpoint caused a silent connect-timeout
failure).

**Decision**
No NAT Gateway. Used VPC Endpoints per service instead, accepting the recurring
"remember to add an endpoint for each new AWS service" maintenance cost in exchange for
avoiding NAT's recurring dollar cost and unnecessary blanket internet access. This is
explicitly named in the README as a portfolio-scale simplification, not a claim that
VPC-Endpoints-only is always the better production choice — a NAT Gateway is still the more
common default for teams that need general outbound internet access.

---

## ADR-003: SSM Session Manager Instead of a Bastion Host

**Context**
Some way to access private-subnet instances for troubleshooting and manual configuration is
needed.

**Alternatives Considered**
1. Bastion host — a small public EC2 instance instances SSH through, requiring an open port
   22 security group rule.
2. AWS Systems Manager Session Manager — the SSM Agent on each instance dials *out* to AWS's
   SSM endpoints; nothing needs to accept inbound connections at all.

**Trade-offs**
A bastion host is a familiar, simple pattern but is itself another instance to patch, secure,
and pay for, and requires at least one open inbound port somewhere in the architecture. SSM
Session Manager needs no open inbound ports anywhere and gives full audit logging of session
activity, but requires VPC Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`) since
there's no NAT Gateway for it to reach the public SSM service instead.

**Decision**
SSM Session Manager. No bastion host, no port 22 open anywhere in the architecture — every
security group in this project has zero SSH-related inbound rules.

---

## ADR-004: One Security Group Per Service

**Context**
Multiple services (ALB, app, database, cache, message broker, VPC endpoints) each need
different, specific inbound access rules.

**Alternatives Considered**
1. One broad, shared security group covering multiple services.
2. A dedicated security group per service.

**Trade-offs**
A shared SG is less setup work initially, but any rule change affects every service using
it, and it becomes hard to audit exactly what can reach what. Per-service SGs mean more
initial setup and more resources to track, but each one's rules stay legible and scoped —
e.g. `mc-sg` allows port 11211 from `app-sg` only, `db-sg` allows 3306 from `app-sg` only.

**Decision**
One security group per service. This also directly surfaced Incident 4 (a shared endpoint
SG that wasn't updated for a new consumer) — a concrete example of why narrow, auditable
scoping matters even when it means more resources to manage.

---

## ADR-005: Per-Instance IAM Roles When Permission Needs Differ

**Context**
Several EC2 instances initially shared one IAM role (`vprofile-ssm-role`) for baseline SSM
access. Some instances then needed additional, service-specific permissions (S3 read for the
DB instance's schema file, Secrets Manager read for DB and RabbitMQ, Secrets Manager + S3 +
EC2 API read for the app instance).

**Alternatives Considered**
1. Widen the shared role to include every permission any instance might need.
2. Give each instance with different needs its own dedicated role.

**Trade-offs**
Widening the shared role is less setup work, but grants permissions to instances that never
asked for them — e.g. Memcached and RabbitMQ would gain S3 read access they don't use, just
because the database instance needed it. Dedicated roles mean more IAM resources to create
and track, but each instance's actual permission set stays visibly scoped to what it needs.

**Decision**
Dedicated roles whenever a permission need diverges from the shared baseline
(`vprofile-db-role`, `vprofile-rmq-role`, `vprofile-app-role`), keeping the shared
`vprofile-ssm-role` only for instances with genuinely identical needs. This is the same
least-privilege reasoning as ADR-004, applied to IAM instead of networking.

---

## ADR-006: Golden AMI for RabbitMQ (Instead of NAT Gateway or Self-Hosted S3 Repo)

**Context**
Erlang and RabbitMQ packages are not available in Amazon Linux 2023's default repositories
at all (Incident 3) — this is a packaging gap, not a networking gap.

**Alternatives Considered**
1. NAT Gateway — reach RabbitMQ's real upstream repos over the public internet at boot.
2. Self-hosted S3 repository — mirror the needed packages into the project's own S3 bucket,
   install from there at boot.
3. Golden AMI — install once on a temporary public builder instance, snapshot the configured
   result, launch the final broker from that image with no install step at boot at all.

**Trade-offs**
NAT Gateway reverses ADR-002 for the sake of one service's package availability, and adds
recurring cost that outlasts the actual one-time need. A self-hosted repo avoids that but
adds ongoing repo-maintenance scope (keeping the mirror current) for something the project
only needs to install once. The golden AMI needs a temporary builder instance and produces
an image that goes stale the moment the baked-in config needs to change — but installs
nothing at boot, boots fast and consistently, and doesn't touch the no-NAT architecture at
all.

**Decision**
Golden AMI. Also chosen because building it manually first (before any Packer automation)
follows the project's own "understand before automating" principle — the eventual
automation would use commands already understood by hand.

---

## ADR-007: Secrets Manager Over SSM Parameter Store for Credentials

**Context**
Database and RabbitMQ credentials were originally hardcoded in userdata scripts (a known,
tracked issue from early in the project) and needed to move to a managed secret store.

**Alternatives Considered**
1. SSM Parameter Store (SecureString) — general-purpose config/secret storage, effectively
   free.
2. AWS Secrets Manager — purpose-built for credentials, ~$0.40/secret/month, with built-in
   rotation support.

**Trade-offs**
Parameter Store is essentially free and would have worked functionally identically for this
project's scale. Secrets Manager costs roughly $1/month total for the two secrets here and
its main differentiator — automatic rotation — isn't actually used in this project yet.

**Decision**
Secrets Manager, on category-fit grounds rather than cost: it's the AWS service explicitly
designed for credentials, even though the near-zero cost difference and unused rotation
feature mean Parameter Store would have been a defensible choice too. Existing password
values were kept as-is during the migration (moving storage location, not rotating values)
since rotation was judged separate, out-of-scope work.

---

## ADR-008: EC2 Tag-Based Service Discovery Instead of Route 53 / Cloud Map

**Context**
Tomcat's userdata needs the current private IP addresses of the database, cache, and message
broker instances at boot time. These IPs can change on any relaunch (and had, multiple times
in this project already).

**Alternatives Considered**
1. Hardcode private IPs into `tomcat.sh`.
2. Look up current IPs at boot via `aws ec2 describe-instances`, filtered by each instance's
   `Name` tag.
3. DNS-based service discovery — a Route 53 private hosted zone, or AWS Cloud Map — the
   actual production-standard answer to this problem.

**Trade-offs**
Hardcoding is simplest but breaks on every relaunch, which had already happened repeatedly.
Tag-based lookup avoids that but requires `vprofile-app-role` to hold
`ec2:DescribeInstances`, which — unlike this project's other IAM policies — can't be scoped
to specific instance ARNs; it's read-only but necessarily account-wide. Route 53 / Cloud Map
is the real production pattern and avoids the account-wide permission, but was already
excluded from this project's architecture for cost/scope reasons (ADR-011), and reversing
that just to solve this one problem would need its own separate justification.

**Decision**
Tag-based `describe-instances` lookup. Named explicitly in the README as a simplification,
with Route 53 / Cloud Map called out as the production alternative — not something to
present as if dynamic tag lookup were the real-world standard answer.

---

## ADR-009: No HTTPS / ACM Certificate on the ALB

**Context**
The ALB currently serves HTTP only, on port 80.

**Alternatives Considered**
1. HTTP only.
2. HTTPS via an AWS Certificate Manager certificate, which requires a custom domain to
   validate against.

**Trade-offs**
HTTPS is the correct production default and ACM certificates themselves are free, but
validating one requires owning a domain and pointing its DNS at AWS — neither of which
exists for this project (see ADR-011, no Route 53 hosted zone).

**Decision**
HTTP only, for now. Named explicitly in the README as a production gap, not a silent
omission — adding a real domain would be the natural trigger to revisit this.

---

## ADR-010: `t2.micro` Retained Across All Instances

**Context**
A new instance (the temporary RabbitMQ AMI builder) was being launched after every prior
instance in the project (`db`, `mc`, `rmq`) had already standardized on `t2.micro`.

**Alternatives Considered**
1. `t2.micro` — the family already used everywhere else in the project.
2. `t3.micro` — same burstable-performance model, newer generation, generally better
   price/performance, and the family AWS now steers new launches toward by default.

**Trade-offs**
`t3.micro` is technically the better current default with no functional downside for this
workload. `t2.micro` has no advantage over `t3.micro` on its own merits — the only reason to
prefer it here is architectural consistency with every other instance already launched.

**Decision**
Stayed on `t2.micro`, for consistency alone. Documented explicitly as a "minor default that
could quietly become an inconsistency" — worth catching before running the launch command,
not after.

---

## ADR-011: No Route 53 Hosted Zone

**Context**
The application needs to be reachable at some URL. A Route 53 hosted zone with a custom
domain is the standard way to give a production app a friendly, stable name.

**Alternatives Considered**
1. Route 53 hosted zone with a custom domain pointed at the ALB.
2. Use the ALB's own auto-generated DNS name directly.

**Trade-offs**
A custom domain is more professional-looking and is a prerequisite for ADR-009's HTTPS
option, but requires either owning a domain already or registering one (recurring cost) for
a project with no real users. The ALB's own DNS name works identically for demonstrating the
architecture and costs nothing extra.

**Decision**
No hosted zone; used the ALB's DNS name (`vprofile-alb-932338318.us-east-1.elb.amazonaws.com`)
directly. This decision is upstream of, and directly explains, ADR-009's HTTP-only choice.
