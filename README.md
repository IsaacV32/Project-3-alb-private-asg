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
