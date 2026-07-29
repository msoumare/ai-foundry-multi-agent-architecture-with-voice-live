Param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$AgentFolders,
    [string]$SubscriptionId,
    [string]$TenantId,
    [string]$ResourceGroup,
    [string]$ProjectId,
    [string]$ProjectEndpoint,
    [string]$ContainerRegistryEndpoint,
    [string]$ModelDeployment = "gpt-5.1"
)
$ErrorActionPreference = "Stop"
# Prefer Azure CLI auth for azd extension calls to avoid AzureDeveloperCLICredential failures.
if (-not $env:AZURE_TOKEN_CREDENTIALS) {
    $env:AZURE_TOKEN_CREDENTIALS = "AzureCliCredential"
}

# Force azd into non-interactive behavior in CI to avoid hidden prompts.
$env:CI = "true"
$env:AZD_NON_INTERACTIVE = "true"

function Invoke-AzdStep {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        [string]$ErrorMessage = "azd command failed"
    )

    Write-Host "[$(Get-Date -Format o)] $Description" -ForegroundColor DarkGray
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Initialize-AzdAuthentication {
    Write-Host "[$(Get-Date -Format o)] Checking azd auth status" -ForegroundColor DarkGray
    azd auth login --check-status --no-prompt 2>$null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    # Workload identity path (federated) for Azure DevOps.
    if (-not [string]::IsNullOrWhiteSpace($env:servicePrincipalId) -and
        -not [string]::IsNullOrWhiteSpace($env:tenantId) -and
        -not [string]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN)) {

        Invoke-AzdStep -Description "Logging into azd with Azure DevOps workload identity federation" `
            -Command { azd auth login --client-id $env:servicePrincipalId --tenant-id $env:tenantId --federated-credential-provider azure-pipelines --no-prompt } `
            -ErrorMessage "azd workload identity login failed"
        return
    }

    # Service principal with secret fallback.
    if (-not [string]::IsNullOrWhiteSpace($env:servicePrincipalId) -and
        -not [string]::IsNullOrWhiteSpace($env:servicePrincipalKey) -and
        -not [string]::IsNullOrWhiteSpace($env:tenantId)) {

        Invoke-AzdStep -Description "Logging into azd with Azure DevOps service principal secret" `
            -Command { azd auth login --client-id $env:servicePrincipalId --client-secret $env:servicePrincipalKey --tenant-id $env:tenantId --no-prompt } `
            -ErrorMessage "azd service principal login failed"
        return
    }

    throw "azd is not authenticated. For workload identity, ensure addSpnToEnvironment=true and SYSTEM_ACCESSTOKEN is available to the task."
}

function Invoke-AzdDeploy {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        [Parameter(Mandatory = $true)]
        [string]$ProjectEndpoint,
        [Parameter(Mandatory = $true)]
        [string]$ContainerRegistryEndpoint,
        [Parameter(Mandatory = $true)]
        [string]$ModelDeployment
    )
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    Push-Location $Path
    try {
        $logDir = Join-Path $PSScriptRoot "deploy-logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir | Out-Null
        }
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $deployLog = Join-Path $logDir ("{0}-{1}-azd-deploy.log" -f $Name, $stamp)
        if (-not (Test-Path "azure.yaml")) {
            throw "azure.yaml not found in '$Path'. Run 'azd ai agent init' in this folder first."
        }
        $envName = if ([string]::IsNullOrWhiteSpace($env:AZURE_ENV_NAME)) { "ci" } else { $env:AZURE_ENV_NAME }
        Write-Host "Using azd environment '$envName'" -ForegroundColor DarkGray
        azd env select $envName --no-prompt 2>$null
        if ($LASTEXITCODE -ne 0) {
            Invoke-AzdStep -Description "Creating azd environment '$envName'" -Command { azd env new $envName --no-prompt } -ErrorMessage "azd env new failed for $Name"
            Invoke-AzdStep -Description "Selecting azd environment '$envName'" -Command { azd env select $envName --no-prompt } -ErrorMessage "azd env select failed for $Name"
        }

        Invoke-AzdStep -Description "Setting AZURE_SUBSCRIPTION_ID" -Command { azd env set AZURE_SUBSCRIPTION_ID $SubscriptionId --no-prompt } -ErrorMessage "azd env set AZURE_SUBSCRIPTION_ID failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_TENANT_ID" -Command { azd env set AZURE_TENANT_ID $TenantId --no-prompt } -ErrorMessage "azd env set AZURE_TENANT_ID failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_RESOURCE_GROUP" -Command { azd env set AZURE_RESOURCE_GROUP $ResourceGroup --no-prompt } -ErrorMessage "azd env set AZURE_RESOURCE_GROUP failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_RESOURCE_GROUP_NAME" -Command { azd env set AZURE_RESOURCE_GROUP_NAME $ResourceGroup --no-prompt } -ErrorMessage "azd env set AZURE_RESOURCE_GROUP_NAME failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_AI_PROJECT_ID" -Command { azd env set AZURE_AI_PROJECT_ID $ProjectId --no-prompt } -ErrorMessage "azd env set AZURE_AI_PROJECT_ID failed for $Name"
        Invoke-AzdStep -Description "Setting FOUNDRY_PROJECT_ID" -Command { azd env set FOUNDRY_PROJECT_ID $ProjectId --no-prompt } -ErrorMessage "azd env set FOUNDRY_PROJECT_ID failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_AI_PROJECT_ENDPOINT" -Command { azd env set AZURE_AI_PROJECT_ENDPOINT $ProjectEndpoint --no-prompt } -ErrorMessage "azd env set AZURE_AI_PROJECT_ENDPOINT failed for $Name"
        Invoke-AzdStep -Description "Setting FOUNDRY_PROJECT_ENDPOINT" -Command { azd env set FOUNDRY_PROJECT_ENDPOINT $ProjectEndpoint --no-prompt } -ErrorMessage "azd env set FOUNDRY_PROJECT_ENDPOINT failed for $Name"
        Invoke-AzdStep -Description "Setting AGENTHUB_MODEL_DEPLOYMENT" -Command { azd env set AGENTHUB_MODEL_DEPLOYMENT $ModelDeployment --no-prompt } -ErrorMessage "azd env set AGENTHUB_MODEL_DEPLOYMENT failed for $Name"
        Invoke-AzdStep -Description "Setting DEFAULT_MODEL_DEPLOYMENT" -Command { azd env set DEFAULT_MODEL_DEPLOYMENT $ModelDeployment --no-prompt } -ErrorMessage "azd env set DEFAULT_MODEL_DEPLOYMENT failed for $Name"
        Invoke-AzdStep -Description "Setting AZURE_CONTAINER_REGISTRY_ENDPOINT" -Command { azd env set AZURE_CONTAINER_REGISTRY_ENDPOINT $ContainerRegistryEndpoint --no-prompt } -ErrorMessage "azd env set AZURE_CONTAINER_REGISTRY_ENDPOINT failed for $Name"

        Write-Host "[$(Get-Date -Format o)] Starting azd deploy for '$Name'..." -ForegroundColor Cyan
        azd deploy --no-prompt 2>&1 | Tee-Object -FilePath $deployLog
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n--- Last 30 lines from $deployLog ---" -ForegroundColor Yellow
            Get-Content -Path $deployLog -Tail 30 | ForEach-Object { Write-Host $_ }
            $deployLogText = Get-Content -Path $deployLog -Raw
            if ($deployLogText -match "AzureDeveloperCLICredential") {
                throw "azd deploy failed for $Name (log: $deployLog). Authentication failure from AzureDeveloperCLICredential. Ensure Azure CLI is logged in ('az login' and 'az account set --subscription $SubscriptionId'), or run 'azd auth login --use-device-code'."
            }
            throw "azd deploy failed for $Name (log: $deployLog)"
        }
        Invoke-AzdStep -Description "Fetching deployed agent details" -Command { azd ai agent show --output table --no-prompt } -ErrorMessage "azd ai agent show failed for $Name"
        Write-Host "Deploy log: $deployLog" -ForegroundColor DarkGray
    }
    finally {
        Pop-Location
    }
}
azd version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Azure Developer CLI (azd) is required. Install azd and try again."
}
azd ext install azure.ai.agents | Out-Null
azd ext upgrade azure.ai.agents | Out-Null
Initialize-AzdAuthentication
$repoRoot = Resolve-Path $PSScriptRoot
if (-not $SubscriptionId) {
    $SubscriptionId = (Read-Host "Enter target Azure subscription ID or name").Trim()
}
if (-not $ResourceGroup) {
    $ResourceGroup = (Read-Host "Enter target Azure resource group name").Trim()
}
if (-not $ProjectId) {
    $ProjectId = (Read-Host "Enter Azure AI Project resource ID (AZURE_AI_PROJECT_ID)").Trim()
}
if (-not $ProjectEndpoint) {
    $ProjectEndpoint = (Read-Host "Enter Azure AI Project endpoint URL (AZURE_AI_PROJECT_ENDPOINT)").Trim()
}
if (-not $ContainerRegistryEndpoint) {
    $ContainerRegistryEndpoint = (Read-Host "Enter Azure Container Registry endpoint (e.g. myregistry.azurecr.io)").Trim()
}
if (-not $SubscriptionId) {
    throw "A target Azure subscription is required."
}
if (-not $ResourceGroup) {
    throw "A target Azure resource group is required."
}
if (-not $ProjectId) {
    throw "An Azure AI project resource ID is required (AZURE_AI_PROJECT_ID)."
}
if (-not $ProjectEndpoint) {
    throw "An Azure AI project endpoint is required (AZURE_AI_PROJECT_ENDPOINT)."
}
if (-not $ContainerRegistryEndpoint) {
    throw "An Azure Container Registry endpoint is required (AZURE_CONTAINER_REGISTRY_ENDPOINT)."
}
if (-not $AgentFolders -or $AgentFolders.Count -eq 0) {
    $rawAgentFolders = (Read-Host "Enter agent folders to deploy (comma-separated, e.g. hub,card,account)").Trim()
    if (-not $rawAgentFolders) {
        throw "At least one agent folder is required."
    }
    $AgentFolders = $rawAgentFolders.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
# Backward-compatible parsing: if a token in AgentFolders is not a folder,
# treat it as subscription when -SubscriptionId was not explicitly provided.
$normalizedAgentFolders = @()
foreach ($token in $AgentFolders) {
    $candidate = $token.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        continue
    }
    $candidatePath = Join-Path $repoRoot $candidate
    if (Test-Path $candidatePath -PathType Container) {
        $normalizedAgentFolders += $candidate
        continue
    }
    if (-not $SubscriptionId) {
        $SubscriptionId = $candidate
        continue
    }
    throw "Agent folder '$candidate' not found at '$candidatePath'."
}
$AgentFolders = $normalizedAgentFolders
if (-not $SubscriptionId) {
    $SubscriptionId = (Read-Host "Enter target Azure subscription ID or name").Trim()
}
if (-not $SubscriptionId) {
    throw "A target Azure subscription is required."
}
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set Azure subscription '$SubscriptionId'."
}
if (-not $TenantId) {
    $TenantId = (az account show --query tenantId -o tsv).Trim()
}
Write-Host "Using Foundry-managed Application Insights reserved keyword: APPLICATIONINSIGHTS_CONNECTION_STRING" -ForegroundColor DarkGray
if (-not $TenantId) {
    $TenantId = (Read-Host "Enter target Azure tenant ID").Trim()
    Write-Host "`nTenant ID: $TenantId" -ForegroundColor Green
}
if (-not $TenantId) {
    throw "A target Azure tenant ID is required (AZURE_TENANT_ID)."
}
foreach ($folder in $AgentFolders) {
    $agentFolder = $folder.Trim()
    Write-Host "`nAgent folder: $agentFolder" -ForegroundColor Green
    if ([string]::IsNullOrWhiteSpace($agentFolder)) {
        continue
    }
    $agentPath = Join-Path $repoRoot $agentFolder
    Write-Host "`nAgent Path: $agentPath" -ForegroundColor Green
    if (-not (Test-Path $agentPath -PathType Container)) {
        throw "Agent folder '$agentFolder' not found at '$agentPath'."
    }
    $services += @{ Name = "$agentFolder-agent"; Path = $agentPath }
    Write-Host "`nAgent Services: $($services | Out-String)" -ForegroundColor Green
    Write-Host "`nInvoking azdDeploy for service '$("$agentFolder-agent")' from path '$agentPath' -SubscriptionId $SubscriptionId -TenantId $TenantId -ResourceGroup $ResourceGroup -ProjectId $ProjectId -ProjectEndpoint $ProjectEndpoint -ContainerRegistryEndpoint $ContainerRegistryEndpoint -ModelDeployment $ModelDeployment" -ForegroundColor Green
    Invoke-AzdDeploy -Path $agentPath -Name "$agentFolder-agent" -SubscriptionId $SubscriptionId -TenantId $TenantId -ResourceGroup $ResourceGroup -ProjectId $ProjectId -ProjectEndpoint $ProjectEndpoint -ContainerRegistryEndpoint $ContainerRegistryEndpoint -ModelDeployment $ModelDeployment
}
