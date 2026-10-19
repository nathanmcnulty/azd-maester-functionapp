#Requires -Version 7.6
BeforeAll {
  $root = Split-Path $PSScriptRoot -Parent
  $lock = Get-Content (Join-Path $root 'runtime-packages.lock.json') -Raw | ConvertFrom-Json
  $runner = Get-Content (Join-Path $root 'src/MaesterTimerTrigger/run.ps1') -Raw
  $manifest = Get-Content (Join-Path $root 'scripts/vendor/Azd.MaesterHooks/Maester-GraphPermissions.json') -Raw | ConvertFrom-Json
}
Describe 'Source-only Function Maester 2.3.0 integration' {
  It 'pins the official reviewed package with the unchanged exact Graph and Pester releases' {
    ($lock.packages | Where-Object name -eq 'Maester').version | Should -BeExactly '2.3.0'
    ($lock.packages | Where-Object name -eq 'Maester').sha256 | Should -BeExactly '95F720822D04271F5E15F4665BC017111DC72E17B97E5D0525CB4EC2FF5BD0B0'
    ($lock.packages | Where-Object name -eq 'Microsoft.Graph.Authentication').version | Should -BeExactly '2.41.0'
    ($lock.packages | Where-Object name -eq 'Pester').version | Should -BeExactly '6.2.0'
    $manifest.maesterVersion | Should -BeExactly '2.3.0'
    @($manifest.profiles.Full).Count | Should -Be 27
    @($manifest.profiles.Minimal).Count | Should -Be 8
    @($manifest.profiles.Extended).Count | Should -Be 19
  }
  It 'uses the bundled exact suite without updates or error-hiding exclusions' {
    $runner | Should -Match "Import-LockedModule -Name 'Maester' -Version '2.3.0'"
    $runner | Should -Match 'Where-Object \{ \$_.Version -eq \[version\]''2.3.0'' \}'
    $runner | Should -Not -Match 'Update-MaesterTests|Install-MaesterTests|Install-Module|Save-Module|ExcludeTag'
    [regex]::Matches($runner, 'ExcludePath\s*=').Count | Should -Be 1
    $runner | Should -Match 'ExcludePath = @\(\(Join-Path \$testsPath ''Maester/Drift/MT1060Drift.tests.ps1''\)\)'
  }
  It 'gates output health before publication while retaining managed identity authentication' {
    $runner | Should -Match 'Connect-MgGraph -Identity'
    $runner | Should -Match 'Get-MaesterAssessmentEvidence -Output \$maesterOutput'
    $runner.IndexOf('$assessmentEvidence = Get-MaesterAssessmentEvidence') | Should -BeLessThan $runner.IndexOf("Write-Step 'Maester run completed.")
    $runner | Should -Match 'PassThru\s*= \$true'
    $runner | Should -Not -Match 'Assert-GraphAccess|Grant-MaesterGraphPermissions|MAESTER_SETUP_CLIENT_ID|AppRoleAssignment.ReadWrite.All'
    @(Get-ChildItem (Join-Path $root 'src') -Recurse -File | Select-String -Pattern 'New-ServicePrincipal|oauth2PermissionGrants|roleManagement/directory/roleAssignments').Count | Should -Be 0
  }
  It 'makes only the azd wrapper interactive while direct setup defaults to planning' {
    $yaml = Get-Content (Join-Path $root 'azure.yaml') -Raw
    $yaml | Should -Match 'Run-AzdPostProvision.ps1 -InteractiveConsent'
    $setup = Get-Content (Join-Path $root 'scripts/Setup-PostDeploy.ps1') -Raw
    $setup.IndexOf('if (-not $Apply)') | Should -BeLessThan $setup.IndexOf('$accessResult = Invoke-MaesterSetupAccessPlan')
    $setup.IndexOf('$accessResult = Invoke-MaesterSetupAccessPlan') | Should -BeLessThan $setup.IndexOf('-Name ''STORAGE_ACCOUNT_NAME''')
    $setup.IndexOf('$accessResult = Invoke-MaesterSetupAccessPlan') | Should -BeLessThan $setup.IndexOf('& "$PSScriptRoot\Deploy-FunctionCode.ps1"')
  }
}
