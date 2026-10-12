SHELL := /usr/bin/env bash

# Environment variables
ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

.PHONY: help up wait init plan apply test destroy down clean restart logs ui dashboard

help:
	@echo "================================================================="
	@echo "         LocalStack Infrastructure Automation Makefile           "
	@echo "================================================================="
	@echo "Available commands:"
	@echo "  make up        - Launch LocalStack & UI containers in background"
	@echo "  make wait      - Wait until LocalStack healthcheck returns HTTP 200"
	@echo "  make init      - Initialize Terraform working directory and providers"
	@echo "  make plan      - Generate Terraform execution plan"
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
