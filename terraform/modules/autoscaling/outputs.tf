output "asg_id" {
  value = aws_autoscaling_group.asg.id
}

output "alb_dns" {
  value       = var.create_alb ? aws_lb.alb[0].dns_name : var.load_balancer_url
  description = "ALB DNS if created, otherwise provided load_balancer_url"
}

