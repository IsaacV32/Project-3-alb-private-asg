output "ec2_ssm_role_name" {
  value = aws_iam_role.ec2_ssm_role.name
}

output "ec2_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}
output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "app_sg_id" {
  value = aws_security_group.app_sg.id
}

output "alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}
