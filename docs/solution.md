# Solution Overview

## Goal
Provide a single stable URL that serves an HTML page rendering:

```html
<h1>The saved string is dynamic string</h1>
```

Where the dynamic string can be updated without redeploying.

## Chosen Architecture
- API Gateway HTTP API (public) → Lambda (Python) → SSM Parameter Store (String)
- Lambda renders HTML by retrieving the current parameter value
- Parameter value can be updated independently via AWS CLI or helper script

### Rationale
- Minimal moving parts, fast to provision, low cost
- Stateless Lambda scales automatically; SSM provides durable, global configuration storage per region
- URL remains constant; behavior changes via configuration value only

## Alternatives Considered
- S3 Static Website + Lambda/Function URL for SSR fragment
  - Pros: Very cheap static hosting
  - Cons: Needs dynamic fetch and client-side rendering or edge function; adds complexity to keep a single canonical URL
- CloudFront + Lambda@Edge / CloudFront Functions
  - Pros: Global latency reduction
  - Cons: Heavier operational burden, versioned deployments to edge; slower iteration for interview demo
- ECS/Fargate or EC2 with a web server reading config from SSM
  - Pros: Full control over runtime
  - Cons: Higher operational cost/complexity versus Lambda for simple HTML
- DynamoDB instead of SSM
  - Pros: Richer data model
  - Cons: Overkill for a single string; SSM Parameter is simpler and cheaper

## Security Considerations
- Principle of least privilege: IAM policy allows only `ssm:GetParameter` on the exact parameter and logging
- No secrets embedded in code or Terraform; runtime configuration comes from SSM
- CloudWatch Logs retained for 14 days; can be adjusted per policy
- Consider `SecureString` + KMS if the value becomes sensitive; add KMS key and `kms:Decrypt` to Lambda role

## Operations & CI/CD
- Terraform IaC provisions all resources; Lambda is packaged via the `archive` provider
- GitHub Actions workflow runs `terraform fmt -check`, `init`, and `validate` on PRs/commits
- Runtime updates via `scripts/update_dynamic_string.py` or AWS CLI; Terraform ignores the parameter value to avoid drift

## Observability
- CloudWatch Logs for Lambda function; can add metrics and alarms if needed

## How to Extend with More Time
- Add CloudFront in front of API Gateway for global caching and WAF integration
- Add custom domain + ACM managed certificate
- Switch to `SecureString` + customer-managed KMS key
- Add canary testing and alarms (Route 53 health check, CloudWatch Alarms)
- Add integration tests in CI using `localstack` or a sandbox account
- Add OpenAPI definition and IaC for alerts/dashboards

## Risk & Trade-offs
- Single-region deployment: If region is down, service is unavailable; can multi-region with Route 53
- Cold starts are small but exist; for a simple page this is acceptable
