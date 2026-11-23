# Installs edge-lighting hooks for GitHub Copilot CLI (user-level, applies to every repo).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File copilot\install.ps1 [-Uninstall]
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE '.copilot' }
$target = Join-Path $copilotHome 'hooks\edge-lighting.json'
if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Force; Write-Host "Removed $target" } else { Write-Host 'Nothing to remove.' }
    return
}
$scripts = (Resolve-Path (Join-Path $PSScriptRoot '..\plugins\edge-lighting\scripts')).Path.Replace([string][char]92, '/')
$template = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'edge-lighting.hooks.json')
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
$json = $template.Replace('__SCRIPTS__', $scripts)
[System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Installed: $target"
Write-Host 'Restart Copilot CLI. Keep this repo folder in place (the hooks point at it).'
