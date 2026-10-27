# Reusable AWS Terraform Infrastructure

## What it creates

- Dedicated VPC, internet gateway, two public subnets, route table
- Ubuntu 24.04 EC2 instance, EC2 security group, generated SSH key pair and local `.pem`
- S3 bucket with ACLs enabled via `BucketOwnerPreferred` and all S3 Block Public Access flags disabled
- IAM user, S3 policy, Secrets Manager policy, IAM role, and attachments to both user and role
- MySQL RDS instance with AWS-managed master password
- Secrets Manager API configuration secret

## Important safety notes

1. The requested default ingress CIDRs for SSH, TCP/5000, and MySQL are `0.0.0.0/0`. This exposes those ports to the internet. Restrict these CIDRs before applying, especially in production.
2. The S3 Block Public Access flags are disabled as requested. That does **not** automatically make objects public, but it removes an important safety barrier. Do not add public bucket policies or public ACLs unless you intentionally need public access.
3. Terraform state contains sensitive resource metadata and the generated private key material from the TLS resource. Protect the state, do not commit it, and restrict access to the working directory. For team use, configure an encrypted remote backend with locking before using this in shared environments.
4. RDS is set `publicly_accessible = true` to match the request. The RDS security group also defaults to public MySQL access; restrict it before applying.
5. RDS's generated master password is managed by RDS in a separate Secrets Manager secret. The custom `/api` secret contains the DB endpoint and the ARN of the managed master secret, not the password itself.
6. S3 bucket names are globally unique. If apply fails because the bucket name is taken, set `s3_bucket_suffix` in `terraform.tfvars`.
7. Resource names are generated from project and environment, but some AWS naming limits apply. Keep names reasonably short.
8. This example creates public subnets to make EC2 and the requested public RDS deployment work. It is not a hardened production network design.

## Prerequisites

Install:
- Terraform CLI >= 1.6
- AWS CLI v2
- An AWS identity with permissions to create the resources listed here
- An AWS account/region where the requested EC2 and RDS instance classes and MySQL version are available

Configure credentials using `aws configure` or your organization's approved SSO/profile flow. Do not paste access keys into Terraform files.

## Run on Windows PowerShell

1. Extract this folder, then open PowerShell in the folder containing `main.tf`.
2. Confirm AWS identity and region:
   ```powershell
   aws sts get-caller-identity
   aws configure get region
   ```
3. Copy the example variables:
   ```powershell
   Copy-Item terraform.tfvars.example terraform.tfvars
   ```
4. Edit `terraform.tfvars`. Replace public CIDRs with your trusted IP ranges, and set `s3_bucket_suffix` if needed.
5. Initialize and validate:
   ```powershell
   terraform init
   terraform fmt -recursive
   terraform validate
   ```
6. Preview changes:
   ```powershell
   terraform plan -out=tfplan
   ```
   Review the plan and cost/security implications before continuing.
7. Create resources:
   ```powershell
   terraform apply tfplan
   ```
8. View outputs:
   ```powershell
   terraform output
   terraform output -raw ec2_public_ip
   terraform output -raw rds_endpoint
   ```
9. The generated `.pem` is written into this folder. Keep it private. On Linux/macOS use `chmod 400 ovulation-tracker-dev.pem`; on Windows restrict file ACLs to your user account if SSH reports an unprotected private key.
10. SSH example:
   ```powershell
   ssh -i .\ovulation-tracker-dev.pem ubuntu@YOUR_EC2_PUBLIC_IP
   ```

## Run on Ubuntu/Linux/macOS

Open a terminal in this folder and run:

```bash
aws sts get-caller-identity
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars before applying
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
# Review the plan, then:
terraform apply tfplan
terraform output
chmod 400 ./ovulation-tracker-dev.pem
```

Use the actual `.pem` name generated from `<project_name>-<environment>`. Example SSH command:

```bash
ssh -i ./ovulation-tracker-dev.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

## Use the same code for staging and production

Create separate variable files, for example:

- `dev.tfvars`
- `staging.tfvars`
- `prod.tfvars`

Run each environment from a separate working directory or use a carefully designed remote backend with separate state keys. Do not reuse the same Terraform state for different environments.

Example:

```bash
terraform plan -var-file=staging.tfvars -out=staging.tfplan
terraform apply staging.tfplan
```

For production, first change ingress CIDRs, use private RDS access, configure a remote encrypted backend with locking, and set a final snapshot/deletion-protection policy appropriate to your data.

## Destroy

Only when you intentionally want to delete the environment:

```bash
terraform plan -destroy
terraform destroy
```

Review every deletion carefully. Terraform destroy may remove the EC2 instance, S3 bucket, RDS instance, IAM resources, and secret. Back up any data first.
# server-setup
