#!/bin/bash
# Install build tools required by Azure DevOps pipeline jobs.
# Agent lifecycle (install, register, deregister) is managed by the Azure DevOps native VMSS pool integration -- no agent registration is done here.
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[$(date)] Starting build tools installation..."

# At first boot, DNS can lag behind cloud-init; with set -e one failed lookup would
# abort setup and leave the agent without az/terraform. Wait for DNS and retry apt.
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
for attempt in $(seq 1 30); do
  getent hosts azure.archive.ubuntu.com >/dev/null && break
  echo "[$(date)] Waiting for DNS (attempt $attempt/30)..."
  sleep 10
done

# Install base dependencies + Terraform repo in one pass (avoid duplicate apt-get update)
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y wget unzip jq curl build-essential gnupg lsb-release --fix-missing -o Acquire::ForceIPv4=true

# Add Terraform repo early to batch with above apt-get update
echo "[$(date)] Adding Terraform repository..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y terraform --fix-missing -o Acquire::ForceIPv4=true
echo "[$(date)] Terraform installed: $(terraform version | head -1)"

# Install Azure CLI (quick - ~30s)
echo "[$(date)] Installing Azure CLI..."
curl --connect-timeout 30 --max-time 300 --retry 5 --retry-delay 10 -sL https://aka.ms/InstallAzureCLIDeb | bash
echo "[$(date)] Azure CLI installed: $(az --version | head -1)"

# Install kubectl (quick - ~15s)
echo "[$(date)] Installing kubectl..."
KUBECTL_VERSION=$(curl --connect-timeout 30 --max-time 30 -L -s https://dl.k8s.io/release/stable.txt)
curl --connect-timeout 30 --max-time 300 -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl --connect-timeout 30 --max-time 300 -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl kubectl.sha256
echo "[$(date)] kubectl installed: $(kubectl version --client --short 2>/dev/null || echo 'v?')"

# Install Helm (quick - ~15s)
echo "[$(date)] Installing Helm..."
curl --connect-timeout 30 --max-time 300 -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm -f get_helm.sh
echo "[$(date)] Helm installed: $(helm version --short)"

# Install kubelogin (quick - ~10s)
echo "[$(date)] Installing kubelogin..."
curl --connect-timeout 30 --max-time 300 -LO "https://github.com/Azure/kubelogin/releases/download/v0.0.25/kubelogin-linux-amd64.zip"
unzip -q -j "kubelogin-linux-amd64.zip" -d /usr/local/bin
rm -f kubelogin-linux-amd64.zip
echo "[$(date)] kubelogin installed: $(kubelogin --version)"

echo "[$(date)] Build tools installation complete."
