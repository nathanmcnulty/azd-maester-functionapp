Describe 'Function validation result correlation' {
  AfterAll { [Environment]::SetEnvironmentVariable('VALIDATION_TEST_MODE', $null, 'Process') }
  BeforeAll { $harness = Join-Path $PSScriptRoot 'fixtures/FunctionValidationHarness.ps1' }

  It 'passes only when this request receives a succeeded invocation receipt' {
    $env:VALIDATION_TEST_MODE = 'success'
    $output = & pwsh -NoProfile -File $harness 2>&1
    $LASTEXITCODE | Should -Be 0
    @($output) -join "`n" | Should -Match 'ValidationPassed  : True'
    @($output) -join "`n" | Should -Match 'InvocationId'
  }

  It 'fails on a reported invocation error' {
    $env:VALIDATION_TEST_MODE = 'failed'
    $output = & pwsh -NoProfile -File $harness 2>&1
    $LASTEXITCODE | Should -Be 1
    @($output) -join "`n" | Should -Match 'Validation invocation .* failed'
  }

  It 'does not accept another invocation receipt' {
    $env:VALIDATION_TEST_MODE = 'stale'
    $output = & pwsh -NoProfile -File $harness 2>&1
    $LASTEXITCODE | Should -Be 1
    @($output) -join "`n" | Should -Match 'mismatched invocation identity'
  }

  It 'fails closed when the current invocation has no completion receipt' {
    $env:VALIDATION_TEST_MODE = 'missing'
    $output = & pwsh -NoProfile -File $harness 2>&1
    $LASTEXITCODE | Should -Be 1
    @($output) -join "`n" | Should -Match 'has no completed receipt'
  }

  It 'refuses to reuse a pre-existing request receipt' {
    $env:VALIDATION_TEST_MODE = 'collision'
    $output = & pwsh -NoProfile -File $harness 2>&1
    $LASTEXITCODE | Should -Be 1
    @($output) -join "`n" | Should -Match 'already exists'
  }
}
