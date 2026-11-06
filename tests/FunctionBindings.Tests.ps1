BeforeAll {
  $script:source=Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
}

Describe 'PowerShell worker entrypoint binding contract' {
  It 'forwards scheduled metadata to the shared assessment without a validation context' {
    $folder=Join-Path $TestDrive 'scheduled';New-Item -ItemType Directory $folder|Out-Null
    Copy-Item (Join-Path $script:source 'MaesterTimerTrigger/trigger.ps1') $folder
    @'
param($Timer,$TriggerMetadata,$ValidationContext)
[pscustomobject]@{pastDue=$Timer.IsPastDue;invocation=$TriggerMetadata.sys.RandGuid;hasValidationContext=($null -ne $ValidationContext)}
'@|Set-Content (Join-Path $folder 'run.ps1')
    $id=[guid]::NewGuid().ToString('D')
    $result=& (Join-Path $folder 'trigger.ps1') -Timer @{IsPastDue=$true} -TriggerMetadata @{sys=@{RandGuid=$id}}
    $result.pastDue|Should -BeTrue
    $result.invocation|Should -BeExactly $id
    $result.hasValidationContext|Should -BeFalse
  }
  It 'declares only input bindings and worker-provided metadata parameters at each indexed entrypoint' {
    # Azure PowerShell worker AzFunctionInfo rejects all remaining parameters
    # after removing input binding names and these three metadata parameters.
    # The shared assessment script is not itself an indexed entrypoint.
    foreach($file in Get-ChildItem $script:source -Filter function.json -Recurse){
      $config=Get-Content $file.FullName -Raw|ConvertFrom-Json -AsHashtable
      $entry=if($config.scriptFile){$config.scriptFile}else{'run.ps1'}
      $path=Join-Path $file.DirectoryName $entry
      Test-Path $path -PathType Leaf|Should -BeTrue
      $tokens=$null;$errors=$null
      $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
      $errors.Count|Should -Be 0
      $parameters=@($ast.ParamBlock.Parameters|ForEach-Object {$_.Name.VariablePath.UserPath})
      $inputs=@($config.bindings|Where-Object direction -eq 'in'|ForEach-Object name)
      $unbound=@($parameters|Where-Object {$_ -notin $inputs -and $_ -notin @('TriggerMetadata','TraceContext','RetryContext')})
      $unbound|Should -BeNullOrEmpty -Because "$($file.Directory.Name) must load in the real PowerShell worker"
      foreach($inputName in $inputs){$inputName|Should -BeIn $parameters}
    }
  }
}
