variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"  # US East (N. Virginia)
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID"
  type        = string
  default     = "ami-0c7217cdde317cfec"  # Ubuntu 22.04 LTS in us-east-1
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"  # 2 vCPU, 4GB RAM (~$30/month)
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Allow from anywhere (restrict to your IP in production)
}

variable "create_key_pair" {
  description = "Whether to create a new key pair"
  type        = bool
  default     = false  # Use existing key by default
}

variable "public_key" {
  description = "Public key for SSH access (if creating new key pair)"
  type        = string
  default     = ""
}

variable "existing_key_name" {
  description = "Name of existing EC2 key pair"
  type        = string
  default     = ""
}

variable "enable_elastic_ip" {
  description = "Whether to allocate an Elastic IP"
  type        = bool
  default     = true  # Static IP recommended for API access
}

variable "db_host" {
  description = "PostgreSQL database host"
  type        = string
  default     = "localhost"  # Use RDS endpoint for production
}

variable "db_port" {
  description = "PostgreSQL database port"
  type        = string
  default     = "5432"  # Standard PostgreSQL port
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "minirun"
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true  # Hidden in Terraform output
  default     = ""
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "minirun"
}