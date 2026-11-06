#Requires -Version 7.6
param([byte[]]$ValidationRequest, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../Maester.ValidationProtocol.psm1') -Force -ErrorAction Stop
if ($null -eq $ValidationRequest -or $ValidationRequest.Length -eq 0 -or $ValidationRequest.Length -gt 16384) {
  throw 'Validation input bytes exceed the supported bounds.'
}
$json = [Text.UTF8Encoding]::new($false, $true).GetString($ValidationRequest)
$context = ConvertFrom-MaesterValidationJson -Json $json
Assert-MaesterValidationContext $context | Out-Null
& (Join-Path $PSScriptRoot '../MaesterTimerTrigger/run.ps1') `
  -Timer @{ IsPastDue = $false } -TriggerMetadata $TriggerMetadata -ValidationContext $context -RequireValidationContext
