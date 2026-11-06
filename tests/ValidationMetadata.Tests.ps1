BeforeAll {
  $root=Split-Path $PSScriptRoot -Parent
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/MaesterTimerTrigger/run.ps1'),[ref]$tokens,[ref]$errors)
  if($errors.Count){throw 'Runner does not parse'}
  $guard=$ast.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.Contains('Validation invocation metadata is missing or invalid.')},$true)|Sort-Object {$_.Extent.Text.Length}|Select-Object -First 1
  $script:metadataGuard=[scriptblock]::Create($guard.Extent.Text)
  function Invoke-ActualMetadataGuard($TriggerMetadata){
    $invocationGuid=[guid]::Empty
    . $script:metadataGuard
    $invocationGuid
  }
}

Describe 'Actual worker-supplied invocation metadata guard' {
  # Worker RequestProcessor.GetTriggerMetadata supplies these flat fields from
  # the native invocation request; sys.RandGuid is not the invocation identity.
  It 'accepts the worker FunctionName and native InvocationId as <Kind>' -ForEach @(@{Kind='String'},@{Kind='Guid'}) {
    $id='77777777-7777-4777-8777-777777777777'
    $value=if($Kind -eq 'Guid'){[guid]$id}else{$id}
    (Invoke-ActualMetadataGuard @{FunctionName='MaesterValidationTrigger';InvocationId=$value}).ToString('D')|Should -BeExactly $id
  }
  It 'rejects missing, legacy or malformed metadata before source/modules (<Case>)' -ForEach @(
    @{Case='Null';Metadata=$null},
    @{Case='LegacySys';Metadata=@{sys=@{MethodName='MaesterValidationTrigger';RandGuid='77777777-7777-4777-8777-777777777777'}}},
    @{Case='WrongFunction';Metadata=@{FunctionName='MaesterTimerTrigger';InvocationId='77777777-7777-4777-8777-777777777777'}},
    @{Case='InvalidGuid';Metadata=@{FunctionName='MaesterValidationTrigger';InvocationId='not-a-guid'}},
    @{Case='EmptyGuid';Metadata=@{FunctionName='MaesterValidationTrigger';InvocationId='00000000-0000-0000-0000-000000000000'}},
    @{Case='ArrayId';Metadata=@{FunctionName='MaesterValidationTrigger';InvocationId=@('77777777-7777-4777-8777-777777777777')}},
    @{Case='ArrayFunction';Metadata=@{FunctionName=@('MaesterValidationTrigger');InvocationId='77777777-7777-4777-8777-777777777777'}}
  ) {
    {Invoke-ActualMetadataGuard $Metadata}|Should -Throw '*Validation invocation metadata is missing or invalid*'
  }
}
