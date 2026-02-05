# Project 3 — Private ALB + Auto Scaling Group (Terraform)

This project builds on my previous cloud engineering work to deploy a **production-style application stack** on AWS using Terraform.

It provisions a **public Application Load Balancer** that routes traffic to an **Auto Scaling Group of EC2 instances running in private subnets**, with **no public IPs** and **no direct SSH access**.

The networking layer (VPC, public/private subnets, NAT, routing) is managed separately and injected into this project via Terraform variables, mirroring real-world infrastructure layering and separation of concerns.

## Goal
Demonstrate how to run scalable, secure workloads on AWS using:
- private compute
- load-balanced ingress
- Infrastructure as Code best practices
- modular Terraform design

This project intentionally avoids SSH-based access and is designed to reflect how production environments are typically operated.

## Stage Progress

**Stage 1 — IAM for SSM-only access**
Provisioned the IAM components required to manage private EC2 instances via SSM:

- EC2 IAM Role with `AmazonSSMManagedInstanceCore`
- EC2 Instance Profile attached to the role

Resources created:
- `aws_iam_role`
- `aws_iam_instance_profile`
- `aws_iam_role_policy_attachment`

**Stage 2 — Security Groups**  
In this stage, we defined dedicated security groups for the internal Application Load Balancer and the private application instances. Traffic policies enforce HTTP only from the ALB to the application tier, with no SSH access permitted. Security group rules are managed as separate resources to avoid circular dependencies and align with production-grade Terraform patterns.

**Stage 3 — Internal Application Load Balancer**
Introduced an internal Application Load Balancer deployed across private subnets within
the existing VPC. A target group and HTTP listener were configured with health checks
to prepare for integration with an Auto Scaling Group. Resource naming was intentionally
kept concise to comply with AWS limits, while descriptive context is preserved through
tagging.

**Stage 4 — Launch Template**
Defined a launch template for private EC2 instances using Amazon Linux 2023. Instances
are configured without SSH or public IPs and are managed exclusively via AWS Systems
Manager. User data provisions a lightweight web server and health endpoint to support
future load balancer integration.

**Stage 5 — Auto Scaling Group**
An Auto Scaling Group was introduced to run private EC2 instances across multiple
Availability Zones. Instances are launched using a reusable launch template and
registered with the internal Application Load Balancer target group. Health checks
are delegated to the load balancer to enable automatic replacement of unhealthy
instances and support high availability.

**Stage 6 — Auto Scaling Policy**
Added a target tracking scaling policy to enable automatic scaling based on
ASG average CPU utilisation. This introduces realistic operational behaviour
by allowing the fleet to expand and contract in response to load rather than
running at a fixed capacity.

**Stage 7 — SSM VPC Interface Endpoints**
Added VPC interface endpoints for Systems Manager (SSM, SSMMessages, and EC2Messages)
to support private instance management without relying on internet egress or NAT.
This enables SSM Session Manager connectivity through AWS PrivateLink while keeping
instances fully private.