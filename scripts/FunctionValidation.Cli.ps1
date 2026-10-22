#Requires -Version 7.6
$ErrorActionPreference='Stop'
try {
  $request=[Console]::In.ReadToEnd()|ConvertFrom-Json -AsHashtable
  if($request.resource -cnotin @('https://management.azure.com/','https://storage.azure.com/') -or $request.subscriptionId -cnotmatch '\A[0-9a-f-]{36}\z'){throw 'Invalid token request.'}
  Add-Type -Path (Join-Path $PSScriptRoot 'FunctionValidation.Transport.cs')
  $cli=(Get-Command az -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $python=$false
  if($IsWindows -and [IO.Path]::GetExtension($cli) -ieq '.cmd'){
    $cli=[IO.Path]::GetFullPath((Join-Path (Split-Path $cli -Parent) '../python.exe'))
    if(-not (Test-Path -LiteralPath $cli -PathType Leaf)){throw 'The Windows Azure CLI Python runtime is required for bounded execution.'}
    $python=$true
  }
  $output=[AzdMaesterValidation.BoundedIO]::RunAzureToken($cli,$python,$request.subscriptionId,$request.resource).GetAwaiter().GetResult()
  [Console]::Out.Write($output)
}catch{[Console]::Error.Write('Token worker failed.');exit 1}
