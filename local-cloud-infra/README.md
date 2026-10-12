# Production-Grade LocalStack Infrastructure

A modular, fully functional AWS local cloud infrastructure codebase provisioned with **LocalStack Community Edition**, **Terraform (AWS Provider v5.x)**, and **Docker Compose**.

---

## Architecture Overview

This project simulates a cloud-native asynchronous event processing pipeline and object storage locally without incurring any AWS cloud costs:

```
                      +-------------------+
                      |   AWS S3 Bucket   |
                      | (Private/SSE/Ver) |
                      +-------------------+

+----------------+      +------------------+      +-------------------+
|  AWS SNS Topic | ---> |  AWS SQS Queue   | ---> |   AWS Lambda      |
+----------------+      +------------------+      | (Python 3.11 Runtime)
                                 |                +---------+---------+
                          (Redrive / DLQ)                   |
                                 v                          v
                        +------------------+      +-------------------+
                        |   Dead-Letter    |      |  Amazon DynamoDB  |
                        |   Queue (DLQ)    |      | (pk: S, sk: S)    |
                        +------------------+      +-------------------+
```

### Infrastructure Components
- **LocalStack (Community)**: Runs in Docker with mock AWS services enabled: `s3`, `dynamodb`, `sqs`, `sns`, `lambda`, `iam`.
- **S3 Module (`modules/s3`)**: Private bucket configured with object versioning, server-side encryption (`AES256`), and strict public access block.
- **DynamoDB Module (`modules/dynamodb`)**: `PAY_PER_REQUEST` billing mode with partition key `pk` (String) and sort key `sk` (String).
- **SNS/SQS Module (`modules/sqs_sns`)**: SNS topic subscribed to an SQS queue with raw message delivery and a dead-letter queue (DLQ) redrive policy.
- **Lambda Module (`modules/lambda`)**: Packaged Python 3.11 function (`archive_file`), IAM execution role/policies, and an SQS Event Source Mapping that polls the queue and persists records into DynamoDB.

---

## Directory Structure

```text
local-cloud-infra/
├── .env.example
├── docker-compose.yml
├── Makefile
├── INSTRUCTIONS.md                      # Developer runbook & reference guide
├── dashboard/                           # Local Cloud Dashboard web console
│   ├── package.json
│   ├── server.js
│   ├── Dockerfile
│   └── public/index.html
├── scripts/
│   ├── wait-for-localstack.sh
│   └── test-resources.sh
├── terraform/
│   ├── main.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── modules/
│       ├── s3/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── dynamodb/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── sqs_sns/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── lambda/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── src/
│               └── index.py
└── README.md
```

---

## Prerequisites

Before running this stack, ensure you have the following installed on your host system:

1. **Docker & Docker Compose**:
   - Docker Desktop / Engine 20.10+
   - Ensure the Docker daemon is active and running.
2. **Terraform CLI**:
   - Version `>= 1.5.0` ([Download](https://www.terraform.io/downloads))
3. **AWS CLI or awslocal**:
   - Standard AWS CLI: `aws --version` ([AWS CLI Guide](https://aws.amazon.com/cli/))
   - Or `awslocal` wrapper:
     ```bash
     pip install awscli-local
     ```
4. **Make & Bash** (optional, recommended for automation targets).

---

## Quick Start Guide

### 1. Configure Environment
Copy the example environment configuration:
```bash
cp .env.example .env
```

### 2. Start LocalStack
Spin up LocalStack in detached mode and wait for the health check:
```bash
make up
make wait
```
*Alternatively, using Docker Compose directly:*
```bash
docker compose up -d
bash scripts/wait-for-localstack.sh
```

### 3. Initialize and Apply Terraform
Provision the complete infrastructure onto LocalStack:
```bash
make init
make apply
```
*Alternatively, using Terraform CLI directly:*
```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

### 4. Run the Integration Tests
Execute the end-to-end test suite to verify all cloud resources:
```bash
make test
```
*Or directly via script:*
```bash
bash scripts/test-resources.sh
```

### 5. Inspect Resources via the Web UI Consoles
Once the containers are running with `make up` (or `docker compose up -d`), you can visually inspect and interact with all provisioned resources:

1. **Local Cloud Dashboard (`http://localhost:3000`)**:
   - **Pipeline Visualizer**: Real-time diagram of SNS &rarr; SQS &rarr; Lambda &rarr; DynamoDB &rarr; S3.
   - **Simulate Live Event**: One-click button to publish a test event and watch it flow through SQS and Lambda into DynamoDB.
   - **DynamoDB Records**: Browse, view, search, and delete records written by the Lambda function.
   - **S3 Bucket Explorer**: Browse files, drag-and-drop file upload, preview sizes, delete objects.
   - **SQS & SNS Queues/Topics**: View message counts, dead-letter queue (DLQ), send test messages, purge queues.
   - **Lambda Invoker**: Inspect function runtime, test-invoke with custom JSON payloads, view execution responses.
   - **Service Health Grid**: Real-time telemetry on LocalStack services.

2. **DynamoDB Admin UI (`http://localhost:8001`)**:
   - Comprehensive web interface dedicated to exploring DynamoDB tables, creating items, and querying primary/sort keys.

3. **Official LocalStack Web App (`https://app.localstack.cloud`)**:
   - LocalStack's browser console connecting directly to `http://localhost:4566`.

---

## Makefile Target Reference

| Target | Description |
|---|---|
| `make up` | Starts LocalStack, the Cloud Dashboard UI, and DynamoDB Admin (`docker compose up -d`). |
| `make wait` | Polls `http://localhost:4566/_localstack/health` until HTTP 200 is returned. |
| `make init` | Runs `terraform init` to download the AWS provider and modules. |
| `make plan` | Runs `terraform plan` to view planned changes. |
| `make apply` | Provisions all resources onto LocalStack with `-auto-approve`. |
| `make test` | Runs `scripts/test-resources.sh` (S3 upload + SNS publish + DynamoDB verification). |
| `make ui` | Displays active Web UI endpoints. |
| `make destroy` | Tears down all Terraform resources on LocalStack. |
| `make down` | Stops and removes LocalStack containers. |
| `make clean` | Stops containers and wipes `.localstack/` storage and Terraform state files. |
| `make logs` | Streams logs from the `localstack-main` container. |

---

## Manual Verification & CLI Usage

If you prefer to interact with LocalStack directly using `awslocal` or `aws`:

### S3
```bash
# List buckets
awslocal s3 ls

# Upload an object
echo "Test file content" > test.txt
awslocal s3 cp test.txt s3://local-assets-bucket/test.txt

# Read back the object
awslocal s3 cp s3://local-assets-bucket/test.txt -
```

### SNS & SQS
```bash
# Publish an event to the SNS Topic
awslocal sns publish \
  --topic-arn arn:aws:sns:us-east-1:000000000000:local-events-topic \
  --message '{"source": "cli", "status": "active"}'

# Receive message directly from SQS (if not yet consumed by Lambda)
awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/local-events-queue
```

### DynamoDB
```bash
# Scan items written by Lambda
awslocal dynamodb scan --table-name local-events-table
```

### Lambda Logs
```bash
# Inspect Lambda CloudWatch logs
awslocal logs tail /aws/lambda/local-sqs-processor
```

---

## Troubleshooting & Best Practices

1. **Docker Socket Permission on Linux / macOS**:
   Ensure Docker Desktop has permission to access `/var/run/docker.sock`. LocalStack requires this mount to spawn Docker containers for Lambda execution.
2. **Lambda Networking in LocalStack**:
   The Lambda function automatically resolves its DynamoDB endpoint using LocalStack's injected environment variables (`AWS_ENDPOINT_URL` or `LOCALSTACK_HOSTNAME:EDGE_PORT`).
3. **State Reset**:
   If you ever need to reset to a completely clean slate, run:
   ```bash
   make clean
   ```
