# Dynamic String HTML Service (Terraform + AWS + Python)

Serves a fixed URL that returns an HTML page:

```html
<h1>The saved string is dynamic string</h1>
```

The "dynamic string" is stored in AWS Systems Manager Parameter Store and can be updated without redeploying infrastructure or changing the URL.

## Architecture
- AWS Lambda (Python 3.12) reads a value from SSM Parameter Store and returns HTML
- Amazon API Gateway HTTP API exposes a single route `GET /` to the Lambda
- SSM Parameter Store holds the dynamic string (plain String). Terraform ignores changes to the value so it can be updated out-of-band
- CloudWatch Logs for observability

## Prerequisites
- Terraform >= 1.5
- AWS credentials configured (e.g., via `aws configure`, environment vars or SSO)
- Python 3.9+ if you want to use the helper update script

## Quick start

```bash
make init
make apply
# Show the URL
make url
# Open the URL in browser; it will render the current string
```

## Updating the dynamic string (no redeploy)
- Using the helper script:

```bash
make update VALUE="Hello Arqiva"
```

- Or with AWS CLI directly:

```bash
aws ssm put-parameter \
  --name $(terraform output -raw ssm_parameter_name) \
  --type String \
  --value "Hello Arqiva" \
  --overwrite
```

Refresh the browser; all users see the updated value immediately. The URL stays the same.

## Configuration
You can customize via `variables.tf`:
- `aws_region` (default `eu-west-2`)
- `project_name`, `environment`
- `dynamic_string_default` (initial value at first deploy)
- `ssm_parameter_name` (optional override)

## Clean up
```bash
make destroy
```

## Security and best practices
- Least-privilege IAM: Lambda can only read the specific SSM parameter and write logs
- No secrets in code or Terraform; the string is in SSM Parameter Store
- Terraform ignores value changes to avoid drift on legitimate runtime updates
- Tags applied to all resources

## Repository structure
- `main.tf`, `variables.tf`, `versions.tf`, `outputs.tf`: Terraform
- `lambda/handler.py`: Lambda code
- `scripts/update_dynamic_string.py`: Helper to update SSM parameter
- `.github/workflows/terraform.yml`: CI for fmt/validate
- `docs/solution.md`: Design/decisions (export to PDF for submission)

## Notes
- `boto3` is available in the Lambda runtime by default; no packaging needed
- For sensitive strings, consider changing the parameter to `SecureString` and granting KMS permissions

## Testing locally with Terratest
Prerequisites: Go 1.21+, AWS credentials.

```bash
# Initialize Go module and download deps (first time)
go mod download

# Run tests (provisions and destroys its own isolated stack)
make test
```

The test deploys into a unique `environment` (e.g., `test-<id>`), verifies the HTML, updates the SSM value, verifies again, and then destroys all resources.

## True local testing with LocalStack
Run end-to-end tests without an AWS account. The test skips API Gateway in local mode and invokes the Lambda directly.

Prerequisites: Docker, Go.

```bash
# Start LocalStack with Docker socket so Lambda can run containers
docker rm -f localstack_main 2>/dev/null || true
docker run -d --name localstack_main \
  -p 4566:4566 -p 4510-4559:4510-4559 \
  -e SERVICES=lambda,ssm,iam,sts,logs,cloudwatch \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack

# Use dummy credentials (LocalStack accepts any) and disable profile reads
unset AWS_PROFILE
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=eu-west-2

# Run the test suite against LocalStack
LOCALSTACK=1 make test
```

Troubleshooting:
- Check LocalStack logs: `docker logs -f localstack_main`
- Health check: `curl -s http://localhost:4566/_localstack/health | jq`
- Run in a clean environment: `AWS_PROFILE= AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=eu-west-2 LOCALSTACK=1 make test`

## Primary test case (AWS demo)
Use this flow during the interview to prove the string can be updated without redeploying and the URL stays the same.

```bash
# 1) Deploy (first time only)
make init && make apply

# 2) Get the URL and open it
URL=$(make url)
echo "$URL"
open "$URL"   # or: curl -s "$URL"
# Expect: <h1>The saved string is Hello from Terraform</h1>

# 3) Update the value (no redeploy) — note the region must match the deployment
aws ssm put-parameter \
  --name $(terraform output -raw ssm_parameter_name) \
  --type String \
  --value "Arqiva Demo" \
  --overwrite \
  --region eu-west-2

# Alternatively, using the helper script (ensure AWS_REGION is set):
AWS_REGION=eu-west-2 make update VALUE="Arqiva Demo"

# 4) Verify the SAME URL now shows the new value
curl -s "$URL"
# Expect: <h1>The saved string is Arqiva Demo</h1>

# Optional sanity check: read the parameter directly
aws ssm get-parameter \
  --name $(terraform output -raw ssm_parameter_name) \
  --region eu-west-2 \
  --query Parameter.Value --output text

# 5) Cleanup after demo
make destroy
```

Notes:
- If your CLI default region isn’t eu-west-2, pass `--region eu-west-2` (or export `AWS_REGION=eu-west-2`).
- The API URL does not change when the string changes; all users see the same updated value.

## Remote state (optional)
Use `backend.tf.example` to configure an S3 backend and DynamoDB lock table. Copy and edit it to `backend.tf` with your bucket/table names, then run `make init` again.

```bash
cp backend.tf.example backend.tf
$EDITOR backend.tf  # update bucket, key, region, dynamodb_table
make init
```

Security options:
- Set `use_secure_string=true` and optionally `kms_key_arn` to store the value as `SecureString` (Lambda will decrypt via IAM).
- Tune Lambda with `lambda_timeout`, `lambda_memory_mb`, and `reserved_concurrency`.
- Logs retention is configurable via `log_retention_days`.

## CI/CD (GitHub Actions)
Three workflows are included under `.github/workflows/`:
- `plan.yml` (terraform-plan): runs on pull requests; executes `fmt`, `init`, `validate`, and `plan`.
- `apply.yml` (terraform-apply): runs on pushes to `main` and via manual dispatch; executes `init` and `apply -auto-approve`.
- `terratest.yml` (terratest-local): runs on PR and manual dispatch; starts LocalStack and runs the Terratest suite.

Required repository secrets (Settings → Secrets and variables → Actions):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (set to `eu-west-2`)

Notes:
- Prefer using a least-privilege IAM user/role for CI.
- The apply workflow will modify live resources in your account. Consider using a dedicated sandbox account.
- If you switch to OIDC later, replace secrets with `aws-actions/configure-aws-credentials` and an assumable role.
