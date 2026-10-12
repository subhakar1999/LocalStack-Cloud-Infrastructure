# LocalStack Cloud Infrastructure & UI Developer Guide

> **Developer & Agent Reference Document**  
> Comprehensive runbook, system topology, architecture flows, debugging playbooks, and extension guides for maintaining and evolving this local cloud infrastructure stack.

---

## 1. System Topology & Architecture

This project provides a complete, production-grade local AWS cloud environment without incurring real AWS costs. It runs locally via Docker Compose, Terraform, and a dedicated custom web console.

```
                              +---------------------------------------+
                              |         Web Browser Clients           |
                              +-------------------+-------------------+
                                                  |
                     +----------------------------+----------------------------+
                     | (port 3000)                                             | (port 8001)
                     v                                                         v
         +-----------------------+                                 +-----------------------+
         | Local Cloud Dashboard |                                 |  DynamoDB Admin UI    |
         | (Node.js/Express/UI)  |                                 | (aaronshaf/dynamodb)  |
         +-----------+-----------+                                 +-----------+-----------+
                     |                                                         |
                     +----------------------------+----------------------------+
                                                  | AWS SDK API Calls
                                                  v
                              +---------------------------------------+
                              |      LocalStack Gateway (4566)        |
                              |       (localstack/localstack)         |
                              +-------------------+-------------------+
                                                  |
         +--------------------+-------------------+--------------------+--------------------+
         |                    |                   |                    |                    |
         v                    v                   v                    v                    v
  +--------------+    +---------------+   +---------------+    +---------------+    +---------------+
  |  AWS S3      |    |   AWS SNS     |-->|   AWS SQS     |--> |  AWS Lambda   |--> | AWS DynamoDB  |
  | Bucket       |    |  Event Topic  |   |  Queue + DLQ  |    | (Python 3.11) |    |  Event Table  |
  +--------------+    +---------------+   +---------------+    +---------------+    +---------------+
```

### Component Breakdown

| Component | Technology | Host Port | Internal Container URL | Description |
|---|---|---|---|---|
| **LocalStack Gateway** | Docker (`localstack/localstack:latest`) | `4566`, `4510-4559` | `http://localstack:4566` | Emulates S3, DynamoDB, SQS, SNS, Lambda, and IAM |
| **Cloud Dashboard** | Node.js Express + Tailwind/HTML5 | `3000` | `http://cloud-dashboard:3000` | Interactive UI with architecture diagram, S3 manager, Lambda runner, & live event simulator |
| **DynamoDB Admin** | Docker (`aaronshaf/dynamodb-admin`) | `8001` | `http://dynamodb-admin:8001` | Dedicated visual explorer for DynamoDB tables and records |
| **Infrastructure as Code** | Terraform AWS Provider `v5.x` | N/A | N/A | Provisions S3, DynamoDB, SNS, SQS, Lambda, and Event Source Mapping |

---

## 2. Directory Layout & Key Files

```text
Local-stack-cloud/
├── README.md                                # Root repository index
└── local-cloud-infra/
    ├── .env                                 # Local configuration (from .env.example)
    ├── .env.example                         # Template environment variables
    ├── docker-compose.yml                   # Docker Compose specification (LocalStack, UI, DynamoDB Admin)
    ├── Makefile                             # Automation workflow targets
    ├── INSTRUCTIONS.md                      # This reference document
    ├── README.md                            # End-user project documentation
    ├── dashboard/                           # Custom Cloud Dashboard UI service
    │   ├── package.json                     # Express and @aws-sdk v3 dependencies
    │   ├── server.js                        # Express server bridging AWS APIs & simulation
    │   ├── Dockerfile                       # Container definition (node:20-alpine)
    │   ├── .dockerignore                    # Excludes node_modules from build context
    │   └── public/
    │       └── index.html                   # Single-page app (Tailwind, Lucide icons, Dark mode)
    ├── scripts/
    │   ├── wait-for-localstack.sh           # Polling loop waiting for HTTP 200 on health endpoint
    │   └── test-resources.sh                # Integration test: S3 upload -> SNS publish -> DynamoDB verify
    └── terraform/
        ├── main.tf                          # Root module calling all child modules
        ├── providers.tf                     # AWS provider configured with localstack_endpoint
        ├── variables.tf                     # Variable definitions & default values
        ├── outputs.tf                       # Exposed ARNs, URLs, and resource names
        ├── terraform.tfvars                 # Environment variable overrides
        └── modules/
            ├── s3/                          # Private S3 bucket with versioning & AES256 encryption
            ├── dynamodb/                    # PAY_PER_REQUEST table with pk (S) and sk (S)
            ├── sqs_sns/                     # SNS Topic subscribed to SQS Queue with DLQ redrive
            └── lambda/                      # SQS trigger function writing events to DynamoDB
                └── src/
                    └── index.py             # Python 3.11 handler implementation
```

---

## 3. Standard Operational Runbook

### Prerequisites
1. **Docker Desktop**: Daemon must be running.
2. **Terraform**: `v1.5.0` or newer.
3. **AWS CLI** or `awslocal` wrapper (`pip install awscli-local`).
4. **Node.js**: `v18+` (if running dashboard outside Docker).

### Step-by-Step Lifecycle Commands

#### 1. Start Container Environment
```bash
cd local-cloud-infra
make up
make wait
```
*Behind the scenes:* Launches LocalStack (`4566`), Cloud Dashboard (`3000`), and DynamoDB Admin (`8001`) on bridge network `localstack-net`. `wait-for-localstack.sh` verifies health check availability.

#### 2. Provision Cloud Resources with Terraform
```bash
make init
make apply
```
*Behind the scenes:* Installs AWS Provider v5.x, packages `terraform/modules/lambda/src/index.py` into `terraform/modules/lambda/dist/lambda_function_payload.zip`, creates S3 bucket, DynamoDB table, SNS topic, SQS queues, and establishes the SQS-Lambda Event Source Mapping.

#### 3. Run Automated End-to-End Verification
```bash
make test
```
*Behind the scenes:* Executes `scripts/test-resources.sh` which:
1. Uploads a timestamped object to `s3://local-assets-bucket/` and verifies presence.
2. Publishes a JSON event to `local-events-topic`.
3. Waits 4 seconds for SQS polling and Lambda execution.
4. Queries `local-events-table` in DynamoDB to verify the record was written with `status: "PROCESSED"`.

#### 4. Open and Inspect the UIs
- **Cloud Dashboard**: [`http://localhost:3000`](http://localhost:3000)
- **DynamoDB Admin**: [`http://localhost:8001`](http://localhost:8001)
- **Official Web App**: [`https://app.localstack.cloud`](https://app.localstack.cloud)

#### 5. Teardown and Cleanup
```bash
# Destroy Terraform resources
make destroy

# Stop containers
make down

# Complete reset (clears .localstack state directory and Terraform cache)
make clean
```

---

## 4. Dashboard Architecture & API Reference

The dashboard in `local-cloud-infra/dashboard/` operates both as a standalone Node.js service and a Docker container.

### Endpoints Implemented in `server.js`

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/status` | Checks LocalStack health and individual service availability |
| `GET` | `/api/overview` | Aggregates all provisioned S3, DynamoDB, SQS, SNS, and Lambda resources |
| `GET` | `/api/s3/buckets` | Lists S3 buckets |
| `GET` | `/api/s3/objects?bucket=<name>` | Lists objects within a specified bucket |
| `POST` | `/api/s3/upload` | Multipart file upload into a specified S3 bucket |
| `DELETE` | `/api/s3/object?bucket=<name>&key=<key>` | Deletes an object from S3 |
| `GET` | `/api/dynamodb/tables` | Lists tables with schema and item counts |
| `GET` | `/api/dynamodb/items?table=<name>` | Scans items from a DynamoDB table |
| `DELETE` | `/api/dynamodb/item` | Deletes an item by `pk` (and optional `sk`) |
| `GET` | `/api/sqs/queues` | Lists queues with approximate visible and in-flight counts |
| `POST` | `/api/sqs/send` | Sends a message directly into an SQS queue |
| `POST` | `/api/sqs/purge` | Purges all messages from a specified SQS queue |
| `GET` | `/api/sns/topics` | Lists all SNS topics |
| `POST` | `/api/sns/publish` | Publishes a message to an SNS topic |
| `GET` | `/api/lambda/functions` | Lists deployed Lambda functions |
| `POST` | `/api/lambda/invoke` | Invokes a function synchronously with JSON payload |
| `POST` | `/api/pipeline/simulate` | Triggers a full event cycle: SNS &rarr; SQS &rarr; Lambda &rarr; DynamoDB |

---

## 5. Troubleshooting & Gotchas

### 1. Docker Daemon Connection Failure on Windows
- **Symptom**: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`
- **Cause**: Docker Desktop is not running.
- **Fix**: Launch Docker Desktop and wait until the whale icon shows "Engine running".

### 2. PowerShell Script Execution Restrictions (`npm.ps1`)
- **Symptom**: `npm : File ... npm.ps1 cannot be loaded because running scripts is disabled on this system`
- **Fix**: Use `npm.cmd` explicitly in PowerShell:
  ```powershell
  npm.cmd install
  npm.cmd start
  ```

### 3. S3 Bucket Path-Style Addressing
- **Important**: LocalStack requires path-style addressing (`http://localhost:4566/<bucket>/<key>`) rather than virtual-hosted style (`http://<bucket>.localhost:4566/<key>`).
- In AWS SDK v3, always set:
  ```javascript
  new S3Client({ endpoint, region, forcePathStyle: true })
  ```
- In AWS CLI, configure via `--endpoint-url http://localhost:4566`.

### 4. Lambda Execution Architecture
- Lambda functions running inside LocalStack execute in separate Docker sibling containers spawned via the host Docker socket (`/var/run/docker.sock`).
- Environment variable `DOCKER_HOST` in `docker-compose.yml` ensures LocalStack can communicate with the Docker daemon.

### 5. Terraform State Mismatch After Clean
- If `.localstack` persistence directory is removed or recreated, existing Terraform state in `terraform/terraform.tfstate` will point to non-existent resources.
- Always run `make clean` (or delete `terraform/terraform.tfstate*`) whenever resetting LocalStack state.

---

## 6. How to Extend This Codebase

### Adding a New AWS Service (e.g., Secrets Manager, SES, EventBridge)
1. **Update `docker-compose.yml`**:
   Add the service name to the `SERVICES` list:
   ```yaml
   - SERVICES=s3,dynamodb,sqs,sns,lambda,iam,secretsmanager
   ```
2. **Add Terraform Module**:
   Create a new directory in `terraform/modules/<service_name>/` with `main.tf`, `variables.tf`, and `outputs.tf`. Call the module from `terraform/main.tf` and expose relevant outputs in `terraform/outputs.tf`.
3. **Expose in Dashboard UI**:
   - Add the corresponding AWS SDK client (e.g. `@aws-sdk/client-secrets-manager`) in `dashboard/server.js`.
   - Add API endpoints (`/api/secrets/...`).
   - Add a new tab/pane in `dashboard/public/index.html`.

