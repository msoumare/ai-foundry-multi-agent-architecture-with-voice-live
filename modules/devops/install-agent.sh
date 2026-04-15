#!/bin/bash
# Install build tools required by Azure DevOps pipeline jobs.
# Agent lifecycle (install, register, deregister) is managed by the Azure DevOps
# native VMSS pool integration -- no agent registration is done here.
set -e
export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y wget unzip jq curl build-essential --fix-missing -o Acquire::ForceIPv4=true

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install kubelogin
curl -LO "https://github.com/Azure/kubelogin/releases/download/v0.0.25/kubelogin-linux-amd64.zip"
unzip -j "kubelogin-linux-amd64.zip" -d /usr/local/bin
kubelogin --version

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -o Acquire::ForceIPv4=true
apt-get install -y terraform --fix-missing -o Acquire::ForceIPv4=true

echo "Build tools installation complete."
