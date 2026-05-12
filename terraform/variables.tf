variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "ID of the existing VPC (cs312-vpc)"
}

variable "subnet_id" {
  type        = string
  description = "ID of the public subnet for the EC2 instance"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name for SSH access"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path to the SSH private key file used by the Ansible provisioner"
  default     = "~/.ssh/cs312-key.pem"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type. t3.medium gives 2 vCPU / 4 GB, sufficient for a small server"
  default     = "t3.medium"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the EC2 instance. Default is Amazon Linux 2023 in us-east-1"
  default     = "ami-0a59ec92177ec3fad"
}

variable "ecr_image_uri" {
  type        = string
  description = "Full ECR URI including tag to deploy, e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/minecraft-server:mc-1.21.4-build1"
}

variable "s3_backup_bucket" {
  type        = string
  description = "S3 bucket name that holds world backups. Must already exist; not destroyed with terraform destroy"
}

variable "student_id" {
  type        = string
  description = "Shown in the server MOTD, satisfies the rubric requirement for name/ID visibility"
  default     = "henderos"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR block allowed SSH on port 22. Restrict to your IP/32 in production"
  default     = "0.0.0.0/0"
}
