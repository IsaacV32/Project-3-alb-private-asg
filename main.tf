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

# App egress: allow all (i will tighten later when we add endpoints)
resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.app_sg.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  description = "Allow all egress"
}

############################################
# Stage 3 — Internal ALB + Target Group
############################################

resource "aws_lb" "internal" {
  name               = "pthree-internal-alb"
  internal           = true
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb_sg.id]
  subnets         = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "pthree-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

############################################
# Stage 4 — Launch Template (SSM-only EC2)
############################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "p3-app-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(file("${path.module}/user_data.sh"))

  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-app"
    }
  }
}

############################################
# Stage 5 — Auto Scaling Group
############################################

resource "aws_autoscaling_group" "app" {
  name             = "p3-app-asg"
  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 60

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}

############################################
# Stage 6 — Auto Scaling Policy (Target Tracking)
############################################

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "p3-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = 50.0
    disable_scale_in = false
  }
}

############################################
# Stage 7 — VPC Interface Endpoints for SSM
############################################

data "aws_region" "current" {}

locals {
  ssm_endpoint_subnet_ids = length(var.endpoint_subnet_ids) > 0 ? var.endpoint_subnet_ids : var.private_subnet_ids
}

# Security group for the endpoints ENIs
# Allows HTTPS from the app instances to the endpoint interfaces
resource "aws_security_group" "vpce_sg" {
  count       = var.enable_ssm_endpoints ? 1 : 0
  name        = "${var.project_name}-vpce-sg"
  description = "Security group for VPC interface endpoints (SSM)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-vpce-sg"
  }
}

resource "aws_security_group_rule" "vpce_ingress_443_from_app" {
  count                    = var.enable_ssm_endpoints ? 1 : 0
  type                     = "ingress"
  security_group_id        = aws_security_group.vpce_sg[0].id
  source_security_group_id = aws_security_group.app_sg.id

  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  description = "HTTPS from app instances to VPC endpoints"
}

# Egress can be left open; endpoints are inside the VPC anyway
resource "aws_security_group_rule" "vpce_egress_all" {
  count             = var.enable_ssm_endpoints ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.vpce_sg[0].id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Allow all egress"
}

resource "aws_vpc_endpoint" "ssm" {
  count               = var.enable_ssm_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ssm"
  subnet_ids          = local.ssm_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-ssm"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.enable_ssm_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
  subnet_ids          = local.ssm_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-ssmmessages"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.enable_ssm_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2messages"
  subnet_ids          = local.ssm_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-ec2messages"
  }
}
