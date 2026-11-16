#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$previewRuleName = 'DopaDash-iPhonePreview-7359'

if ($Remove) {
    if ($PSCmdlet.ShouldProcess($previewRuleName, 'Rimuovi la regola di anteprima iPhone')) {
        Get-NetFirewallRule -Name $previewRuleName -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule
    }
    return
}

$previewNode = (Get-Command node -ErrorAction Stop).Source
$previewWifi = Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 |
    Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1
if (-not $previewWifi) { throw 'Connettere prima il PC alla stessa Wi-Fi del telefono.' }

# This rule is limited to this executable, Wi-Fi address, TCP port and local subnet.
# It does not change the network profile, VPN or any other firewall rule.
$previewRule = @{
    Name = $previewRuleName
    DisplayName = 'DopaDash - anteprima iPhone (Wi-Fi, porta 7359)'
    Description = 'Consente al solo server locale di ricevere connessioni dalla sottorete Wi-Fi sulla porta TCP 7359.'
    Direction = 'Inbound'
    Action = 'Allow'
    Enabled = 'True'
    Profile = @('Private', 'Public')
    Program = $previewNode
    Protocol = 'TCP'
    LocalPort = 7359
    LocalAddress = $previewWifi.IPAddress
    RemoteAddress = 'LocalSubnet'
    InterfaceAlias = 'Wi-Fi'
    EdgeTraversalPolicy = 'Block'
}
if ($PSCmdlet.ShouldProcess("$($previewWifi.IPAddress):7359", 'Consenti anteprima iPhone dalla sottorete Wi-Fi')) {
    if (Get-NetFirewallRule -Name $previewRuleName -ErrorAction SilentlyContinue) {
        Set-NetFirewallRule @previewRule | Out-Null
    } else {
        New-NetFirewallRule @previewRule | Out-Null
    }
    Write-Host "Anteprima iPhone: http://$($previewWifi.IPAddress):7359"
}
