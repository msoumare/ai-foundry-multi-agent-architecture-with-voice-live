#!/bin/bash
#!/bin/bash
# Install Azure DevOps Agent and required tools for AKS and Terraform
set -e

# Update system
apt-get update
apt-get install -y wget unzip jq curl build-essential

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
apt-get update
apt-get install -y terraform

# Create agent directory
mkdir -p /opt/azure-devops-agent
cd /opt/azure-devops-agent

# Download latest agent (adjust version as needed)
AGENT_VERSION="3.236.1"
wget https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz
tar zxvf vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz

# Configure the Azure DevOps self-hosted agent automatically from environment variables.
# Required values should be passed securely (for example, via VMSS extension protected settings or Key Vault)
if [ -z "${AZDO_URL:-}" ] || [ -z "${AZDO_PAT:-}" ]; then
  echo "ERROR: AZDO_URL and AZDO_PAT must be set to configure the Azure DevOps agent."
  echo "Set AZDO_URL to your Azure DevOps organization URL and AZDO_PAT to a PAT with agent pool registration rights."
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
  --acceptteeeula

sudo ./svc.sh install
sudo ./svc.sh start