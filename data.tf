data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["aws-vpc-terraform-v2-dev-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Tier = "private"
  }
}