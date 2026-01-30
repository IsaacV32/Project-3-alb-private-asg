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
