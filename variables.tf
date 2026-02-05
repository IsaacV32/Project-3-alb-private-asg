variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "project-3-private-alb-asg-ssm"
}
variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the VPC (e.g. 10.0.0.0/16)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for internal ALB (and later ASG)"
}

variable "enable_ssm_endpoints" {
  type        = bool
  description = "Create VPC interface endpoints for SSM (ssm, ssmmessages, ec2messages)"
  default     = true
}

variable "endpoint_subnet_ids" {
  type        = list(string)
  description = "Subnets to place the interface endpoints in (usually the same private subnets)"
  default     = []
}
