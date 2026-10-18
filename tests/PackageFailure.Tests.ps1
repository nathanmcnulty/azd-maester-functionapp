Describe 'Locked Function module packaging' {
  AfterAll {
    foreach ($name in 'RUNNER_TEST_TEMP_ROOT', 'RUNNER_TEST_PLAN') {
      [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
  }
  BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $deployPath = Join-Path $repoRoot 'scripts/Deploy-FunctionCode.ps1'
    $installerPath = Join-Path $repoRoot 'scripts/Install-LockedModules.ps1'
    $harness = @'
$env:TEMP = $env:RUNNER_TEST_TEMP_ROOT
function Invoke-WebRequest {
  param($Uri, $OutFile)
  Set-Content -LiteralPath (Join-Path $env:TEMP 'download-attempted') -Value 'yes'
  Set-Content -LiteralPath $OutFile -Value 'untrusted bytes'
}

function az {
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'rest' -and $args -contains '--subscription') {
    return '{"id":"/subscriptions/11111111-1111-4111-8111-111111111111","subscriptionId":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222","displayName":"Offline test","state":"Enabled"}'
  }
  Set-Content -LiteralPath (Join-Path $env:TEMP 'az-called') -Value 'yes'
  throw "Unexpected Azure CLI invocation: $args"
}
& '__DEPLOY_SCRIPT__' -SubscriptionId '11111111-1111-4111-8111-111111111111' `
  -TenantId '22222222-2222-4222-8222-222222222222' `
  -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -Plan $env:RUNNER_TEST_PLAN
'@.Replace('__DEPLOY_SCRIPT__', $deployPath.Replace("'", "''"))
    $harnessPath = Join-Path $TestDrive 'package-harness.ps1'
    Set-Content -LiteralPath $harnessPath -Value $harness
  }

  It 'rejects tampered package bytes before zip deployment on <Plan>' -ForEach @(
    @{ Plan = 'FC1' }, @{ Plan = 'B1' }
  ) {
      $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive "tamper-$Plan"
      $env:RUNNER_TEST_PLAN = $Plan
      New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT | Out-Null
      $output = & pwsh -NoProfile -File $harnessPath 2>&1
      $LASTEXITCODE | Should -Be 1
      @($output) -join "`n" | Should -Match 'failed SHA-256 verification'
      (Test-Path -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'download-attempted')) | Should -BeTrue
      (Test-Path -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'az-called')) | Should -BeFalse
      @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
  }

  It 'rejects a hash-valid package without the locked module manifest' {
    $packageDir = Join-Path $TestDrive 'empty-package'
    $destination = Join-Path $TestDrive 'empty-modules'
    New-Item -ItemType Directory -Path $packageDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $source = Join-Path $TestDrive 'zip-source'
    New-Item -ItemType Directory -Path $source | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'other.txt') -Value 'no manifest'
    $packagePath = Join-Path $packageDir 'Fake.1.0.0.nupkg'
    [IO.Compression.ZipFile]::CreateFromDirectory($source, $packagePath)
    $hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    $lockPath = Join-Path $TestDrive 'empty.lock.json'
    @{ schemaVersion = 1; packages = @(@{ name = 'Fake'; version = '1.0.0'; sha256 = $hash }) } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath
    { & $installerPath -LockPath $lockPath -PackageDirectory $packageDir -DestinationRoot $destination } |
      Should -Throw '*has no expected module manifest*'
  }
}

Describe 'Unconfirmed Function deployment' {
  BeforeEach {
    $env:RUNNER_TEST_RESOURCE_GROUP = $null
    $env:RUNNER_TEST_TIMEOUT = $null
  }
  BeforeAll {
    $fixture = Join-Path $TestDrive 'deployment-fixture'
    $scripts = Join-Path $fixture 'scripts'
    $src = Join-Path $fixture 'src'
    $bin = Join-Path $fixture 'bin'
    $null = New-Item -ItemType Directory -Path $scripts, (Join-Path $src 'MaesterTimerTrigger'), $bin
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Deploy-FunctionCode.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/vendor') -Destination $scripts -Recurse
    '{"version":"2.0","managedDependency":{"enabled":false}}' | Set-Content (Join-Path $src 'host.json')
    '@{}' | Set-Content (Join-Path $src 'requirements.psd1')
    '# Test-only packaging fixture' | Set-Content (Join-Path $src 'profile.ps1')
    # This fixture starts after successful module verification, covered above.
    'param($LockPath, $DestinationRoot, $PackageNames)' | Set-Content (Join-Path $scripts 'Install-LockedModules.ps1')
    $stubScriptPath = Join-Path $bin 'az-stub.ps1'
    $stubScript = @(
      'param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)',
      'if ($Arguments[0] -eq ''rest'' -and $Arguments -contains ''--subscription'') {',
      '  [Console]::WriteLine(''{"id":"/subscriptions/11111111-1111-4111-8111-111111111111","subscriptionId":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222","displayName":"Offline test","state":"Enabled"}'')',
      '  exit 0',
      '}',
      '$srcIndex = [Array]::IndexOf($Arguments, ''--src'')',
      'if ($srcIndex -lt 0) { exit 9 }',
      'Add-Content -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''submissions.txt'') -Value ''submitted''',
      '(Get-FileHash -LiteralPath $Arguments[$srcIndex + 1] -Algorithm SHA256).Hash | Set-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''submitted.sha256'')',
      '$Arguments | ConvertTo-Json | Set-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''arguments.json'')',
      'Set-Content -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''stub.pid'') -Value $PID',
      '$pwshName = if ($IsWindows) { ''pwsh.exe'' } else { ''pwsh'' }',
      'if ($env:RUNNER_TEST_DEPLOY_MODE -eq ''hang'') {',
      '  $childArguments = @{ FilePath = (Join-Path $PSHOME $pwshName); ArgumentList = @(''-NoLogo'', ''-NoProfile'', ''-NonInteractive'', ''-Command'', ''Start-Sleep -Seconds 600''); PassThru = $true }',
      '  if ($IsWindows) { $childArguments.WindowStyle = ''Hidden'' }',
      '  $child = Start-Process @childArguments',
      '  Set-Content -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''child.pid'') -Value $child.Id',
      '  while ($true) { Start-Sleep -Seconds 1 }',
      '}',
      'if ($env:RUNNER_TEST_DEPLOY_MODE -eq ''large-output'') {',
      '  1..50000 | ForEach-Object { [Console]::WriteLine((''output-line-{0}'' -f $_)) }',
      '  [Console]::Error.WriteLine(''large-output-stderr'')',
      '  exit 0',
      '}',
      'if ($env:RUNNER_TEST_DEPLOY_MODE -eq ''failure'') {',
      '  [Console]::Error.WriteLine($env:RUNNER_TEST_DEPLOY_MESSAGE)',
      '  exit 1',
      '}',
      '[Console]::WriteLine($env:RUNNER_TEST_DEPLOY_MESSAGE)',
      'exit ([int]$env:RUNNER_TEST_DEPLOY_EXIT_CODE)'
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $stubScriptPath -Value $stubScript
    if ($IsWindows) {
      $stubPath = Join-Path $bin 'az.cmd'
      $launcher = @"
@echo off
"$PSHOME\pwsh.exe" -NoLogo -NoProfile -NonInteractive -File "$stubScriptPath" %*
exit /b %ERRORLEVEL%
"@
      Set-Content -LiteralPath $stubPath -Value $launcher -Encoding ascii
    }
    else {
      $stubPath = Join-Path $bin 'az'
      $quotedPwsh = "'" + (Join-Path $PSHOME 'pwsh').Replace("'", "'\''") + "'"
      $quotedStub = "'" + $stubScriptPath.Replace("'", "'\''") + "'"
      $launcher = '#!/bin/sh' + [Environment]::NewLine + 'exec ' + $quotedPwsh + ' -NoLogo -NoProfile -NonInteractive -File ' + $quotedStub + ' "$@"'
      Set-Content -LiteralPath $stubPath -Value $launcher
      & chmod +x $stubPath
    }
    $dispatchHarness = @'
$env:TEMP = $env:RUNNER_TEST_TEMP_ROOT
$resourceGroup = if ($env:RUNNER_TEST_RESOURCE_GROUP) { $env:RUNNER_TEST_RESOURCE_GROUP } else { 'rg-test' }
$invoke = @{ SubscriptionId = '11111111-1111-4111-8111-111111111111'; TenantId = '22222222-2222-4222-8222-222222222222'; ResourceGroupName = $resourceGroup; FunctionAppName = 'func-test'; Plan = 'B1' }
if ($env:RUNNER_TEST_TIMEOUT) { $invoke.DeploymentTimeoutSeconds = [int]$env:RUNNER_TEST_TIMEOUT }
try { & '__SCRIPT__' @invoke }
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@.Replace('__SCRIPT__', (Join-Path $scripts 'Deploy-FunctionCode.ps1').Replace("'", "''"))
    $dispatchHarnessPath = Join-Path $TestDrive 'deployment-dispatch.ps1'
    Set-Content -LiteralPath $dispatchHarnessPath -Value $dispatchHarness
  }
  AfterAll {
    foreach ($name in 'RUNNER_TEST_TEMP_ROOT', 'RUNNER_TEST_DEPLOY_MESSAGE', 'RUNNER_TEST_DEPLOY_EXIT_CODE', 'RUNNER_TEST_DEPLOY_MODE', 'RUNNER_TEST_TIMEOUT', 'RUNNER_TEST_RESOURCE_GROUP') {
      [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
  }
  It 'preserves the exact submitted ZIP and does not resubmit after <case>' -ForEach @(
    @{case='an active server timeout'; message='ERROR: Timeout reached by the command, however, the deployment operation is still on-going.'},
    @{case='an unspecified CLI failure'; message='ERROR: Unable to retrieve deployment status.'}
  ) {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = $message
    $env:RUNNER_TEST_DEPLOY_MODE = 'failure'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '1'
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 1
    ($output -join "`n") | Should -Match 'did not confirm completion'
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    $preserved = @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip')
    $preserved.Count | Should -Be 1
    (Get-FileHash $preserved[0].FullName -Algorithm SHA256).Hash |
      Should -BeExactly (Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submitted.sha256'))
  }
  It 'removes the transport ZIP only after confirmed deployment success' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.'
    $env:RUNNER_TEST_DEPLOY_MODE = 'success'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $null = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 0
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
  }
  It 'drains large subprocess output and preserves literal deployment arguments' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.'
    $env:RUNNER_TEST_DEPLOY_MODE = 'large-output'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_RESOURCE_GROUP = "rg'quoted"
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 0
    (Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'arguments.json') -Raw | ConvertFrom-Json) | Should -Contain "rg'quoted"
    $output.Count | Should -BeGreaterThan 1000
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
  }
  It 'kills a hanging subprocess tree at the local deadline and preserves the package' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'deployment still running'
    $env:RUNNER_TEST_DEPLOY_MODE = 'hang'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_TIMEOUT = '5'
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath; $elapsed.Stop() }
    $LASTEXITCODE | Should -Be 1
    # Allow startup and bounded shutdown grace, but catch an ignored five-second deadline.
    $elapsed.Elapsed.TotalSeconds | Should -BeLessThan 30
    ($output -join "`n") | Should -Match 'local deadline'
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 1
    $processIds = @(
      [int](Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'stub.pid'))
      [int](Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'child.pid'))
    )
    foreach ($processId in $processIds) {
      $gone = $false
      for ($i = 0; $i -lt 50; $i++) {
        if (-not (Get-Process -Id $processId -ErrorAction SilentlyContinue)) { $gone = $true; break }
        Start-Sleep -Milliseconds 100
      }
      $gone | Should -BeTrue
    }
  }
  It 'rejects <unsafe> before a Windows batch launcher runs' -Skip:(-not $IsWindows) -ForEach @(
    @{ unsafe = 'shell expansion'; resourceGroup = 'rg&Set-Content sentinel.txt pwned' },
    @{ unsafe = 'parentheses'; resourceGroup = 'rg(test)' }
  ) {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.'
    $env:RUNNER_TEST_DEPLOY_MODE = 'success'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_RESOURCE_GROUP = $resourceGroup
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 1
    ($output -join "`n") | Should -Match 'unsupported shell-expansion'
    (Test-Path -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')) | Should -BeFalse
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 1
  }
}
