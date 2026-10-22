#Requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../src/Maester.ValidationProtocol.psm1') -Force

function Write-MaesterValidationRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12 -Compress))
  $file=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try { $file.Write($bytes); $file.Flush($true) } finally { $file.Dispose() }
}

function Assert-MaesterValidationEvidence {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][ValidateSet('Claim','Terminal')][string]$Kind,$Claim)
  $names=@('schemaVersion','validationId','invocationId','contextSha256','status','startedAt')
  if($Kind -eq 'Terminal'){$names+='completedAt'}
  if($Value -isnot [Collections.IDictionary] -or $Value.Count -ne $names.Count){throw 'Malformed validation evidence.'}
  foreach($name in $names){if(-not $Value.Contains($name)){throw 'Missing validation evidence field.'}}
  if(($Value.schemaVersion -isnot [int] -and $Value.schemaVersion -isnot [long]) -or $Value.schemaVersion -ne 2){throw 'Invalid validation evidence schema.'}
  foreach($name in $names|Where-Object{$_ -ne 'schemaVersion'}){if($Value[$name] -isnot [string]){throw 'Validation evidence fields must be scalar strings.'}}
  $invocation=[guid]::Empty
  $hash=Get-MaesterValidationHash (Get-MaesterValidationContextJson $Context)
  if($Value.validationId -cne $Context.validationId -or $Value.contextSha256 -cne $hash -or -not [guid]::TryParseExact($Value.invocationId,'D',[ref]$invocation) -or $invocation -eq [guid]::Empty -or $invocation.ToString('D') -cne $Value.invocationId){throw 'Conflicting validation evidence identity.'}
  $start=[DateTimeOffset]::MinValue
  if(-not [DateTimeOffset]::TryParseExact($Value.startedAt,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$start) -or $start.Offset -ne [TimeSpan]::Zero -or $start -ge [DateTimeOffset]::Parse($Context.deadlineUtc)){throw 'Invalid validation start timestamp.'}
  if($Kind -eq 'Claim'){
    if($Value.status -cne 'Started'){throw 'Invalid validation claim state.'}
  }else{
    if($null -eq $Claim -or $Value.invocationId -cne $Claim.invocationId -or $Value.startedAt -cne $Claim.startedAt -or $Value.status -cnotin @('Succeeded','Failed')){throw 'Terminal validation evidence conflicts with the owning claim.'}
    $end=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParseExact($Value.completedAt,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$end) -or $end.Offset -ne [TimeSpan]::Zero -or $end -lt $start){throw 'Invalid validation completion timestamp.'}
  }
  $true
}

function Assert-MaesterValidationTargetSnapshot {
  param([Parameter(Mandatory)]$Subscription,[Parameter(Mandatory)]$Site,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Binding,[switch]$ReconcileOnly)
  $subscriptionId=$Binding.subscriptionId
  if($Subscription -isnot [Collections.IDictionary]){throw 'Invalid subscription metadata shape.'}
  foreach($field in @('id','subscriptionId','tenantId','state')){if($Subscription[$field] -isnot [string]){throw 'Subscription metadata fields must be scalar strings.'}}
  if($Subscription.id -ine "/subscriptions/$subscriptionId" -or $Subscription.subscriptionId -cne $subscriptionId -or $Subscription.tenantId -cne $Context.tenantId -or $Subscription.state -cne 'Enabled'){throw 'Subscription identity, tenant or Enabled state differs.'}
  $siteId="/subscriptions/$subscriptionId/resourceGroups/$($Binding.resourceGroupName)/providers/Microsoft.Web/sites/$($Context.siteName)"
  if($Site -isnot [Collections.IDictionary] -or $Site.properties -isnot [Collections.IDictionary] -or $Site.identity -isnot [Collections.IDictionary] -or $Site.id -isnot [string] -or $Site.id -ine $siteId -or $Site.kind -isnot [string] -or $Site.kind -notlike '*functionapp*' -or $Site.properties.state -isnot [string] -or $Site.identity.principalId -isnot [string] -or $Site.identity.principalId -cne $Context.workloadIdentityId){throw 'Function target differs from its binding.'}
  if(-not $ReconcileOnly -and $Site.properties.state -cne 'Running'){throw 'New validation requires the exact Function to be Running.'}
  if($Site.properties.functionAppConfig -isnot [Collections.IDictionary] -or $Site.properties.functionAppConfig.deployment -isnot [Collections.IDictionary]){throw 'Missing Flex deployment binding.'}
  $deployment=$Site.properties.functionAppConfig.deployment.storage
  $url="https://$($Context.storageAccountName).blob.core.windows.net/deploymentpackage"
  if($deployment -isnot [Collections.IDictionary] -or $deployment.authentication -isnot [Collections.IDictionary] -or $deployment.type -isnot [string] -or $deployment.type -cne 'blobContainer' -or $deployment.value -isnot [string] -or $deployment.value -cne $url -or $deployment.authentication.type -isnot [string] -or $deployment.authentication.type -cne 'SystemAssignedIdentity'){throw 'Function deployment storage differs from the reviewed binding.'}
  $true
}

function Invoke-MaesterValidationSession {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][Collections.IDictionary]$Binding,
    [Parameter(Mandatory)][string]$ReceiptPath,[switch]$ReconcileOnly,
    [Parameter(Mandatory)][scriptblock]$ValidateTarget,[Parameter(Mandatory)][scriptblock]$Submit,
    [Parameter(Mandatory)][scriptblock]$ReadEvidence,
    [scriptblock]$Clock={ [DateTimeOffset]::UtcNow },[scriptblock]$Delay={param($seconds) Start-Sleep -Seconds $seconds}
  )
  $contextJson=Get-MaesterValidationContextJson $Context
  $intent=[ordered]@{schemaVersion=2;context=$Context;binding=$Binding;contextSha256=(Get-MaesterValidationHash $contextJson)}
  $intentJson=$intent|ConvertTo-Json -Depth 12 -Compress
  $submissionPath=$ReceiptPath+'.submission.json'
  $outcomePath=$ReceiptPath+'.outcome.'+[guid]::NewGuid().ToString('N')+'.json'
  $deadline=[DateTimeOffset]::ParseExact($Context.deadlineUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
  if($ReconcileOnly){
    $saved=Get-Content -LiteralPath $ReceiptPath -Raw|ConvertFrom-Json -AsHashtable -DateKind String
    if(($saved|ConvertTo-Json -Depth 12 -Compress) -cne $intentJson){throw 'Saved validation intent differs from this exact binding.'}
    if(-not (Test-Path -LiteralPath $submissionPath -PathType Leaf)){throw 'No possible submission was recorded; reconciliation cannot submit.'}
    $marker=Get-Content -LiteralPath $submissionPath -Raw|ConvertFrom-Json -AsHashtable -DateKind String
    if($marker.contextSha256 -cne $intent.contextSha256 -or $marker.submissionPossible -isnot [bool] -or -not $marker.submissionPossible){throw 'Invalid saved submission checkpoint.'}
  }else{
    if((& $Clock) -ge $deadline){throw 'Validation deadline has expired before submission.'}
    # Both durable writes must succeed before a provider mutation is possible.
    Write-MaesterValidationRecord $ReceiptPath $intent
    & $ValidateTarget
    Write-MaesterValidationRecord $submissionPath ([ordered]@{schemaVersion=2;contextSha256=$intent.contextSha256;submissionPossible=$true;recordedUtc=(& $Clock).ToUniversalTime().ToString('o')})
    if((& $Clock) -ge $deadline){throw 'Validation deadline expired before the single submission; preserve its intent.'}
    try { & $Submit $contextJson | Out-Null } catch { Write-Verbose 'Single submission response was inconclusive; reconciling the same identity without replay.' }
  }
  $claim=$null
  $terminal=$null
  $errorKind=$null
  try{
    # One final read after expiry allows a later ReconcileOnly call to report a
    # late terminal result. It does not extend execution or acceptance deadlines.
    do{
      & $ValidateTarget
      $candidate=& $ReadEvidence 'Claim' $Context.validationId
      if($null -ne $candidate){
        Assert-MaesterValidationEvidence $candidate $Context Claim | Out-Null
        if($null -ne $claim -and ($claim|ConvertTo-Json -Compress) -cne ($candidate|ConvertTo-Json -Compress)){throw 'Validation claim changed.'}
        $claim=$candidate
      }
      $candidate=& $ReadEvidence 'Terminal' $Context.validationId
      if($null -ne $candidate){Assert-MaesterValidationEvidence $candidate $Context Terminal $claim|Out-Null;$terminal=$candidate;break}
      $remaining=($deadline-(& $Clock)).TotalSeconds
      if($remaining -le 0){break}
      & $Delay ([Math]::Min(5,[Math]::Ceiling($remaining)))
    }while((& $Clock) -lt $deadline)
  }catch{$errorKind='EvidenceOrTargetRejected'}
  $complete=$null -ne $terminal
  $onTime=$complete -and [DateTimeOffset]::Parse($terminal.completedAt) -le $deadline
  $result=[ordered]@{ValidationId=$Context.validationId;ContextSha256=$intent.contextSha256;SubmissionPossible=$true;ExecutionComplete=$complete;InvocationTerminalConfirmed=$complete;AppStoppedConfirmed=$false;ValidationPassed=($onTime -and $terminal.status -ceq 'Succeeded');FinalStatus=$(if($complete){$terminal.status}elseif($errorKind){$errorKind}else{'Unresolved'});CompletedWithinDeadline=$onTime;DeadlineUtc=$Context.deadlineUtc;ReconcileOnly=[bool]$ReconcileOnly;Claim=$claim;Terminal=$terminal}
  Write-MaesterValidationRecord $outcomePath $result
  [pscustomobject]$result
}

Export-ModuleMember -Function Write-MaesterValidationRecord,Assert-MaesterValidationEvidence,Assert-MaesterValidationTargetSnapshot,Invoke-MaesterValidationSession
