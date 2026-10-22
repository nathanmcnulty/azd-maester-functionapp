#Requires -Version 7.6
<#
.SYNOPSIS
Builds a source-bound Function ZIP without Azure authentication or deployment.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$PackageDirectory,
  [switch]$IncludeExchange,
  [switch]$IncludeTeams
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$srcPath=Join-Path $projectRoot 'src'
$sourceRoot=Get-Item -LiteralPath $srcPath -Force
if(-not $sourceRoot.PSIsContainer -or ($sourceRoot.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Function source requires an ordinary directory.'}
$zipPath=[IO.Path]::GetFullPath($OutputPath)
$manifestPath=$zipPath+'.manifest.json'
$parent=Get-Item -LiteralPath (Split-Path $zipPath -Parent) -ErrorAction Stop
if(-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Package output requires an existing ordinary parent directory.'}
foreach($path in @($zipPath,$manifestPath)){if(Test-Path -LiteralPath $path){throw 'Refusing to overwrite an existing package or manifest.'}}
foreach($name in @('host.json','requirements.psd1','profile.ps1','MaesterTimerTrigger/function.json','MaesterTimerTrigger/run.ps1')){
  if(-not (Test-Path -LiteralPath (Join-Path $srcPath $name) -PathType Leaf)){throw "Required Function source is missing: $name"}
}
$sourceItems=@(Get-ChildItem -LiteralPath $srcPath -Recurse -Force)
if(@($sourceItems|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Function source must not contain reparse points.'}
$sourceFiles=@($sourceItems|Where-Object {-not $_.PSIsContainer}|Sort-Object FullName|ForEach-Object {
  [ordered]@{path=[IO.Path]::GetRelativePath($projectRoot,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$lockPath=Join-Path $projectRoot 'runtime-packages.lock.json'
$lock=Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if($lock.schemaVersion -ne 1){throw 'Unsupported runtime package lock.'}
$moduleNames=@('Az.Accounts','Microsoft.Graph.Authentication','Maester','Pester','DnsClient-PS')
if($IncludeExchange){$moduleNames+=@('ExchangeOnlineManagement','PackageManagement','PowerShellGet')}
if($IncludeTeams){$moduleNames+='MicrosoftTeams'}
$packages=foreach($name in $moduleNames){
  $entry=@($lock.packages|Where-Object {$_.name -ceq $name})
  if($entry.Count -ne 1 -or $entry[0].version -notmatch '\A\d+(\.\d+){1,3}\z' -or $entry[0].sha256 -notmatch '\A[a-fA-F0-9]{64}\z'){throw "Invalid or missing locked package: $name"}
  $entry[0]
}
$temporaryPath=if([string]::IsNullOrWhiteSpace($env:TEMP)){[IO.Path]::GetTempPath()}else{$env:TEMP}
$temporaryRoot=(Resolve-Path -LiteralPath $temporaryPath).ProviderPath
$temporaryItem=Get-Item -LiteralPath $temporaryRoot -Force
if(-not $temporaryItem.PSIsContainer -or ($temporaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Package staging requires an ordinary temporary directory.'}
$buildRoot=Join-Path $temporaryRoot ('function-package-build-'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $buildRoot){throw 'Package staging already exists.'}
$stagingPath=Join-Path $buildRoot 'content'
$null=New-Item -ItemType Directory -Path $buildRoot
Copy-Item -LiteralPath $srcPath -Destination $stagingPath -Recurse -Force
$hostPath=Join-Path $stagingPath 'host.json'
$hostConfig=Get-Content -LiteralPath $hostPath -Raw | ConvertFrom-Json
$hostConfig.managedDependency=[pscustomobject]@{enabled=$false}
$hostConfig|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $hostPath -Encoding utf8
Set-Content -LiteralPath (Join-Path $stagingPath 'requirements.psd1') -Value '@{}' -Encoding utf8
if(-not $PackageDirectory){
  $PackageDirectory=Join-Path $buildRoot 'packages'
  $null=New-Item -ItemType Directory -Path $PackageDirectory
  foreach($package in $packages){
    $archive=Join-Path $PackageDirectory "$($package.name).$($package.version).nupkg"
    Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/$($package.name)/$($package.version)" -OutFile $archive -TimeoutSec 30 -MaximumRetryCount 0
  }
}
$modulesPath=Join-Path $stagingPath 'Modules'
$null=New-Item -ItemType Directory -Path $modulesPath
# The maintained installer removes a failed extraction target. Check every
# resolved target before invoking it; never adopt existing module directories.
$prefix=[IO.Path]::GetFullPath($modulesPath)+[IO.Path]::DirectorySeparatorChar
$comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
foreach($package in $packages){
  $target=[IO.Path]::GetFullPath((Join-Path (Join-Path $modulesPath $package.name) $package.version))
  if(-not $target.StartsWith($prefix,$comparison) -or (Test-Path -LiteralPath $target)){throw 'Unsafe or preexisting module extraction target.'}
}
& (Join-Path $PSScriptRoot 'Install-LockedModules.ps1') -LockPath $lockPath -DestinationRoot $modulesPath -PackageDirectory $PackageDirectory -PackageNames $moduleNames
if(-not $?){throw 'Locked module installation failed.'}
# Do not publish a manifest that silently binds files changed during packaging.
foreach($file in $sourceFiles){
  if((Get-FileHash -LiteralPath (Join-Path $projectRoot $file.path) -Algorithm SHA256).Hash -ine $file.sha256){throw 'Function source changed during package preparation; preserve staging for inspection.'}
}
$files=@(Get-ChildItem -LiteralPath $stagingPath -Recurse -File -Force|Sort-Object FullName|ForEach-Object {
  [ordered]@{path=[IO.Path]::GetRelativePath($stagingPath,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
# The internal inventory binds all packaged source and dependencies without a
# circular dependency on the containing ZIP hash. The external manifest binds both.
$inventoryPath=Join-Path $stagingPath 'validation-source.json'
if(Test-Path -LiteralPath $inventoryPath){throw 'Function source reserves validation-source.json for the package builder.'}
$inventoryJson=[ordered]@{schemaVersion=1;files=$files}|ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllText($inventoryPath,$inventoryJson,[Text.UTF8Encoding]::new($false))
$inventorySha=(Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
$files+= [ordered]@{path='validation-source.json';bytes=(Get-Item $inventoryPath).Length;sha256=$inventorySha}
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
    foreach($file in $files){
      $entry=$zip.CreateEntry($file.path,[IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
      $inputFile=[IO.File]::OpenRead((Join-Path $stagingPath $file.path))
      $output=$entry.Open()
      try{$inputFile.CopyTo($output)}finally{$output.Dispose();$inputFile.Dispose()}
    }
  }finally{$zip.Dispose()}
  $stream.Flush($true)
}finally{$stream.Dispose()}
$git=Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1
$commit=& $git.Source -C $projectRoot rev-parse HEAD
if($LASTEXITCODE -ne 0){throw 'Cannot identify package source commit; preserve the ZIP.'}
$dirty=@(& $git.Source -C $projectRoot status --porcelain --untracked-files=all)
if($LASTEXITCODE -ne 0){throw 'Cannot identify source working-tree state; preserve the ZIP.'}
$manifest=[ordered]@{schemaVersion=1;validationSourceSha256=$inventorySha;sourceCommit=$commit;sourceTreeClean=($dirty.Count -eq 0);runtimePackageLockSha256=(Get-FileHash $lockPath -Algorithm SHA256).Hash.ToLowerInvariant();componentLockSha256=(Get-FileHash (Join-Path $projectRoot 'azd-components.lock.json') -Algorithm SHA256).Hash.ToLowerInvariant();powershell=$PSVersionTable.PSVersion.ToString();dotnet=[Environment]::Version.ToString();includeExchange=[bool]$IncludeExchange;includeTeams=[bool]$IncludeTeams;packages=$packages;sourceFiles=$sourceFiles;files=$files;zipPath=$zipPath;zipBytes=(Get-Item $zipPath).Length;zipSha256=(Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant();stagingRoot=$buildRoot;azureAccessPerformed=$false;deploymentPerformed=$false}
$bytes=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 10))
$output=[IO.File]::Open($manifestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$output.Write($bytes);$output.Flush($true)}finally{$output.Dispose()}
[pscustomobject]@{ZipPath=$zipPath;ManifestPath=$manifestPath;Sha256=$manifest.zipSha256;StagingRoot=$buildRoot;AzureAccessPerformed=$false;DeploymentPerformed=$false}
