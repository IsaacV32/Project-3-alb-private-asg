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
