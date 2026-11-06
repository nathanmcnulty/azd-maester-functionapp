BeforeAll {
  $script:repo=Split-Path $PSScriptRoot -Parent
  $script:probe=Join-Path $TestDrive 'controller-probe.ps1'
  @'
param($Controller,$Request,$Receipt)
$ErrorActionPreference='Stop'
try {
  & $Controller -SubscriptionId '55555555-5555-4555-8555-555555555555' -TenantId '33333333-3333-4333-8333-333333333333' -ResourceGroupName 'rg-different' -FunctionAppName 'func-test' -StorageAccountName 'sttest' -RequestPath $Request -ReceiptPath $Receipt
  exit 9
}catch{[Console]::Out.Write($_.Exception.Message);exit 7}
'@ | Set-Content $script:probe
}

Describe 'Actual controller command visibility in a fresh process' {
  It 'reaches the explicit target guard after nested module imports without provider I/O' {
    $dir=Join-Path $TestDrive 'package';New-Item -ItemType Directory $dir|Out-Null
    $inventory=Join-Path $dir 'validation-source.json';Set-Content $inventory '{}'
    $zip=Join-Path $TestDrive 'package.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($dir,$zip)
    $context=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=(Get-FileHash $inventory).Hash.ToLowerInvariant();configurationSha256=('b'*64);packageSha256=(Get-FileHash $zip).Hash.ToLowerInvariant();activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')}
    $request=Join-Path $TestDrive 'request.json';$receipt=Join-Path $TestDrive 'receipt.json'
    @{schemaVersion=2;context=$context;binding=@{subscriptionId='55555555-5555-4555-8555-555555555555';resourceGroupName='rg-reviewed'};packagePath=$zip}|ConvertTo-Json -Depth 8|Set-Content $request
    $output=& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $script:probe (Join-Path $script:repo 'scripts/Invoke-FunctionValidation.ps1') $request $receipt 2>&1
    $LASTEXITCODE|Should -Be 7
    ($output -join [Environment]::NewLine)|Should -BeExactly 'Reviewed validation request does not match the explicit target.'
    Test-Path $receipt|Should -BeFalse
    Test-Path ($receipt+'.submission.json')|Should -BeFalse
  }
}
