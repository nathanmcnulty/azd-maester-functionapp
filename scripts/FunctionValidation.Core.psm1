#Requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'FunctionValidation.Session.psm1') -Force

function Assert-MaesterValidationReceipt {
  param(
    [Parameter(Mandatory)]$Receipt,
    [Parameter(Mandatory)][guid]$ValidationId,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Claim
  )
  $expected = $ValidationId.ToString('D')
  if($Context.validationId -cne $expected){throw 'Validation request and context identity differ.'}
  Assert-MaesterValidationEvidence -Value $Claim -Context $Context -Kind Claim|Out-Null
  Assert-MaesterValidationEvidence -Value $Receipt -Context $Context -Kind Terminal -Claim $Claim|Out-Null
  if ($Receipt.status -eq 'Failed') { throw "Validation invocation '$expected' failed." }
  if ($Receipt.status -ne 'Succeeded') { throw "Validation receipt for '$expected' has unknown status '$($Receipt.status)'." }
  return $true
}

Export-ModuleMember -Function Assert-MaesterValidationReceipt
