#!/bin/bash
# Fetches a fresh ECR token using the EC2 instance profile (LabRole) and writes
# it to k3s registries.yaml, then restarts k3s so the new credentials are used.
# This script is deployed to /usr/local/bin/refresh-ecr-creds.sh by cloud-init
# and executed by the ecr-cred-refresh.timer systemd unit every 6 hours.
# ECR tokens are valid for 12 hours; refreshing at 6h provides a safety margin.

set -euo pipefail

AWS_REGION="us-east-1"
ECR_REGISTRY="232259924361.dkr.ecr.us-east-1.amazonaws.com"

ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")

mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << YAML
configs:
  "$ECR_REGISTRY":
    auth:
      username: AWS
      password: "$ECR_TOKEN"
YAML

systemctl restart k3s
echo "ECR credentials refreshed at $(date)"
