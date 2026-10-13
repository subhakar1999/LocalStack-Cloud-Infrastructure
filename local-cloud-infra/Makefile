SHELL := /usr/bin/env bash

# Environment variables
ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

.PHONY: help up wait init plan apply test destroy down clean restart logs ui dashboard policy policy-test apply-approved governance-check governance-remediate governance-watch governance-test sentinel-test sentinel-check

help:
	@echo "================================================================="
	@echo "         LocalStack Infrastructure Automation Makefile           "
	@echo "================================================================="
	@echo "Available commands:"
	@echo "  make up        - Launch LocalStack & UI containers in background"
	@echo "  make wait      - Wait until LocalStack healthcheck returns HTTP 200"
	@echo "  make init      - Initialize Terraform working directory and providers"
	@echo "  make plan      - Generate Terraform execution plan"
	@echo "  make policy    - Generate a plan and enforce OPA and Sentinel policies"
	@echo "  make sentinel-test - Verify Sentinel allow and deny outcomes"
	@echo "  make sentinel-check - Run Sentinel on the exported saved plan"
	@echo "  make policy-test - Run Rego tests and verify gate exit codes"
	@echo "  make apply-approved - Check policies and apply that saved plan"
	@echo "  make governance-check - Check all S3 buckets in configured local accounts"
	@echo "  make governance-remediate - Enable versioning on violating local buckets"
	@echo "  make governance-watch - Recheck and repair local buckets every 30 seconds"
	@echo "  make governance-test - Test real LocalStack detection and remediation"
	@echo "  make apply     - Provision infrastructure on LocalStack"
	@echo "  make test      - Run integration tests (S3, SNS, SQS, Lambda, DynamoDB)"
	@echo "  make ui        - Display UI URLs and start local dashboard if needed"
	@echo "  make destroy   - Tear down Terraform-managed infrastructure"
	@echo "  make down      - Stop and remove LocalStack & UI containers"
	@echo "  make clean     - Stop containers and purge local state data (.localstack)"
	@echo "  make restart   - Restart LocalStack containers"
	@echo "  make logs      - Follow container output logs"
	@echo "================================================================="

up:
	@echo "[INFO] Starting LocalStack, Cloud Dashboard, and DynamoDB Admin..."
	docker compose up -d

ui:
	@echo "================================================================="
	@echo "  🚀 LocalStack Cloud Web UI & Inspection Consoles:"
	@echo "  - Local Cloud Dashboard : http://localhost:3000"
	@echo "  - DynamoDB Admin UI     : http://localhost:8001"
	@echo "  - Official Web Console  : https://app.localstack.cloud"
	@echo "================================================================="

wait:
	@echo "[INFO] Verifying LocalStack operational status..."
	bash scripts/wait-for-localstack.sh

init:
	@echo "[INFO] Initializing Terraform modules and providers..."
	terraform -chdir=terraform init

plan:
	@echo "[INFO] Generating Terraform execution plan..."
	terraform -chdir=terraform plan

apply:
	@echo "[INFO] Applying Terraform configuration..."
	terraform -chdir=terraform apply -auto-approve

policy:
	bash scripts/check-policies.sh

policy-test:
	conftest verify --policy policy --data policy/tests --rego-version v1
	node scripts/test-policy-gate.cjs
	node scripts/test-sentinel-gate.cjs

sentinel-test:
	node scripts/test-sentinel-gate.cjs

sentinel-check:
	node scripts/check-sentinel.cjs

apply-approved: policy
	terraform -chdir=terraform apply -input=false policy.tfplan

governance-check:
	node scripts/localstack-governance.cjs --check

governance-remediate:
	node scripts/localstack-governance.cjs --remediate

governance-watch:
	node scripts/localstack-governance.cjs --remediate --watch 30

governance-test:
	conftest verify --policy policy/live --rego-version v1
	node --test scripts/localstack-governance.test.cjs
	node scripts/test-localstack-governance.cjs

test:
	@echo "[INFO] Executing integration test suite against LocalStack..."
	bash scripts/test-resources.sh

destroy:
	@echo "[INFO] Destroying Terraform resources..."
	terraform -chdir=terraform destroy -auto-approve

down:
	@echo "[INFO] Stopping LocalStack container..."
	docker compose down

clean: down
	@echo "[INFO] Purging persistent state in .localstack..."
	rm -rf .localstack
	rm -rf terraform/.terraform
	rm -rf terraform/.terraform.lock.hcl
	rm -rf terraform/terraform.tfstate*
	rm -rf terraform/modules/lambda/dist
	@echo "[INFO] Clean completed."

restart: down up wait

logs:
	docker compose logs -f
