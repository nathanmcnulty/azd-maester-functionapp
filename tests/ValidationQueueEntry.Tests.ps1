BeforeAll {
  $script:repo=Split-Path $PSScriptRoot -Parent
  $script:fixture=Join-Path $TestDrive 'queue-entry'
  New-Item -ItemType Directory (Join-Path $script:fixture 'MaesterValidationTrigger'),(Join-Path $script:fixture 'MaesterTimerTrigger')|Out-Null
  Copy-Item (Join-Path $script:repo 'src/MaesterValidationTrigger/run.ps1') (Join-Path $script:fixture 'MaesterValidationTrigger')
  Copy-Item (Join-Path $script:repo 'src/Maester.ValidationProtocol.psm1') $script:fixture
  @'
param($Timer,$TriggerMetadata,[Collections.IDictionary]$ValidationContext,[switch]$RequireValidationContext)
[IO.File]::WriteAllText($env:QUEUE_ENTRY_MARKER,($ValidationContext|ConvertTo-Json -Depth 8))
[IO.File]::WriteAllText(($env:QUEUE_ENTRY_MARKER+'.required'),[string]$RequireValidationContext.IsPresent)
'@|Set-Content (Join-Path $script:fixture 'MaesterTimerTrigger/run.ps1')
  $script:probe=Join-Path $script:fixture 'probe.ps1'
  @'
param($Entry,$Payload,$Marker,$Kind)
$ErrorActionPreference='Continue'
$env:QUEUE_ENTRY_MARKER=$Marker
$value=[IO.File]::ReadAllBytes($Payload)
if($Kind -eq 'Object'){$value=Get-Content $Payload -Raw|ConvertFrom-Json -AsHashtable}
& $Entry -ValidationRequest $value -TriggerMetadata @{sys=@{MethodName='MaesterValidationTrigger'}}
if(Test-Path $Marker){exit 23}
exit 0
'@|Set-Content $script:probe
  $script:valid=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')}
}

Describe 'Actual queue entrypoint rejects failed admission before assessment' {
  It 'requests raw bytes from the queue binding to preserve JSON without worker object conversion' {
    $config=Get-Content (Join-Path $script:repo 'src/MaesterValidationTrigger/function.json') -Raw|ConvertFrom-Json
    ($config.bindings|Where-Object name -eq 'ValidationRequest').dataType|Should -BeExactly 'binary'
  }
  It 'does not reach the shared runner under a Continue caller for <Mode>' -ForEach @(
    @{Mode='Malformed';Kind='Bytes'},@{Mode='ObjectCoercion';Kind='Object'},@{Mode='InvalidShape';Kind='Bytes'},@{Mode='DuplicateKey';Kind='Bytes'},@{Mode='InvalidUtf8';Kind='Bytes'},@{Mode='Oversized';Kind='Bytes'}
  ) {
    $payload=Join-Path $TestDrive ($Mode+'.json');$marker=Join-Path $TestDrive ($Mode+'.marker')
    $json=switch($Mode){Malformed {'not-json'};ObjectCoercion {$script:valid|ConvertTo-Json -Depth 8};InvalidShape {'{}'};DuplicateKey {'{"schemaVersion":2,"SchemaVersion":2}'}}
    if($Mode -eq 'InvalidUtf8'){[IO.File]::WriteAllBytes($payload,[byte[]]@(255,254,255))}
    elseif($Mode -eq 'Oversized'){[IO.File]::WriteAllBytes($payload,[byte[]]::new(16385))}
    else{Set-Content $payload $json}
    $output=& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $script:probe (Join-Path $script:fixture 'MaesterValidationTrigger/run.ps1') $payload $marker $Kind 2>&1
    $LASTEXITCODE|Should -BeIn @(0,1) -Because ($output -join [Environment]::NewLine)
    Test-Path $marker|Should -BeFalse
  }
  It 'forwards a valid raw context unchanged to the shared assessment' {
    $payload=Join-Path $TestDrive 'valid.json';$marker=Join-Path $TestDrive 'valid.marker'
    $script:valid|ConvertTo-Json -Depth 8|Set-Content $payload
    $output=& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $script:probe (Join-Path $script:fixture 'MaesterValidationTrigger/run.ps1') $payload $marker 'Bytes' 2>&1
    $LASTEXITCODE|Should -Be 23 -Because ($output -join [Environment]::NewLine)
    $read=Get-Content $marker -Raw|ConvertFrom-Json -AsHashtable -DateKind String
    ($read|ConvertTo-Json -Compress)|Should -BeExactly ($script:valid|ConvertTo-Json -Compress)
    Get-Content ($marker+'.required') -Raw|Should -BeExactly 'True'
  }
  It 'rejects a missing required context in the actual shared runner before module or identity work' {
    $folder=Join-Path $TestDrive 'core-guard';New-Item -ItemType Directory $folder|Out-Null
    Copy-Item (Join-Path $script:repo 'src/MaesterTimerTrigger/run.ps1') $folder
    @'
param($Core)
$ErrorActionPreference='Continue'
& $Core -Timer @{IsPastDue=$false} -TriggerMetadata @{} -RequireValidationContext
exit 0
'@|Set-Content (Join-Path $folder 'probe.ps1')
    $output=& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File (Join-Path $folder 'probe.ps1') (Join-Path $folder 'run.ps1') 2>&1
    $LASTEXITCODE|Should -Be 1
    ($output -join [Environment]::NewLine)|Should -Match 'Validation context is required before assessment'
    ($output -join [Environment]::NewLine)|Should -Not -Match 'Importing core modules|Connecting with managed identity|Running Invoke-Maester'
  }
}
