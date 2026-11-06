BeforeAll {
  $path=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Setup-PostDeploy.ps1'
  $source=Get-Content -LiteralPath $path -Raw
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
  $gate=$ast.Find({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -ceq '$AccessOnly'},$true)
  if(-not$gate){throw 'Production access-only deployment boundary missing'}
  $tail=$source.Substring($gate.Extent.StartOffset)
  $parameters=$ast.ParamBlock.Extent.Text
}
Describe 'Reviewed setup access and code deployment choices' {
  It 'honors AccessOnly=<_> at the actual post-approval deployment boundary' -ForEach @($true,$false) {
    $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $dir
    $stub=@'
param($SubscriptionId,$TenantId,$ResourceGroupName,$FunctionAppName,$Plan)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'deployment-attempted') -Value $FunctionAppName
'@
    Set-Content -LiteralPath (Join-Path $dir 'Deploy-FunctionCode.ps1') -Value $stub
    $setup=@'
$ErrorActionPreference='Stop'
$accessResult=[pscustomobject]@{status='Applied'}
$resolvedResourceGroupName=$ResourceGroupName
$functionAppName='func-test'
'@
    $harness=Join-Path $dir 'setup-tail.ps1'
    Set-Content -LiteralPath $harness -Value ($parameters+[Environment]::NewLine+$setup+[Environment]::NewLine+$tail)
    $arguments=@('-NoProfile','-NonInteractive','-File',$harness,'-Apply','-SubscriptionId','11111111-1111-4111-8111-111111111111','-TenantId','22222222-2222-4222-8222-222222222222','-ResourceGroupName','rg-test','-Plan','FC1')
    if($_){$arguments+='-AccessOnly'}
    $output=& pwsh @arguments 2>&1
    $LASTEXITCODE | Should -Be 0
    (Test-Path -LiteralPath (Join-Path $dir 'deployment-attempted')) | Should -Be (-not $_)
    if($_){($output -join [Environment]::NewLine) | Should -Match 'Code deployment was not requested'}
    else {Get-Content -LiteralPath (Join-Path $dir 'deployment-attempted') | Should -BeExactly 'func-test'}
  }
}
