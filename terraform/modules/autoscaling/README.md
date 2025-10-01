# File: `modules/autoscaling/README.md`
# autoscaling module
Inputs: `asg_name`, `load_balancer_url`, `vpc_id`, `private_subnet_ids`, optional ALB (`create_alb`, `certificate_arn`).
Provides: ASG launching Amazon Linux 2023 AMIs, SSM access, pushes `/var/log/messages` to CloudWatch, installs nginx, and triggers instance refresh every 30 days.

# File: `examples/simple/main.tf`
provider "aws" {
region = "us-east-1"
}

module "ephemeral_asg" {
source             = "../../modules/autoscaling"
asg_name           = "asx-ephemeral"
load_balancer_url  = ""
vpc_id             = "vpc-012345"
private_subnet_ids = ["subnet-aaa","subnet-bbb"]
create_alb         = false
}

# File: `modules/autoscaling/.gitignore`
lambda.zip
*.tfstate
*.tfstate.*