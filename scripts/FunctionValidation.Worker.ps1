#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try {
  $inputValue=[Console]::In.ReadToEnd()
  Add-Type -Path (Join-Path $PSScriptRoot 'FunctionValidation.Transport.cs')
  [AzdMaesterValidation.BoundedIO]::ValidateJsonObject($inputValue)
  $inputData=$inputValue|ConvertFrom-Json -AsHashtable -DateKind String
  $request=$inputData.request
  $context=$request.context
  $binding=$request.binding
  Import-Module (Join-Path $PSScriptRoot 'FunctionValidation.Session.psm1') -Force
  Import-Module (Join-Path $PSScriptRoot '../src/Maester.ValidationProtocol.psm1') -Force
  Assert-MaesterValidationContext $context|Out-Null
  if($binding.Count -ne 8 -or $binding.transport -cne 'QueueStorage' -or $binding.queueName -cne 'maester-validation' -or $binding.queueEncoding -cne 'base64'){throw 'Unexpected validation transport or binding fields.'}
  foreach($key in @('subscriptionId','resourceGroupName','operatorObjectId','packageETag','selectorETag','transport','queueName','queueEncoding')){
    if($binding[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($binding[$key])){throw 'Invalid validation binding.'}
  }
  foreach($key in @('subscriptionId','operatorObjectId')){
    $id=[guid]::Empty
    if(-not [guid]::TryParseExact($binding[$key],'D',[ref]$id) -or $id -eq [guid]::Empty){throw 'Invalid validation identity.'}
  }
  if($binding.resourceGroupName -cnotmatch '\A[a-zA-Z0-9_.()-]{1,90}\z'){throw 'Invalid resource group binding.'}
  $subscription=$binding.subscriptionId
  $siteId="/subscriptions/$subscription/resourceGroups/$($binding.resourceGroupName)/providers/Microsoft.Web/sites/$($context.siteName)"
  $arm='https://management.azure.com'
  $blob="https://$($context.storageAccountName).blob.core.windows.net"
  $allowed=@(($arm+"/subscriptions/${subscription}?api-version=2022-12-01"),($arm+$siteId+'?api-version=2024-04-01'),($arm+$siteId+'/config/appsettings/list?api-version=2024-04-01'),($blob+'/deploymentpackage/kudu-state.json'),($blob+'/deploymentpackage/released-package.zip'),($blob+"/validation/$($context.validationId).claim.json"),($blob+"/validation/$($context.validationId).json"))
  function Get-ValidationToken([string]$Resource){
    $json=[AzdMaesterValidation.BoundedIO]::Run((Get-Process -Id $PID).Path,(Join-Path $PSScriptRoot 'FunctionValidation.Cli.ps1'),(@{resource=$Resource;subscriptionId=$subscription}|ConvertTo-Json -Compress),30).GetAwaiter().GetResult()
    [AzdMaesterValidation.BoundedIO]::ValidateJsonObject($json)
    $value=$json|ConvertFrom-Json -AsHashtable -DateKind String
    if($value.accessToken -isnot [string]){throw 'Missing token.'}
    $parts=$value.accessToken.Split('.')
    if($parts.Count -ne 3){throw 'Unverifiable token identity.'}
    $part=$parts[1].Replace('-','+').Replace('_','/');$part=$part.PadRight($part.Length+((4-$part.Length%4)%4),'=')
    $claims=[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($part))|ConvertFrom-Json -AsHashtable -DateKind String
    $audiences=if($Resource -ceq 'https://storage.azure.com/'){@('https://storage.azure.com/','https://storage.azure.com')}else{@('https://management.azure.com/','https://management.azure.com','https://management.core.windows.net/')}
    if($claims.oid -isnot [string] -or $claims.tid -isnot [string] -or $claims.aud -isnot [string] -or $claims.aud -cnotin $audiences -or $claims.oid -cne $binding.operatorObjectId -or $claims.tid -cne $context.tenantId){throw 'Operator, tenant or audience mismatch.'}
    $value.accessToken
  }
  $armToken=Get-ValidationToken 'https://management.azure.com/'
  $storageToken=Get-ValidationToken 'https://storage.azure.com/'
  function Send-ValidationRequest([string]$Method,[string]$Uri,[string]$Token,$Body,[bool]$XmlBody=$false){
    $queuePattern='\Ahttps://'+[regex]::Escape($context.queueStorageAccountName)+'\.queue\.core\.windows\.net/maester-validation/messages\?messagettl=([1-9][0-9]{0,3})\z'
    $queueMatch=[regex]::Match($Uri,$queuePattern,[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    $isQueueRequest=$Method -ceq 'POST' -and $XmlBody -and $queueMatch.Success -and [int]$queueMatch.Groups[1].Value -le 7200
    if($Uri -cnotin $allowed -and -not $isQueueRequest){throw 'Request target is outside the validation binding.'}
    $remaining=([DateTimeOffset]::Parse($context.deadlineUtc)-[DateTimeOffset]::UtcNow).TotalSeconds
    if($Method -ceq 'POST' -and $remaining -le 0){throw 'No POST is allowed after the absolute validation deadline.'}
    $seconds=if($remaining -gt 0){[Math]::Max(1,[Math]::Min(30,[Math]::Floor($remaining)))}else{30}
    [AzdMaesterValidation.BoundedIO]::Send($Method,[uri]$Uri,$Token,$Body,[int]$seconds,$XmlBody).GetAwaiter().GetResult()
  }
  function Read-ValidationObject($Response){
    if($Response.StatusCode -ne 200){throw 'Validation read was not HTTP200.'}
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($Response.Bytes)
    [AzdMaesterValidation.BoundedIO]::ValidateJsonObject($json)
    $json|ConvertFrom-Json -AsHashtable -DateKind String
  }
  $validateTarget={
    $native=Read-ValidationObject (Send-ValidationRequest GET $allowed[0] $armToken $null)
    $site=Read-ValidationObject (Send-ValidationRequest GET $allowed[1] $armToken $null)
    Assert-MaesterValidationTargetSnapshot -Subscription $native -Site $site -Context $context -Binding $binding -ReconcileOnly:([bool]$inputData.reconcileOnly)|Out-Null
  }
  $submit={param($contextJson)
    # Strong ETags bind the already hashed private package capture to the current
    # deployment selector. This read does not infer package identity from a name.
    $selectorResponse=Send-ValidationRequest GET $allowed[3] $storageToken $null
    if($selectorResponse.ETag -cne $binding.selectorETag){throw 'Deployment selector ETag changed.'}
    $selector=Read-ValidationObject $selectorResponse
    if($selector -isnot [Collections.IDictionary] -or $selector.Deployments -isnot [Collections.IDictionary] -or $selector.ActiveDeploymentId -isnot [string] -or $selector.LatestDeploymentId -isnot [string]){throw 'Invalid deployment selector shape.'}
    if($selector.ActiveDeploymentId -cne $context.activeDeploymentId -or $selector.LatestDeploymentId -cne $context.activeDeploymentId){throw 'Active deployment changed.'}
    $entry=$selector.Deployments[$context.activeDeploymentId]
    if($entry -isnot [Collections.IDictionary] -or $entry.Id -isnot [string] -or $entry.Id -cne $context.activeDeploymentId -or $entry.UploadedPackageName -isnot [string] -or ($entry.Status -isnot [string] -and $entry.Status -isnot [int] -and $entry.Status -isnot [long])){throw 'Invalid deployment entry shape.'}
    if($entry.Complete -isnot [bool] -or -not $entry.Complete -or $entry.UploadedPackageName -cne 'released-package.zip' -or [string]$entry.Status -cne '4'){throw 'Active deployment is not complete.'}
    $package=Send-ValidationRequest HEAD $allowed[4] $storageToken $null
    if($package.StatusCode -ne 200 -or $package.ETag -cne $binding.packageETag){throw 'Active package ETag changed.'}
    foreach($uri in @($allowed[5],$allowed[6])){
      $existing=Send-ValidationRequest GET $uri $storageToken $null
      if($existing.StatusCode -ne 404){throw 'Validation identity already exists or cannot be established unused.'}
    }
    # This sensitive read remains in memory and establishes the host queue
    # account independently of report/deployment storage. Never print settings.
    $settings=Read-ValidationObject (Send-ValidationRequest POST $allowed[2] $armToken '{}')
    try{
      if($settings.properties -isnot [Collections.IDictionary] -or (Get-MaesterValidationHostQueueAccount $settings.properties) -cne $context.queueStorageAccountName){throw 'Actual host queue account differs from the reviewed target.'}
    }finally{$settings=$null}
    & $validateTarget
    $message=Get-MaesterValidationQueueMessage $context
    $response=Send-ValidationRequest POST $message.uri $storageToken $message.body $true
    if($response.StatusCode -ne 201){throw 'Single queue submission response was not HTTP201.'}
  }
  $readEvidence={param($kind,$id)
    $uri=if($kind -ceq 'Claim'){$allowed[5]}else{$allowed[6]}
    $response=Send-ValidationRequest GET $uri $storageToken $null
    if($response.StatusCode -eq 404){return $null}
    $value=Read-ValidationObject $response
    # Evidence has a smaller bound than generic ARM responses.
    if($response.Bytes.Length -gt 16384){throw 'Evidence exceeds its bound.'}
    $value
  }
  $result=Invoke-MaesterValidationSession -Context $context -Binding $binding -ReceiptPath $inputData.receiptPath -ReconcileOnly:([bool]$inputData.reconcileOnly) -ValidateTarget $validateTarget -Submit $submit -ReadEvidence $readEvidence
  [Console]::Out.Write(($result|ConvertTo-Json -Depth 12 -Compress))
}catch{[Console]::Error.Write('Validation worker rejected the request or failed; preserve intent and reconcile without resubmission.');exit 1}
