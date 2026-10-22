#Requires -Version 7.6
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TenantId,

  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string]$FunctionAppName,

  [Parameter(Mandatory = $false)]
  [switch]$IncludeExchange,

  [Parameter(Mandatory = $false)]
  [switch]$IncludeTeams,

  [Parameter(Mandatory = $false)]
  [ValidateSet('FC1', 'B1')]
  [string]$Plan = 'FC1',

  [Parameter(Mandatory = $false)]
  [ValidateRange(1, 3600)]
  [int]$DeploymentTimeoutSeconds = 600,

  [string]$PackagePath,

  [ValidatePattern('\A[a-fA-F0-9]{64}\z')]
  [string]$ExpectedPackageSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackagePath) -ne [string]::IsNullOrWhiteSpace($ExpectedPackageSha256)) {
  throw 'PackagePath and ExpectedPackageSha256 must be supplied together.'
}
if ($PackagePath -and ($IncludeExchange -or $IncludeTeams)) {
  throw 'Optional modules must already be included in the approved prepared package.'
}
if ($PackagePath) {
  $preparedFile = Get-Item -LiteralPath $PackagePath -ErrorAction Stop
  if ($preparedFile.PSIsContainer -or ($preparedFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Prepared package must be an ordinary file.' }
  if ((Get-FileHash -LiteralPath $preparedFile.FullName -Algorithm SHA256).Hash -ine $ExpectedPackageSha256) { throw 'Prepared package SHA256 mismatch.' }
}

Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.MaesterHooks/Maester-SetupHelpers.psm1') -Force
if ([string]::IsNullOrWhiteSpace($TenantId)) { $TenantId = $env:AZURE_TENANT_ID }
if ([string]::IsNullOrWhiteSpace($TenantId)) {
  throw 'TenantId is required. Pass -TenantId or set AZURE_TENANT_ID to the expected tenant.'
}
# Fail before package preparation or module downloads, independently of the caller.
$target = Get-AzCliSubscriptionContext -SubscriptionId $SubscriptionId -TenantId $TenantId
$SubscriptionId = $target.id
$TenantId = $target.tenantId

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryPath = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { [IO.Path]::GetTempPath() } else { $env:TEMP }
$temporaryRoot = (Resolve-Path -LiteralPath $temporaryPath -ErrorAction Stop).ProviderPath
$generatedPackage = $null
if ($PackagePath) {
  $zipPath = $preparedFile.FullName
} else {
  $zipPath = Join-Path $temporaryRoot ("function-app-deploy-$([guid]::NewGuid().ToString('N')).zip")
  $generatedPackage = & (Join-Path $PSScriptRoot 'Build-FunctionPackage.ps1') -OutputPath $zipPath -IncludeExchange:$IncludeExchange -IncludeTeams:$IncludeTeams
}

$zipSizeKB = [math]::Round((Get-Item $zipPath).Length / 1024, 1)
Write-Host "Deployment package created: $zipPath ($zipSizeKB KB)"

function ConvertTo-PowerShellLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)
  "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-BoundedAzDeployment {
  param(
    [Parameter(Mandatory = $true)][string]$AzPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][ValidateRange(1, 3600)][int]$TimeoutSeconds
  )

  $pwshName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
  $pwshPath = Join-Path -Path $PSHOME -ChildPath $pwshName
  if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
    throw 'The current PowerShell executable could not be found.'
  }
  $useMsiPython = $false
  if ([IO.Path]::GetExtension($AzPath) -in '.cmd', '.bat') {
    $cliPython = [IO.Path]::GetFullPath((Join-Path (Split-Path $AzPath) '../python.exe'))
    if (Test-Path -LiteralPath $cliPython -PathType Leaf) {
      # Match the MSI launcher without passing deployment arguments through cmd.exe.
      $AzPath = $cliPython
      $Arguments = @('-IBm', 'azure.cli') + $Arguments
      $useMsiPython = $true
    }
    elseif ($AzPath -match '["%&|<>^!\r\n]' -or @($Arguments | Where-Object { $_ -match '["%&|<>^!()\r\n]' }).Count -gt 0) {
      # Parentheses remain valid in executable paths such as Program Files (x86).
      throw 'Azure CLI batch launcher or argument contains unsupported shell-expansion characters.'
    }
  }

  $literalArguments = @($Arguments | ForEach-Object { ConvertTo-PowerShellLiteral -Value $_ }) -join ' '
  $encodedScript = "`$ErrorActionPreference = 'Stop'`n& " + (ConvertTo-PowerShellLiteral -Value $AzPath) + ' ' + $literalArguments + "`n`$exitCode = `$LASTEXITCODE`nif (`$null -eq `$exitCode) { exit 1 }`nexit `$exitCode"
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($encodedScript))

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $pwshPath
  foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand)) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  if ($useMsiPython) { $startInfo.Environment['AZ_INSTALLER'] = 'MSI' }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.WorkingDirectory = (Get-Location).Path

  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  $started = $false
  $exited = $false
  $timedOut = $false
  $streamsDrained = $false
  $stdoutTask = $null
  $stderrTask = $null
  try {
    if (-not $process.Start()) { throw 'The Azure CLI deployment process could not be started.' }
    $started = $true
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $deadline = [Diagnostics.Stopwatch]::GetTimestamp() + [int64]($TimeoutSeconds * [Diagnostics.Stopwatch]::Frequency)
    while (-not $process.HasExited -and [Diagnostics.Stopwatch]::GetTimestamp() -lt $deadline) {
      Start-Sleep -Milliseconds 100
    }
    if (-not $process.HasExited) {
      $timedOut = $true
      try { $process.Kill($true) } catch { }
      $exited = $process.WaitForExit(5000)
    }
    else {
      $exited = $true
    }
    $stdoutComplete = $stdoutTask.Wait(5000)
    $stderrComplete = $stderrTask.Wait(5000)
    $streamsDrained = $stdoutComplete -and $stderrComplete
    $stdout = if ($stdoutComplete) { $stdoutTask.GetAwaiter().GetResult() } else { '' }
    $stderr = if ($stderrComplete) { $stderrTask.GetAwaiter().GetResult() } else { '' }
    [pscustomobject]@{
      ExitCode = if ($exited) { $process.ExitCode } else { $null }
      TimedOut = $timedOut
      StreamsTimedOut = -not $streamsDrained
      Output = @($stdout -split "`r?`n", 0) + @($stderr -split "`r?`n", 0)
    }
  }
  finally {
    if ($started -and -not $process.HasExited) {
      try { $process.Kill($true) } catch { }
      try { [void]$process.WaitForExit(2000) } catch { }
    }
    $process.Dispose()
  }
}

Write-Host "Deploying function code to '$FunctionAppName'..."
$azCommand = Get-Command az -CommandType Application -ErrorAction Stop | Select-Object -First 1
$azPath = [IO.Path]::GetFullPath([string]$azCommand.Source)
# Packaging can take time. Re-read ARM immediately before the ZIP mutation.
$null = Get-AzCliSubscriptionContext -SubscriptionId $SubscriptionId -TenantId $TenantId
if ($PackagePath -and (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ine $ExpectedPackageSha256) {
  throw 'Prepared package changed before deployment.'
}
$deployResult = Invoke-BoundedAzDeployment -AzPath $azPath -Arguments @(
  'functionapp', 'deployment', 'source', 'config-zip',
  '--subscription', $SubscriptionId,
  '--resource-group', $ResourceGroupName,
  '--name', $FunctionAppName,
  '--src', $zipPath,
  '--timeout', '300',
  '--output', 'none',
  '--only-show-errors'
) -TimeoutSeconds $DeploymentTimeoutSeconds
$deployOutput = $deployResult.Output
$deployExitCode = $deployResult.ExitCode
foreach ($line in $deployOutput) {
  $text = "$line"
  if ($text -match '^WARNING:\s*(.+)') {
    Write-Host "Deployment status: $($Matches[1])"
  } elseif ($text) {
    Write-Host $text
  }
}
if ($deployResult.TimedOut -or $deployResult.StreamsTimedOut -or $null -eq $deployExitCode) {
  throw "Function app ZIP deployment did not confirm completion before the local deadline. The remote deployment may still be active. Inspect its existing deployment before submitting another package. Preserved package: $zipPath"
}
if ($deployExitCode -ne 0) {
  # A CLI timeout can leave an active server deployment. Never upload another
  # package until that operation's actual result has been established.
  throw "Function app ZIP deployment did not confirm completion for '$FunctionAppName'. Inspect its existing deployment before submitting another package. Preserved package: $zipPath"
}

Write-Host "Function code deployed successfully to '$FunctionAppName'."

# Clean up temp artifacts
if ($null -ne $generatedPackage) { try {
  $temporaryPrefix = $temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  foreach ($target in @($zipPath, $generatedPackage.ManifestPath, $generatedPackage.StagingRoot)) {
    if (-not [IO.Path]::GetFullPath($target).StartsWith($temporaryPrefix, $comparison)) {
      throw 'Temporary artifact cleanup target is outside the selected temporary directory.'
    }
  }
  Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $generatedPackage.ManifestPath -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $generatedPackage.StagingRoot) {
    Remove-Item -LiteralPath $generatedPackage.StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
catch {
  Write-Verbose "Could not remove temporary deployment artifacts."
}
}
