# Offline subprocess harness. The production entrypoints and target/token helpers
# are copied verbatim; only cloud IO and the independent locked installer are stubs.
param(
  [Parameter(Mandatory)][string]$FixtureRoot,
  [Parameter(Mandatory)][string]$WorkRoot,
  [Parameter(Mandatory)][ValidateSet('Deploy', 'Setup', 'PreUp', 'Validation')][string]$EntryPoint,
  [Parameter(Mandatory)][string]$Scenario
)
$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'
$env:TEMP = $WorkRoot
$env:TARGET_GUARD_WORK_ROOT = $WorkRoot
$env:TARGET_GUARD_SCENARIO = $Scenario
$global:TargetGuardScenario = $Scenario
$global:TargetGuardMetadataReads = 0
$global:TargetGuardEntryPoint = $EntryPoint
$global:TargetGuardSubscription = '11111111-1111-4111-8111-111111111111'
$global:TargetGuardTenant = '22222222-2222-4222-8222-222222222222'
$global:TargetGuardOther = '33333333-3333-4333-8333-333333333333'
$global:TargetGuardPrincipal = '44444444-4444-4444-8444-444444444444'
foreach ($name in @('AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'AZURE_ENV_NAME', 'AZURE_RESOURCE_GROUP',
    'INCLUDE_EXCHANGE', 'INCLUDE_TEAMS', 'INCLUDE_AZURE', 'MAIL_RECIPIENT', 'AZURE_RBAC_SCOPES',
    'SECURITY_GROUP_OBJECT_ID', 'EASY_AUTH_SECURITY_GROUP_OBJECT_ID', 'SECURITY_GROUP_DISPLAY_NAME')) {
  [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
function global:Write-TargetGuardEvent {
  param([string]$Kind, $Data)
  @{ kind = $Kind; data = $Data } | ConvertTo-Json -Depth 10 -Compress |
    Add-Content -LiteralPath (Join-Path $env:TARGET_GUARD_WORK_ROOT 'events.jsonl')
}
function global:az {
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'rest' -and $args -contains '--subscription') {
    Write-TargetGuardEvent 'metadata' @($args)
    $global:TargetGuardMetadataReads++
    $subIndex = [Array]::IndexOf($args, '--subscription')
    $urlIndex = [Array]::IndexOf($args, '--url')
    if ($args[$subIndex + 1] -ne $global:TargetGuardSubscription -or
        $args[$urlIndex + 1] -ne "https://management.azure.com/subscriptions/$global:TargetGuardSubscription`?api-version=2022-12-01") {
      throw 'Metadata request did not explicitly target the selected subscription.'
    }
    if ($global:TargetGuardScenario -eq 'query-failure') { $global:LASTEXITCODE = 17; return '' }
    $metadata = @{
      id = "/subscriptions/$global:TargetGuardSubscription"
      subscriptionId = $global:TargetGuardSubscription
      tenantId = $global:TargetGuardTenant
      displayName = 'Explicit target, different from the CLI default'
      state = 'Enabled'
    }
    switch ($global:TargetGuardScenario) {
      'wrong-tenant' { $metadata.tenantId = $global:TargetGuardOther }
      'wrong-subscription' { $metadata.subscriptionId = $global:TargetGuardOther; $metadata.id = "/subscriptions/$global:TargetGuardOther" }
      'stale-enabled' { $metadata.state = 'Disabled' }
      'missing-state' { $metadata.Remove('state') }
      'change-before-exchange' { if ($global:TargetGuardMetadataReads -gt 1) { $metadata.state = 'Disabled' } }
      'change-before-apply' { if ($global:TargetGuardMetadataReads -gt 2) { $metadata.state = 'Disabled' } }
      'change-before-trigger' { if ($global:TargetGuardMetadataReads -gt 1) { $metadata.state = 'Disabled' } }
      'change-during-packaging' {
        if (Test-Path (Join-Path $env:TARGET_GUARD_WORK_ROOT 'packaged')) { $metadata.state = 'Disabled' }
      }
    }
    return ($metadata | ConvertTo-Json -Compress)
  }
  if ($args[0] -eq 'account' -and $args[1] -in @('list', 'show')) {
    # Deliberately stale and not the selected target. This is not authority.
    Write-TargetGuardEvent 'cached-account' @($args)
    $account = @{ id = $global:TargetGuardOther; tenantId = $global:TargetGuardOther; name = 'Wrong default'; state = 'Enabled'; isDefault = $true }
    if ($args[1] -eq 'list') {
      return (ConvertTo-Json -InputObject @($account, @{ id = $global:TargetGuardSubscription; tenantId = $global:TargetGuardTenant; state = 'Enabled'; isDefault = $false }) -Compress)
    }
    return ($account | ConvertTo-Json -Compress)
  }
  if ($args[0] -eq 'account' -and $args[1] -eq 'get-access-token') {
    Write-TargetGuardEvent 'token' @($args)
    if ($args -contains 'https://outlook.office365.com') {
      $tenant = if ($global:TargetGuardScenario -like 'wrong-exchange-token*') { $global:TargetGuardOther } else { $global:TargetGuardTenant }
      return (@{ accessToken = 'offline-exchange-token'; tenant = $tenant } | ConvertTo-Json -Compress)
    }
    return 'offline-arm-token'
  }
  if ($args[0] -eq 'group' -and $args[1] -eq 'exists') {
    Write-TargetGuardEvent 'group-exists' @($args)
    return 'false'
  }
  if ($args[0] -eq 'group' -and $args[1] -eq 'create') {
    Write-TargetGuardEvent 'group-create' @($args)
    return '{}'
  }
  Write-TargetGuardEvent 'unexpected-az' @($args)
  throw "Unexpected Azure CLI call was blocked: $args"
}
function global:azd {
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'env' -and $args[1] -eq 'get-values') {
    return (@{
      AZURE_ENV_NAME = 'guard-test'; AZURE_SUBSCRIPTION_ID = $global:TargetGuardSubscription
      AZURE_TENANT_ID = $global:TargetGuardTenant; AZURE_RESOURCE_GROUP = 'rg-test'; AZURE_LOCATION = 'westus2'
      STORAGE_ACCOUNT_NAME = 'sttest'; WEB_APP_ENABLED = 'false'
      functionAppName = 'func-test'; functionAppPrincipalId = $global:TargetGuardPrincipal
    } | ConvertTo-Json -Compress)
  }
  if ($args[0] -eq 'env' -and $args[1] -eq 'set') {
    Write-TargetGuardEvent 'environment-write' @($args)
    return
  }
  throw "Unexpected azd call was blocked: $args"
}
function global:Invoke-RestMethod {
  param($Method, $Uri, $Headers, $Body, $ContentType, $ErrorAction)
  Write-TargetGuardEvent 'http' @{ method = [string]$Method; uri = [string]$Uri }
  if ($global:TargetGuardEntryPoint -eq 'Validation' -and $global:TargetGuardScenario -eq 'change-before-trigger' -and $Method -eq 'POST' -and $Uri -like '*/host/default/listkeys?*') {
    return @{ masterKey = 'offline-function-key' }
  }
  if (($global:TargetGuardEntryPoint -ne 'Setup' -and $global:TargetGuardScenario -ne 'change-before-trigger') -or $Method -ne 'GET') { throw 'Unexpected HTTP operation was blocked.' }
  $scope = "/subscriptions/$global:TargetGuardSubscription/resourceGroups/rg-test"
  $tags = @{ workload = 'maester'; solution = 'function-app'; environment = 'guard-test'; managedBy = 'azd' }
  if ($Uri -like "https://management.azure.com$scope/providers/Microsoft.Storage/storageAccounts/sttest?*") {
    return [pscustomobject]@{ id = "$scope/providers/Microsoft.Storage/storageAccounts/sttest"; name = 'sttest'; type = 'Microsoft.Storage/storageAccounts'; tags = $tags }
  }
  if ($Uri -like "https://management.azure.com$scope/providers/Microsoft.Web/sites/func-test?*") {
    return [pscustomobject]@{ id = "$scope/providers/Microsoft.Web/sites/func-test"; name = 'func-test'; type = 'Microsoft.Web/sites'; kind = 'functionapp,linux'; tags = $tags; identity = @{ type = 'SystemAssigned'; principalId = $global:TargetGuardPrincipal } }
  }
  throw "Unexpected REST request was blocked: $Method $Uri"
}
function global:Invoke-WebRequest {
  param($Method, $Uri, $Headers, $Body, $OutFile, [switch]$UseBasicParsing, $ErrorAction)
  if ($global:TargetGuardScenario -eq 'change-before-trigger' -and $Method -eq 'HEAD') {
    Write-TargetGuardEvent 'receipt-check' @{ method = $Method; uri = $Uri }
    $errorValue = [Exception]::new('Offline 404 for unused receipt')
    $errorValue | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{ StatusCode = 404 })
    throw $errorValue
  }
  Write-TargetGuardEvent 'download-or-http-write' $PSBoundParameters
  throw 'Network download or request was blocked.'
}
function global:Install-Module { Write-TargetGuardEvent 'module-download' @($args); throw 'Module installation was blocked.' }
function global:Save-Module { Write-TargetGuardEvent 'module-download' @($args); throw 'Module download was blocked.' }
function global:Connect-ExchangeOnline {
  param($AccessToken, [bool]$ShowBanner, $Organization)
  Write-TargetGuardEvent 'exchange-connect' $PSBoundParameters
}
function global:New-ServicePrincipal {
  param($AppId, $ObjectId, $DisplayName)
  Write-TargetGuardEvent 'exchange-service-principal' $PSBoundParameters
}
function global:New-ManagementRoleAssignment {
  param($Role, $App, $ErrorAction)
  Write-TargetGuardEvent 'exchange-rbac' $PSBoundParameters
  return @{ Identity = 'offline-role' }
}
# Retain the real guard, token helper and Exchange connection helper. Replace
# only the separate Graph IO/role and module-availability functions for Setup.
function global:Import-Module {
  param($Name, [switch]$Force)
  $module = Microsoft.PowerShell.Core\Import-Module -Name $Name -Force:$Force -Global -PassThru
  if ($global:TargetGuardEntryPoint -eq 'Setup' -and $Name -like '*Maester-SetupConsent.psm1') {
    function global:Get-MaesterSetupAccessPlan {
      param($TenantId, $SubscriptionId, $PrincipalObjectId, $ResourceId, $StorageAccount, $WebApp, $ArmHeaders, $SecurityGroupObjectId, $SecurityGroupDisplayName, $PermissionProfile, $IncludeMailSend, $IncludeReportSettingsWrite, $IncludeExchange, $IncludeTeams, $IncludeAzure, $AzureScopes)
      Write-TargetGuardEvent 'access-plan' $PSBoundParameters
      [pscustomobject]@{ capability = 'DeploymentSetupAccess'; planHash = ('a' * 64) }
    }
    function global:Invoke-MaesterSetupAccessPlan {
      param($PlanParameters, $ApprovedPlanHash)
      if ($ApprovedPlanHash -cne ('a' * 64)) { throw 'Fixture approval did not match.' }
      foreach ($kind in @('graph-permissions', 'exchange-app-role', 'exchange-service-principal', 'exchange-rbac')) {
        Write-TargetGuardEvent $kind $PlanParameters
      }
      [pscustomobject]@{ Receipts = @{ EXO_APPROLE_ASSIGNMENT_IDS = @('offline-app-role'); TEAMS_READER_ROLE_ASSIGNMENT_IDS = @(); AZURE_ROLE_ASSIGNMENT_IDS = @() }; EasyAuth = $null; PrincipalDisplayName = 'Offline identity' }
    }
  }
  if ($global:TargetGuardEntryPoint -eq 'Setup' -and $Name -like '*Maester-SetupHelpers.psm1') {
    function global:Invoke-GraphRestRequest {
      param($Method, $Uri, $TenantId)
      if ($Method -eq 'GET' -and $Uri -like '*organization?*') { return @{ value = @(@{ verifiedDomains = @(@{ isInitial = $true; name = 'guard-test.onmicrosoft.com' }) }) } }
      throw "Unexpected Graph request was blocked: $Method $Uri"
    }
    function global:Assert-GraphAccess {
      param($TenantId, $ClientId, $ExpectedAccount, $Scopes, $AllowInteractive, $AllowContextReplacement)
      Write-TargetGuardEvent 'graph-connect' @{ tenant = $TenantId; client = $ClientId; account = $ExpectedAccount; scopes = $Scopes }
    }
    function global:Get-MaesterSetupScopes { param([switch]$IncludeTeams, [switch]$IncludeWebApp); @('Application.Read.All', 'AppRoleAssignment.ReadWrite.All') }
    function global:Connect-MgGraphSilent {
      param($TenantId, $Scopes)
      Write-TargetGuardEvent 'graph-connect' @{ tenant = $TenantId }
    }
    function global:Invoke-MgGraphRequest {
      param($Method, $Uri)
      if ($Method -ne 'GET') { throw 'Graph mutation was blocked.' }
      if ($Uri -like '*servicePrincipals/*') { return @{ id = $global:TargetGuardPrincipal; appId = '55555555-5555-4555-8555-555555555555'; displayName = 'Offline identity' } }
      if ($Uri -like '*organization?*') { return @{ value = @(@{ verifiedDomains = @(@{ isInitial = $true; name = 'guard-test.onmicrosoft.com' }) }) } }
      throw "Unexpected Graph request was blocked: $Uri"
    }
    function global:Test-ModuleAvailable { param($ModuleName, $InstallMessage); return $true }
    function global:Grant-ServicePrincipalAppRoleAssignment {
      param($PrincipalObjectId, $ResourceAppId, $AppRoleId)
      Write-TargetGuardEvent 'exchange-app-role' $PSBoundParameters
      return 'offline-app-role'
    }
    function global:Resolve-StepFailureAction {
      param($StepName, $Message)
      Write-TargetGuardEvent 'step-failure' @{ step = $StepName; message = $Message }
      if ($global:TargetGuardScenario -eq 'wrong-exchange-token-skip') { return 'Skip' }
      return 'Stop'
    }
  }
}
function global:Get-Module {
  param($Name, [switch]$ListAvailable)
  if ($Name -eq 'ExchangeOnlineManagement' -and $ListAvailable) { return [pscustomobject]@{ Name = $Name; Version = [version]'3.10.1' } }
  Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
}
$env:MAESTER_SETUP_CLIENT_ID = '66666666-6666-4666-8666-666666666666'
$env:MAESTER_SETUP_ACCOUNT = 'operator@example.test'
$invoke = @{
  SubscriptionId = $global:TargetGuardSubscription
  ResourceGroupName = 'rg-test'
}
if ($Scenario -eq 'environment-tenant') { $env:AZURE_TENANT_ID = $global:TargetGuardTenant }
elseif ($Scenario -notin @('missing-tenant', 'blank-tenant')) { $invoke.TenantId = $global:TargetGuardTenant }
elseif ($Scenario -eq 'blank-tenant') { $invoke.TenantId = ' ' }
try {
  switch ($EntryPoint) {
    'Deploy' {
      & (Join-Path $FixtureRoot 'scripts/Deploy-FunctionCode.ps1') @invoke -FunctionAppName 'func-test' -Plan B1 -DeploymentTimeoutSeconds 10
    }
    'Setup' {
      if ($Scenario -ne 'plan-only') { $invoke.Apply = $true; $invoke.ApprovedPlanHash = 'a' * 64 }
      & (Join-Path $FixtureRoot 'scripts/Setup-PostDeploy.ps1') @invoke -EnvironmentName 'guard-test' -IncludeExchange -Plan B1
    }
    'PreUp' {
      & (Join-Path $FixtureRoot 'scripts/Run-AzdPreUp.ps1')
    }
    'Validation' {
      & (Join-Path $FixtureRoot 'scripts/Invoke-FunctionValidation.ps1') @invoke -FunctionAppName 'func-test' -StorageAccountName 'sttest' -TimeoutMinutes 1
    }
  }
  exit 0
}
catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
