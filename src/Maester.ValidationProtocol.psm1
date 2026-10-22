#Requires -Version 7.6
Set-StrictMode -Version Latest

function Get-MaesterValidationHash {
  param([Parameter(Mandatory)][string]$Text)
  [Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}

function ConvertFrom-MaesterValidationJson {
  param([Parameter(Mandatory)][string]$Json)
  if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 16384) { throw 'Validation JSON exceeds its bound.' }
  $document = [Text.Json.JsonDocument]::Parse($Json)
  try {
    if ($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Validation JSON must be an object.' }
    # The protocol is deliberately flat. Reject case aliases before PowerShell
    # conversion can turn a duplicate name into an apparent trusted value.
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($field in $document.RootElement.EnumerateObject()) {
      if (-not $names.Add($field.Name) -or $field.Value.ValueKind -in @([Text.Json.JsonValueKind]::Object,[Text.Json.JsonValueKind]::Array)) {
        throw 'Validation JSON contains duplicate names or structured values.'
      }
    }
    $Json | ConvertFrom-Json -AsHashtable -DateKind String
  } finally { $document.Dispose() }
}

function Assert-MaesterValidationContext {
  param([Parameter(Mandatory)]$Context)
  $keys = @('schemaVersion','validationId','siteName','storageAccountName','queueStorageAccountName','sourceSha256','configurationSha256','packageSha256','activeDeploymentId','tenantId','workloadIdentityId','runtimeVersion','deadlineUtc')
  if ($Context -isnot [Collections.IDictionary] -or $Context.Count -ne $keys.Count) { throw 'Invalid validation context shape.' }
  foreach ($key in $keys) { if (-not $Context.Contains($key)) { throw 'Missing validation context field.' } }
  if ($Context.schemaVersion -isnot [long] -and $Context.schemaVersion -isnot [int]) { throw 'Invalid validation schema type.' }
  if ($Context.schemaVersion -ne 2) { throw 'Unsupported validation schema.' }
  foreach ($key in $keys | Where-Object { $_ -ne 'schemaVersion' }) {
    if ($Context[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Context[$key])) { throw 'Validation context fields must be scalar strings.' }
  }
  foreach ($key in @('validationId','activeDeploymentId','tenantId','workloadIdentityId')) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParseExact($Context[$key], 'D', [ref]$parsed) -or $parsed -eq [guid]::Empty -or $parsed.ToString('D') -cne $Context[$key]) { throw 'Invalid canonical validation identity.' }
  }
  if ($Context.siteName -cnotmatch '\A[a-z0-9][a-z0-9-]{0,58}[a-z0-9]\z' -or $Context.storageAccountName -cnotmatch '\A[a-z0-9]{3,24}\z' -or $Context.queueStorageAccountName -cnotmatch '\A[a-z0-9]{3,24}\z') { throw 'Invalid validation target.' }
  foreach ($key in @('sourceSha256','configurationSha256','packageSha256')) {
    if ($Context[$key] -cnotmatch '\A[a-f0-9]{64}\z') { throw 'Invalid validation digest.' }
  }
  if ($Context.runtimeVersion -cne '7.6') { throw 'Validation requires the reviewed PowerShell 7.6 runtime.' }
  $deadline = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParseExact($Context.deadlineUtc, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$deadline) -or $deadline.Offset -ne [TimeSpan]::Zero) { throw 'Invalid absolute validation deadline.' }
  $true
}

function Get-MaesterValidationContextJson {
  param([Parameter(Mandatory)]$Context)
  Assert-MaesterValidationContext $Context | Out-Null
  $canonical = [ordered]@{}
  foreach ($key in @('schemaVersion','validationId','siteName','storageAccountName','queueStorageAccountName','sourceSha256','configurationSha256','packageSha256','activeDeploymentId','tenantId','workloadIdentityId','runtimeVersion','deadlineUtc')) { $canonical[$key] = $Context[$key] }
  $canonical | ConvertTo-Json -Compress
}

function Get-MaesterValidationSourceDigest {
  param([Parameter(Mandatory)][string]$Root)
  $base = (Resolve-Path -LiteralPath $Root).ProviderPath
  $rootItem=Get-Item -LiteralPath $base -Force
  if(-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid validation package root.'}
  $manifestPath = Join-Path $base 'validation-source.json'
  $manifestItem=Get-Item -LiteralPath $manifestPath -Force
  if($manifestItem.PSIsContainer -or ($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $manifestItem.Length -gt 1MB){throw 'Invalid packaged source inventory file.'}
  $text=[IO.File]::ReadAllText($manifestPath,[Text.UTF8Encoding]::new($false,$true))
  $document=[Text.Json.JsonDocument]::Parse($text)
  try{
    function Assert-InventoryNames($Element){
      if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($field in $Element.EnumerateObject()){if(-not $seen.Add($field.Name)){throw 'Duplicate inventory JSON field.'};Assert-InventoryNames $field.Value}
      }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($elementValue in $Element.EnumerateArray()){Assert-InventoryNames $elementValue}}
    }
    Assert-InventoryNames $document.RootElement
    if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Invalid inventory JSON root.'}
  }finally{$document.Dispose()}
  $manifest = $text | ConvertFrom-Json -AsHashtable -DateKind String
  if ($manifest.Count -ne 2 -or -not $manifest.Contains('schemaVersion') -or -not $manifest.Contains('files') -or ($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long]) -or $manifest.schemaVersion -ne 1 -or $manifest.files -isnot [array] -or $manifest.files.Count -lt 1 -or $manifest.files.Count -gt 10000) { throw 'Invalid packaged validation source inventory.' }
  $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($file in $manifest.files) {
    if($file -isnot [Collections.IDictionary] -or $file.Count -ne 3 -or -not $file.Contains('path') -or -not $file.Contains('bytes') -or -not $file.Contains('sha256') -or ($file.bytes -isnot [int] -and $file.bytes -isnot [long]) -or $file.bytes -lt 0 -or $file.bytes -gt 100MB){throw 'Invalid packaged source inventory entry shape.'}
    if ($file.path -isnot [string] -or $file.path -cnotmatch '\A[a-zA-Z0-9_@.\[\]-]+(/[a-zA-Z0-9_@.\[\]-]+)*\z' -or @($file.path.Split('/') | Where-Object { $_ -in @('.','..') }).Count -or -not $names.Add($file.path) -or $file.path -ceq 'validation-source.json' -or $file.sha256 -isnot [string] -or $file.sha256 -cnotmatch '\A[a-f0-9]{64}\z') { throw 'Invalid packaged source inventory entry.' }
    $target = Join-Path $base $file.path
    $targetItem=Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if($targetItem.PSIsContainer -or $targetItem.Length -ne $file.bytes){throw 'Deployed source length differs from inventory.'}
    $cursor = $targetItem
    while ($cursor.FullName -ne $base) {
      if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Validation source cannot contain reparse points.' }
      $cursor = Get-Item -LiteralPath (Split-Path $cursor.FullName -Parent) -Force
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { throw 'Deployed validation source does not match its packaged inventory.' }
  }
  $actual=@(Get-ChildItem -LiteralPath $base -Recurse -Force)
  if(@($actual|Where-Object{$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Validation source cannot contain reparse points.'}
  $actualFiles=@($actual|Where-Object{-not $_.PSIsContainer -and $_.FullName -cne $manifestPath})
  if($actualFiles.Count -ne $names.Count){throw 'Deployed source contains unlisted or missing files.'}
  foreach($file in $actualFiles){if(-not $names.Contains([IO.Path]::GetRelativePath($base,$file.FullName).Replace('\','/'))){throw 'Deployed source contains an unlisted file.'}}

  (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-MaesterValidationHostQueueAccount {
  param([Parameter(Mandatory)][Collections.IDictionary]$Settings)
  $account=$null
  if($Settings.Contains('AzureWebJobsStorage') -and -not [string]::IsNullOrWhiteSpace($Settings['AzureWebJobsStorage'])){
    if($Settings['AzureWebJobsStorage'] -isnot [string]){throw 'Invalid host storage setting type.'}
    try{
      $connection=[Data.Common.DbConnectionStringBuilder]::new()
      $connection.set_ConnectionString($Settings['AzureWebJobsStorage'])
      if(-not $connection.ContainsKey('AccountName') -or -not $connection.ContainsKey('DefaultEndpointsProtocol') -or $connection['DefaultEndpointsProtocol'] -cne 'https' -or ($connection.ContainsKey('EndpointSuffix') -and $connection['EndpointSuffix'] -cne 'core.windows.net')){throw 'Unqualified host storage connection.'}
      $account=$connection['AccountName']
      if($connection.ContainsKey('QueueEndpoint') -and $connection['QueueEndpoint'].TrimEnd('/') -cne "https://$account.queue.core.windows.net"){throw 'Unqualified host queue endpoint.'}
    }catch{throw 'Host storage connection does not identify a supported public Azure queue account.'}
  }elseif($Settings.Contains('AzureWebJobsStorage__accountName')){
    $account=$Settings['AzureWebJobsStorage__accountName']
    if($Settings.Contains('AzureWebJobsStorage__queueServiceUri') -and $Settings['AzureWebJobsStorage__queueServiceUri'] -cne "https://$account.queue.core.windows.net"){throw 'Host queue endpoint differs from its account.'}
  }
  if($account -isnot [string] -or $account -cnotmatch '\A[a-z0-9]{3,24}\z'){throw 'Host queue account could not be independently established.'}
  $account
}

function Get-MaesterValidationQueueMessage {
  param([Parameter(Mandatory)]$Context,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
  $json=Get-MaesterValidationContextJson $Context
  $ttl=[Math]::Floor(([DateTimeOffset]::ParseExact($Context.deadlineUtc,'o',[Globalization.CultureInfo]::InvariantCulture)-$Now).TotalSeconds)
  if($ttl -lt 1 -or $ttl -gt 7200){throw 'Queue message lifetime must fit the original absolute validation deadline.'}
  $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
  [ordered]@{uri="https://$($Context.queueStorageAccountName).queue.core.windows.net/maester-validation/messages?messagettl=$ttl";body="<QueueMessage><MessageText>$base64</MessageText></QueueMessage>";ttlSeconds=[int]$ttl}
}

function Get-MaesterValidationConfigurationDigest {
  param([Parameter(Mandatory)][Collections.IDictionary]$Settings)
  $values = [ordered]@{}
  foreach ($name in @('STORAGE_ACCOUNT_NAME','INCLUDE_AZURE','INCLUDE_EXCHANGE','INCLUDE_TEAMS','MAIL_RECIPIENT','WEB_APP_NAME','WEB_APP_RESOURCE_GROUP_NAME','AzureWebJobs.MaesterTimerTrigger.Disabled','WEBSITE_SITE_NAME','FUNCTIONS_WORKER_RUNTIME','FUNCTIONS_WORKER_RUNTIME_VERSION')) {
    if (-not $Settings.Contains($name) -or $null -eq $Settings[$name]) { $values[$name] = $null }
    elseif ($Settings[$name] -is [string]) { $values[$name] = $Settings[$name] }
    else { throw 'Configuration values must be scalar strings or null.' }
  }
  Get-MaesterValidationHash ($values | ConvertTo-Json -Compress)
}

function Send-MaesterValidationEvidence {
  param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$Token,[Parameter(Mandatory)][string]$Json)
  # Never retry: an unknown PUT outcome must preserve the request identity.
  $headers = @{Authorization="Bearer $Token";'x-ms-version'='2023-11-03';'x-ms-blob-type'='BlockBlob';'If-None-Match'='*'}
  Invoke-WebRequest -Uri $Uri -Method Put -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($Json)) -ContentType 'application/json' -TimeoutSec 30 -MaximumRetryCount 0 -MaximumRedirection 0 -ErrorAction Stop | Out-Null
}

function New-MaesterValidationClaim {
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][guid]$InvocationId,
    [Parameter(Mandatory)][string]$SourceDigest,[Parameter(Mandatory)][string]$ConfigurationDigest,
    [Parameter(Mandatory)][string]$SiteName,[Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$WorkloadIdentityId,[string]$RuntimeVersion = ($PSVersionTable.PSVersion.ToString(2)),
    [Parameter(Mandatory)][string]$Token,[DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
    [scriptblock]$Writer = { param($uri,$token,$json) Send-MaesterValidationEvidence -Uri $uri -Token $token -Json $json }
  )
  $json = Get-MaesterValidationContextJson $Context
  if ($InvocationId -eq [guid]::Empty -or $Context.siteName -cne $SiteName -or $Context.storageAccountName -cne $StorageAccountName -or $Context.tenantId -cne $TenantId -or $Context.workloadIdentityId -cne $WorkloadIdentityId -or $Context.runtimeVersion -cne $RuntimeVersion -or $Context.sourceSha256 -cne $SourceDigest -or $Context.configurationSha256 -cne $ConfigurationDigest) { throw 'Validation execution context does not match this host.' }
  $deadline = [DateTimeOffset]::ParseExact($Context.deadlineUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
  if ($Now -ge $deadline) { throw 'Validation deadline has already expired; no claim or assessment is allowed.' }
  $claim = [ordered]@{schemaVersion=2;validationId=$Context.validationId;invocationId=$InvocationId.ToString('D');contextSha256=(Get-MaesterValidationHash $json);status='Started';startedAt=$Now.ToUniversalTime().ToString('o')}
  & $Writer "https://$StorageAccountName.blob.core.windows.net/validation/$($Context.validationId).claim.json" $Token ($claim | ConvertTo-Json -Compress)
  # Return only after the conditional write has conclusively succeeded. A 412,
  # timeout or disconnected response never confers execution ownership.
  $claim
}

function Complete-MaesterValidationClaim {
  param([Parameter(Mandatory)][Collections.IDictionary]$Claim,[Parameter(Mandatory)][ValidateSet('Succeeded','Failed')][string]$Status,[Parameter(Mandatory)][string]$StorageAccountName,[Parameter(Mandatory)][string]$Token,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
    [scriptblock]$Writer = { param($uri,$token,$json) Send-MaesterValidationEvidence -Uri $uri -Token $token -Json $json })
  if ($Claim.status -cne 'Started') { throw 'Only the owning started claim can publish terminal evidence.' }
  $receipt = [ordered]@{}
  foreach ($key in @('schemaVersion','validationId','invocationId','contextSha256','startedAt')) { $receipt[$key]=$Claim[$key] }
  $receipt.status=$Status
  $receipt.completedAt=$Now.ToUniversalTime().ToString('o')
  & $Writer "https://$StorageAccountName.blob.core.windows.net/validation/$($Claim.validationId).json" $Token ($receipt | ConvertTo-Json -Compress)
}

Export-ModuleMember -Function Get-MaesterValidationHash,ConvertFrom-MaesterValidationJson,Assert-MaesterValidationContext,Get-MaesterValidationContextJson,Get-MaesterValidationSourceDigest,Get-MaesterValidationHostQueueAccount,Get-MaesterValidationQueueMessage,Get-MaesterValidationConfigurationDigest,New-MaesterValidationClaim,Complete-MaesterValidationClaim
