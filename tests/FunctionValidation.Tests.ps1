BeforeAll {
  $root=Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $root 'scripts/FunctionValidation.Session.psm1') -Force
  Import-Module (Join-Path $root 'src/Maester.ValidationProtocol.psm1') -Force
  function New-TestValidationContext {
    [ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=([DateTimeOffset]'2026-10-22T03:01:00Z').ToString('o')}
  }
}

Describe 'Native target and keyless queue binding' {
  BeforeEach {
    $context=New-TestValidationContext
    $binding=@{subscriptionId='55555555-5555-4555-8555-555555555555';resourceGroupName='rg-test'}
    $subscription=@{id='/subscriptions/'+$binding.subscriptionId;subscriptionId=$binding.subscriptionId;tenantId=$context.tenantId;state='Enabled'}
    $site=@{id="/subscriptions/$($binding.subscriptionId)/resourceGroups/rg-test/providers/Microsoft.Web/sites/func-test";kind='functionapp,linux';identity=@{principalId=$context.workloadIdentityId};properties=@{state='Running';functionAppConfig=@{deployment=@{storage=@{type='blobContainer';value='https://sttest.blob.core.windows.net/deploymentpackage';authentication=@{type='SystemAssignedIdentity'}}}}}}
  }
  It 'accepts the exact Flex site and its separately bound deployment storage' {
    Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding|Should -BeTrue
  }
  It 'rejects the wrong deployment <Field> before submission' -ForEach @(@{Field='value';Value='https://stother.blob.core.windows.net/deploymentpackage'},@{Field='type';Value='other'}) {
    $site.properties.functionAppConfig.deployment.storage[$Field]=$Value
    {Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding}|Should -Throw '*deployment storage*'
  }
  It 'rejects deployment authentication changes and scalar-to-array provider coercion' {
    $site.properties.functionAppConfig.deployment.storage.authentication.type='StorageAccountConnectionString'
    {Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding}|Should -Throw
    $site.properties.functionAppConfig.deployment.storage.authentication.type='SystemAssignedIdentity'
    $site.identity.principalId=@($context.workloadIdentityId)
    {Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding}|Should -Throw
  }
  It 'allows read-only reconciliation of the exact stopped site but forbids a new submission' {
    $site.properties.state='Stopped'
    Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding -ReconcileOnly|Should -BeTrue
    {Assert-MaesterValidationTargetSnapshot $subscription $site $context $binding}|Should -Throw '*Running*'
  }
  It 'encodes one canonical context in a deadline-bound base64 queue message' {
    $message=Get-MaesterValidationQueueMessage $context -Now ([DateTimeOffset]'2026-10-22T03:00:00Z')
    $message.ttlSeconds|Should -Be 60
    $message.uri|Should -BeExactly 'https://sthost.queue.core.windows.net/maester-validation/messages?messagettl=60'
    $xml=[xml]$message.body
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($xml.QueueMessage.MessageText))|Should -BeExactly (Get-MaesterValidationContextJson $context)
  }
  It 'refuses a zero or negative queue lifetime rather than using a default expiry' {
    {Get-MaesterValidationQueueMessage $context -Now ([DateTimeOffset]'2026-10-22T03:00:59.500Z')}|Should -Throw '*lifetime*'
    {Get-MaesterValidationQueueMessage $context -Now ([DateTimeOffset]'2026-10-22T03:02:00Z')}|Should -Throw '*lifetime*'
  }
  It 'derives host queue account independently from an existing secret connection without returning the secret' {
    $settings=@{AzureWebJobsStorage='DefaultEndpointsProtocol=https;AccountName=sthost;AccountKey=synthetic-not-a-credential;EndpointSuffix=core.windows.net'}
    Get-MaesterValidationHostQueueAccount $settings|Should -BeExactly 'sthost'
    $settings.AzureWebJobsStorage+=';QueueEndpoint=https://stother.queue.core.windows.net'
    {Get-MaesterValidationHostQueueAccount $settings}|Should -Throw
  }
  It 'accepts a supported keyless host account and rejects ambiguous missing account configuration' {
    Get-MaesterValidationHostQueueAccount @{AzureWebJobsStorage__accountName='sthost'}|Should -BeExactly 'sthost'
    {Get-MaesterValidationHostQueueAccount @{AzureWebJobsStorage__accountName=@('sthost')}}|Should -Throw
    {Get-MaesterValidationHostQueueAccount @{STORAGE_ACCOUNT_NAME='sttest'}}|Should -Throw
  }
}
Describe 'Durable single-submit validation and reconciliation' {
  BeforeEach {
    $context=New-TestValidationContext
    $binding=[ordered]@{subscriptionId='55555555-5555-4555-8555-555555555555';resourceGroupName='rg-test';operatorObjectId='66666666-6666-4666-8666-666666666666'}
    $state=@{now=[DateTimeOffset]'2026-10-22T03:00:00Z';posts=0;checks=0;claim=$null;terminal=$null}
    $path=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
    $parameters=@{Context=$context;Binding=$binding;ReceiptPath=$path;Clock={ $state.now };Delay={param($seconds) $state.now=$state.now.AddSeconds($seconds)};ValidateTarget={$state.checks++};Submit={param($json) $state.posts++};ReadEvidence={param($kind,$id) if($kind -eq 'Claim'){$state.claim}else{$state.terminal}}}
    $claim=[ordered]@{schemaVersion=2;validationId=$context.validationId;invocationId='77777777-7777-4777-8777-777777777777';contextSha256=(Get-MaesterValidationHash (Get-MaesterValidationContextJson $context));status='Started';startedAt=$state.now.ToString('o')}
    $terminal=[ordered]@{};foreach($key in $claim.Keys){$terminal[$key]=$claim[$key]};$terminal.status='Succeeded';$terminal.completedAt=$state.now.AddSeconds(1).ToString('o')
  }
  It 'keeps an uncertain accepted POST to one submission and reconciles its terminal evidence' {
    $parameters.Submit={param($json) $state.posts++;$state.claim=$claim;$state.terminal=$terminal;throw 'lost response after acceptance'}
    $result=Invoke-MaesterValidationSession @parameters
    $state.posts|Should -Be 1
    $result.ValidationPassed|Should -BeTrue
    $result.InvocationTerminalConfirmed|Should -BeTrue
    $result.AppStoppedConfirmed|Should -BeFalse
    (Get-Content ($path+'.submission.json') -Raw|ConvertFrom-Json).submissionPossible|Should -BeTrue
  }
  It 'never submits when the durable intent cannot be created' {
    Set-Content -LiteralPath $path 'preserve'
    {Invoke-MaesterValidationSession @parameters}|Should -Throw
    $state.posts|Should -Be 0
    (Get-Content $path -Raw).Trim()|Should -BeExactly 'preserve'
  }
  It 'never submits when the pre-submission checkpoint cannot be created' {
    Set-Content -LiteralPath ($path+'.submission.json') 'preserve'
    {Invoke-MaesterValidationSession @parameters}|Should -Throw
    $state.posts|Should -Be 0
  }
  It 'stops on fresh target rejection before the checkpoint and POST' {
    $parameters.ValidateTarget={throw 'subscription disabled'}
    {Invoke-MaesterValidationSession @parameters}|Should -Throw '*disabled*'
    $state.posts|Should -Be 0
    Test-Path ($path+'.submission.json')|Should -BeFalse
  }
  It 'records missing evidence as unresolved without claiming cancellation' {
    $result=Invoke-MaesterValidationSession @parameters
    $state.posts|Should -Be 1
    $result.FinalStatus|Should -BeExactly 'Unresolved'
    $result.ExecutionComplete|Should -BeFalse
    $result.AppStoppedConfirmed|Should -BeFalse
    $state.now|Should -Be ([DateTimeOffset]::Parse($context.deadlineUtc))
  }
  It 'reconciles later evidence without POST or a deadline extension' {
    $first=Invoke-MaesterValidationSession @parameters
    $state.claim=$claim;$state.terminal=$terminal
    $state.terminal.completedAt=$state.now.AddSeconds(10).ToString('o')
    $state.now=$state.now.AddSeconds(20)
    $result=Invoke-MaesterValidationSession @parameters -ReconcileOnly
    $state.posts|Should -Be 1
    $result.ExecutionComplete|Should -BeTrue
    $result.CompletedWithinDeadline|Should -BeFalse
    $result.ValidationPassed|Should -BeFalse
    $result.DeadlineUtc|Should -BeExactly $context.deadlineUtc
  }
  It 'rejects changed saved bindings without resubmission' {
    $first=Invoke-MaesterValidationSession @parameters
    $binding.resourceGroupName='rg-other'
    {Invoke-MaesterValidationSession @parameters -ReconcileOnly}|Should -Throw '*differs*'
    $state.posts|Should -Be 1
  }
  It 'does not accept a terminal receipt from a conflicting invocation' {
    $state.claim=$claim;$state.terminal=$terminal
    $state.terminal.invocationId=[guid]::NewGuid().ToString('D')
    $result=Invoke-MaesterValidationSession @parameters
    $result.FinalStatus|Should -BeExactly 'EvidenceOrTargetRejected'
    $result.ValidationPassed|Should -BeFalse
    $result.InvocationTerminalConfirmed|Should -BeFalse
  }
  It 'does not accept terminal evidence without its immutable claim' {
    $state.terminal=$terminal
    $result=Invoke-MaesterValidationSession @parameters
    $result.FinalStatus|Should -BeExactly 'EvidenceOrTargetRejected'
  }
  It 'separates a failed but terminal execution from assessment acceptance' {
    $state.claim=$claim;$state.terminal=$terminal;$state.terminal.status='Failed'
    $result=Invoke-MaesterValidationSession @parameters
    $result.ExecutionComplete|Should -BeTrue
    $result.ValidationPassed|Should -BeFalse
    $result.FinalStatus|Should -BeExactly 'Failed'
  }
  It 'refuses the previous implicit GUID invocation entrypoint before provider work' {
    { & (Join-Path $root 'scripts/Invoke-FunctionValidation.ps1') -SubscriptionId $binding.subscriptionId -TenantId $context.tenantId -ResourceGroupName $binding.resourceGroupName -FunctionAppName $context.siteName -StorageAccountName $context.storageAccountName }|Should -Throw '*reviewed RequestPath*'
  }
}
