terraform
# File: `terraform/modules/autoscaling/variable.tf`
variable "asg_name" {
  description = "Autoscaling group name"
  type        = string
}

variable "load_balancer_url" {
  description = "Optional external Load Balancer URL (currently unused inside this module)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC id where resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ASG (list)"
  type        = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "desired_capacity" { type = number; default = 1 }
variable "min_size" { type = number; default = 1 }
variable "max_size" { type = number; default = 2 }

variable "create_alb" { type = bool; default = false }

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Must be provided when create_alb = true."
  type        = string
  default     = ""
}

variable "ami_ssm_parameter" {
  description = "SSM parameter holding latest Amazon Linux 2023 AMI"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/amzn-ami-2023-x86_64"
}