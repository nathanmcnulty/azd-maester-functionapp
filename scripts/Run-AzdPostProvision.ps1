#Requires -Version 7.6
[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TenantId,

  [Parameter(Mandatory = $false)]
  [string]$EnvironmentName,

  [Parameter(Mandatory = $false)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $false)]
  [string]$SecurityGroupObjectId,

  [Parameter(Mandatory = $false)]
  [string]$SecurityGroupDisplayName,

  [Parameter(Mandatory = $false)]
  [ValidateSet('Minimal', 'Full', 'Extended')]
  [string]$PermissionProfile = 'Full',
  [switch]$Apply,
  [string]$ApprovedPlanHash,
  [switch]$InteractiveConsent,
  [switch]$AllowInteractiveGraphLogin,
  [switch]$AllowGraphContextReplacement,
  [switch]$IncludeMailSend,
  [switch]$IncludeReportSettingsWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'vendor\Azd.MaesterHooks\Maester-SetupHelpers.psm1') -Force
. (Join-Path $PSScriptRoot 'Resolve-DeploymentTargets.ps1')

function Get-EnvValue {
  param(
    [Parameter(Mandatory = $true)]
    $Lines,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if ($Lines -is [hashtable]) {
    if ($Lines.ContainsKey($Name)) {
      return [string]$Lines[$Name]
    }
    return $null
  }

  foreach ($line in @($Lines)) {
    if ($line -like "$Name=*") {
      return $line.Split('=', 2)[1].Trim('"')
    }
  }

  return $null
}

if (-not $SubscriptionId) {
  $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
}
if (-not $TenantId -and $env:AZURE_TENANT_ID) {
  $TenantId = $env:AZURE_TENANT_ID
}
if (-not $EnvironmentName) {
  $EnvironmentName = if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { 'dev' }
}
if (-not $ResourceGroupName) {
  $ResourceGroupName = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } else { "rg-$EnvironmentName" }
}
if (-not $SecurityGroupObjectId) {
  if ($env:SECURITY_GROUP_OBJECT_ID) {
    $SecurityGroupObjectId = $env:SECURITY_GROUP_OBJECT_ID
  }
  elseif ($env:EASY_AUTH_SECURITY_GROUP_OBJECT_ID) {
    $SecurityGroupObjectId = $env:EASY_AUTH_SECURITY_GROUP_OBJECT_ID
  }
}
if (-not $SecurityGroupDisplayName -and $env:SECURITY_GROUP_DISPLAY_NAME) {
  $SecurityGroupDisplayName = $env:SECURITY_GROUP_DISPLAY_NAME
}
if (-not $PSBoundParameters.ContainsKey('PermissionProfile') -and $env:PERMISSION_PROFILE) {
  $PermissionProfile = $env:PERMISSION_PROFILE
}

# Capture infrastructure ownership before optional setup can be declined or fail.
$ownershipRoot = Split-Path $PSScriptRoot -Parent
$infrastructureReceipt = Join-Path $ownershipRoot ".azure/$EnvironmentName/maester-infrastructure-ownership.json"
if (Test-Path -LiteralPath $infrastructureReceipt) {
  Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.MaesterHooks/Maester-InfrastructureOwnership.psm1') -ErrorAction Stop
  Complete-MaesterInfrastructureOwnership -ProjectRoot $ownershipRoot -EnvironmentName $EnvironmentName -SolutionName 'function-app' `
    -TenantId $TenantId -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
} else {
  Write-Warning 'No fresh infrastructure ownership receipt exists. Existing deployment behavior is preserved; automatic down requires explicit ownership recovery.'
}

Write-Host 'Running postprovision setup...'

$setupParams = @{
  SubscriptionId    = $SubscriptionId
  EnvironmentName   = $EnvironmentName
  ResourceGroupName = $ResourceGroupName
  PermissionProfile = $PermissionProfile
}
if ($TenantId) {
  $setupParams['TenantId'] = $TenantId
}
if ($SecurityGroupObjectId) {
  $setupParams['SecurityGroupObjectId'] = $SecurityGroupObjectId
}
if ($SecurityGroupDisplayName) {
  $setupParams['SecurityGroupDisplayName'] = $SecurityGroupDisplayName
}

foreach ($name in @('Apply', 'ApprovedPlanHash', 'InteractiveConsent', 'AllowInteractiveGraphLogin', 'AllowGraphContextReplacement', 'IncludeMailSend', 'IncludeReportSettingsWrite')) {
  if ($PSBoundParameters.ContainsKey($name)) { $setupParams[$name] = $PSBoundParameters[$name] }
}
$setupResult = & "$PSScriptRoot\Setup-PostDeploy.ps1" @setupParams
if ($setupResult -and $setupResult.PSObject.Properties['capability'] -and $setupResult.capability -eq 'DeploymentSetupAccess') {
  return $setupResult
}

$easyAuthAppObjectId = 'n/a'
$easyAuthAppClientIdFromEnv = 'n/a'
$easyAuthAppDisplayName = 'n/a'
$includeExchangeFromEnv = 'n/a'
$includeTeamsFromEnv = 'n/a'
$includeAzureFromEnv = 'n/a'
$azureScopesFromEnv = 'n/a'
$exchangeSetupStatusFromEnv = 'n/a'
$teamsSetupStatusFromEnv = 'n/a'
$azureSetupStatusFromEnv = 'n/a'
$exoAppRoleAssignmentIdsFromEnv = 'n/a'
$teamsRoleAssignmentIdsFromEnv = 'n/a'
$azureRoleAssignmentIdsFromEnv = 'n/a'
$exoServicePrincipalDisplayNameFromEnv = 'n/a'
$envValues = Get-MaesterDeploymentValues -EnvironmentName $EnvironmentName -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName

if ($envValues.Count -gt 0) {
  $easyAuthAppObjectIdValue = Get-EnvValue -Lines $envValues -Name 'EASY_AUTH_ENTRA_APP_OBJECT_ID'
  $easyAuthAppClientIdValue = Get-EnvValue -Lines $envValues -Name 'EASY_AUTH_ENTRA_APP_CLIENT_ID'
  $easyAuthAppDisplayNameValue = Get-EnvValue -Lines $envValues -Name 'EASY_AUTH_ENTRA_APP_DISPLAY_NAME'

  if (-not [string]::IsNullOrWhiteSpace($easyAuthAppObjectIdValue)) {
    $easyAuthAppObjectId = $easyAuthAppObjectIdValue
  }
  if (-not [string]::IsNullOrWhiteSpace($easyAuthAppClientIdValue)) {
    $easyAuthAppClientIdFromEnv = $easyAuthAppClientIdValue
  }
  if (-not [string]::IsNullOrWhiteSpace($easyAuthAppDisplayNameValue)) {
    $easyAuthAppDisplayName = $easyAuthAppDisplayNameValue
  }

  $includeExchangeValue = Get-EnvValue -Lines $envValues -Name 'INCLUDE_EXCHANGE'
  $includeTeamsValue = Get-EnvValue -Lines $envValues -Name 'INCLUDE_TEAMS'
  $includeAzureValue = Get-EnvValue -Lines $envValues -Name 'INCLUDE_AZURE'
  $azureScopesValue = Get-EnvValue -Lines $envValues -Name 'AZURE_RBAC_SCOPES'
  $exchangeStatusValue = Get-EnvValue -Lines $envValues -Name 'SETUP_EXCHANGE_STATUS'
  $teamsStatusValue = Get-EnvValue -Lines $envValues -Name 'SETUP_TEAMS_STATUS'
  $azureStatusValue = Get-EnvValue -Lines $envValues -Name 'SETUP_AZURE_STATUS'
  $exoAppRoleIdsValue = Get-EnvValue -Lines $envValues -Name 'EXO_APPROLE_ASSIGNMENT_IDS'
  $teamsRoleIdsValue = Get-EnvValue -Lines $envValues -Name 'TEAMS_READER_ROLE_ASSIGNMENT_IDS'
  $azureRoleIdsValue = Get-EnvValue -Lines $envValues -Name 'AZURE_ROLE_ASSIGNMENT_IDS'
  $exoSpDisplayNameValue = Get-EnvValue -Lines $envValues -Name 'EXO_SERVICE_PRINCIPAL_DISPLAY_NAME'

  if (-not [string]::IsNullOrWhiteSpace($includeExchangeValue)) { $includeExchangeFromEnv = $includeExchangeValue }
  if (-not [string]::IsNullOrWhiteSpace($includeTeamsValue)) { $includeTeamsFromEnv = $includeTeamsValue }
  if (-not [string]::IsNullOrWhiteSpace($includeAzureValue)) { $includeAzureFromEnv = $includeAzureValue }
  if (-not [string]::IsNullOrWhiteSpace($azureScopesValue)) { $azureScopesFromEnv = $azureScopesValue }
  if (-not [string]::IsNullOrWhiteSpace($exchangeStatusValue)) { $exchangeSetupStatusFromEnv = $exchangeStatusValue }
  if (-not [string]::IsNullOrWhiteSpace($teamsStatusValue)) { $teamsSetupStatusFromEnv = $teamsStatusValue }
  if (-not [string]::IsNullOrWhiteSpace($azureStatusValue)) { $azureSetupStatusFromEnv = $azureStatusValue }
  if (-not [string]::IsNullOrWhiteSpace($exoAppRoleIdsValue)) { $exoAppRoleAssignmentIdsFromEnv = $exoAppRoleIdsValue }
  if (-not [string]::IsNullOrWhiteSpace($teamsRoleIdsValue)) { $teamsRoleAssignmentIdsFromEnv = $teamsRoleIdsValue }
  if (-not [string]::IsNullOrWhiteSpace($azureRoleIdsValue)) { $azureRoleAssignmentIdsFromEnv = $azureRoleIdsValue }
  if (-not [string]::IsNullOrWhiteSpace($exoSpDisplayNameValue)) { $exoServicePrincipalDisplayNameFromEnv = $exoSpDisplayNameValue }
}

Write-Host 'Running postprovision function validation...'

# Setup receipts establish accepted writes, not propagated effective workload access.
# ZIP deployment may reload setup helpers; do not reconnect Graph or infer Teams
# readiness from unrelated Graph application-role assignments after deployment.
if ($exchangeSetupStatusFromEnv -eq 'configured' -or $teamsSetupStatusFromEnv -eq 'configured') {
  Write-Warning 'Exchange/Teams setup responses were recorded. Permission propagation and effective workload access are unverified; inspect the separately requested native assessment before claiming coverage.'
}

$validateOnProvision = $env:VALIDATE_FUNCTION_ON_PROVISION
if ($validateOnProvision -and $validateOnProvision.Trim().ToLower() -eq 'true') {
  $testParams = @{
    SubscriptionId    = $SubscriptionId
    ResourceGroupName = $ResourceGroupName
    TimeoutMinutes    = 5
  }
  $testParams['FunctionAppName'] = Get-EnvValue -Lines $envValues -Name 'FUNCTION_APP_NAME'
  $testParams['StorageAccountName'] = Get-EnvValue -Lines $envValues -Name 'STORAGE_ACCOUNT_NAME'
  if ($TenantId) {
    $testParams['TenantId'] = $TenantId
  }

  $testParams['PassThru'] = $true

  # Temporarily relax error handling so validation errors stay non-fatal
  $savedErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $validationResult = & "$PSScriptRoot\Invoke-FunctionValidation.ps1" @testParams
    if (-not $validationResult) {
      $validationResult = [pscustomobject]@{
        ValidationPassed  = $false
        ExecutionComplete = $false
        FunctionAppName   = 'unknown'
        FinalStatus       = 'no result returned'
        CompletedAt       = (Get-Date).ToString('o')
      }
    }
  }
  catch {
    Write-Warning "Function validation encountered an error (non-fatal): $($_.Exception.Message)"
    $validationResult = [pscustomobject]@{
      ValidationPassed  = $false
      ExecutionComplete = $false
      FunctionAppName   = 'unknown'
      FinalStatus       = "error: $($_.Exception.Message)"
      CompletedAt       = (Get-Date).ToString('o')
    }
  }
  finally {
    $ErrorActionPreference = $savedErrorActionPreference
  }
}
else {
  Write-Host 'Function validation skipped (VALIDATE_FUNCTION_ON_PROVISION is not set to true).'
  $validationResult = [pscustomobject]@{
    ValidationPassed = 'skipped'
    FunctionAppName  = 'n/a'
    FinalStatus      = 'skipped'
    CompletedAt      = (Get-Date).ToString('o')
  }
}

$armToken = az account get-access-token --subscription $SubscriptionId --resource https://management.azure.com/ --query accessToken -o tsv
$armHeaders = @{ Authorization = "Bearer $armToken" }
$customDnsDocsUrl = 'https://learn.microsoft.com/azure/app-service/app-service-web-tutorial-custom-domain'
$getExactResource = {
  param($path)
  Invoke-RestMethod -Method GET -Uri "https://management.azure.com$path" -Headers $armHeaders
}
$summaryTargets = Resolve-MaesterDeploymentTargets -EnvironmentValues $envValues -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -EnvironmentName $EnvironmentName -SolutionName 'function-app' -GetResource $getExactResource
$functionAppResource = Resolve-MaesterMainDeploymentTarget -EnvironmentValues $envValues -NameOutput 'functionAppName' -PrincipalOutput 'functionAppPrincipalId' -ProviderType 'Microsoft.Web/sites' -ApiVersion '2023-12-01' -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -EnvironmentName $EnvironmentName -SolutionName 'function-app' -Kind FunctionApp -GetResource $getExactResource
$storageResource = $summaryTargets.StorageAccount
$webAppResource = $summaryTargets.WebApp
$hostingPlanResource = Resolve-MaesterHostingPlan -Site $functionAppResource -Label 'Function App' -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -GetResource $getExactResource
$webAppPlanResource = Resolve-MaesterHostingPlan -Site $webAppResource -Label 'Web App' -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -GetResource $getExactResource
$includeWebAppEffective = [string]$envValues['WEB_APP_ENABLED'] -eq 'true'
$deploymentModeEffective = if ($includeWebAppEffective) { 'webapp' } else { 'quick' }

$summaryDir = Join-Path -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -ChildPath 'outputs'
if (-not (Test-Path -Path $summaryDir)) {
  New-Item -Path $summaryDir -ItemType Directory -Force | Out-Null
}

$summaryPath = Join-Path -Path $summaryDir -ChildPath ("{0}-setup-summary.md" -f $EnvironmentName)
$summaryLines = @()
$summaryLines += '# Deployment and Validation Summary'
$summaryLines += ""
$summaryLines += "Generated: $(Get-Date -Format u)"
$summaryLines += "Environment: $EnvironmentName"
$summaryLines += "Subscription: $SubscriptionId"
$summaryLines += "Resource group: $ResourceGroupName"
$summaryLines += "Deployment mode: $deploymentModeEffective"
$summaryLines += "Include web app: $($includeWebAppEffective.ToString().ToLower())"
$summaryLines += "Include Exchange: $includeExchangeFromEnv"
$summaryLines += "Include Teams: $includeTeamsFromEnv"
$summaryLines += "Include Azure: $includeAzureFromEnv"
$summaryLines += "Permission profile: $PermissionProfile"
$summaryLines += "Azure RBAC scopes: $azureScopesFromEnv"
$summaryLines += "Exchange setup status: $exchangeSetupStatusFromEnv"
$summaryLines += "Teams setup status: $teamsSetupStatusFromEnv"
$summaryLines += "Azure setup status: $azureSetupStatusFromEnv"
$summaryLines += "Workload permission propagation/effective access: unverified by setup responses; inspect native assessment evidence separately."
$summaryLines += "Exchange appRoleAssignment ids: $exoAppRoleAssignmentIdsFromEnv"
$summaryLines += "Teams roleAssignment ids: $teamsRoleAssignmentIdsFromEnv"
$summaryLines += "Azure roleAssignment ids: $azureRoleAssignmentIdsFromEnv"
$summaryLines += "Exchange SP display name: $exoServicePrincipalDisplayNameFromEnv"
$summaryLines += "Security group object id: $(if ($SecurityGroupObjectId) { $SecurityGroupObjectId } else { 'n/a' })"
$summaryLines += "Security group display name: $(if ($SecurityGroupDisplayName) { $SecurityGroupDisplayName } else { 'n/a' })"
$easyAuthClientId = 'n/a'
$easyAuthIssuer = 'n/a'
if ($webAppResource) {
  $webAppResourceName = $webAppResource.name
  $authPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$webAppResourceName/config/authsettingsV2?api-version=2023-12-01"
  $auth = Invoke-RestMethod -Method GET -Uri "https://management.azure.com$authPath" -Headers $armHeaders
  if ($auth.properties.identityProviders.azureActiveDirectory.registration.clientId) {
    $easyAuthClientId = $auth.properties.identityProviders.azureActiveDirectory.registration.clientId
  }
  if ($auth.properties.identityProviders.azureActiveDirectory.registration.openIdIssuer) {
    $easyAuthIssuer = $auth.properties.identityProviders.azureActiveDirectory.registration.openIdIssuer
  }
}
$effectiveEasyAuthClientId = if ($easyAuthClientId -and $easyAuthClientId -ne 'n/a') { $easyAuthClientId } else { $easyAuthAppClientIdFromEnv }
$summaryLines += "Easy Auth clientId: $easyAuthClientId"
$summaryLines += "Easy Auth issuer: $easyAuthIssuer"
$summaryLines += "Easy Auth Entra app objectId: $easyAuthAppObjectId"
$summaryLines += "Easy Auth Entra app display name: $easyAuthAppDisplayName"
$summaryLines += "Easy Auth Entra app clientId (azd env): $easyAuthAppClientIdFromEnv"
$summaryLines += "Easy Auth effective clientId: $effectiveEasyAuthClientId"
$summaryLines += ""
$summaryLines += '## Resources Created'
$summaryLines += "- Function App: $(if ($functionAppResource) { $functionAppResource.name } else { 'not found' })"
$summaryLines += "- Function Hosting Plan: $(if ($hostingPlanResource) { $hostingPlanResource.name } else { 'not found' })"
$summaryLines += "- Storage Account: $(if ($storageResource) { $storageResource.name } else { 'not found' })"
$summaryLines += "- App Service Plan: $(if ($webAppPlanResource) { $webAppPlanResource.name } else { 'not deployed' })"
$summaryLines += "- Web App: $(if ($webAppResource) { $webAppResource.name } else { 'not deployed' })"
$summaryLines += ""
$summaryLines += '## How Components Interoperate'
$summaryLines += '- Function App executes Maester tests on a weekly timer schedule (Sunday 9am UTC) and on-demand via admin trigger.'
$summaryLines += '- Exact SHA-256 verified PowerShell modules are bundled in the Function App deployment package.'
$summaryLines += '- Function App managed identity calls Microsoft Graph using the configured permission profile.'
$summaryLines += '- Function App managed identity uploads gzip-compressed dated reports to storage container `archive` and `latest.html` to `latest`.'
if ($webAppResource) {
  $summaryLines += '- Web App hosts the latest dashboard experience and is protected by Easy Auth + Entra security group restriction.'
  $summaryLines += "- Optional custom DNS setup guidance: $customDnsDocsUrl"
}
else {
  $summaryLines += '- Web App is not deployed in quick mode; reports remain available through storage-backed workflow.'
}
$summaryLines += ""
$summaryLines += '## Validation Results'
$validationPassed = if ($validationResult.ValidationPassed -is [bool]) { if ($validationResult.ValidationPassed) { 'Passed' } else { 'Failed' } } else { $validationResult.ValidationPassed }
$summaryLines += "- Function validation status: $validationPassed"
if ($validationResult.PSObject.Properties.Match('FunctionAppName').Count -gt 0) {
  $summaryLines += "- Function app name: $($validationResult.FunctionAppName)"
}
$summaryLines += "- Final status: $($validationResult.FinalStatus)"
$summaryLines += "- Validation completed at: $($validationResult.CompletedAt)"

Set-Content -Path $summaryPath -Value ($summaryLines -join [Environment]::NewLine) -Encoding utf8

Write-Host "Deployment summary written to: $summaryPath"

if ($webAppResource) {
  Write-Host "Optional custom DNS setup guide: $customDnsDocsUrl"
}

Write-Host "azd postprovision setup completed. Function validation status: $validationPassed."
