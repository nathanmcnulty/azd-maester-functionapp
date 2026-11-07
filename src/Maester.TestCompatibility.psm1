#Requires -Version 7.6
Set-StrictMode -Version Latest

function Initialize-MaesterAssessmentTests {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$DestinationPath
  )
  # Function packages may be mounted read-only and shared by warm invocations.
  # Repair a private copy; never modify the verified module or its package.
  $source = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
  if (-not $source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'assessment.whatIfSourceInvalid' }
  if (@(Get-ChildItem -LiteralPath $SourcePath -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'assessment.whatIfSourceInvalid' }
  $destination = [IO.Path]::GetFullPath($DestinationPath)
  $sourceFull = [IO.Path]::GetFullPath($SourcePath).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if ($destination.StartsWith($sourceFull, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $destination)) { throw 'assessment.whatIfDestinationInvalid' }
  $parent = Get-Item -LiteralPath (Split-Path $destination -Parent) -Force -ErrorAction Stop
  if (-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'assessment.whatIfDestinationInvalid' }
  Copy-Item -LiteralPath $SourcePath -Destination $destination -Recurse -ErrorAction Stop
  $copiedTarget = Get-Item -LiteralPath (Join-Path $destination 'Maester/Entra/Test-ConditionalAccessWhatIf.Tests.ps1') -ErrorAction Stop
  if ($copiedTarget.IsReadOnly) { $copiedTarget.IsReadOnly = $false }
  $receipt = Repair-MaesterWhatIfDiscovery -TestsPath $destination
  [pscustomobject]@{ TestsPath = $destination; Compatibility = $receipt }
}

function Repair-MaesterWhatIfDiscovery {
  param([Parameter(Mandatory)][string]$TestsPath)
  # Maester 2.3.0 emits a scalar for a single user. Its bundled CA What-If
  # discovery calls IndexOf on those results. Keep every test and API call;
  # Normalize the five collection assignments in this exact locked file. Pester
  # 6.2 must also explicitly allow empty data on these two contexts; other
  # discovery failures and all real user cases remain enabled.
  $path = Join-Path $TestsPath 'Maester/Entra/Test-ConditionalAccessWhatIf.Tests.ps1'
  $file = Get-Item -LiteralPath $path -ErrorAction Stop
  if ($file -isnot [IO.FileInfo] -or $file.LinkType) { throw 'assessment.whatIfSourceInvalid' }
  $source = [IO.File]::ReadAllText($path).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
  $originalHash = '4EAFA3104AA711BB186E0633AC1EF8BA9074F9160AF8573D35570559B03BA384'
  $patchedHash = '957AC886DF9FFFBEB75BA5F27CE0735057142F8BEDEA383D80FFE4858D138939'
  $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source)))
  if ($hash -cne $originalHash -and $hash -cne $patchedHash) { throw 'assessment.whatIfSourceUnrecognized' }
  $changed = $hash -ceq $originalHash
  if ($changed) {
    $replacements = @(
      @('$RegularUsers = Get-MtUser -Count 5 -UserType ''Member''', '$RegularUsers = @(Get-MtUser -Count 5 -UserType ''Member'')'),
      @('$AdminUsers = Get-MtUser -Count 5 -UserType ''Admin''', '$AdminUsers = @(Get-MtUser -Count 5 -UserType ''Admin'')'),
      @('$EmergencyAccessUsers = Get-MtUser -Count 5 -UserType ''EmergencyAccess''', '$EmergencyAccessUsers = @(Get-MtUser -Count 5 -UserType ''EmergencyAccess'')'),
      @('$RegularUsers = $RegularUsers | Where-Object { $_.id -notin $EmergencyAccessUsers.id }', '$RegularUsers = @($RegularUsers | Where-Object { $_.id -notin $EmergencyAccessUsers.id })'),
      @('$AdminUsers = $AdminUsers | Where-Object { $_.id -notin $EmergencyAccessUsers.id }', '$AdminUsers = @($AdminUsers | Where-Object { $_.id -notin $EmergencyAccessUsers.id })'),
      @('-ForEach @( $RegularUsers ) {', '-ForEach @( $RegularUsers ) -AllowNullOrEmptyForEach {'),
      @('-ForEach @( $EmergencyAccessUsers ) {', '-ForEach @( $EmergencyAccessUsers ) -AllowNullOrEmptyForEach {')
    )
    foreach ($pair in $replacements) {
      if ([regex]::Matches($source, [regex]::Escape($pair[0])).Count -ne 1) { throw 'assessment.whatIfSourceUnrecognized' }
      $source = $source.Replace($pair[0], $pair[1])
    }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source)))
    if ($hash -cne $patchedHash) { throw 'assessment.whatIfPatchInvalid' }
    [IO.File]::WriteAllText($path, $source, [Text.UTF8Encoding]::new($false))
  }
  [pscustomobject]@{ Kind = 'Maester.WhatIfCollectionCompatibility'; SchemaVersion = 1; OriginalSha256 = $originalHash; EffectiveSha256 = $patchedHash; Changed = $changed }
}
