#Requires -Version 7.6
BeforeAll {
  $root = Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $root 'src/Maester.ValidationProtocol.psm1') -Force
  $tokens = $null; $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/MaesterTimerTrigger/run.ps1'), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw 'The real Function runner must parse.' }
  $gate = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
      $node.Clauses[0].Item1.Extent.Text -like '*validatedSourceDigest*'
  }, $true)
  if (-not $gate) { throw 'The actual pre-module runtime guard was not found.' }
  $runtimeGuard = [scriptblock]::Create($gate.Extent.Text)
  function Invoke-ActualRuntimeGuard {
    param([string]$ExpectedRuntime = '7.6', [string]$ExpectedSource = 'source')
    $ValidationContext = @{ sourceSha256 = $ExpectedSource; configurationSha256 = 'configuration'; runtimeVersion = $ExpectedRuntime }
    $validatedSourceDigest = 'source'
    $validatedConfigurationDigest = 'configuration'
    & $runtimeGuard
  }
}
Describe 'Actual Function runtime guard' {
  It 'rejects the prerelease runtime <Version> rather than labelling it stable' -ForEach @(
    @{ Version = '7.6.0-preview.5' }, @{ Version = '7.6.1-rc.1' }
  ) {
    { Get-MaesterValidationRuntimeVersion -Version ([semver]$Version) } | Should -Throw '*stable PowerShell runtime*'
  }
  It 'accepts stable runtime build metadata without treating it as a prerelease' {
    Get-MaesterValidationRuntimeVersion -Version ([semver]'7.6.9+azure') | Should -BeExactly '7.6'
  }
  It 'accepts the real stable PowerShell SemanticVersion before importing workload modules' {
    { Invoke-ActualRuntimeGuard } | Should -Not -Throw
  }
  It 'rejects an incompatible expected runtime at the real guard' {
    { Invoke-ActualRuntimeGuard -ExpectedRuntime '7.4' } | Should -Throw '*runtime differs before module execution*'
  }
  It 'preserves the source mismatch refusal' {
    { Invoke-ActualRuntimeGuard -ExpectedSource 'different source' } | Should -Throw '*runtime differs before module execution*'
  }
}
