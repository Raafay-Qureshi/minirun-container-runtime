# AWS Deployment with Terraform

Infrastructure as Code configuration for deploying the container runtime to AWS. Creates a complete VPC, EC2 instance, and security groups with one command.

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.0 installed
- AWS CLI configured (`aws configure`)
- SSH key pair (existing or create new)

## Quick Deploy
```bash
# 1. Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
# Edit with your AWS details

# 2. Initialize Terraform
terraform init

# 3. Preview changes
terraform plan

# 4. Deploy
terraform apply
```

After deployment, the API will be running at `http://<INSTANCE_IP>:8080`

## What Gets Created

**Network Infrastructure:**
- VPC with 10.0.0.0/16 CIDR block
- Public subnet (10.0.1.0/24)
- Internet gateway for public access
- Route table for internet traffic

**Compute:**
- EC2 instance (Ubuntu 22.04)
- Instance type: t3.medium (configurable)
- 20GB root volume
- Elastic IP (optional)

**Security:**
- Security group with SSH (22), HTTP (8080), HTTPS (8443)
- IAM role for CloudWatch monitoring
- fail2ban for SSH protection

**Auto-configuration:**
- Installs all dependencies on first boot
- Builds and starts the container runtime
- Sets up systemd service
- Configures metrics collection

## Configuration

Edit `terraform.tfvars`:
```hcl
# Basic settings
aws_region    = "us-east-1"
instance_type = "t3.medium"
project_name  = "minirun"

# SSH access (restrict to your IP!)
ssh_cidr_blocks = ["YOUR_IP/32"]

# Key pair - choose one option:
# Option 1: Use existing key
create_key_pair   = false
existing_key_name = "my-existing-key"

# Option 2: Create new key
create_key_pair = true
public_key      = "ssh-rsa AAAAB3NzaC1yc2E..."

# Optional: Database (leave empty for file storage)
db_host     = ""  # RDS endpoint if using PostgreSQL
db_port     = "5432"
db_user     = "minirun"
db_password = ""
db_name     = "minirun"
```

### SSH Key Setup

**If you don't have a key pair:**
```bash
# Generate new key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/minirun-aws

# Get public key for terraform.tfvars
cat ~/.ssh/minirun-aws.pub
```

**If using existing AWS key:**
```hcl
create_key_pair   = false
existing_key_name = "your-key-name"
```

## Usage

### Deploy
```bash
terraform apply
# Review changes, type 'yes' to confirm
```

Output will show connection details:
```
Outputs:

instance_public_ip = "54.123.45.67"
api_url = "http://54.123.45.67:8080"
ssh_command = "ssh -i ~/.ssh/your-key.pem ubuntu@54.123.45.67"
```

### Connect
```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ubuntu@<IP>

# Test API
curl http://<IP>:8080/health

# Create container
curl -X POST http://<IP>:8080/containers \
  -H "Content-Type: application/json" \
  -d '{"name":"test","command":"/bin/bash"}'
```

### Check Status
```bash
# On the instance
systemctl status minirun-api      # Service status
journalctl -u minirun-api -f      # Live logs
cat /var/log/minirun/access.log   # Access logs
```

### Update Deployment
```bash
# Modify terraform.tfvars or *.tf files
terraform plan    # Preview changes
terraform apply   # Apply updates
```

### Destroy Everything
```bash
terraform destroy
# Type 'yes' to confirm deletion
```

## Post-Deployment Setup

### Enable HTTPS (Recommended for Production)
```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ubuntu@<IP>

# Generate certificates
sudo /opt/minirun/scripts/generate_certificates.sh

# Restart API (now on port 8443)
sudo systemctl restart minirun-api

# Test HTTPS
curl -k https://<IP>:8443/health
```

### Configure Database (Optional)

If using RDS PostgreSQL:

1. Create RDS instance separately
2. Add credentials to `terraform.tfvars`
3. Run `terraform apply` to update configuration
4. Service automatically detects and uses database

### Set Up Monitoring

Metrics collected automatically every 5 minutes:
```bash
# View metrics
ssh ubuntu@<IP>
ls /opt/minirun/metrics/history/
cat /opt/minirun/metrics/history/metrics_*.json
```

## Troubleshooting

**Can't connect to instance:**
```bash
# Check security group allows your IP
terraform show | grep cidr_blocks

# Verify instance is running
aws ec2 describe-instances --filters "Name=tag:Name,Values=minirun-*"

# Check user-data execution
ssh ubuntu@<IP>
sudo cat /var/log/cloud-init-output.log
```

**API not responding:**
```bash
# SSH in and check
systemctl status minirun-api
journalctl -u minirun-api -n 50

# Manual restart
sudo systemctl restart minirun-api
```

**Build failed during deployment:**
```bash
# Check build logs
ssh ubuntu@<IP>
cat /opt/minirun/build.log
```

**Permission denied on SSH:**
```bash
# Fix key permissions
chmod 400 ~/.ssh/your-key.pem

# Use correct username (ubuntu, not root)
ssh -i ~/.ssh/your-key.pem ubuntu@<IP>
```

## Terraform Commands
```bash
# Initialize (first time only)
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply

# Show current state
terraform show

# List all resources
terraform state list

# Get specific output
terraform output instance_public_ip

# Destroy everything
terraform destroy
```

## File Structure
```
terraform/
├── main.tf                    # Main infrastructure definition
├── variables.tf               # Variable declarations
├── terraform.tfvars.example   # Example configuration
├── user-data.sh              # EC2 initialization script
└── README.md                 # This file
```

## Cost Estimate

**Development (t3.medium, us-east-1):**
- EC2: ~$30/month
- Elastic IP: ~$0/month (free when attached)
- Data transfer: ~$5-10/month
- **Total: ~$35-40/month**

**Production with RDS (t3.large + db.t3.small):**
- EC2: ~$60/month
- RDS: ~$30/month
- Backups: ~$5-10/month
- **Total: ~$100-120/month**

Stop instance when not in use to reduce costs:
```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
```

## Security Notes

**Currently configured for development/testing.**

For production:
- Restrict `ssh_cidr_blocks` to your IP only
- Enable HTTPS with proper certificates
- Use AWS Secrets Manager for database credentials
- Set up VPN or bastion host for SSH access
- Enable CloudWatch alarms
- Regular security updates: `apt-get update && apt-get upgrade`

**Default security group allows:**
- SSH from anywhere (configure `ssh_cidr_blocks` to restrict)
- HTTP/HTTPS from anywhere (API access)
- All outbound traffic

## Customization

### Change Instance Type

In `terraform.tfvars`:
```hcl
# Smaller (for testing)
instance_type = "t3.small"

# Larger (for production)
instance_type = "t3.large"
```

### Use Different Region
```hcl
aws_region = "us-west-2"
```

Note: Update AMI ID in `main.tf` if changing region.

### Disable Elastic IP

In `variables.tf`:
```hcl
variable "allocate_elastic_ip" {
  default = false
}
```

## Outputs Reference

After deployment:

| Output | Description |
|--------|-------------|
| `instance_id` | EC2 instance identifier |
| `instance_public_ip` | Public IP address |
| `api_url` | Direct API endpoint URL |
| `ssh_command` | SSH connection command |

Access outputs:
```bash
terraform output
terraform output -json
terraform output instance_public_ip
```

## Monitoring and Logs

**System logs:**
```bash
# Cloud-init (deployment)
/var/log/cloud-init-output.log

# API service
journalctl -u minirun-api

# Application logs
/var/log/minirun/
```

**CloudWatch (if configured):**
- Instance metrics via IAM role
- Custom application metrics
- Log aggregation

## Updating the Deployment

To update after code changes:
```bash
# Method 1: Destroy and recreate
terraform destroy
terraform apply

# Method 2: SSH and update manually
ssh ubuntu@<IP>
cd /opt/minirun
git pull
./scripts/deploy.sh
sudo systemctl restart minirun-api
```

## Cleanup

**Important:** This deletes everything.
```bash
terraform destroy
# Type 'yes' to confirm
```

This removes:
- EC2 instance
- VPC and subnets
- Security groups
- Elastic IP (if created)
- All associated resources

---

**Part of MiniRun Container Runtime** - AWS deployment automation