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
  param($Uri, $OutFile, $TimeoutSec, $MaximumRetryCount)
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

  It 'rejects a tampered locked archive before zip deployment on <Plan>' -ForEach @(
    @{ Plan = 'FC1' }, @{ Plan = 'B1' }
  ) {
      $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive "tamper-$Plan"
      $env:RUNNER_TEST_PLAN = $Plan
      New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT | Out-Null
      $oldPath = $env:PATH
      $env:PATH = "$([IO.Path]::GetDirectoryName((Get-Command git).Source))$([IO.Path]::PathSeparator)$oldPath"
      try { $output = & pwsh -NoProfile -File $harnessPath 2>&1 } finally { $env:PATH = $oldPath }
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
    $env:RUNNER_TEST_PACKAGE_DIRECTORY = $null
  }
  BeforeAll {
    $fixture = Join-Path $TestDrive 'deployment-fixture'
    $scripts = Join-Path $fixture 'scripts'
    $src = Join-Path $fixture 'src'
    $bin = Join-Path $fixture 'bin'
    $packageDirectory = Join-Path $fixture 'packages'
    $null = New-Item -ItemType Directory -Path $scripts, (Join-Path $src 'MaesterTimerTrigger'), $bin, $packageDirectory
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Deploy-FunctionCode.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Build-FunctionPackage.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Install-LockedModules.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/vendor') -Destination $scripts -Recurse
    '{"components":[]}' | Set-Content -LiteralPath (Join-Path $fixture 'azd-components.lock.json')
    '{"version":"2.0","managedDependency":{"enabled":false}}' | Set-Content (Join-Path $src 'host.json')
    '@{}' | Set-Content (Join-Path $src 'requirements.psd1')
    '# Test-only packaging fixture' | Set-Content (Join-Path $src 'profile.ps1')
    '{"bindings":[]}' | Set-Content (Join-Path $src 'MaesterTimerTrigger/function.json')
    'Write-Output "fixture"' | Set-Content (Join-Path $src 'MaesterTimerTrigger/run.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $lockedPackages = [Collections.Generic.List[object]]::new()
    foreach ($moduleName in @('Az.Accounts','Microsoft.Graph.Authentication','Maester','Pester','DnsClient-PS')) {
      $moduleVersion = '1.0.0'
      $moduleSource = Join-Path $fixture "module-$moduleName"
      $null = New-Item -ItemType Directory -Path $moduleSource
      "@{ ModuleVersion = '$moduleVersion'; GUID = '00000000-0000-0000-0000-000000000001' }" |
        Set-Content -LiteralPath (Join-Path $moduleSource "$moduleName.psd1")
      $nupkg = Join-Path $packageDirectory "$moduleName.$moduleVersion.nupkg"
      [IO.Compression.ZipFile]::CreateFromDirectory($moduleSource, $nupkg)
      $lockedPackages.Add([ordered]@{name=$moduleName;version=$moduleVersion;sha256=(Get-FileHash $nupkg -Algorithm SHA256).Hash})
    }
    [ordered]@{schemaVersion=1;packages=@($lockedPackages.ToArray())} | ConvertTo-Json -Depth 5 |
      Set-Content -LiteralPath (Join-Path $fixture 'runtime-packages.lock.json')
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
      '$packagePath = $Arguments[$srcIndex + 1]',
      '$manifestPath = $packagePath + ''.manifest.json''',
      'if (Test-Path -LiteralPath $manifestPath) {',
      '  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json',
      '  @{ PackagePath=$packagePath; ManifestPath=$manifestPath; StagingRoot=$manifest.stagingRoot; ManifestZipSha256=$manifest.zipSha256 } | ConvertTo-Json | Set-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT ''package-paths.json'')',
      '}',
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
if ($env:RUNNER_TEST_PACKAGE_DIRECTORY) {
  function Invoke-WebRequest {
    param([string]$Uri,[string]$OutFile,[int]$TimeoutSec,[int]$MaximumRetryCount)
    $leaf = [IO.Path]::GetFileName($OutFile)
    Copy-Item -LiteralPath (Join-Path $env:RUNNER_TEST_PACKAGE_DIRECTORY $leaf) -Destination $OutFile
  }
}
$resourceGroup = if ($env:RUNNER_TEST_RESOURCE_GROUP) { $env:RUNNER_TEST_RESOURCE_GROUP } else { 'rg-test' }
$invoke = @{ SubscriptionId = '11111111-1111-4111-8111-111111111111'; TenantId = '22222222-2222-4222-8222-222222222222'; ResourceGroupName = $resourceGroup; FunctionAppName = 'func-test'; Plan = 'B1' }
if ($env:RUNNER_TEST_PACKAGE_PATH) { $invoke.PackagePath = $env:RUNNER_TEST_PACKAGE_PATH; $invoke.ExpectedPackageSha256 = $env:RUNNER_TEST_PACKAGE_HASH }
if ($env:RUNNER_TEST_TIMEOUT) { $invoke.DeploymentTimeoutSeconds = [int]$env:RUNNER_TEST_TIMEOUT }
try { & '__SCRIPT__' @invoke }
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@.Replace('__SCRIPT__', (Join-Path $scripts 'Deploy-FunctionCode.ps1').Replace("'", "''"))
    $dispatchHarnessPath = Join-Path $TestDrive 'deployment-dispatch.ps1'
    Set-Content -LiteralPath $dispatchHarnessPath -Value $dispatchHarness
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $preparedPackagePath = Join-Path $TestDrive 'prepared-transport-package.zip'
    $preparedPackageRoot = Join-Path $TestDrive 'prepared-transport-package-content'
    $null = New-Item -ItemType Directory -Path $preparedPackageRoot
    'prepared transport bytes' | Set-Content -LiteralPath (Join-Path $preparedPackageRoot 'payload.txt')
    [IO.Compression.ZipFile]::CreateFromDirectory($preparedPackageRoot, $preparedPackagePath)
    $preparedPackageHash = (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash
    & git -C $fixture init --quiet
    & git -C $fixture -c user.name='Offline Test' -c user.email='offline@example.invalid' add --all
    & git -C $fixture -c user.name='Offline Test' -c user.email='offline@example.invalid' commit --quiet -m 'synthetic deployment fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated deployment Git fixture.' }
  }
  AfterAll {
    foreach ($name in 'RUNNER_TEST_TEMP_ROOT', 'RUNNER_TEST_DEPLOY_MESSAGE', 'RUNNER_TEST_DEPLOY_EXIT_CODE', 'RUNNER_TEST_DEPLOY_MODE', 'RUNNER_TEST_TIMEOUT', 'RUNNER_TEST_RESOURCE_GROUP', 'RUNNER_TEST_PACKAGE_PATH', 'RUNNER_TEST_PACKAGE_HASH', 'RUNNER_TEST_PACKAGE_DIRECTORY') {
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
    $env:RUNNER_TEST_PACKAGE_PATH = $preparedPackagePath
    $env:RUNNER_TEST_PACKAGE_HASH = $preparedPackageHash
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 1
    ($output -join "`n") | Should -Match 'did not confirm completion'
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    (Test-Path -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submitted.sha256')) | Should -BeTrue
    (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash | Should -BeExactly $preparedPackageHash
    (Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submitted.sha256')) | Should -BeExactly $preparedPackageHash
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
  }
  It 'submits the prepared ZIP once after confirmed deployment success and preserves its bytes' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.'
    $env:RUNNER_TEST_DEPLOY_MODE = 'success'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_PACKAGE_PATH = $preparedPackagePath
    $env:RUNNER_TEST_PACKAGE_HASH = $preparedPackageHash
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $null = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 0
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
    (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash | Should -BeExactly $preparedPackageHash
  }
  It 'cleans generated artifacts only after confirmed success and preserves all on CLI failure' -ForEach @(
    @{ Mode='success'; ExitCode=0; Preserve=$false },
    @{ Mode='failure'; ExitCode=1; Preserve=$true }
  ) {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ("generated-" + [guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MODE = $Mode
    if ($Preserve) { $env:RUNNER_TEST_DEPLOY_MESSAGE = 'ERROR: Unable to retrieve deployment status.' }
    else { $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.' }
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = [string]$ExitCode
    $env:RUNNER_TEST_PACKAGE_PATH = $null
    $env:RUNNER_TEST_PACKAGE_HASH = $null
    $env:RUNNER_TEST_PACKAGE_DIRECTORY = $packageDirectory
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $sentinel = Join-Path $env:RUNNER_TEST_TEMP_ROOT 'unrelated-sentinel.txt'
    Set-Content -LiteralPath $sentinel -Value 'keep me'
    $oldPath = $env:PATH
    $oldTemp = $env:TEMP
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    $env:TEMP = $env:RUNNER_TEST_TEMP_ROOT
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath; $env:TEMP = $oldTemp }
    $LASTEXITCODE | Should -Be $ExitCode -Because ($output -join [Environment]::NewLine)
    $paths = Get-Content -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'package-paths.json') -Raw | ConvertFrom-Json
    (Get-Content -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submitted.sha256')).ToLowerInvariant() | Should -BeExactly $paths.ManifestZipSha256
    if ($Preserve) {
      (Get-FileHash -LiteralPath $paths.PackagePath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $paths.ManifestZipSha256
      (Test-Path -LiteralPath $paths.PackagePath) | Should -BeTrue
      (Test-Path -LiteralPath $paths.ManifestPath) | Should -BeTrue
      (Test-Path -LiteralPath $paths.StagingRoot) | Should -BeTrue
    } else {
      (Test-Path -LiteralPath $paths.PackagePath) | Should -BeFalse
      (Test-Path -LiteralPath $paths.ManifestPath) | Should -BeFalse
      (Test-Path -LiteralPath $paths.StagingRoot) | Should -BeFalse
    }
    (Test-Path -LiteralPath $sentinel) | Should -BeTrue
    (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -BeExactly 'keep me'
  }

  It 'drains large subprocess output and preserves literal deployment arguments' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'Deployment completed.'
    $env:RUNNER_TEST_DEPLOY_MODE = 'large-output'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_RESOURCE_GROUP = "rg'quoted"
    $env:RUNNER_TEST_PACKAGE_PATH = $preparedPackagePath
    $env:RUNNER_TEST_PACKAGE_HASH = $preparedPackageHash
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 0
    (Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'arguments.json') -Raw | ConvertFrom-Json) | Should -Contain "rg'quoted"
    $output.Count | Should -BeGreaterThan 1000
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
    (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash | Should -BeExactly $preparedPackageHash
  }
  It 'kills a hanging subprocess tree at the local deadline and preserves the package' {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = 'deployment still running'
    $env:RUNNER_TEST_DEPLOY_MODE = 'hang'
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $env:RUNNER_TEST_TIMEOUT = '5'
    $env:RUNNER_TEST_PACKAGE_PATH = $preparedPackagePath
    $env:RUNNER_TEST_PACKAGE_HASH = $preparedPackageHash
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
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
    (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash | Should -BeExactly $preparedPackageHash
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
    $env:RUNNER_TEST_PACKAGE_PATH = $preparedPackagePath
    $env:RUNNER_TEST_PACKAGE_HASH = $preparedPackageHash
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $oldPath = $env:PATH
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    try { $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1 } finally { $env:PATH = $oldPath }
    $LASTEXITCODE | Should -Be 1
    ($output -join "`n") | Should -Match 'unsupported shell-expansion'
    (Test-Path -LiteralPath (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')) | Should -BeFalse
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
    (Get-FileHash -LiteralPath $preparedPackagePath -Algorithm SHA256).Hash | Should -BeExactly $preparedPackageHash
  }
}
