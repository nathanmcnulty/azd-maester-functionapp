BeforeAll {
  $root=Split-Path $PSScriptRoot -Parent
  if(-not ('AzdMaesterValidation.BoundedIO' -as [type])){Add-Type -Path (Join-Path $root 'scripts/FunctionValidation.Transport.cs')}
  $pwsh=(Get-Process -Id $PID).Path
}

Describe 'Bounded validation subprocess transport' {
  It 'accepts bounded output and rejects a nonzero worker without exposing its error' {
    $ok=Join-Path $TestDrive 'ok.ps1'
    Set-Content $ok '[Console]::Out.Write("bounded")'
    [AzdMaesterValidation.BoundedIO]::Run($pwsh,$ok,'{}',5).GetAwaiter().GetResult()|Should -BeExactly 'bounded'
    $bad=Join-Path $TestDrive 'bad.ps1'
    Set-Content $bad '[Console]::Error.Write("synthetic-secret-must-not-escape");exit 1'
    try{[AzdMaesterValidation.BoundedIO]::Run($pwsh,$bad,'{}',5).GetAwaiter().GetResult();throw 'Unexpected success'}catch{
      $_.Exception.ToString()|Should -Not -Match 'synthetic-secret-must-not-escape'
      $_.Exception.ToString()|Should -Match 'failed or timed out'
    }
  }
  It 'kills a worker that exceeds <Stream> output bounds' -ForEach @(@{Stream='Out';Count=2097153},@{Stream='Error';Count=65537}) {
    $worker=Join-Path $TestDrive ("overflow-$Stream.ps1")
    Set-Content $worker ("[Console]::$Stream.Write(('x' * $Count));Start-Sleep -Seconds 20")
    $watch=[Diagnostics.Stopwatch]::StartNew()
    {[AzdMaesterValidation.BoundedIO]::Run($pwsh,$worker,'{}',5).GetAwaiter().GetResult()}|Should -Throw '*failed or timed out*'
    $watch.Elapsed.TotalSeconds|Should -BeLessThan 8
  }
  It 'kills a timed out child and preserves a bounded elapsed time' {
    $worker=Join-Path $TestDrive 'hang.ps1'
    $pidPath=Join-Path $TestDrive 'child.pid'
    Set-Content $worker ("[IO.File]::WriteAllText('"+$pidPath.Replace("'","''")+"',[string]`$PID);Start-Sleep -Seconds 20")
    $watch=[Diagnostics.Stopwatch]::StartNew()
    {[AzdMaesterValidation.BoundedIO]::Run($pwsh,$worker,'{}',2).GetAwaiter().GetResult()}|Should -Throw '*failed or timed out*'
    $watch.Elapsed.TotalSeconds|Should -BeLessThan 6
    if(Test-Path $pidPath){Get-Process -Id ([int](Get-Content $pidPath)) -ErrorAction SilentlyContinue|Should -BeNullOrEmpty}
  }
  It 'rejects invalid HTTP schemes and bounds before a request can be sent' {
    {[AzdMaesterValidation.BoundedIO]::Send('GET',[uri]'http://127.0.0.1:1/','synthetic',$null,1,$false).GetAwaiter().GetResult()}|Should -Throw '*Invalid HTTP request bound*'
    {[AzdMaesterValidation.BoundedIO]::Send('GET',[uri]'https://example.invalid/','synthetic',$null,31,$false).GetAwaiter().GetResult()}|Should -Throw '*Invalid HTTP request bound*'
  }
  It 'terminates a spawned descendant when its supervising worker times out' {
    $worker=Join-Path $TestDrive 'descendant.ps1'
    $pidPath=Join-Path $TestDrive 'descendant.pid'
    $source=@'
$start=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
$start.UseShellExecute=$false;$start.CreateNoWindow=$true
foreach($arg in @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 20')){$start.ArgumentList.Add($arg)}
$child=[Diagnostics.Process]::Start($start)
[IO.File]::WriteAllText('__PIDPATH__',[string]$child.Id)
Start-Sleep -Seconds 20
'@.Replace('__PIDPATH__',$pidPath.Replace("'","''"))
    Set-Content $worker $source
    {[AzdMaesterValidation.BoundedIO]::Run($pwsh,$worker,'{}',3).GetAwaiter().GetResult()}|Should -Throw '*failed or timed out*'
    Test-Path $pidPath|Should -BeTrue
    Get-Process -Id ([int](Get-Content $pidPath)) -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
  }
}

Describe 'Actual server entrypoint boundaries' {
  It 'does not execute a bundled module whose bytes differ from its inventory' {
    $package=Join-Path $TestDrive 'package'
    $timer=Join-Path $package 'MaesterTimerTrigger'
    $module=Join-Path $package 'Modules/Az.Accounts/5.5.3'
    $null=New-Item -ItemType Directory $timer,$module
    Copy-Item (Join-Path $root 'src/MaesterTimerTrigger/run.ps1') $timer
    Copy-Item (Join-Path $root 'src/Maester.ValidationProtocol.psm1') $package
    $marker=Join-Path $TestDrive 'module-executed'
    Set-Content (Join-Path $module 'Az.Accounts.psd1') "@{RootModule='Az.Accounts.psm1';ModuleVersion='5.5.3';GUID='11111111-1111-4111-8111-111111111111'}"
    Set-Content (Join-Path $module 'Az.Accounts.psm1') ("Set-Content '"+$marker.Replace("'","''")+"' 'executed'")
    $files=@(Get-ChildItem $package -Recurse -File|ForEach-Object{[ordered]@{path=[IO.Path]::GetRelativePath($package,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
    @{schemaVersion=1;files=$files}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $package 'validation-source.json')
    Add-Content (Join-Path $module 'Az.Accounts.psm1') '# tampered'
    $context=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName='func-test';storageAccountName='sttest';queueStorageAccountName='sthost';sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId='22222222-2222-4222-8222-222222222222';tenantId='33333333-3333-4333-8333-333333333333';workloadIdentityId='44444444-4444-4444-8444-444444444444';runtimeVersion='7.6';deadlineUtc=[DateTimeOffset]::UtcNow.AddMinutes(1).ToString('o')}
    {& (Join-Path $timer 'run.ps1') -Timer @{IsPastDue=$false} -TriggerMetadata @{sys=@{MethodName='MaesterValidationTrigger';RandGuid='77777777-7777-4777-8777-777777777777'}} -ValidationContext $context}|Should -Throw '*differs*'
    Test-Path $marker|Should -BeFalse
  }
  It 'attempts terminal evidence only once after a lost success-write response' {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/MaesterTimerTrigger/run.ps1'),[ref]$tokens,[ref]$errors)
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-ValidationReceipt'},$true).Extent.Text
    $block=[scriptblock]::Create($definition+@'

$validationClaim=@{status='Started'}
$StorageAccountName='sttest'
$script:validationTerminalAttempted=$false
$script:terminalWrites=0
function Get-PlainToken {param($ResourceUrl) 'synthetic'}
function Complete-MaesterValidationClaim {param($Claim,$Status,$StorageAccountName,$Token) $script:terminalWrites++;throw 'response lost after storage accepted success'}
try{Write-ValidationReceipt Succeeded}catch{}
try{Write-ValidationReceipt Failed}catch{}
$script:terminalWrites
'@)
    (& $block)|Should -Be 1
  }
}
