# QuickEats infrastructure (Terraform)

Describes the AWS side of the production deployment in `eu-north-1`:

| File | What |
|---|---|
| `compute.tf` | EC2 instance `quickeats-server`, IAM role/instance profile for ECR pulls |
| `network.tf` | Security group `quickeats-sg`, Elastic IP |
| `ecr.tf` | One ECR repository per image, scan on push, keep-10 lifecycle policy |
| `budget.tf` | Monthly AWS Budget with email alerts |
| `imports.tf` | Adopts the resources originally created in the console |

The containers on the instance are deployed by Jenkins (`../Jenkinsfile`), not by Terraform.

## One-time setup

```powershell
winget install Hashicorp.Terraform
winget install Amazon.AWSCLI
aws login --region eu-north-1        # or: aws configure (IAM user access key)

# State bucket (Terraform can't create the bucket that stores its own state)
aws s3api create-bucket --bucket quickeats-tfstate-256130491262 --region eu-north-1 --create-bucket-configuration LocationConstraint=eu-north-1
aws s3api put-bucket-versioning --bucket quickeats-tfstate-256130491262 --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket quickeats-tfstate-256130491262 --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

copy terraform.tfvars.example terraform.tfvars   # then fill it in
terraform init
```

## Everyday use

`admin_cidr` is your current public IP, the only source allowed on SSH and Jenkins.
Passing it on each run replaces editing the security group by hand when your IP changes:

```powershell
$ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
terraform plan  -var "admin_cidr=$ip/32"
terraform apply -var "admin_cidr=$ip/32"
```

The instance, security group and Elastic IP have `prevent_destroy`, so a plan that
would replace them fails instead of running.
