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
