############################################
# Stage 1 — IAM for SSM-only access (no SSH)
############################################

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name
}
############################################
# Stage 2 — Security Groups 
############################################

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for internal ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for private app instances (ASG)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}
# ALB inbound: HTTP from inside VPC (internal-only testing)
resource "aws_security_group_rule" "alb_ingress_http_from_vpc" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr]

  description = "HTTP from inside the VPC"
}

# App inbound: HTTP only from ALB SG
resource "aws_security_group_rule" "app_ingress_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.alb_sg.id

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  description = "HTTP from internal ALB only"
}

# ALB egress: HTTP only to App SG
resource "aws_security_group_rule" "alb_egress_http_to_app" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb_sg.id
  source_security_group_id = aws_security_group.app_sg.id

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  description = "HTTP to app instances"
}

# App egress: allow all (we'll tighten later when we add endpoints)
resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.app_sg.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  description = "Allow all egress"
}

