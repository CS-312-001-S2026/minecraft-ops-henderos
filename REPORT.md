# Ops 4: Container Orchestration — Architecture and Operations Documentation

**Student ID:** henderos  
**Course:** CS-312  
**Repository:** https://github.com/CS-312-001-S2026/minecraft-ops-henderos  
**Public endpoint:** 54.197.145.134:25565

---

## 1. Architecture Diagram

```
  Internet
     │
     │ TCP 25565 (Minecraft clients)
     │ TCP 22 (SSH admin, 0.0.0.0/0)
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS us-east-1  │  VPC: cs312-vpc (10.0.0.0/16)               │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  EC2: t3.medium  │  Amazon Linux 2023  │  10.0.1.23       │  │
│  │  IAM: LabInstanceProfile (LabRole)  —  no hardcoded creds │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  k3s v1.29.4  (single-node control-plane + worker)  │  │  │
│  │  │  Namespace: minecraft                                │  │  │
│  │  │                                                      │  │  │
│  │  │  ┌──────────────────┐   ┌─────────────────────────┐ │  │  │
│  │  │  │  Deployment      │   │  Service (LoadBalancer)  │ │  │  │
│  │  │  │  minecraft       │   │  minecraft               │ │  │  │
│  │  │  │  replicas: 1     │   │  port: 25565 → 25565     │ │  │  │
│  │  │  │  strategy:       │   │  k3s ServiceLB binds     │ │  │  │
│  │  │  │    Recreate      │   │  host port directly      │ │  │  │
│  │  │  │                  │   └─────────────────────────┘ │  │  │
│  │  │  │  Pod:            │                                │  │  │
│  │  │  │  ┌────────────┐  │   ┌─────────────────────────┐ │  │  │
│  │  │  │  │init:       │  │   │  ConfigMap               │ │  │  │
│  │  │  │  │world-      │  │   │  minecraft-config        │ │  │  │
│  │  │  │  │restore     │──┼──▶│  EULA, VERSION, MOTD,    │ │  │  │
│  │  │  │  ├────────────┤  │   │  MEMORY                  │ │  │  │
│  │  │  │  │minecraft   │  │   └─────────────────────────┘ │  │  │
│  │  │  │  │(itzg image)│  │                                │  │  │
│  │  │  │  └─────┬──────┘  │   ┌─────────────────────────┐ │  │  │
│  │  │  │        │ mount   │   │  PVC: minecraft-world    │ │  │  │
│  │  │  │        └─────────┼──▶│  5Gi  │  local-path      │ │  │  │
│  │  │  └──────────────────┘   └─────────────────────────┘ │  │  │
│  │  │                                                      │  │  │
│  │  │  ┌──────────────────────────────────────────────┐   │  │  │
│  │  │  │  CronJob: minecraft-backup (0 * * * *)        │   │  │  │
│  │  │  │  mounts PVC read-only → tar → S3              │   │  │  │
│  │  │  └──────────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ECR: 232259924361.dkr.ecr.us-east-1.amazonaws.com              │
│       /minecraft-server:mc-1.21.4-build1  ◄── GitHub Actions    │
│                                                                  │
│  S3: minecraft-backups-rosshenderson                             │
│      /minecraft/world-backup.tar.gz                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Runbook

### 2.1 Prerequisites

- AWS Academy session active with credentials exported
- Terraform >= 1.5 installed
- SSH key at `C:\Users\Ross\Downloads\cs312-key.pem`
- ECR repository `minecraft-server` exists in account 232259924361
- S3 bucket `minecraft-backups-rosshenderson` exists

### 2.2 Deployment Procedure

**Step 1 — Export AWS credentials** from the AWS Academy Vocareum console:

```powershell
$env:AWS_ACCESS_KEY_ID     = "<from Vocareum>"
$env:AWS_SECRET_ACCESS_KEY = "<from Vocareum>"
$env:AWS_SESSION_TOKEN     = "<from Vocareum>"
```

**Step 2 — Initialize and apply Terraform:**

```powershell
cd C:\Users\Ross\ops4-minecraft\terraform
terraform init
terraform apply -auto-approve
```

Terraform provisions one EC2 instance (t3.medium) and reuses the existing `minecraft-sg` security group. The `user_data` cloud-init script runs automatically and:

1. Installs k3s v1.29.4
2. Installs `amazon-ecr-credential-helper` and writes ECR credentials to `/etc/rancher/k3s/registries.yaml` using the instance's IAM role
3. Schedules an `ecr-cred-refresh` systemd timer to refresh the ECR token every 6 hours
4. Writes Kubernetes manifests to `/opt/minecraft/k8s/` and applies them

**Step 3 — Monitor bootstrap progress** (takes ~5 minutes):

```bash
ssh -i C:\Users\Ross\Downloads\cs312-key.pem ec2-user@<public-ip> \
  sudo tail -f /var/log/cloud-init-minecraft.log
```

Wait for `=== Bootstrap complete ===`.

**Step 4 — Verify the pod is running:**

```bash
sudo kubectl -n minecraft get pods
# Expected: minecraft-<hash>   1/1   Running
```

**Step 5 — Verify service is reachable:**

```
nmap -sV -Pn -p T:25565 <public-ip>
# Expected: 25565/tcp open  minecraft  Minecraft 1.21.4 ... Message: Minecraft Server | henderos
```

---

### 2.3 Service Exposure on Port 25565

The Kubernetes Service is of type `LoadBalancer`. On single-node k3s, the built-in ServiceLB (klipper-lb) binds port 25565 directly on the EC2 host's network interface. No additional ingress or port-forwarding configuration is required. The security group allows inbound TCP 25565 from `0.0.0.0/0`.

Verify binding:

```bash
sudo kubectl -n minecraft get svc
# Expected: minecraft   LoadBalancer   10.43.x.x   10.0.1.23   25565:xxxxx/TCP
```

---

### 2.4 Rollout Procedure

To deploy a new image version:

```bash
sudo kubectl set image deployment/minecraft -n minecraft \
  minecraft=232259924361.dkr.ecr.us-east-1.amazonaws.com/minecraft-server:<new-tag>

sudo kubectl rollout status deployment/minecraft -n minecraft
# Wait for: deployment "minecraft" successfully rolled out
```

Because the deployment uses `strategy: Recreate`, the old pod is terminated before the new pod starts. Expect ~30-90 seconds of downtime during the rollout.

---

### 2.5 Rollback Procedure

To revert to the previous image version:

```bash
sudo kubectl rollout undo deployment/minecraft -n minecraft

sudo kubectl rollout status deployment/minecraft -n minecraft
# Wait for: deployment "minecraft" successfully rolled out
```

To view rollout history:

```bash
sudo kubectl rollout history deployment/minecraft -n minecraft
```

---

### 2.6 Backup Procedure

World data is backed up automatically by a Kubernetes CronJob (`minecraft-backup`) that runs every hour (`0 * * * *`). The job:

1. Mounts the `minecraft-world` PVC read-only
2. Archives `/data/world` with `tar -czf`
3. Uploads the archive to `s3://minecraft-backups-rosshenderson/minecraft/world-backup.tar.gz`

To trigger a manual backup immediately:

```bash
sudo kubectl create job --from=cronjob/minecraft-backup manual-backup-$(date +%s) -n minecraft
sudo kubectl get jobs -n minecraft
```

To confirm the backup exists in S3:

```bash
aws s3 ls s3://minecraft-backups-rosshenderson/minecraft/world-backup.tar.gz --region us-east-1
```

---

### 2.7 Restore Procedure

World data is restored automatically from S3 on the first pod start when `/data/world` does not exist. This is handled by the `world-restore` init container in the Deployment.

**To restore from S3 to an existing deployment (e.g., after data corruption):**

**Step 1** — SSH into the EC2 host:

```bash
ssh -i C:\Users\Ross\Downloads\cs312-key.pem ec2-user@<public-ip>
```

**Step 2** — Delete the world directory inside the running pod:

```bash
POD=$(sudo kubectl get pod -n minecraft -l app=minecraft \
  -o jsonpath='{.items[0].metadata.name}')

sudo kubectl exec -n minecraft $POD -- rm -rf /data/world
```

**Step 3** — Delete the pod to trigger a replacement with a fresh init container run:

```bash
sudo kubectl delete pod -n minecraft $POD
```

**Step 4** — Watch the replacement pod start:

```bash
sudo kubectl get pods -n minecraft -w
```

The init container detects `/data/world` is missing, downloads `world-backup.tar.gz` from S3, and extracts it to `/data` before the Minecraft container starts.

**Step 5** — Verify world data is present:

```bash
POD=$(sudo kubectl get pod -n minecraft -l app=minecraft \
  -o jsonpath='{.items[0].metadata.name}')

sudo kubectl exec -n minecraft $POD -- ls /data/world
# Expected: data  datapacks  DIM-1  DIM1  entities  level.dat  region  ...
```

**Step 6** — Confirm the server is reachable:

```
nmap -sV -Pn -p T:25565 <public-ip>
```

---

## 3. Tradeoff Notes

### 3.1 Workload Controller: Deployment vs. StatefulSet

A `Deployment` with a PVC was chosen over a `StatefulSet`. A StatefulSet provides stable pod identity and ordered scaling, which is valuable for distributed stateful systems. For a single-replica Minecraft server, stable pod identity is unnecessary — there is only one replica and it is never scaled horizontally. A Deployment is simpler to configure, roll back, and reason about. The world data persistence guarantee is provided by the PVC, not by the pod identity.

### 3.2 Deployment Strategy: Recreate vs. RollingUpdate

The deployment uses `strategy: Recreate` rather than the default `RollingUpdate`. Recreate terminates the old pod before creating the new one. Two reasons justify this:

1. **Memory constraint**: t3.medium has 4 GB RAM. With k3s overhead (~1 GB), only ~3 GB is available for pods. The Minecraft pod requests 2 Gi. A rolling update would require two pods simultaneously, exceeding available memory and leaving the new pod stuck in `Pending`.
2. **PVC access**: The PVC uses `ReadWriteOnce` access mode. On single-node k3s with the `local-path` provisioner, this is not strictly enforced at the node level, but two Minecraft processes writing to the same world directory simultaneously would corrupt data. Recreate eliminates this risk.

The tradeoff is brief downtime (~30–90 seconds) during rollouts, which is acceptable for a non-production single-player server.

### 3.3 Persistence: local-path vs. Cloud-Managed Volume

The PVC uses k3s's default `local-path` storage class, which provisions volumes on the node's local disk at `/var/lib/rancher/k3s/storage/`. This is simpler than provisioning an EBS volume and attaching it. The tradeoff is that world data is tied to the EC2 instance: if the instance is terminated, the PVC data is lost. This is mitigated by the hourly S3 backup, which provides a durable off-node copy that survives instance termination and is used to restore on fresh deployments.

For a production workload, an EBS-backed PersistentVolume would be appropriate. For this single-node assignment, local-path is acceptable and well-documented.

### 3.4 Service Exposure: LoadBalancer vs. NodePort

The Service uses type `LoadBalancer`. On single-node k3s, the built-in ServiceLB (klipper-lb) binds the service port directly on the host's network interface without requiring an external load balancer. This is the assignment's primary submission path. NodePort was not used because it allocates a high port (30000–32767) and requires NAT rules to reach port 25565 from the internet. HostPort was not used because it bypasses the Kubernetes service abstraction. LoadBalancer with ServiceLB is the cleanest single-node path.

### 3.5 Probe Configuration

All probes use `tcpSocket` on port 25565. Minecraft does not expose an HTTP health endpoint, so a TCP socket check is the strongest signal available without implementing a custom RCON-based health check. An open TCP socket means the JVM has started and the Minecraft server is accepting connections, which is the practical definition of readiness for this workload. The limitation is that the socket can briefly accept connections while the world is still loading, but in practice the server is joinable immediately after the port opens.

**startupProbe**: `initialDelaySeconds: 30`, `periodSeconds: 15`, `failureThreshold: 20`. This gives the JVM up to 5 minutes (30 + 20×15 = 330 seconds) to open port 25565 before Kubernetes declares the pod failed. Minecraft on a fresh world load typically opens the port within 30–60 seconds. The generous window prevents restart loops on slow world loads or large world sizes. Without a startupProbe, the liveness probe would kill the container before it finishes starting.

**readinessProbe**: `periodSeconds: 10`, `failureThreshold: 3`. Gates traffic to the pod. If the server stops responding (e.g., garbage collection pause), the pod is removed from the service endpoint within 30 seconds.

**livenessProbe**: `periodSeconds: 30`, `failureThreshold: 3`. Kills and restarts the container if it is completely unresponsive for 90 seconds. The longer period avoids false positives during GC pauses.

### 3.6 Resource Requests and Limits

| Field | Value | Rationale |
|---|---|---|
| `requests.memory` | 2 Gi | The JVM heap is configured to 2 GB via `MEMORY=2G`. This request ensures the scheduler places the pod only on nodes with sufficient memory. |
| `limits.memory` | 3 Gi | Allows 1 GB of headroom above the heap for JVM metadata, native memory, and OS buffers. Without a limit, a memory leak could consume all node memory and crash k3s. |
| `requests.cpu` | 500m | Guarantees half a core at all times, sufficient for a low-player-count server. |
| `limits.cpu` | 1500m | Allows burst to 1.5 cores during chunk generation or startup without monopolizing the node. |

### 3.7 Security

**Security Group**: Two inbound rules only — SSH (22) from `0.0.0.0/0` and Minecraft (25565) from `0.0.0.0/0`. No other ports are open. For a production deployment, SSH should be restricted to a known CIDR (`/32`). All outbound is permitted for ECR pulls, S3 backups, and package installation.

**IAM**: The EC2 instance uses `LabInstanceProfile` (LabRole). No AWS credentials are stored in Kubernetes Secrets, environment variables, manifests, or on the filesystem. The ECR credential refresh script calls `aws ecr get-login-password` using the instance metadata service, which returns short-lived credentials from the role. The same role provides S3 access for backups and restores.

---

## 4. Repository Link and File Map

**Repository:** https://github.com/CS-312-001-S2026/minecraft-ops-henderos

| File | Description |
|---|---|
| `terraform/main.tf` | Provisions EC2 instance and security group; renders cloud-init via `templatefile()` |
| `terraform/variables.tf` | Input variable definitions |
| `terraform/outputs.tf` | Public IP, SSH command, bootstrap log command |
| `terraform/terraform.tfvars` | Variable values (VPC, subnet, ECR URI, S3 bucket, student ID) |
| `terraform/cloud-init.sh.tpl` | Bootstrap script: installs k3s, configures ECR auth, writes and applies manifests |
| `k8s/namespace.yaml` | `minecraft` namespace |
| `k8s/configmap.yaml` | Server configuration (EULA, VERSION, MOTD, MEMORY) |
| `k8s/pvc.yaml` | 5 Gi PersistentVolumeClaim using `local-path` storage class |
| `k8s/deployment.yaml` | Deployment with init container (S3 restore), probes, resource limits, Recreate strategy |
| `k8s/service.yaml` | LoadBalancer Service on port 25565 |
| `k8s/backup-cronjob.yaml` | Hourly CronJob — tars world directory and uploads to S3 |
| `scripts/refresh-ecr-creds.sh` | Reference copy of the ECR token refresh script deployed by cloud-init |
| `.github/workflows/publish.yml` | CI pipeline — smoke-tests image and pushes to ECR on `mc-*` git tags |

---

## 5. Teardown Checklist

Complete these steps in order after the assignment ends to avoid ongoing charges.

- [ ] **1. Trigger a final backup** before destroying infrastructure:

```bash
ssh -i C:\Users\Ross\Downloads\cs312-key.pem ec2-user@<public-ip>
sudo kubectl create job --from=cronjob/minecraft-backup final-backup -n minecraft
sudo kubectl wait --for=condition=complete job/final-backup -n minecraft --timeout=120s
```

- [ ] **2. Destroy all Terraform-managed resources:**

```powershell
cd C:\Users\Ross\ops4-minecraft\terraform
terraform destroy -auto-approve
```

This terminates the EC2 instance and deletes the security group. The EBS root volume is deleted automatically (`delete_on_termination = true`).

- [ ] **3. Confirm EC2 instance is terminated** in the AWS console (EC2 → Instances).

- [ ] **4. Confirm no orphaned volumes** (EC2 → Elastic Block Store → Volumes). Delete any volumes in `available` state.

- [ ] **5. The S3 bucket and ECR repository are NOT destroyed by Terraform** (intentional — they hold the world backup and images). Empty and delete them manually if no longer needed:

```bash
aws s3 rm s3://minecraft-backups-rosshenderson --recursive
aws s3 rb s3://minecraft-backups-rosshenderson
aws ecr delete-repository --repository-name minecraft-server --force --region us-east-1
```

- [ ] **6. Stop the AWS Academy lab session** in Vocareum to prevent the session timer from running.

---

## 6. Cost Controls

| Control | Detail |
|---|---|
| Instance type | t3.medium ($0.0464/hr). Sufficient for Minecraft + k3s; no over-provisioning. |
| Stop schedule | Stop the EC2 instance when not in use via the AWS console or `aws ec2 stop-instances`. World data persists on the EBS root volume. |
| No Elastic IP | Public IP is ephemeral; no additional EIP charge. Update the security group and nmap target after restart if IP changes. |
| Single instance | No NAT gateway, no ALB, no multi-AZ — only one EC2 instance and its EBS volume incur charges. |
| S3 storage | One `world-backup.tar.gz` object, overwritten hourly. Typical Minecraft world is under 50 MB; S3 cost is negligible. |
| Teardown | `terraform destroy` eliminates all compute cost. Run it immediately after the assignment is graded. |
