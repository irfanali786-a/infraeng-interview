terraform {
  required_version = ">= 1.2"
}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.asg_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.asg_name}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cw_config = file("${path.module}/cloudwatch-config.json")
  }))
}

# ALB security group (counted)
resource "aws_security_group" "alb_sg" {
  count       = var.create_alb ? 1 : 0
  name        = "${var.asg_name}-alb-sg"
  description = "ALB SG (TLS ingress)"
  vpc_id      = var.vpc_id

  # Allow TLS from anywhere
  ingress {
    description = "TLS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instance security group
resource "aws_security_group" "instance_sg" {
  name        = "${var.asg_name}-instance-sg"
  description = "Allow ALB -> NGINX on port 80; outbound for SSM/CloudWatch"
  vpc_id      = var.vpc_id

  # Default egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# If an ALB is created, allow inbound from ALB SG to instance SG on 80
resource "aws_security_group_rule" "alb_to_instance_ingress" {
  count = var.create_alb ? 1 : 0

  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.instance_sg.id
  source_security_group_id = aws_security_group.alb_sg[0].id
  description              = "Allow ALB to reach NGINX"
}

# If no ALB, permit a default internal CIDR to reach instances on 80 (adjust as needed)
resource "aws_security_group_rule" "internal_cidr_to_instance" {
  count = var.create_alb ? 0 : 1

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.instance_sg.id
  cidr_blocks       = ["10.0.0.0/8"]
  description       = "Allow internal CIDR to reach NGINX (no ALB)"
}

resource "aws_launch_template" "lt" {
  name_prefix   = "${var.asg_name}-lt-"
  image_id      = data.aws_ssm_parameter.ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.profile.name
  }

  # Attach instance security group
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = local.user_data

  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "asg" {
  name                = var.asg_name
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  health_check_type = var.create_alb ? "ELB" : "EC2"
  target_group_arns = var.create_alb ? [aws_lb_target_group.tg[0].arn] : []

  tag {
    key                 = "Name"
    value               = var.asg_name
    propagate_at_launch = true
  }

  force_delete = true
  lifecycle { create_before_destroy = true }
}

# Optional ALB + target group (internal, TLS listener)
resource "aws_lb" "alb" {
  count              = var.create_alb ? 1 : 0
  name               = "${var.asg_name}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = var.create_alb ? [aws_security_group.alb_sg[0].id] : []
}

resource "aws_lb_target_group" "tg" {
  count    = var.create_alb ? 1 : 0
  name     = "${var.asg_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path     = "/"
    protocol = "HTTP"
  }
}

resource "aws_lb_listener" "https" {
  count = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.alb[0].arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[0].arn
  }
}

# Connect target group to ASG when created
resource "aws_autoscaling_attachment" "asg_tg" {
  count                   = var.create_alb ? 1 : 0
  autoscaling_group_name  = aws_autoscaling_group.asg.name
  lb_target_group_arn     = aws_lb_target_group.tg[0].arn
}

# 30-day scheduled instance refresh via EventBridge -> Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.asg_name}-refresh-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "lambda_asg_policy" {
  name = "${var.asg_name}-lambda-asg"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["autoscaling:StartInstanceRefresh","autoscaling:DescribeAutoScalingGroups"], Resource = "*" }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "refresh" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.asg_name}-refresh"
  role             = aws_iam_role.lambda_role.arn
  handler          = "refresh_lambda.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
  environment { variables = { ASG_NAME = var.asg_name } }
}

resource "aws_cloudwatch_event_rule" "every_30_days" {
  name                = "${var.asg_name}-every-30-days"
  schedule_expression = "rate(30 days)"
}
resource "aws_cloudwatch_event_target" "target" {
  rule = aws_cloudwatch_event_rule.every_30_days.name
  arn  = aws_lambda_function.refresh.arn
}
resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowCWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.refresh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_30_days.arn
}