#!/bin/bash
set -euo pipefail
exec >> /var/log/cloud-init-minecraft.log 2>&1

echo "=== Minecraft k3s bootstrap: $(date) ==="

# ── 1. Install k3s ──────────────────────────────────────────────────────────────
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.29.4+k3s1" sh -
# The k3s installer enables and starts the k3s systemd service automatically.

echo "Waiting for k3s node to be Ready..."
timeout 180 bash -c 'until /usr/local/bin/kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done'
echo "k3s ready"

# ── 2. ECR authentication ────────────────────────────────────────────────────────
# k3s uses containerd. We configure ECR credentials via registries.yaml and
# refresh them every 6 hours with a systemd timer. The LabInstanceProfile
# (LabRole) provides AWS credentials via the EC2 metadata service — no
# credentials are stored in manifests or environment variables.

dnf install -y amazon-ecr-credential-helper

# Write the refresh script. ${aws_region} and ${ecr_registry} are substituted
# by Terraform. $ECR_TOKEN is a bash variable expanded at runtime.
cat > /usr/local/bin/refresh-ecr-creds.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
ECR_TOKEN=$(aws ecr get-login-password --region ${aws_region})
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << YAML
configs:
  "${ecr_registry}":
    auth:
      username: AWS
      password: "$ECR_TOKEN"
YAML
systemctl restart k3s
SCRIPT
chmod +x /usr/local/bin/refresh-ecr-creds.sh

# Fetch initial credentials and restart k3s with them loaded.
/usr/local/bin/refresh-ecr-creds.sh

echo "Waiting for k3s to be Ready after credential update..."
timeout 180 bash -c 'until /usr/local/bin/kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done'
echo "k3s ready"

# Schedule refresh every 6 hours (ECR tokens are valid for 12 hours).
cat > /etc/systemd/system/ecr-cred-refresh.service << 'UNIT'
[Unit]
Description=Refresh ECR credentials for k3s registries.yaml

[Service]
Type=oneshot
ExecStart=/usr/local/bin/refresh-ecr-creds.sh
UNIT

cat > /etc/systemd/system/ecr-cred-refresh.timer << 'UNIT'
[Unit]
Description=Refresh ECR credentials every 6 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now ecr-cred-refresh.timer

# ── 3. Write Kubernetes manifests ────────────────────────────────────────────────
# Manifests are rendered by Terraform from the k8s/ directory in the repo and
# written here so the host can re-apply them manually if needed.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p /opt/minecraft/k8s

cat > /opt/minecraft/k8s/namespace.yaml << 'MANIFEST'
${namespace_yaml}
MANIFEST

cat > /opt/minecraft/k8s/configmap.yaml << 'MANIFEST'
${configmap_yaml}
MANIFEST

cat > /opt/minecraft/k8s/pvc.yaml << 'MANIFEST'
${pvc_yaml}
MANIFEST

cat > /opt/minecraft/k8s/deployment.yaml << 'MANIFEST'
${deployment_yaml}
MANIFEST

cat > /opt/minecraft/k8s/service.yaml << 'MANIFEST'
${service_yaml}
MANIFEST

cat > /opt/minecraft/k8s/backup-cronjob.yaml << 'MANIFEST'
${backup_yaml}
MANIFEST

# ── 4. Apply manifests ───────────────────────────────────────────────────────────
# Namespace must be created first; remaining resources are applied in dependency
# order to avoid "namespace not found" errors.
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/namespace.yaml
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/configmap.yaml
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/pvc.yaml
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/service.yaml
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/deployment.yaml
/usr/local/bin/kubectl apply -f /opt/minecraft/k8s/backup-cronjob.yaml

echo "=== Bootstrap complete: $(date) ==="
echo "Monitor pod: kubectl -n minecraft get pods -w"
