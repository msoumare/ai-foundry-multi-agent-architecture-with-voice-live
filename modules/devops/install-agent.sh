#!/bin/bash
# Install Azure DevOps Agent and required tools for AKS and Terraform
set -e
export DEBIAN_FRONTEND=noninteractive

# This VMSS subnet uses NAT-based IPv4 egress; disable IPv6 preference for apt.
cat >/etc/apt/apt.conf.d/99force-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

# Update system
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y wget unzip jq curl build-essential --fix-missing -o Acquire::ForceIPv4=true

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
# Validate kubectl binary (optional)
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# Install kubelogin
curl -LO "https://github.com/Azure/kubelogin/releases/download/v0.0.25/kubelogin-linux-amd64.zip"
unzip -j "kubelogin-linux-amd64.zip" -d /usr/local/bin
rm -f "kubelogin-linux-amd64.zip"
kubelogin --version

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y terraform --fix-missing -o Acquire::ForceIPv4=true

# Create agent directory
mkdir -p /opt/azure-devops-agent
cd /opt/azure-devops-agent

# Download agent with fallback URLs and retries to avoid transient DNS/endpoint issues
AGENT_VERSION="3.236.1"
AGENT_TARBALL="vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
AGENT_URLS=(
  "https://download.agent.dev.azure.com/agent/${AGENT_VERSION}/${AGENT_TARBALL}"
  "https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/${AGENT_TARBALL}"
)

DOWNLOAD_OK=0
for AGENT_URL in "${AGENT_URLS[@]}"; do
  echo "Attempting Azure DevOps agent download from: ${AGENT_URL}"
  if curl -fL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 180 -o "${AGENT_TARBALL}" "${AGENT_URL}"; then
    DOWNLOAD_OK=1
    break
  fi
done

if [ "$DOWNLOAD_OK" -ne 1 ]; then
  echo "ERROR: Unable to download Azure DevOps agent from all known endpoints."
  exit 1
fi

tar zxvf "${AGENT_TARBALL}"

# Configure the Azure DevOps self-hosted agent from environment variables.
# This script uses a PAT for unattended agent registration.
if [ -z "${AZDO_URL:-}" ]; then
  echo "ERROR: AZDO_URL must be set to configure the Azure DevOps agent."
  echo "Example: AZDO_URL=https://dev.azure.com/mosoum"
  exit 1
fi

if [ -z "${AZDO_PAT:-}" ]; then
  echo "ERROR: AZDO_PAT is required to configure the Azure DevOps agent."
  echo "Create a PAT in Azure DevOps: User settings -> Personal access tokens"
  echo "Use at least scope: Agent Pools (Read & manage)"
  echo "Store it as secret variable AZDO_PAT in your variable group"
  exit 1
fi

AZDO_POOL="${AZDO_POOL:-default}"
AZDO_AGENT_NAME="${AZDO_AGENT_NAME:-$(hostname)}"

./config.sh --unattended \
  --url "$AZDO_URL" \
  --auth pat \
  --token "$AZDO_PAT" \
  --pool "$AZDO_POOL" \
  --agent "$AZDO_AGENT_NAME" \
  --acceptTeeEula

sudo ./svc.sh install
sudo ./svc.sh start
