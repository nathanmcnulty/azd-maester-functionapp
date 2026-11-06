BeforeAll {
  Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Maester.ValidationProtocol.psm1') -Force
}
Describe 'Immutable server execution ownership' {
  BeforeEach {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Maester.ValidationProtocol.psm1') -Force
    $now=[DateTimeOffset]'2026-10-22T03:00:00Z'
    $context=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=$now.AddMinutes(1).ToString('o')}
    $store=[Collections.Generic.Dictionary[string,string]]::new()
    $writer={param($uri,$token,$json) if($store.ContainsKey($uri)){throw 'HTTP412 existing immutable object'};$store.Add($uri,$json)}
    $parameters=@{Context=$context;InvocationId=[guid]'77777777-7777-4777-8777-777777777777';SourceDigest=$context.sourceSha256;ConfigurationDigest=$context.configurationSha256;SiteName=$context.siteName;StorageAccountName=$context.storageAccountName;TenantId=$context.tenantId;WorkloadIdentityId=$context.workloadIdentityId;RuntimeVersion='7.6';Token='synthetic';Now=$now;Writer=$writer}
  }
  It 'uses the real PowerShell runtime when the claim caller omits its version override' {
    $parameters.Remove('RuntimeVersion')
    (New-MaesterValidationClaim @parameters).status | Should -BeExactly 'Started'
    $store.Count | Should -Be 1
  }
  It 'creates one started claim and rejects both same and different invocation duplicates' {
    $claim=New-MaesterValidationClaim @parameters
    $claim.status|Should -BeExactly 'Started'
    {New-MaesterValidationClaim @parameters}|Should -Throw '*HTTP412*'
    $parameters.InvocationId=[guid]::NewGuid()
    {New-MaesterValidationClaim @parameters}|Should -Throw '*HTTP412*'
    $store.Count|Should -Be 1
  }
  It 'does not return execution ownership after a lost claim response' {
    $parameters.Writer={param($uri,$token,$json) $store.Add($uri,$json);throw 'lost response'}
    {New-MaesterValidationClaim @parameters}|Should -Throw '*lost response*'
    $store.Count|Should -Be 1
  }
  It 'rejects mismatched <Field> before writing a claim' -ForEach @(
    @{Field='SourceDigest';Value=('d'*64)},@{Field='ConfigurationDigest';Value=('d'*64)},@{Field='SiteName';Value='func-other'},@{Field='StorageAccountName';Value='stother'},@{Field='TenantId';Value='55555555-5555-4555-8555-555555555555'},@{Field='WorkloadIdentityId';Value='55555555-5555-4555-8555-555555555555'},@{Field='RuntimeVersion';Value='7.4'}
  ) {
    $parameters[$Field]=$Value
    {New-MaesterValidationClaim @parameters}|Should -Throw '*does not match*'
    $store.Count|Should -Be 0
  }
  It 'rejects an expired request without a claim' {
    $parameters.Now=$now.AddMinutes(2)
    {New-MaesterValidationClaim @parameters}|Should -Throw '*expired*'
    $store.Count|Should -Be 0
  }
  It 'prevents contradictory terminal overwrites' {
    $claim=New-MaesterValidationClaim @parameters
    Complete-MaesterValidationClaim -Claim $claim -Status Succeeded -StorageAccountName sttest -Token synthetic -Now $now.AddSeconds(1) -Writer $writer
    {Complete-MaesterValidationClaim -Claim $claim -Status Failed -StorageAccountName sttest -Token synthetic -Now $now.AddSeconds(2) -Writer $writer}|Should -Throw '*HTTP412*'
    $store.Count|Should -Be 2
    ($store['https://sttest.blob.core.windows.net/validation/'+$context.validationId+'.json']|ConvertFrom-Json).status|Should -BeExactly 'Succeeded'
  }
  It 'rejects scalar-to-array coercion and case alias JSON' {
    $context.siteName=@('func-test')
    {Assert-MaesterValidationContext $context}|Should -Throw '*scalar strings*'
    {ConvertFrom-MaesterValidationJson '{"validationId":"one","ValidationId":"two"}'}|Should -Throw '*duplicate*'
  }
  It 'writes bounded failure diagnostics in the same conditional terminal PUT without changing its v2 body' {
    $claim=New-MaesterValidationClaim @parameters
    $diagnostic=@{Counts=@{PassedCount=1;FailedCount=0;ErrorCount=1;InvestigateCount=0;SkippedCount=0;NotRunCount=0;TotalCount=2};ErrorTestIds=@('MT.1068');UniqueErrorTestIdCount=1;UnidentifiedErrorCount=0;PrivateMessage='must never serialize'}
    $captured=[Collections.Generic.List[object]]::new()
    # Other regression containers retain original-source fixture modules with
    # the same name. Give this exact source copy a unique mock boundary.
    $probePath=Join-Path $TestDrive ('ReceiptTransport'+[guid]::NewGuid().ToString('N')+'.psm1')
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Maester.ValidationProtocol.psm1') -Destination $probePath
    $probe=Import-Module $probePath -PassThru -Force
    Mock Invoke-WebRequest -ModuleName $probe.Name {
      param($Uri,$Method,$Headers,$Body)
      $captured.Add(@{uri=$Uri;method=$Method;headers=$Headers;body=[Text.Encoding]::UTF8.GetString($Body)})
    }
    try {
    & $probe { param($claim,$diagnostic,$time) Complete-MaesterValidationClaim -Claim $claim -Status Failed -StorageAccountName sttest -Token synthetic -FailureDiagnostic $diagnostic -FailureReason assessment.maesterErrors -Now $time } $claim $diagnostic $now.AddSeconds(1)
    $captured.Count | Should -Be 1
    $captured[0].headers['If-None-Match'] | Should -BeExactly '*'
    $captured[0].method | Should -BeExactly 'Put'
    $summary=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($captured[0].headers['x-ms-meta-maester_failure_diagnostic']))
    $summary | Should -Not -Match 'PrivateMessage|must never serialize|token|ScriptBlock'
    ($summary|ConvertFrom-Json).Counts.ErrorCount | Should -Be 1
    ($summary|ConvertFrom-Json).failureCode | Should -BeExactly 'assessment.maesterErrors'
    ($summary|ConvertFrom-Json).ErrorTestIds[0] | Should -BeExactly 'MT.1068'
    $body=$captured[0].body|ConvertFrom-Json -AsHashtable
    $body.Count | Should -Be 7
    $body.schemaVersion | Should -Be 2
    $body.status | Should -BeExactly 'Failed'
    $body.contextSha256 | Should -BeExactly $claim.contextSha256
    Should -Invoke Invoke-WebRequest -ModuleName $probe.Name -Times 1 -Exactly
    } finally { Remove-Module $probe -Force }
  }
  It 'retains only an unclassified code when a failure message has private contents' {
    $claim=New-MaesterValidationClaim @parameters
    $captured=[Collections.Generic.List[string]]::new()
    $diagnosticWriter={param($uri,$token,$json,$diagnosticJson) $captured.Add($diagnosticJson)}
    Complete-MaesterValidationClaim -Claim $claim -Status Failed -StorageAccountName sttest -Token synthetic -FailureReason 'private tenant token and request payload' -Writer $diagnosticWriter
    $captured.Count | Should -Be 1
    ($captured[0]|ConvertFrom-Json).failureCode | Should -BeExactly 'unclassified'
    $captured[0] | Should -Not -Match 'private|tenant|token|payload'
  }
  It 'forwards the runner diagnostic to its terminal writer exactly once in a fresh process' {
    $runner=Join-Path (Split-Path $PSScriptRoot -Parent) 'src/MaesterTimerTrigger/run.ps1'
    $ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$null,[ref]$null)
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-ValidationReceipt'},$true).Extent.Text
    $harness=@'
$ErrorActionPreference='Stop'
$validationClaim=@{status='Started'}
$script:validationTerminalAttempted=$false
$StorageAccountName='sttest'
$validationFailureDiagnostic=@{Value=@{Counts=@{ErrorCount=1}};Reason='assessment.maesterErrors'}
$script:attempts=0
function Get-PlainToken { param($ResourceUrl) 'synthetic' }
function Complete-MaesterValidationClaim {
 param($Claim,$Status,$StorageAccountName,$Token,$FailureDiagnostic,$FailureReason)
 $script:attempts++
 $script:seen=@{code=$FailureReason;errors=$FailureDiagnostic.Counts.ErrorCount}
}
'@ + [Environment]::NewLine + $definition + [Environment]::NewLine + @'
Write-ValidationReceipt -Status Failed
$blocked=$false
try { Write-ValidationReceipt -Status Failed } catch { $blocked=$_.Exception.Message -like 'Terminal evidence was already attempted*' }
@{attempts=$script:attempts;seen=$script:seen;secondAttemptBlocked=$blocked}|ConvertTo-Json -Compress
'@
    $path=Join-Path $TestDrive 'receipt-forwarding.ps1'
    Set-Content -LiteralPath $path -Value $harness
    $output=& pwsh -NoProfile -NonInteractive -File $path 2>&1
    $LASTEXITCODE | Should -Be 0
    $value=($output -join [Environment]::NewLine)|ConvertFrom-Json
    $value.attempts | Should -Be 1
    $value.seen.code | Should -BeExactly 'assessment.maesterErrors'
    $value.seen.errors | Should -Be 1
    $value.secondAttemptBlocked | Should -BeTrue
  }
  It 'rejects invalid metadata before any terminal write for <_>' -ForEach @('identifier','count','success','inconsistent','duplicate') {
    $claim=New-MaesterValidationClaim @parameters
    $diagnostic=@{Counts=@{PassedCount=1;FailedCount=0;ErrorCount=1;InvestigateCount=0;SkippedCount=0;NotRunCount=0;TotalCount=2};ErrorTestIds=@('MT.1068');UniqueErrorTestIdCount=1;UnidentifiedErrorCount=0}
    $status='Failed'
    switch($_){
      'identifier' {$diagnostic.ErrorTestIds=@('private-tenant-payload')}
      'count' {$diagnostic.Counts.ErrorCount='1'}
      'success' {$status='Succeeded'}
      'inconsistent' {$diagnostic.Counts.TotalCount=3}
      'duplicate' {$diagnostic.ErrorTestIds=@('MT.1068','MT.1068')}
    }
    {Complete-MaesterValidationClaim -Claim $claim -Status $status -StorageAccountName sttest -Token synthetic -FailureDiagnostic $diagnostic -Writer $writer}|Should -Throw '*diagnostic*'
    $store.Count | Should -Be 1
  }
  It 'detects a tampered file in a packaged source inventory' {
    $dir=Join-Path $TestDrive 'inventory';New-Item -ItemType Directory $dir|Out-Null
    Set-Content (Join-Path $dir 'run.ps1') 'source'
    $hash=(Get-FileHash (Join-Path $dir 'run.ps1')).Hash.ToLowerInvariant()
    @{schemaVersion=1;files=@(@{path='run.ps1';bytes=(Get-Item (Join-Path $dir 'run.ps1')).Length;sha256=$hash})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $dir 'validation-source.json')
    Get-MaesterValidationSourceDigest $dir|Should -Match '^[a-f0-9]{64}$'
    Add-Content (Join-Path $dir 'run.ps1') 'tampered'
    {Get-MaesterValidationSourceDigest $dir}|Should -Throw '*differs*'
  }
  It 'rejects an unlisted source file even when every listed hash matches' {
    $dir=Join-Path $TestDrive 'unlisted';New-Item -ItemType Directory $dir|Out-Null
    Set-Content (Join-Path $dir 'run.ps1') 'source'
    $file=Get-Item (Join-Path $dir 'run.ps1')
    @{schemaVersion=1;files=@(@{path='run.ps1';bytes=$file.Length;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant()})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $dir 'validation-source.json')
    Set-Content (Join-Path $dir 'unexpected.psm1') 'throw "must never execute"'
    {Get-MaesterValidationSourceDigest $dir}|Should -Throw '*unlisted*'
  }
  It 'hashes literal bracket and at-sign names from locked upstream packages' {
    $dir=Join-Path $TestDrive 'package-names';New-Item -ItemType Directory $dir|Out-Null
    foreach($name in @('[Content_Types].xml','@template.Testsps1.txt')){[IO.File]::WriteAllText((Join-Path $dir $name),'locked literal bytes')}
    $files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
    @{schemaVersion=1;files=$files}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $dir 'validation-source.json')
    Get-MaesterValidationSourceDigest $dir|Should -Match '^[a-f0-9]{64}$'
    [IO.File]::WriteAllText((Join-Path $dir '[Content_Types].xml'),'different literal bytes')
    {Get-MaesterValidationSourceDigest $dir}|Should -Throw
  }
}
