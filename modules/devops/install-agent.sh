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

# Note: In production, configure the agent with PAT and URL from Key Vault or environment variables
# Example: ./config.sh --unattended --url https://dev.azure.com/org --auth pat --token $PAT --pool default --agent $(hostname) --acceptTeeEula

# For now, placeholder - replace with actual config
echo "Agent downloaded. Configure manually or via automation."

# Start agent (uncomment when configured)
# sudo ./svc.sh install
# sudo ./svc.sh start