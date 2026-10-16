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
  Set-Content -LiteralPath (Join-Path $env:TEMP 'az-called') -Value 'yes'
  $global:LASTEXITCODE = 0
}
& '__DEPLOY_SCRIPT__' -SubscriptionId '11111111-1111-4111-8111-111111111111' `
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
  BeforeAll {
    $fixture = Join-Path $TestDrive 'deployment-fixture'
    $scripts = Join-Path $fixture 'scripts'
    $src = Join-Path $fixture 'src'
    $null = New-Item -ItemType Directory -Path $scripts, (Join-Path $src 'MaesterTimerTrigger')
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Deploy-FunctionCode.ps1') -Destination $scripts
    '{"version":"2.0","managedDependency":{"enabled":false}}' | Set-Content (Join-Path $src 'host.json')
    '@{}' | Set-Content (Join-Path $src 'requirements.psd1')
    '# Test-only packaging fixture' | Set-Content (Join-Path $src 'profile.ps1')
    # This fixture starts after successful module verification, covered above.
    'param($LockPath, $DestinationRoot, $PackageNames)' | Set-Content (Join-Path $scripts 'Install-LockedModules.ps1')
    $dispatchHarness = @'
$env:TEMP = $env:RUNNER_TEST_TEMP_ROOT
function az {
  Add-Content -LiteralPath (Join-Path $env:TEMP 'submissions.txt') -Value 'submitted'
  $zip = $args[[Array]::IndexOf($args, '--src') + 1]
  (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash | Set-Content (Join-Path $env:TEMP 'submitted.sha256')
  Write-Output $env:RUNNER_TEST_DEPLOY_MESSAGE
  $global:LASTEXITCODE = [int]$env:RUNNER_TEST_DEPLOY_EXIT_CODE
}
& '__SCRIPT__' -SubscriptionId '11111111-1111-4111-8111-111111111111' -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -Plan B1
'@.Replace('__SCRIPT__', (Join-Path $scripts 'Deploy-FunctionCode.ps1').Replace("'", "''"))
    $dispatchHarnessPath = Join-Path $TestDrive 'deployment-dispatch.ps1'
    Set-Content -LiteralPath $dispatchHarnessPath -Value $dispatchHarness
  }
  AfterAll {
    foreach ($name in 'RUNNER_TEST_TEMP_ROOT', 'RUNNER_TEST_DEPLOY_MESSAGE', 'RUNNER_TEST_DEPLOY_EXIT_CODE') {
      [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
  }
  It 'preserves the exact submitted ZIP and does not resubmit after <case>' -ForEach @(
    @{case='an active server timeout'; message='ERROR: Timeout reached by the command, however, the deployment operation is still on-going.'},
    @{case='an unspecified CLI failure'; message='ERROR: Unable to retrieve deployment status.'}
  ) {
    $env:RUNNER_TEST_TEMP_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $env:RUNNER_TEST_DEPLOY_MESSAGE = $message
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '1'
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $output = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1
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
    $env:RUNNER_TEST_DEPLOY_EXIT_CODE = '0'
    $null = New-Item -ItemType Directory -Path $env:RUNNER_TEST_TEMP_ROOT
    $null = & pwsh -NoProfile -File $dispatchHarnessPath 2>&1
    $LASTEXITCODE | Should -Be 0
    @(Get-Content (Join-Path $env:RUNNER_TEST_TEMP_ROOT 'submissions.txt')).Count | Should -Be 1
    @(Get-ChildItem -LiteralPath $env:RUNNER_TEST_TEMP_ROOT -Filter '*.zip').Count | Should -Be 0
  }
}
