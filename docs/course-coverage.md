# Course Coverage Matrix — aws-lift-and-shift (Project 1)

This matrix covers only the course topics **this project** (Project 1 of 5) is responsible for,
per the Portfolio Plan's project-to-course mapping. Topics owned by later projects — Terraform,
Ansible, CI/CD, Elastic Beanstalk/RDS, Kubernetes/GitOps — are intentionally **not** claimed here;
they get their own coverage matrix in their own repo when that project is built. Forcing full
course coverage into one project would misrepresent what was actually done in this one.

## Status definitions

- **Fully demonstrated** — implemented, verified working, and something I can explain end-to-end
  in an interview (what it does, why it was chosen, what broke, how it was fixed).
- **Partially demonstrated** — touched, but shallow, incomplete, or verified only indirectly.
- **Not demonstrated** — genuinely not built in this project, whether by scope (belongs to a later
  project) or by a deliberate architecture decision (see `PROGRESS.md` Key Decisions).
- **Not portfolio-relevant** — a course topic with little standalone recruiter/interview value on
  its own merits, not because it was skipped for convenience.

A concept is never marked "demonstrated" just because a service name appears in the repo — it
needs a real implementation and verification behind it, per each row's Evidence column.

---

## Networking

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| VPC design & CIDR planning | Custom VPC `vprofile-vpc` (`172.20.0.0/16`), three subnets across two AZs with distinct CIDR blocks | PROGRESS.md Phase 1; Resource Reference table | Fully demonstrated |
| Public vs. private subnets | ALB in public subnets; all four backend EC2s in a private subnet with no direct internet route | PROGRESS.md Phase 1; `docs/architecture.md` diagram 1 | Fully demonstrated |
| Internet Gateway & route tables | IGW attached, public route table routes `0.0.0.0/0` to it; verified as a distinct table from the VPC's main table | PROGRESS.md Phase 1; NOTES.md 2026-09-03 (route table association lesson) | Fully demonstrated |
| Security groups (least privilege) | One SG per service (`alb-sg`, `app-sg`, `db-sg`, `mc-sg`, `rmq-sg`, plus per-endpoint SGs), each scoped to a specific source SG and port, not CIDR ranges | PROGRESS.md Resource Reference; Incident #4 (SG scoped to wrong consumer, caught and fixed) | Fully demonstrated |
| VPC Interface Endpoints (PrivateLink) | Six separate Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`, `secretsmanager`, `ec2` API) — each AWS service needed its own | PROGRESS.md VPC Endpoints table; Incidents #1 and #4; NOTES.md "every AWS service needs its own VPC endpoint" (repeated 3 times across sessions) | Fully demonstrated |
| VPC Gateway Endpoint (S3) | Free, route-table-based S3 access from the private subnet, used for yum repos and artifact downloads | PROGRESS.md Phase 1; Incident #1 resolution | Fully demonstrated |
| NAT Gateway | Deliberately excluded — architecture decision to avoid recurring hourly cost; RabbitMQ packaging gap solved via golden AMI instead | PROGRESS.md Key Decisions ("No NAT Gateway"); Incident #3 | Not demonstrated (deliberate exclusion, not a gap) |
| DNS / Route 53 | Deliberately excluded — ALB DNS name used directly instead of a hosted zone; service discovery uses `describe-instances` instead of private DNS | PROGRESS.md Key Decisions ("No Route 53 hosted zone"); Key Decisions ("Phase 3 service discovery") | Not demonstrated (named simplification, production alternative documented) |
| Core networking fundamentals (IP, CIDR, ports, TCP/UDP) | Applied throughout SG rules, subnet design, and endpoint troubleshooting; started from zero prior networking experience | NOTES.md — networking entries across nearly every session | Fully demonstrated |

## Compute & AMI Management

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| EC2 launch & configuration | Four backend instances + ALB, all `t2.micro`, launched via AWS CLI with explicit subnet/SG/instance-profile choices | PROGRESS.md Phase 2–4 | Fully demonstrated |
| Userdata / bootstrap automation | Bash userdata scripts for `db`, `mc`, `app` — package install, service config, credential/IP fetch at boot | `userdata/*.sh`; PROGRESS.md Phase 2–3 | Fully demonstrated |
| Custom/golden AMI creation | RabbitMQ: manually built, snapshotted, and iterated through 4 versions (packaging gap → node-identity bug → fix) | PROGRESS.md "RabbitMQ golden AMI rebuild"; NOTES.md 2026-09-04/09-05/09-07 (node-identity pinning) | Fully demonstrated |
| Auto Scaling | Not implemented — single instance per tier, appropriate for portfolio scale, not attempted as a false claim | — | Not demonstrated (out of scope for this project's architecture) |

## IAM & Security

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| IAM roles & instance profiles | Per-service roles (`vprofile-db-role`, `vprofile-rmq-role`, `vprofile-app-role`) plus a shared SSM-only role where permissions were genuinely identical | PROGRESS.md IAM Roles table; NOTES.md 2026-09-03 ("shared vs. per-instance roles — the actual rule") | Fully demonstrated |
| Least-privilege policy scoping | S3 read scoped to specific prefixes (`db/*`, `app/*`); Secrets Manager read scoped to specific secret ARNs; `ec2:DescribeInstances` explicitly noted as the one necessarily-unscoped exception | PROGRESS.md Phase 3; Secrets Manager Migration section | Fully demonstrated |
| Secrets management (AWS Secrets Manager) | DB and RabbitMQ credentials migrated off hardcoded values into Secrets Manager, fetched at boot with a fail-fast check if the fetch fails | PROGRESS.md "Secrets Manager Migration"; Known Issues (resolved) | Fully demonstrated |
| No SSH / bastion host | Zero inbound SSH anywhere; all access via SSM Session Manager | PROGRESS.md Key Decisions; `docs/architecture.md` | Fully demonstrated |
| Secret/credential hygiene in source control | `grep`-based secret sanity check run on IAM policy files before commit | Git history (`grep -iE "password|secret|AKIA|admin123"` before the IAM policy commit) | Fully demonstrated |

## Storage

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| S3 (buckets, access policies) | `vprofile-artifacts-...` bucket, all public access blocked, used for schema file, WAR, and Tomcat tarball | PROGRESS.md Phase 2–3 | Fully demonstrated |

## Load Balancing

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| Application Load Balancer | Internet-facing ALB across two public subnets, listener on port 80 forwarding to a target group | PROGRESS.md Phase 4 | Fully demonstrated |
| Target groups & health checks | Health check path verified before configuration (`/login` rejected as POST-only, `/` used instead); target flipped `unused` → `healthy` once the listener attached | PROGRESS.md Phase 4; NOTES.md 2026-09-08 (HEAD/GET/POST lesson) | Fully demonstrated |
| End-to-end request verification | Matched `Content-Length` between direct `curl localhost:8080` and the public ALB DNS name to confirm real app content flows through the full path | PROGRESS.md Phase 4; NOTES.md 2026-09-08 | Fully demonstrated |

## Observability & Cost Control

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| Billing alerts / cost awareness | CloudWatch billing alarms configured before any resource creation | PROGRESS.md Phase 0 | Fully demonstrated |
| Application/infrastructure monitoring (CloudWatch metrics, dashboards) | Not built — billing alarms only; no custom metrics, dashboards, or alerting on the app/instance tier | — | Not demonstrated (real monitoring/observability work is planned for the Kubernetes + PaaS projects, where there's a live system worth instrumenting) |

## Practices (cross-cutting, not single course sections)

| Course Topic | Implementation | Evidence | Status |
|---|---|---|---|
| Git workflow & Conventional Commits | Consistent `feat`/`fix`/`docs`/`chore` prefixes across the project history | Git log | Fully demonstrated |
| Systematic troubleshooting | Five logged incidents, each following symptom → root cause → resolution, including at least one case where an earlier "verified" claim turned out to be false and was caught by re-checking live state | PROGRESS.md Incidents #1–#5 | Fully demonstrated |
| Infrastructure as Code | Not used in this project — everything provisioned via AWS CLI by design, specifically so the next project (Terraform) has real manual-process pain to codify against | PROGRESS.md Portfolio Plan — recommended sequence, item 2 | Not demonstrated (deliberately deferred to Project 2, not a gap in this project) |
| Configuration management (Ansible) | Not used — same reasoning as IaC above | PROGRESS.md Portfolio Plan | Not demonstrated (deferred to Project 2) |
| CI/CD | Not used — no automated build/deploy pipeline; WAR was built and uploaded manually | — | Not demonstrated (deferred to Project 3) |
| Containers / Kubernetes | Not used — this project deploys directly to EC2, not containers | — | Not portfolio-relevant for this project (owned by Project 5) |

---

## Honest gaps worth naming explicitly

A few things this project does **not** demonstrate, stated plainly rather than glossed over:

- No Auto Scaling — single instance per tier throughout.
- No custom CloudWatch metrics or alerting beyond billing alarms — health is verified manually via
  SSM/curl, not through a monitoring stack.
- `ec2:DescribeInstances` on the app role is account-wide (can't be scoped to specific instance
  ARNs) — the one IAM permission in this project that isn't fully least-privilege, and it's
  documented as such rather than hidden.
- Route 53 / DNS-based service discovery was deliberately skipped in favor of a `describe-instances`
  tag lookup — functional, but not the production-standard approach, and the README/interview prep
  should name that trade-off directly if asked "how would you improve this."
