terraform {
  required_version = ">= 1.0"  # Minimum Terraform version
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # AWS provider v5.x
    }
  }
}

provider "aws" {
  region = var.aws_region  # Set via variables.tf (default: us-east-1)
}

resource "aws_vpc" "minirun" {
  cidr_block           = "10.0.0.0/16"  # 65,536 IPs in VPC
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "minirun-vpc", Project = "MiniRun", Environment = var.environment }
}

resource "aws_internet_gateway" "minirun" {
  vpc_id = aws_vpc.minirun.id  # Enables internet access for VPC
  tags = { Name = "minirun-igw", Project = "MiniRun" }
}

resource "aws_subnet" "minirun_public" {
  vpc_id                  = aws_vpc.minirun.id
  cidr_block              = "10.0.1.0/24"  # 256 IPs in subnet
  map_public_ip_on_launch = true           # Auto-assign public IPs to instances
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = { Name = "minirun-public-subnet", Project = "MiniRun" }
}

resource "aws_route_table" "minirun_public" {
  vpc_id = aws_vpc.minirun.id
  route {
    cidr_block = "0.0.0.0/0"  # Route all traffic to internet gateway
    gateway_id = aws_internet_gateway.minirun.id
  }
  tags = { Name = "minirun-public-rt", Project = "MiniRun" }
}

resource "aws_route_table_association" "minirun_public" {
  subnet_id      = aws_subnet.minirun_public.id
  route_table_id = aws_route_table.minirun_public.id
}

resource "aws_security_group" "minirun" {
  name        = "minirun-sg"
  description = "Firewall rules for MiniRun: SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.minirun.id
  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTP API (restrict in production)
    description = "HTTP API access"
  }
  
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTPS API
    description = "HTTPS API access"
  }
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks  # SSH access (configurable)
    description = "SSH access"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"           # -1 = all protocols
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound
    description = "Allow all outbound traffic"
  }
  
  tags = { Name = "minirun-sg", Project = "MiniRun" }
}

resource "aws_iam_role" "minirun_ec2" {
  name = "minirun-ec2-role"  # IAM role for CloudWatch logging
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = { Name = "minirun-ec2-role", Project = "MiniRun" }
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.minirun_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"  # Enables CloudWatch
}

resource "aws_iam_instance_profile" "minirun" {
  name = "minirun-instance-profile"
  role = aws_iam_role.minirun_ec2.name  # Links role to EC2
}

resource "aws_key_pair" "minirun" {
  count      = var.create_key_pair ? 1 : 0  # Create only if requested
  key_name   = "minirun-key"
  public_key = var.public_key
  tags = { Name = "minirun-key", Project = "MiniRun" }
}

resource "aws_instance" "minirun" {
  ami           = var.ami_id         # Ubuntu 22.04 LTS AMI
  instance_type = var.instance_type  # Default: t3.medium (2 vCPU, 4GB RAM)
  subnet_id     = aws_subnet.minirun_public.id
  
  vpc_security_group_ids = [aws_security_group.minirun.id]
  iam_instance_profile   = aws_iam_instance_profile.minirun.name
  
  key_name = var.create_key_pair ? aws_key_pair.minirun[0].key_name : var.existing_key_name
  
  user_data = templatefile("${path.module}/user-data.sh", {  # Run on first boot
    db_host     = var.db_host
    db_port     = var.db_port
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
  })
  
  root_block_device {
    volume_size = 30        # 30GB root volume
    volume_type = "gp3"     # General Purpose SSD (3000 IOPS)
    encrypted   = true      # Encrypt at rest for security
  }
  
  tags = {
    Name        = "minirun-container-host"
    Project     = "MiniRun"
    Environment = var.environment
  }
  
  lifecycle {
    ignore_changes = [ami]  # Don't force recreation on AMI updates
  }
}

resource "aws_eip" "minirun" {
  count    = var.enable_elastic_ip ? 1 : 0  # Static IP (optional, default: enabled)
  instance = aws_instance.minirun.id
  domain   = "vpc"
  tags = { Name = "minirun-eip", Project = "MiniRun" }
}

data "aws_availability_zones" "available" {
  state = "available"  # Query available AZs in current region
}

output "instance_id" {
  description = "EC2 instance ID for AWS CLI commands"
  value       = aws_instance.minirun.id
}

output "instance_public_ip" {
  description = "Public IP to access API and SSH"
  value       = var.enable_elastic_ip ? aws_eip.minirun[0].public_ip : aws_instance.minirun.public_ip
}

output "instance_private_ip" {
  description = "Private IP within VPC"
  value       = aws_instance.minirun.private_ip
}

output "api_url" {
  description = "Direct URL to access MiniRun API"
  value       = "http://${var.enable_elastic_ip ? aws_eip.minirun[0].public_ip : aws_instance.minirun.public_ip}:8080"
}

output "ssh_command" {
  description = "Copy-paste command to SSH into instance"
  value       = "ssh -i ~/.ssh/minirun-key.pem ubuntu@${var.enable_elastic_ip ? aws_eip.minirun[0].public_ip : aws_instance.minirun.public_ip}"
}