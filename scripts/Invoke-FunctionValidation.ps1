#Requires -Version 7.6
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SubscriptionId,
  [string]$TenantId,
  [Parameter(Mandatory)][string]$ResourceGroupName,
  [string]$FunctionAppName,
  [string]$StorageAccountName,
  [ValidateRange(1,120)][int]$TimeoutMinutes=15,
  [string]$RequestPath,
  [string]$ReceiptPath,
  [switch]$ReconcileOnly,
  [switch]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $RequestPath -or -not $ReceiptPath){throw 'Validation requires a reviewed RequestPath and durable ReceiptPath; automatic GUID submission is disabled.'}
Add-Type -Path (Join-Path $PSScriptRoot 'FunctionValidation.Transport.cs')
Import-Module (Join-Path $PSScriptRoot '../src/Maester.ValidationProtocol.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'FunctionValidation.Session.psm1') -Force
$info=Get-Item -LiteralPath $RequestPath -Force
if($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $info.Length -gt 65536){throw 'Invalid validation request file.'}
$json=[IO.File]::ReadAllText($info.FullName,[Text.UTF8Encoding]::new($false,$true))
[AzdMaesterValidation.BoundedIO]::ValidateJsonObject($json)
$request=$json|ConvertFrom-Json -AsHashtable -DateKind String
Assert-MaesterValidationContext $request.context|Out-Null
if($request.Count -ne 4 -or ($request.schemaVersion -isnot [int] -and $request.schemaVersion -isnot [long]) -or $request.schemaVersion -ne 2 -or $request.binding -isnot [Collections.IDictionary] -or $request.packagePath -isnot [string]){throw 'Invalid reviewed request shape.'}
$package=Get-Item -LiteralPath $request.packagePath -Force
if($package.PSIsContainer -or ($package.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $package.Length -gt 100MB -or (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $request.context.packageSha256){throw 'Reviewed local package identity differs.'}
$archive=[IO.Compression.ZipFile]::OpenRead($package.FullName)
try{
  $entries=@($archive.Entries|Where-Object FullName -CEQ 'validation-source.json')
  if($entries.Count -ne 1 -or $entries[0].Length -gt 1MB){throw 'Missing or oversized packaged source inventory.'}
  $stream=$entries[0].Open();$memory=[IO.MemoryStream]::new()
  try{
    $buffer=[byte[]]::new(8192)
    while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){if($memory.Length+$read -gt 1MB){throw 'Packaged inventory exceeds its bound.'};$memory.Write($buffer,0,$read)}
    $digest=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($memory.ToArray()))
    if($digest -cne $request.context.sourceSha256){throw 'Reviewed package and execution inventory differ.'}
  }finally{$stream.Dispose();$memory.Dispose()}
}finally{$archive.Dispose()}
if(-not $TenantId){$TenantId=$env:AZURE_TENANT_ID}
if(-not $FunctionAppName){$FunctionAppName=$env:FUNCTION_APP_NAME}
if(-not $StorageAccountName){$StorageAccountName=$env:STORAGE_ACCOUNT_NAME}
if($request.binding.subscriptionId -cne $SubscriptionId -or $request.binding.resourceGroupName -cne $ResourceGroupName -or $request.context.tenantId -cne $TenantId -or $request.context.siteName -cne $FunctionAppName -or $request.context.storageAccountName -cne $StorageAccountName){throw 'Reviewed validation request does not match the explicit target.'}
$deadline=[DateTimeOffset]::ParseExact($request.context.deadlineUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
$remaining=($deadline-[DateTimeOffset]::UtcNow).TotalSeconds
if(-not $ReconcileOnly -and ($remaining -le 0 -or $remaining -gt $TimeoutMinutes*60)){throw 'Absolute reviewed deadline must be within the selected overall timeout.'}
$receipt=[IO.Path]::GetFullPath($ReceiptPath)
$parent=Get-Item -LiteralPath (Split-Path $receipt -Parent) -Force
if(-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Receipt parent must be an ordinary existing directory.'}
$inputJson=[ordered]@{request=$request;receiptPath=$receipt;reconcileOnly=[bool]$ReconcileOnly}|ConvertTo-Json -Depth 12 -Compress
$bound=[Math]::Min(7500,[Math]::Max(120,[Math]::Ceiling($remaining)+120))
try{
  $output=[AzdMaesterValidation.BoundedIO]::Run((Get-Process -Id $PID).Path,(Join-Path $PSScriptRoot 'FunctionValidation.Worker.ps1'),$inputJson,[int]$bound).GetAwaiter().GetResult()
  [AzdMaesterValidation.BoundedIO]::ValidateJsonObject($output)
  $result=$output|ConvertFrom-Json -AsHashtable -DateKind String
}catch{
  Write-MaesterValidationRecord ($receipt+'.supervisor.'+[guid]::NewGuid().ToString('N')+'.json') ([ordered]@{schemaVersion=2;validationId=$request.context.validationId;workerConclusive=$false;invocationTerminalConfirmed=$false;appStoppedConfirmed=$false;replayPermitted=$false;observedUtc=[DateTimeOffset]::UtcNow.ToString('o')})
  throw 'Validation worker failed or timed out. Execution is unresolved; preserve the intent and use ReconcileOnly. No cancellation or app-stop is implied.'
}
if($PassThru){return [pscustomobject]$result}
if(-not $result.ValidationPassed){throw 'Validation did not pass. Inspect the durable outcome; unresolved execution requires the separately approved containment procedure.'}
Write-Host "Validation request '$($request.context.validationId)' completed within its reviewed deadline."
