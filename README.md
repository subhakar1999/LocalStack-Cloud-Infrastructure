# LocalStack Cloud Infrastructure

This repository contains a production-grade local cloud infrastructure setup based on **LocalStack Community Edition**, **Terraform (AWS Provider v5.x)**, and **Docker Compose**.

## Getting Started

All code, modules, automation scripts, and Docker manifests are organized inside the [`local-cloud-infra/`](./local-cloud-infra/) directory:

- 🐳 **[Docker Compose Configuration](./local-cloud-infra/docker-compose.yml)**
- ⚙️ **[Makefile](./local-cloud-infra/Makefile)**
- 📜 **[Automation Scripts](./local-cloud-infra/scripts/)**
  - [wait-for-localstack.sh](./local-cloud-infra/scripts/wait-for-localstack.sh)
  - [test-resources.sh](./local-cloud-infra/scripts/test-resources.sh)
- 🏗️ **[Terraform Root & Modules](./local-cloud-infra/terraform/)**
  - [S3 Module](./local-cloud-infra/terraform/modules/s3/)
  - [DynamoDB Module](./local-cloud-infra/terraform/modules/dynamodb/)
  - [SQS & SNS Module](./local-cloud-infra/terraform/modules/sqs_sns/)
  - [Lambda Module](./local-cloud-infra/terraform/modules/lambda/)
- 🌐 **[Web UI Cloud Consoles](./local-cloud-infra/dashboard/)**:
  - Interactive Local Cloud Dashboard (`http://localhost:3000`)
  - DynamoDB Admin UI (`http://localhost:8001`)

- 📖 **[Developer & Reference Guide](./local-cloud-infra/INSTRUCTIONS.md)**: Architecture deep-dive, runbooks, and debugging notes.

For full documentation and instructions, refer to **[`local-cloud-infra/README.md`](./local-cloud-infra/README.md)**.
