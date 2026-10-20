#Requires -Version 7.6
[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'vendor\Azd.MaesterHooks\Maester-PreProvision.psm1') -Force

Invoke-MaesterPreProvision `
  -SolutionName 'function-app' `
  -SubscriptionId $SubscriptionId `
  -TenantId $TenantId `
  -Location $env:AZURE_LOCATION

# Capture infrastructure separately from optional Graph/setup. Only this hook's
# exact HTTP 201 response can establish fresh dedicated resource-group ownership.
Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.MaesterHooks/Maester-InfrastructureOwnership.psm1') -Force
Initialize-MaesterInfrastructureOwnership -ProjectRoot (Split-Path $PSScriptRoot -Parent) `
  -EnvironmentName $env:AZURE_ENV_NAME -SolutionName 'function-app' `
  -TenantId $TenantId -SubscriptionId $SubscriptionId | Out-Null
