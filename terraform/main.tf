terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State is stored locally in terraform.tfstate.
  # For shared team workflows, replace with an S3 backend + DynamoDB lock:
  #
  # backend "s3" {
  #   bucket         = "minecraft-backups-rosshenderson"
  #   key            = "ops3/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# ── Reference pre-existing network resources from Ops 2 ────────────────────────

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  id = var.subnet_id
}

# ── Security Group ──────────────────────────────────────────────────────────────

resource "aws_security_group" "minecraft" {
  name        = "minecraft-sg"
  description = "SSH admin access and Minecraft client connections"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Minecraft clients"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound (ECR pull, S3 backup, package installs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-sg"
  }
}

# ── EC2 instance ────────────────────────────────────────────────────────────────

resource "aws_instance" "minecraft" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.public.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true

  # LabInstanceProfile contains LabRole, which grants ECR pull and S3 read/write.
  # No AWS credentials are placed on the host.
  iam_instance_profile = "LabInstanceProfile"

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  # Bootstrap: install Python so Ansible can connect immediately.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y python3
  EOF

  tags = {
    Name = "minecraft-server"
  }
}

# ── Ansible provisioner ─────────────────────────────────────────────────────────
# Runs ansible-playbook from the local machine after the instance is ready.
# On Windows: run from WSL or execute the ansible-playbook command manually
# after terraform apply completes.

resource "null_resource" "ansible_provision" {
  triggers = {
    instance_id = aws_instance.minecraft.id
  }

  provisioner "local-exec" {
    interpreter = ["wsl", "--", "bash", "-c"]
    command     = "sleep 45 && ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${aws_instance.minecraft.public_ip},' --private-key ~/.ssh/cs312-key.pem -u ec2-user --ssh-extra-args='-o StrictHostKeyChecking=no' -e 'ecr_image_uri=${var.ecr_image_uri}' -e 's3_backup_bucket=${var.s3_backup_bucket}' -e 'student_id=${var.student_id}' /mnt/c/Users/Ross/ops3-minecraft/ansible/playbook.yml"
  }
}
