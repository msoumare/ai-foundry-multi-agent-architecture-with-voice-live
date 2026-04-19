# Configure Azure DNS Private Resolver for P2S VPN Client
#
# This script sets the DNS server for the Azure VPN connection to use the Azure DNS Private Resolver.
# Run this script on your Windows client AFTER connecting to the P2S VPN.
#
# Usage:
#   .\set-p2s-dns.ps1 -DnsIp "10.1.6.4" -ConnectionName "agenthubspoke-prd"
#
# Parameters:
#   -DnsIp: IP address of the Azure DNS Private Resolver inbound endpoint (e.g., 10.1.6.4 for prd-ne)
#   -ConnectionName: Name of the VPN connection in Windows (appears in Settings > Network > VPN)

param(
    [Parameter(Mandatory = $true)]
    [string]$DnsIp,

    [Parameter(Mandatory = $true)]
    [string]$ConnectionName
)

$ErrorActionPreference = "Stop"

Write-Host "Setting DNS for P2S VPN connection: $ConnectionName" -ForegroundColor Green
Write-Host "DNS Server IP: $DnsIp" -ForegroundColor Cyan

# Configure the VPN adapter to use the specified DNS server
try {
    # Get the network adapter for the VPN connection
    $vpnAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$ConnectionName*" }
    
    if (-not $vpnAdapter) {
        Write-Host "Error: VPN adapter not found for connection '$ConnectionName'" -ForegroundColor Red
        Write-Host "Available adapters:" -ForegroundColor Yellow
        Get-NetAdapter | Select-Object Name, InterfaceDescription | Format-Table
        exit 1
    }

    Write-Host "Found VPN adapter: $($vpnAdapter.Name)" -ForegroundColor Green
    
    # Set the DNS server for this adapter
    Set-DnsClientServerAddress -InterfaceIndex $vpnAdapter.InterfaceIndex -ServerAddresses $DnsIp -Confirm:$false
    
    # Verify the configuration
    $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $vpnAdapter.InterfaceIndex
    Write-Host "DNS configuration applied:" -ForegroundColor Green
    Write-Host "  Interface: $($dnsConfig.InterfaceAlias)" -ForegroundColor Cyan
    Write-Host "  DNS Servers: $($dnsConfig.ServerAddresses -join ', ')" -ForegroundColor Cyan
    
    # Test resolution of a known private endpoint
    Write-Host "`nTesting DNS resolution..." -ForegroundColor Green
    $testResult = Resolve-DnsName -Name "akv-agenthubspoke-prd-ne.vault.azure.net" -ErrorAction SilentlyContinue
    
    if ($testResult) {
        Write-Host "✓ Successfully resolved private endpoint FQDN" -ForegroundColor Green
        Write-Host "  FQDN: akv-agenthubspoke-prd-ne.vault.azure.net" -ForegroundColor Cyan
        Write-Host "  IP Address: $($testResult.IPAddress)" -ForegroundColor Cyan
        
        if ($testResult.IPAddress -match "^10\.|^172\.|^192\.168\.") {
            Write-Host "✓ Resolved to private IP address (correct!)" -ForegroundColor Green
        } else {
            Write-Host "⚠ Warning: Resolved to public IP address" -ForegroundColor Yellow
            Write-Host "  Ensure your VPN is connected and no local DNS is overriding this." -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠ DNS resolution test failed (expected if VPN not yet connected)" -ForegroundColor Yellow
        Write-Host "  Ensure you are connected to the P2S VPN before running this script." -ForegroundColor Yellow
    }
    
    Write-Host "`n✓ DNS configuration completed successfully." -ForegroundColor Green

} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
