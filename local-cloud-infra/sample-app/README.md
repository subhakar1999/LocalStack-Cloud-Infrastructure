# Sample order application

This local application uses a Standard Step Functions workflow to invoke three
Python Lambda functions: `ValidateOrder` → `CalculateTotal` → `SaveOrder`.
Completed orders are stored in the `sample-orders` DynamoDB table. Each task
routes errors to `OrderFailed`; the storage task retries transient Lambda errors.
The included order costs `31.00`.

## Deploy locally

From `local-cloud-infra`, ensure `.env` includes
`SERVICES=s3,dynamodb,sqs,sns,lambda,iam,stepfunctions,logs`, then run:

```powershell
docker compose up -d --build
cd sample-app
terraform init
terraform plan -out="sample.tfplan"
terraform apply "sample.tfplan"
```

Open [the sample application](http://localhost:3000/#sample), choose **Start
execution**, and submit the prefilled input. The execution view shows status,
visited tasks, input, output, and event history. Open **DynamoDB → sample-orders**
to inspect saved orders. Use `{}` as input to verify the failure path.

The provider is pinned to AWS `5.66.0` because LocalStack `3.8.1` lacks
`ValidateStateMachineDefinition`, called by newer providers. See the
[LocalStack compatibility issue](https://github.com/localstack/localstack/issues/11553).
The sample uses its own Terraform state and provider lock file; the original
pipeline and its policy checks remain in `../terraform`.

This root targets localhost with mock credentials. LocalStack may lose resource
data when its container is recreated; rerun Terraform for both roots to restore
the resource definitions. Saved execution history and records are local data.

## Replace the sample code

Replace `handler.py` with the application code when it is available. The task
entry points are `validate`, `calculate`, and `persist`, each accepting an event
and context and returning JSON. Update the handlers, runtime, dependencies, IAM
permissions, and state machine definition to match the supplied application.
Run `terraform plan` and `terraform apply` to deploy the updated code. Packaging
currently uses only `handler.py`; third-party dependencies must be packaged if
the application needs them. Python's Lambda runtime provides boto3.

The console provides AWS-style navigation and resource views for the services
in this stack. It is a local interface, not the official AWS console or a full
implementation of every AWS console feature.
