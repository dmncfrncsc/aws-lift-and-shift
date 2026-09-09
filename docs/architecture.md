# Architecture

Two diagrams, split by concern:

1. **Network & Security Architecture** — VPC layout, subnets, security groups, and VPC endpoints.
   Answers "how is this isolated and secured?"
2. **Request Flow** — how a client request actually gets served, including the backend services,
   Secrets Manager, and S3 artifact retrieval.

Both reflect only what is actually implemented and verified in this project — no NAT Gateway,
no Route 53 (deliberately excluded; see Key Decisions in `PROGRESS.md`).

---

## 1. Network & Security Architecture

```mermaid
flowchart TB
    Internet(["Internet"])

    subgraph VPC["VPC — vprofile-vpc (172.20.0.0/16)"]
        IGW["Internet Gateway"]
        ALB["ALB — vprofile-alb (spans both public subnets)\nsg: alb-sg\n0.0.0.0/0 → :80"]
        RT["Public Route Table\n0.0.0.0/0 → IGW"]

        subgraph PrivA["Private Subnet 1a — 172.20.3.0/24 (us-east-1a)"]
            APP["EC2: vprofile-app\nsg: app-sg\n:8080 ← alb-sg"]
            DB["EC2: vprofile-db\nsg: db-sg\n:3306 ← app-sg"]
            MC["EC2: vprofile-mc\nsg: mc-sg\n:11211 ← app-sg"]
            RMQ["EC2: vprofile-rmq\nsg: rmq-sg\n← app-sg"]

            subgraph Endpoints["VPC Interface Endpoints (PrivateLink)\nsg: ssm-ep-sg / secretsmgr-ep-sg / ec2api-ep-sg"]
                EP_SSM["ssm"]
                EP_SSMMSG["ssmmessages"]
                EP_EC2MSG["ec2messages"]
                EP_SECRETS["secretsmanager"]
                EP_EC2API["ec2 (API)"]
            end
        end

        MAINRT["Main Route Table\nS3 prefix → S3 Gateway Endpoint"]
    end

    S3EP[("S3 Gateway Endpoint\n(free, route-table based)")]
    S3[("S3 bucket\nvprofile-artifacts-...")]
    SM[("Secrets Manager\ndb + rmq passwords")]

    Internet -->|":80"| IGW
    IGW --> ALB
    ALB -->|":8080"| APP

    APP -->|":3306"| DB
    APP -->|":11211"| MC
    APP --> RMQ

    APP -.->|"via secretsmanager endpoint"| EP_SECRETS
    DB -.->|"via secretsmanager endpoint"| EP_SECRETS
    EP_SECRETS -.-> SM

    APP -.->|"via ec2 API endpoint\n(describe-instances lookup)"| EP_EC2API

    APP -.->|"SSM Session Manager\n(no inbound needed)"| EP_SSM
    DB -.-> EP_SSM
    MC -.-> EP_SSM
    RMQ -.-> EP_SSM

    DB -.->|"via S3 Gateway Endpoint\n(schema file)"| S3EP
    APP -.->|"via S3 Gateway Endpoint\n(WAR, Tomcat tarball)"| S3EP
    S3EP -.-> S3

    RT -.->|"routes"| IGW
    MAINRT -.->|"routes"| S3EP

    classDef public fill:#fde8e8,stroke:#c0392b
    classDef private fill:#e8f0fe,stroke:#2c5fa8
    classDef svc fill:#eafaf1,stroke:#1e8449
    class ALB public
    class PrivA,APP,DB,MC,RMQ,Endpoints,EP_SSM,EP_SSMMSG,EP_EC2MSG,EP_SECRETS,EP_EC2API private
    class S3,S3EP,SM svc
```

**Key points this diagram makes:**
- Only the ALB sits in public subnets; every backend service (`app`, `db`, `mc`, `rmq`) is private,
  reachable only through security-group-scoped rules from the tier in front of it.
- No NAT Gateway, no bastion host, no inbound SSH anywhere — all instance access is via SSM
  Session Manager, which requires zero inbound rules (the SSM Agent dials out).
- Every AWS service reached privately needed its **own** VPC endpoint — `ssm`, `ssmmessages`,
  `ec2messages`, `secretsmanager`, and `ec2` (API) are five separate Interface Endpoints; S3 uses
  a free Gateway Endpoint via the route table instead. This was the single most repeated lesson of
  the project (Incidents #1, and the Secrets Manager / EC2 API gaps in Incident #4).
- `vprofile-rmq-role` has IAM permission to call Secrets Manager, but the diagram deliberately
  does **not** draw that arrow: `vprofile-rmq` launches from a golden AMI with no userdata
  (verified via `describe-instances` — `UserData` is `None`), so it never actually calls Secrets
  Manager at runtime. The `test` user's password was baked into the AMI during the manual build.
  The permission is provisioned for a future AMI rebuild that adopts the same fetch-at-boot
  pattern as `db`/`app`, not an active path today — a real, currently-unused piece of IAM scope,
  named here rather than silently implied as active.

---

## 2. Request Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant ALB as ALB (vprofile-alb)
    participant APP as Tomcat (vprofile-app)
    participant DB as MariaDB (vprofile-db)
    participant MC as Memcached (vprofile-mc)
    participant RMQ as RabbitMQ (vprofile-rmq)
    participant SM as Secrets Manager
    participant S3 as S3 (artifacts bucket)

    Note over APP,S3: Boot-time (userdata), before serving traffic
    APP->>SM: GetSecretValue (db + rmq passwords)
    SM-->>APP: password values
    APP->>S3: fetch WAR / Tomcat tarball
    S3-->>APP: artifact contents
    APP->>APP: describe-instances (EC2 API)<br/>resolve current private IPs of db/mc/rmq
    APP->>APP: write application.properties<br/>(real DB/RMQ IPs + credentials)

    Note over C,RMQ: Runtime — serving a request
    C->>ALB: HTTP GET /  (port 80)
    ALB->>APP: forward to target group (port 8080)
    APP->>DB: query (accounts schema)
    APP->>MC: cache read/write
    APP->>RMQ: publish/consume messages
    DB-->>APP: result set
    MC-->>APP: cached value
    APP-->>ALB: 200 OK
    ALB-->>C: 200 OK
```

**Key points this diagram makes:**
- Config values (DB/RMQ credentials, backend IPs) are resolved **dynamically at boot**, not
  hardcoded — credentials via Secrets Manager, IPs via a live `describe-instances` lookup keyed
  off each instance's `Name` tag. This survives any backend instance being relaunched with a new
  private IP (which happened repeatedly during this project).
- The named simplification: IP discovery via `ec2:DescribeInstances` (account-wide, read-only)
  instead of proper DNS-based service discovery (Route 53 private hosted zone / AWS Cloud Map) —
  a deliberate trade-off documented in `PROGRESS.md`, not the production-recommended pattern.
- RabbitMQ ships pre-configured via a golden AMI (no boot-time install step), unlike `app`/`db`/`mc`
  which install and configure via userdata — visible in the diagram as RMQ having no userdata
  fetch step shown for itself.
