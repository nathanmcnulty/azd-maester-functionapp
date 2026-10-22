BeforeAll {
  Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Maester.ValidationProtocol.psm1') -Force
}
Describe 'Immutable server execution ownership' {
  BeforeEach {
    $now=[DateTimeOffset]'2026-10-22T03:00:00Z'
    $context=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=$now.AddMinutes(1).ToString('o')}
    $store=[Collections.Generic.Dictionary[string,string]]::new()
    $writer={param($uri,$token,$json) if($store.ContainsKey($uri)){throw 'HTTP412 existing immutable object'};$store.Add($uri,$json)}
    $parameters=@{Context=$context;InvocationId=[guid]'77777777-7777-4777-8777-777777777777';SourceDigest=$context.sourceSha256;ConfigurationDigest=$context.configurationSha256;SiteName=$context.siteName;StorageAccountName=$context.storageAccountName;TenantId=$context.tenantId;WorkloadIdentityId=$context.workloadIdentityId;RuntimeVersion='7.6';Token='synthetic';Now=$now;Writer=$writer}
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
