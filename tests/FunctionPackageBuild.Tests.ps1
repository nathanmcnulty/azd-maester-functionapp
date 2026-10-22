#Requires -Version 7.6

BeforeAll {
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $sourceBuilder = Join-Path $repoRoot 'scripts/Build-FunctionPackage.ps1'
  $sourceInstaller = Join-Path $repoRoot 'scripts/Install-LockedModules.ps1'
  $sourceDeploy = Join-Path $repoRoot 'scripts/Deploy-FunctionCode.ps1'
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  function New-SyntheticPackageFixture {
    param([Parameter(Mandatory)][string]$Root)

    $fixtureRepo = Join-Path $Root 'repo'
    $scripts = Join-Path $fixtureRepo 'scripts'
    $src = Join-Path $fixtureRepo 'src/MaesterTimerTrigger'
    $packages = Join-Path $Root 'packages'
    $output = Join-Path $Root 'output'
    $temp = Join-Path $Root 'temp'
    $null = New-Item -ItemType Directory -Path $scripts, $src, $packages, $output, $temp
    Copy-Item -LiteralPath $sourceBuilder -Destination $scripts
    Copy-Item -LiteralPath $sourceInstaller -Destination $scripts

    '{"version":"2.0","managedDependency":{"enabled":true}}' | Set-Content (Join-Path $fixtureRepo 'src/host.json')
    '@{ "Az" = "test" }' | Set-Content (Join-Path $fixtureRepo 'src/requirements.psd1')
    '# fixture profile' | Set-Content (Join-Path $fixtureRepo 'src/profile.ps1')
    '{"bindings":[]}' | Set-Content (Join-Path $src 'function.json')
    'Write-Output "fixture"' | Set-Content (Join-Path $src 'run.ps1')
    'source payload' | Set-Content (Join-Path $fixtureRepo 'src/fixture.txt')
    $hiddenSource = Join-Path $fixtureRepo 'src/.hidden-fixture'
    'hidden source payload' | Set-Content -LiteralPath $hiddenSource
    $hiddenItem = Get-Item -LiteralPath $hiddenSource -Force
    $hiddenItem.Attributes = $hiddenItem.Attributes -bor [IO.FileAttributes]::Hidden
    '{"components":[]}' | Set-Content (Join-Path $fixtureRepo 'azd-components.lock.json')

    $lockPackages = [Collections.Generic.List[object]]::new()
    foreach ($name in @('Az.Accounts','Microsoft.Graph.Authentication','Maester','Pester','DnsClient-PS')) {
      $version = '1.0.0'
      $packageSource = Join-Path $Root "package-$name"
      $null = New-Item -ItemType Directory -Path $packageSource
      "@{ RootModule = '$name.psm1'; ModuleVersion = '$version'; GUID = '00000000-0000-0000-0000-000000000001' }" |
        Set-Content -LiteralPath (Join-Path $packageSource "$name.psd1")
      $packageFile = Join-Path $packages "$name.$version.nupkg"
      [IO.Compression.ZipFile]::CreateFromDirectory($packageSource, $packageFile)
      $lockPackages.Add([ordered]@{
        name = $name
        version = $version
        sha256 = (Get-FileHash -LiteralPath $packageFile -Algorithm SHA256).Hash
      })
    }
    [ordered]@{ schemaVersion = 1; packages = @($lockPackages.ToArray()) } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRepo 'runtime-packages.lock.json')

    & git -C $fixtureRepo init --quiet
    & git -C $fixtureRepo -c user.name='Offline Test' -c user.email='offline@example.invalid' add --all
    & git -C $fixtureRepo -c user.name='Offline Test' -c user.email='offline@example.invalid' commit --quiet -m 'synthetic function fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated synthetic Git fixture.' }

    [pscustomobject]@{ Root=$Root; Repo=$fixtureRepo; Packages=$packages; Output=$output; Temp=$temp }
  }

  function Get-ZipEntryText {
    param([string]$ZipPath,[string]$EntryName)
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
      $entry = $archive.GetEntry($EntryName)
      if (-not $entry) { throw "ZIP entry missing: $EntryName" }
      $reader = [IO.StreamReader]::new($entry.Open())
      try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
  }
}

Describe 'Source-bound Function package builder' {
  It 'builds deterministic ZIP bytes with verified source, transformed configuration and locked modules' {
    $fixture = New-SyntheticPackageFixture -Root (Join-Path $TestDrive 'deterministic')
    $oldTemp = $env:TEMP
    $builder = Join-Path $fixture.Repo 'scripts/Build-FunctionPackage.ps1'
    try {
      $env:TEMP = $fixture.Temp
      $first = Join-Path $fixture.Output 'first.zip'
      $second = Join-Path $fixture.Output 'second.zip'
      $one = & $builder -OutputPath $first -PackageDirectory $fixture.Packages
      $two = & $builder -OutputPath $second -PackageDirectory $fixture.Packages
    } finally { $env:TEMP = $oldTemp }

    $one.Sha256 | Should -BeExactly $two.Sha256
    $manifest = Get-Content -LiteralPath $one.ManifestPath -Raw | ConvertFrom-Json
    $manifest.azureAccessPerformed | Should -BeFalse
    $manifest.deploymentPerformed | Should -BeFalse
    $manifest.sourceTreeClean | Should -BeTrue
    (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $manifest.zipSha256
    $archive = [IO.Compression.ZipFile]::OpenRead($first)
    try { $archive.Entries.Count | Should -Be $manifest.files.Count } finally { $archive.Dispose() }
    foreach ($source in $manifest.sourceFiles) {
      (Get-FileHash -LiteralPath (Join-Path $fixture.Repo ($source.path -replace '/', '\')) -Algorithm SHA256).Hash.ToLowerInvariant() |
        Should -BeExactly $source.sha256 -Because $source.path
    }
    (Get-ZipEntryText -ZipPath $first -EntryName 'host.json') | Should -Match '"enabled": false'
    (Get-ZipEntryText -ZipPath $first -EntryName 'requirements.psd1').Trim([char]0xFEFF).Trim() | Should -BeExactly '@{}'
    (Get-ZipEntryText -ZipPath $first -EntryName 'fixture.txt').Trim() | Should -BeExactly 'source payload'
    (Get-ZipEntryText -ZipPath $first -EntryName '.hidden-fixture').Trim() | Should -BeExactly 'hidden source payload'
    foreach ($package in $manifest.packages) {
      $moduleManifest = "$($package.name)/$($package.version)/$($package.name).psd1"
      $moduleText = Get-ZipEntryText -ZipPath $first -EntryName "Modules/$moduleManifest"
      $moduleText | Should -Not -BeNullOrEmpty
      $moduleText | Should -Match "ModuleVersion = '$($package.version)'"
    }
    foreach ($file in $manifest.files) {
      $archive = [IO.Compression.ZipFile]::OpenRead($first)
      try {
        $entry = $archive.GetEntry($file.path)
        $entry | Should -Not -BeNullOrEmpty
        $input = $entry.Open()
        $buffer = [IO.MemoryStream]::new()
        try { $input.CopyTo($buffer); $bytes = $buffer.ToArray() } finally { $input.Dispose(); $buffer.Dispose(); $archive.Dispose() }
        $actual = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $actual | Should -BeExactly $file.sha256 -Because $file.path
        $bytes.Length | Should -Be $file.bytes
      } finally { if ($archive) { $archive.Dispose() } }
    }
  }

  It 'rejects a bad locked archive before producing a ZIP or sidecar' {
    $fixture = New-SyntheticPackageFixture -Root (Join-Path $TestDrive 'bad-archive')
    $archive = Join-Path $fixture.Packages 'Az.Accounts.1.0.0.nupkg'
    [IO.File]::AppendAllText($archive, 'tampered')
    $output = Join-Path $fixture.Output 'bad.zip'
    $builder = Join-Path $fixture.Repo 'scripts/Build-FunctionPackage.ps1'
    $oldTemp = $env:TEMP
    try {
      $env:TEMP = $fixture.Temp
      { & $builder -OutputPath $output -PackageDirectory $fixture.Packages } |
        Should -Throw '*failed SHA-256 verification*'
    } finally { $env:TEMP = $oldTemp }
    (Test-Path -LiteralPath $output) | Should -BeFalse
    (Test-Path -LiteralPath "$output.manifest.json") | Should -BeFalse
  }

  It 'refuses to overwrite either an existing ZIP or its manifest' {
    $fixture = New-SyntheticPackageFixture -Root (Join-Path $TestDrive 'no-overwrite')
    $output = Join-Path $fixture.Output 'existing.zip'
    $builder = Join-Path $fixture.Repo 'scripts/Build-FunctionPackage.ps1'
    Set-Content -LiteralPath $output -Value 'preserve zip'
    $oldTemp = $env:TEMP
    try {
      $env:TEMP = $fixture.Temp
      { & $builder -OutputPath $output -PackageDirectory $fixture.Packages } |
        Should -Throw '*Refusing to overwrite*'
      $output | Should -Exist
      (Get-Content -LiteralPath $output -Raw).Trim() | Should -BeExactly 'preserve zip'
      Remove-Item -LiteralPath $output
      Set-Content -LiteralPath "$output.manifest.json" -Value 'preserve manifest'
      { & $builder -OutputPath $output -PackageDirectory $fixture.Packages } |
        Should -Throw '*Refusing to overwrite*'
      (Get-Content -LiteralPath "$output.manifest.json" -Raw).Trim() | Should -BeExactly 'preserve manifest'
      (Test-Path -LiteralPath $output) | Should -BeFalse
    } finally { $env:TEMP = $oldTemp }
  }

  It 'uses a bounded no-retry package request when the maintained builder downloads archives' {
    $fixture = New-SyntheticPackageFixture -Root (Join-Path $TestDrive 'download-contract')
    $global:FunctionPackageBuilderDownloadCalls = [Collections.Generic.List[object]]::new()
    $global:FunctionPackageBuilderFixturePackages = $fixture.Packages
    function global:Invoke-WebRequest {
      param([string]$Uri,[string]$OutFile,[int]$TimeoutSec,[int]$MaximumRetryCount)
      $global:FunctionPackageBuilderDownloadCalls.Add([pscustomobject]@{Uri=$Uri;TimeoutSec=$TimeoutSec;MaximumRetryCount=$MaximumRetryCount})
      $leaf = [IO.Path]::GetFileName($OutFile)
      Copy-Item -LiteralPath (Join-Path $global:FunctionPackageBuilderFixturePackages $leaf) -Destination $OutFile
    }
    $oldTemp = $env:TEMP
    try {
      $env:TEMP = $fixture.Temp
      $result = & (Join-Path $fixture.Repo 'scripts/Build-FunctionPackage.ps1') -OutputPath (Join-Path $fixture.Output 'downloaded.zip')
    } finally {
      $env:TEMP = $oldTemp
      Remove-Item Function:\global:Invoke-WebRequest -ErrorAction SilentlyContinue
      Remove-Variable FunctionPackageBuilderFixturePackages -Scope Global -ErrorAction SilentlyContinue
    }
    $global:FunctionPackageBuilderDownloadCalls.Count | Should -Be 5
    foreach ($call in $global:FunctionPackageBuilderDownloadCalls) {
      $call.TimeoutSec | Should -Be 30
      $call.MaximumRetryCount | Should -Be 0
    }
    $result.AzureAccessPerformed | Should -BeFalse
    $result.DeploymentPerformed | Should -BeFalse
  }

  It 'rejects mismatched prepared-package arguments and SHA before any provider call and preserves bytes' {
    $deployRoot = Join-Path $TestDrive 'prepared-deploy-source'
    $deployScripts = Join-Path $deployRoot 'scripts'
    $null = New-Item -ItemType Directory -Path $deployScripts
    Copy-Item -LiteralPath $sourceDeploy -Destination $deployScripts
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/vendor') -Destination $deployScripts -Recurse
    $package = Join-Path $TestDrive 'prepared.zip'
    [IO.File]::WriteAllBytes($package,[byte[]](1,2,3,4,5,6,7,8))
    $originalHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
    $global:FunctionPackageBuilderProviderCalls = 0
    function global:az { $global:FunctionPackageBuilderProviderCalls++; throw 'PROVIDER_TRIPWIRE' }
    try {
      { & (Join-Path $deployScripts 'Deploy-FunctionCode.ps1') -SubscriptionId '11111111-1111-4111-8111-111111111111' -TenantId '22222222-2222-4222-8222-222222222222' -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -PackagePath $package } |
        Should -Throw '*must be supplied together*'
      { & (Join-Path $deployScripts 'Deploy-FunctionCode.ps1') -SubscriptionId '11111111-1111-4111-8111-111111111111' -TenantId '22222222-2222-4222-8222-222222222222' -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -PackagePath $package -ExpectedPackageSha256 ('0' * 64) } |
        Should -Throw '*SHA256 mismatch*'
    } finally { Remove-Item Function:\global:az -ErrorAction SilentlyContinue }
    $global:FunctionPackageBuilderProviderCalls | Should -Be 0
    (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash | Should -BeExactly $originalHash
  }
}
