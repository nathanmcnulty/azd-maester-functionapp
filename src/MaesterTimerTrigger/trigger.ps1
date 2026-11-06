#Requires -Version 7.6
# Azure indexes this binding-compatible entrypoint. The shared assessment script
# also accepts a validation context supplied only by MaesterValidationTrigger.
param($Timer, $TriggerMetadata)

& (Join-Path $PSScriptRoot 'run.ps1') -Timer $Timer -TriggerMetadata $TriggerMetadata
