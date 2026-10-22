#Requires -Version 7.6
param([string]$ValidationRequest, $TriggerMetadata)

Import-Module (Join-Path $PSScriptRoot '../Maester.ValidationProtocol.psm1') -Force -ErrorAction Stop
$context = ConvertFrom-MaesterValidationJson -Json $ValidationRequest
Assert-MaesterValidationContext $context | Out-Null
& (Join-Path $PSScriptRoot '../MaesterTimerTrigger/run.ps1') `
  -Timer @{ IsPastDue = $false } -TriggerMetadata $TriggerMetadata -ValidationContext $context
