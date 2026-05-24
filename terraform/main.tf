terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Reference pre-existing network resources from Ops 2/3 ──────────────────────

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
  # No AWS credentials are placed on the host or in any manifest.
  iam_instance_profile = "LabInstanceProfile"

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/cloud-init.sh.tpl", {
    aws_region       = var.aws_region
    ecr_registry     = var.ecr_registry
    ecr_image_uri    = var.ecr_image_uri
    s3_backup_bucket = var.s3_backup_bucket
    student_id       = var.student_id
    namespace_yaml   = file("${path.module}/../k8s/namespace.yaml")
    configmap_yaml   = file("${path.module}/../k8s/configmap.yaml")
    pvc_yaml         = file("${path.module}/../k8s/pvc.yaml")
    deployment_yaml  = file("${path.module}/../k8s/deployment.yaml")
    service_yaml     = file("${path.module}/../k8s/service.yaml")
    backup_yaml      = file("${path.module}/../k8s/backup-cronjob.yaml")
  })

  tags = {
    Name = "minecraft-server"
  }
}
