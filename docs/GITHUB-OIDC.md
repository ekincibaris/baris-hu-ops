# GitHub Actions → AWS with OIDC (for `terraform plan` on pull requests)

The `plan` job in `.github/workflows/terraform.yml` is commented out until this role exists. It
uses **GitHub's OIDC provider**, so no AWS access keys are stored in GitHub. Each workflow run gets
a short-lived token, and AWS STS exchanges it for temporary credentials. That only works if the
token comes from this repository and from a `pull_request` event.

## Option A: create it with Terraform (recommended)

The role is defined in `bootstrap/github_oidc.tf` and is disabled by default.

```bash
cd bootstrap
# in terraform.tfvars:
#   create_github_oidc_role     = true
#   create_github_oidc_provider = true   # false if the account already has token.actions.githubusercontent.com
terraform apply
terraform output -raw github_plan_role_arn
```

## Option B: create it by hand

1. **IAM → Identity providers → Add provider**: type *OpenID Connect*, URL
   `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. **IAM → Roles → Create role → Web identity**, using that provider. Use this trust policy
   (replace the account ID):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:ekincibaris/baris-hu-ops:pull_request"
        }
      }
    }
  ]
}
```

3. Attach the AWS managed policy **`ReadOnlyAccess`**.
4. Add this inline policy for the state bucket. `plan` reads the state and takes the S3 lock by
   writing and then deleting `<key>.tflock`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "ListStateBucket", "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::ops-baris-hu-tfstate-123456789012" },
    { "Sid": "ReadState", "Effect": "Allow", "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::ops-baris-hu-tfstate-123456789012/*" },
    { "Sid": "ManageLockFile", "Effect": "Allow", "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::ops-baris-hu-tfstate-123456789012/*.tflock" }
  ]
}
```

## Wire it into GitHub

| Where | Name | Value |
|---|---|---|
| Settings → Secrets and variables → Actions → **Variables** | `AWS_PLAN_ROLE_ARN` | the role ARN |
| ... → **Variables** | `TF_STATE_BUCKET` | the state bucket name |
| ... → **Secrets** | `TF_VAR_ALARM_EMAIL` | the alarm email (kept out of logs) |
| ... → **Secrets** | `TF_VAR_ALLOWED_ACCOUNT_IDS` | `["123456789012"]` |

Then uncomment the `plan:` job in `.github/workflows/terraform.yml`.

## Security notes

- **`sub` is pinned to `repo:ekincibaris/baris-hu-ops:pull_request`.** Other repositories, pushes
  and tags cannot assume the role. GitHub does not issue OIDC tokens with `id-token: write` to
  workflows triggered from forks. The job also checks
  `head.repo.full_name == github.repository`.
- **The role is read-only.** It cannot apply. Applies stay on a human's machine, which matches how
  this project is meant to be run. For CI applies, create a separate role trusted only for
  `repo:...:environment:prod`, protected by a GitHub environment with required reviewers.
- **`ReadOnlyAccess` is broad.** It can read every S3 object and every SSM parameter in the account.
  That is fine for a single-purpose portfolio account. In a shared account, replace it with a custom
  read policy that covers only the services in this stack.
- A `terraform plan` output can contain sensitive values. `alarm_email` is marked `sensitive`, so
  it is redacted in plan output. The job summary only shows the last 200 lines of the plan.
