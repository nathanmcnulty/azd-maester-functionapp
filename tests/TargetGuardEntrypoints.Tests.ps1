BeforeAll {
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $harnessPath = Join-Path $PSScriptRoot 'fixtures/TargetGuardHarness.ps1'
  $fixture = Join-Path $TestDrive 'target-guard-fixture'
  $scripts = Join-Path $fixture 'scripts'
  $bin = Join-Path $fixture 'bin'
  $null = New-Item -ItemType Directory -Path $scripts, $bin, (Join-Path $fixture 'src/MaesterTimerTrigger')
  foreach ($name in @('Deploy-FunctionCode.ps1', 'Setup-PostDeploy.ps1', 'Run-AzdPreUp.ps1', 'Invoke-FunctionValidation.ps1', 'Resolve-DeploymentTargets.ps1', 'FunctionValidation.Core.psm1', 'Maester-SetupConsent.psm1')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination $scripts
  }
  Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/vendor') -Destination $scripts -Recurse
  # Setup invokes this separate grant script and ZIP script. Capture the real
  # caller splat at that boundary; direct ZIP tests use the unchanged ZIP script.
  $setupFixture = Join-Path $TestDrive 'setup-guard-fixture'
  Copy-Item -LiteralPath $fixture -Destination $setupFixture -Recurse
  @'
param($TenantId, $PrincipalObjectId, $PermissionProfile, $IncludeMailSend)
Write-TargetGuardEvent 'graph-permissions' $PSBoundParameters
'@ | Set-Content (Join-Path $setupFixture 'scripts/vendor/Azd.MaesterHooks/Grant-MaesterGraphPermissions.ps1')
  @'
param($SubscriptionId, $TenantId, $ResourceGroupName, $FunctionAppName, $Plan, [switch]$IncludeExchange, [switch]$IncludeTeams)
Write-TargetGuardEvent 'setup-deploy' $PSBoundParameters
'@ | Set-Content (Join-Path $setupFixture 'scripts/Deploy-FunctionCode.ps1')
  '{"version":"2.0","managedDependency":{"enabled":false}}' | Set-Content (Join-Path $fixture 'src/host.json')
  '@{}' | Set-Content (Join-Path $fixture 'src/requirements.psd1')
  '# Offline packaging fixture' | Set-Content (Join-Path $fixture 'src/profile.ps1')
  @'
param($LockPath, $DestinationRoot, $PackageNames)
Write-TargetGuardEvent 'package' $PackageNames
Set-Content (Join-Path $env:TARGET_GUARD_WORK_ROOT 'packaged') 'yes'
'@ | Set-Content (Join-Path $scripts 'Install-LockedModules.ps1')
  $azStub = Join-Path $bin 'az-stub.ps1'
  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
# This is the only executable az available to the bounded deployment child.
@{ kind = 'deployment'; data = $Arguments } | ConvertTo-Json -Compress |
  Add-Content -LiteralPath (Join-Path $env:TARGET_GUARD_WORK_ROOT 'events.jsonl')
if (($Arguments[0..3] -join ' ') -ne 'functionapp deployment source config-zip') { exit 91 }
[Console]::WriteLine('Offline deployment stub completed.')
exit 0
'@ | Set-Content $azStub
  if ($IsWindows) {
    "@echo off`r`n`"$PSHOME\pwsh.exe`" -NoLogo -NoProfile -NonInteractive -File `"$azStub`" %*`r`nexit /b %ERRORLEVEL%" |
      Set-Content (Join-Path $bin 'az.cmd') -Encoding ascii
  }
  else {
    $quotedPwsh = "'" + (Join-Path $PSHOME 'pwsh').Replace("'", "'\''") + "'"
    $quotedStub = "'" + $azStub.Replace("'", "'\''") + "'"
    ('#!/bin/sh' + "`nexec $quotedPwsh -NoLogo -NoProfile -NonInteractive -File $quotedStub " + '"$@"') |
      Set-Content (Join-Path $bin 'az')
    & chmod +x (Join-Path $bin 'az')
  }
  function Invoke-TargetGuardEntrypoint {
    param([string]$EntryPoint, [string]$Scenario)
    $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work
    $selectedFixture = if ($EntryPoint -eq 'Setup') { $setupFixture } else { $fixture }
    $oldPath = $env:PATH
    try {
      $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
      $output = & (Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })) -NoLogo -NoProfile -NonInteractive -File $harnessPath `
        -FixtureRoot $selectedFixture -WorkRoot $work -EntryPoint $EntryPoint -Scenario $Scenario 2>&1
      $code = $LASTEXITCODE
    }
    finally { $env:PATH = $oldPath }
    $eventsPath = Join-Path $work 'events.jsonl'
    $events = if (Test-Path $eventsPath) { @(Get-Content $eventsPath | ConvertFrom-Json) } else { @() }
    [pscustomobject]@{ ExitCode = $code; Output = $output -join "`n"; Events = @($events); WorkRoot = $work }
  }
  function Assert-NoCloudMutation {
    param($Result)
    @($Result.Events | Where-Object kind -in @('deployment', 'setup-deploy', 'group-create', 'exchange-app-role', 'exchange-service-principal', 'exchange-rbac', 'graph-permissions', 'environment-write')).Count | Should -Be 0
    @($Result.Events | Where-Object kind -in @('module-download', 'download-or-http-write', 'unexpected-az')).Count | Should -Be 0
  }
}

Describe 'Actual direct ZIP entrypoint target guards' {
  It 'rejects <Scenario> before module preparation, downloads or deployment' -ForEach @(
    @{ Scenario = 'wrong-tenant'; Error = 'belongs to tenant' },
    @{ Scenario = 'wrong-subscription'; Error = 'identity/tenant metadata' },
    @{ Scenario = 'stale-enabled'; Error = 'currently be Enabled' },
    @{ Scenario = 'missing-state'; Error = 'currently be Enabled' },
    @{ Scenario = 'query-failure'; Error = 'current ARM metadata' },
    @{ Scenario = 'missing-tenant'; Error = 'TenantId is required' },
    @{ Scenario = 'blank-tenant'; Error = 'TenantId is required' }
  ) {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Deploy -Scenario $Scenario
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match $Error
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -eq 'package').Count | Should -Be 0
    @($result.Events | Where-Object kind -eq 'cached-account').Count | Should -Be 0
  }
  It 'uses the explicit valid target while the global default differs (<Scenario>)' -ForEach @(
    @{ Scenario = 'valid' }, @{ Scenario = 'environment-tenant' }
  ) {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Deploy -Scenario $Scenario
    $result.ExitCode | Should -Be 0 -Because $result.Output
    ($result.Events.kind -join ',') | Should -Be 'metadata,package,metadata,deployment'
    $deployment = @($result.Events | Where-Object kind -eq 'deployment')[0].data
    $deployment[[Array]::IndexOf($deployment, '--subscription') + 1] | Should -Be '11111111-1111-4111-8111-111111111111'
  }
  It 'rechecks current state after packaging and stops before config-zip when the target becomes Disabled' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Deploy -Scenario 'change-during-packaging'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'currently be Enabled'
    ($result.Events.kind -join ',') | Should -Be 'metadata,package,metadata'
    Assert-NoCloudMutation $result
  }
}

Describe 'Actual optional Exchange setup caller' {
  It 'forwards the validated tenant through the real Exchange token splat and ZIP caller splat' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'valid'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    $exchangeTokens = @($result.Events | Where-Object { $_.kind -eq 'token' -and $_.data -contains 'https://outlook.office365.com' })
    $exchangeTokens.Count | Should -Be 1
    $tokenArgs = $exchangeTokens[0].data
    $tokenArgs[[Array]::IndexOf($tokenArgs, '--tenant') + 1] | Should -Be '22222222-2222-4222-8222-222222222222'
    $tokenArgs | Should -Not -Contain '--subscription'
    $connect = @($result.Events | Where-Object kind -eq 'exchange-connect')
    $connect.Count | Should -Be 1
    $connect[0].data.AccessToken | Should -Be 'offline-exchange-token'
    $connect[0].data.Organization | Should -Be 'guard-test.onmicrosoft.com'
    $deploy = @($result.Events | Where-Object kind -eq 'setup-deploy')
    $deploy.Count | Should -Be 1
    $deploy[0].data.TenantId | Should -Be '22222222-2222-4222-8222-222222222222'
    $deploy[0].data.SubscriptionId | Should -Be '11111111-1111-4111-8111-111111111111'
    $deploy[0].data.IncludeExchange.IsPresent | Should -BeTrue
    foreach ($kind in @('exchange-app-role', 'exchange-service-principal', 'exchange-rbac')) {
      @($result.Events | Where-Object kind -eq $kind).Count | Should -Be 1
      [Array]::IndexOf($result.Events.kind, 'exchange-connect') | Should -BeLessThan ([Array]::IndexOf($result.Events.kind, $kind))
    }
  }
  It 'returns a read-only plan without deployment, writes, or receipts by default' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'plan-only'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -eq 'access-plan').Count | Should -Be 1
  }
  It 'rechecks fresh target state before applying any reviewed grants' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'change-before-apply'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'currently be Enabled'
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -eq 'access-plan').Count | Should -Be 1
  }
  It 'stops failed <Scenario> target validation before any role or deployment change' -ForEach @(
    @{ Scenario = 'wrong-tenant' }, @{ Scenario = 'wrong-subscription' }, @{ Scenario = 'stale-enabled' },
    @{ Scenario = 'missing-state' }, @{ Scenario = 'query-failure' }, @{ Scenario = 'missing-tenant' }
  ) {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario $Scenario
    $result.ExitCode | Should -Be 1
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -in @('token', 'http', 'graph-connect', 'exchange-connect')).Count | Should -Be 0
  }
  It 'rejects a changed target before entering optional Exchange setup' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'change-before-exchange'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'currently be Enabled'
    @($result.Events | Where-Object kind -eq 'metadata').Count | Should -Be 2
    @($result.Events | Where-Object kind -in @('graph-connect', 'exchange-connect', 'exchange-app-role', 'exchange-service-principal', 'exchange-rbac', 'setup-deploy')).Count | Should -Be 0
  }
  It 'fails closed even when the legacy optional-step policy requests skipping failed Exchange token validation' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'wrong-exchange-token-skip'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'Exchange Online token acquisition failed'
    @($result.Events | Where-Object kind -in @('exchange-connect', 'exchange-app-role', 'exchange-service-principal', 'exchange-rbac', 'setup-deploy')).Count | Should -Be 0
    @($result.Events | Where-Object { $_.kind -eq 'token' -and $_.data -contains 'https://outlook.office365.com' }).Count | Should -Be 1
  }
  It 'rejects a token from the wrong tenant before Exchange app-role, service-principal or RBAC changes' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Setup -Scenario 'wrong-exchange-token'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'Exchange Online token acquisition failed'
    @($result.Events | Where-Object kind -in @('exchange-connect', 'exchange-app-role', 'exchange-service-principal', 'exchange-rbac', 'setup-deploy')).Count | Should -Be 0
    @($result.Events | Where-Object { $_.kind -eq 'token' -and $_.data -contains 'https://outlook.office365.com' }).Count | Should -Be 1
  }
}

Describe 'Actual preup and validation entrypoints' {
  It 'preup rejects a mismatched tenant with a missing group before any group-create call' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint PreUp -Scenario 'wrong-tenant'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'belongs to tenant'
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -eq 'group-exists').Count | Should -Be 0
  }
  It 'preup validates the selected target and leaves creation to ownership-aware preprovision' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint PreUp -Scenario 'valid'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    ($result.Events.kind -join ',') | Should -Be 'metadata,group-exists'
    $groupArgs = @($result.Events | Where-Object kind -eq 'group-exists')[0].data
    $groupArgs[[Array]::IndexOf($groupArgs, '--subscription') + 1] | Should -Be '11111111-1111-4111-8111-111111111111'
  }
  It 'direct validation fails closed on <Scenario> before keys, tokens or trigger HTTP' -ForEach @(
    @{ Scenario = 'wrong-tenant' }, @{ Scenario = 'wrong-subscription' }, @{ Scenario = 'stale-enabled' },
    @{ Scenario = 'missing-state' }, @{ Scenario = 'query-failure' }, @{ Scenario = 'missing-tenant' }
  ) {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Validation -Scenario $Scenario
    $result.ExitCode | Should -Be 1
    Assert-NoCloudMutation $result
    @($result.Events | Where-Object kind -in @('http', 'token', 'download-or-http-write')).Count | Should -Be 0
  }
}

Describe 'Actual validation trigger recheck' {
  It 'fails terminally if the target is disabled after preparation and before the trigger POST' {
    $result = Invoke-TargetGuardEntrypoint -EntryPoint Validation -Scenario 'change-before-trigger'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'currently be Enabled'
    @($result.Events | Where-Object kind -eq 'metadata').Count | Should -Be 2
    @($result.Events | Where-Object kind -eq 'receipt-check').Count | Should -Be 1
    $result.Events[-1].kind | Should -Be 'metadata'
    @($result.Events | Where-Object kind -eq 'download-or-http-write').Count | Should -Be 0
    Assert-NoCloudMutation $result
  }
}
