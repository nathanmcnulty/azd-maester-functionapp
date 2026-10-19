#Requires -Version 7.6
BeforeAll {
  $root = Split-Path $PSScriptRoot -Parent
  $fixture = Join-Path $TestDrive 'wrapper-fixture'
  $scripts = Join-Path $fixture 'scripts'
  $null = New-Item -ItemType Directory -Path $scripts
  foreach ($name in 'Run-AzdPostProvision.ps1','Resolve-DeploymentTargets.ps1') {
    Copy-Item (Join-Path $root "scripts/$name") $scripts
  }
  Copy-Item (Join-Path $root 'scripts/vendor') $scripts -Recurse
  @'
param($SubscriptionId, $TenantId, $EnvironmentName, $ResourceGroupName, $PermissionProfile)
if ($env:WRAPPER_TEST_MODE -eq 'plan') {
  return [pscustomobject]@{ capability = 'DeploymentSetupAccess'; planHash = ('a' * 64) }
}
# Exercise the real helper lifecycle that independent ZIP deployment uses.
$helper = Join-Path $PSScriptRoot 'vendor/Azd.MaesterHooks/Maester-SetupHelpers.psm1'
$module = Get-Module Maester-SetupHelpers
& $module { $script:MaesterGraphSession = @{ TenantId = [guid]'22222222-2222-4222-8222-222222222222' } }
Import-Module $helper -Force
if (Test-MaesterGraphSession -TenantId $TenantId) { throw 'Fixture expected the ZIP helper reload to clear its session.' }
Write-Host 'OFFLINE_ZIP_HELPER_RELOADED'
'@ | Set-Content (Join-Path $scripts 'Setup-PostDeploy.ps1')
  @'
param($SubscriptionId, $TenantId, $ResourceGroupName, $FunctionAppName, $StorageAccountName, $TimeoutMinutes, [switch]$PassThru)
Write-Host 'OFFLINE_NATIVE_VALIDATION_REQUESTED'
[pscustomobject]@{ ValidationPassed = $false; ExecutionComplete = $false; FunctionAppName = $FunctionAppName; FinalStatus = 'fixture failure'; CompletedAt = '2026-10-19T00:00:00Z' }
'@ | Set-Content (Join-Path $scripts 'Invoke-FunctionValidation.ps1')
  $harness = @'
param([string]$FixtureRoot, [string]$Mode)
$ErrorActionPreference = 'Stop'
$env:WRAPPER_TEST_MODE = $Mode
$env:VALIDATE_FUNCTION_ON_PROVISION = 'true'
$env:AZURE_ENV_NAME = 'wrapper-test'
$env:AZURE_SUBSCRIPTION_ID = '11111111-1111-4111-8111-111111111111'
$env:AZURE_TENANT_ID = '22222222-2222-4222-8222-222222222222'
$env:AZURE_RESOURCE_GROUP = 'rg-test'
function global:az {
  if ($Mode -eq 'plan') { throw 'Plan-only wrapper must stop before Azure calls.' }
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'account' -and $args[1] -eq 'get-access-token') { return 'offline-token' }
  throw 'Unexpected Azure CLI call.'
}
function global:azd {
  if ($Mode -eq 'plan') { throw 'Plan-only wrapper must stop before environment reads.' }
  $global:LASTEXITCODE = 0
  if ($args[0] -ne 'env' -or $args[1] -ne 'get-values') { throw 'Unexpected azd call.' }
  @{
    AZURE_ENV_NAME = 'wrapper-test'; AZURE_SUBSCRIPTION_ID = $env:AZURE_SUBSCRIPTION_ID
    AZURE_TENANT_ID = $env:AZURE_TENANT_ID; AZURE_RESOURCE_GROUP = 'rg-test'
    STORAGE_ACCOUNT_NAME = 'sttest'; WEB_APP_ENABLED = 'false'
    functionAppName = 'func-test'; functionAppPrincipalId = '44444444-4444-4444-8444-444444444444'
    FUNCTION_APP_NAME = 'func-test'; FUNCTION_APP_MI_PRINCIPAL_ID = '44444444-4444-4444-8444-444444444444'
    INCLUDE_EXCHANGE = 'true'; INCLUDE_TEAMS = 'true'; SETUP_EXCHANGE_STATUS = 'configured'; SETUP_TEAMS_STATUS = 'configured'
  } | ConvertTo-Json -Compress
}
function global:Start-Sleep { throw 'No obsolete permission-poll delay is allowed.' }
function global:Connect-MgGraph { throw 'Post-ZIP Graph reconnection is forbidden.' }
function global:Invoke-MgGraphRequest { throw 'Post-ZIP Graph polling is forbidden.' }
function global:Invoke-RestMethod {
  param($Method, $Uri, $Headers)
  if ($Method -ne 'GET') { throw 'Remote write is forbidden.' }
  $scope = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/rg-test"
  $tags = @{ workload = 'maester'; solution = 'function-app'; environment = 'wrapper-test'; managedBy = 'azd' }
  if ($Uri -like "https://management.azure.com$scope/providers/Microsoft.Storage/storageAccounts/sttest?*") {
    return [pscustomobject]@{ id = "$scope/providers/Microsoft.Storage/storageAccounts/sttest"; name = 'sttest'; type = 'Microsoft.Storage/storageAccounts'; tags = $tags }
  }
  if ($Uri -like "https://management.azure.com$scope/providers/Microsoft.Web/sites/func-test?*") {
    return [pscustomobject]@{ id = "$scope/providers/Microsoft.Web/sites/func-test"; name = 'func-test'; type = 'Microsoft.Web/sites'; kind = 'functionapp,linux'; tags = $tags; identity = @{ type = 'SystemAssigned'; principalId = '44444444-4444-4444-8444-444444444444' }; properties = @{ serverFarmId = "$scope/providers/Microsoft.Web/serverfarms/plan-test" } }
  }
  if ($Uri -like "https://management.azure.com$scope/providers/Microsoft.Web/serverfarms/plan-test?*") {
    return [pscustomobject]@{ id = "$scope/providers/Microsoft.Web/serverfarms/plan-test"; name = 'plan-test'; type = 'Microsoft.Web/serverfarms' }
  }
  throw "Unexpected REST request: $Uri"
}
& (Join-Path $FixtureRoot 'scripts/Run-AzdPostProvision.ps1') -EnvironmentName 'wrapper-test' -SubscriptionId $env:AZURE_SUBSCRIPTION_ID -TenantId $env:AZURE_TENANT_ID -ResourceGroupName 'rg-test'
'@
  $harnessPath = Join-Path $TestDrive 'wrapper-harness.ps1'
  $harness | Set-Content $harnessPath
}
Describe 'Actual Function postprovision wrapper after reviewed setup' {
  It 'does not poll or reconnect after the ZIP helper reset and keeps native failure visible' {
    $output = & (Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })) -NoProfile -NonInteractive -File $harnessPath -FixtureRoot $fixture -Mode applied 2>&1
    $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    ($output -join "`n") | Should -Match 'OFFLINE_ZIP_HELPER_RELOADED'
    ($output -join "`n") | Should -Match 'Permission propagation and effective workload access are unverified'
    ($output -join "`n") | Should -Match 'OFFLINE_NATIVE_VALIDATION_REQUESTED'
    ($output -join "`n") | Should -Not -Match 'assignments confirmed|Permission verification timed out'
    $summary = Get-Content (Join-Path $fixture 'outputs/wrapper-test-setup-summary.md') -Raw
    $summary | Should -Match 'Function validation status: Failed'
    $summary | Should -Match 'fixture failure'
  }
  It 'returns the plan without polling, summary reads or native validation' {
    $output = & (Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })) -NoProfile -NonInteractive -File $harnessPath -FixtureRoot $fixture -Mode plan 2>&1
    $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    ($output -join "`n") | Should -Match 'DeploymentSetupAccess'
    ($output -join "`n") | Should -Not -Match 'OFFLINE_NATIVE_VALIDATION_REQUESTED|OFFLINE_ZIP_HELPER_RELOADED'
  }
}
