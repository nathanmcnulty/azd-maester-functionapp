# Fresh target guards (issue #30)

This source-only candidate depends on Function draft [PR #29](https://github.com/nathanmcnulty/azd-maester-functionapp/pull/29)
at frozen revision `7ecbec134446d3057dab902f29c98d873e64289e`. It does not rewrite
that branch or extend its historical native qualification to new bytes.

## Explicit target contract and migration

`Setup-PostDeploy.ps1`, `Deploy-FunctionCode.ps1`, and
`Invoke-FunctionValidation.ps1` require the selected subscription and the expected
tenant. Pass `-TenantId <expected-tenant-guid>` or set `AZURE_TENANT_ID` explicitly;
missing/blank expected tenant fails closed instead of discovering it from the
ambient account. Setup still accepts `AZURE_SUBSCRIPTION_ID`; direct deployment
and validation still require `-SubscriptionId`. Expected IDs are configurable.

For a manual deployment, supply all three exact resource identifiers:

```powershell
./scripts/Deploy-FunctionCode.ps1 -SubscriptionId <subscription-guid> -TenantId <tenant-guid> -ResourceGroupName <resource-group> -FunctionAppName <function-app> -Plan B1
```

For separately authorized validation:

```powershell
./scripts/Invoke-FunctionValidation.ps1 -SubscriptionId <subscription-guid> -TenantId <tenant-guid> -ResourceGroupName <resource-group> -FunctionAppName <function-app> -StorageAccountName <storage-account>
```

The shared guard reads ARM subscription metadata with explicit `--subscription`.
It requires matching subscription resource ID, subscription ID, tenant ID,
display name and exact `Enabled` state. Missing/failed/malformed responses stop
execution; cached `az account list/show` is not authority. A differing global
CLI default is left untouched. Direct ZIP checks before staging/downloads and
again immediately before submission after packaging. Validation rechecks before
each trigger attempt. Setup passes its validated tenant in the real deploy
argument splat and optional Exchange call. Exchange obtains and validates its
tenant-scoped token before its app-role, service-principal, or RBAC writes.

## Immutable component provenance

`maester-azd-hooks` **1.0.0 (pilot)** is vendored from independently reviewed
reference revision `fd26f7351f36c569067ae37edcb35d6b6cc40f29`, addressing
[reference issue #110](https://github.com/nathanmcnulty/azd-reference/issues/110).
`azd-components.lock.json` records the exact canonical revision and all eight
file SHA-256 hashes. The template remains self-contained at runtime; no private
reference checkout or mutable branch is fetched during deployment.

The vendored bytes were generated with the canonical sync tool from the reviewed
local source. The published commit has the identical Git tree
`320e48ab68b6462f4e66189cb1c23c62cbcfd820`; the lock records that remotely reachable
commit. Reproduce the adoption from a reference checkout containing it:

```powershell
./tooling/Sync-AzdComponent.ps1 -Component maester-azd-hooks -TargetPath <function-checkout> -Revision fd26f7351f36c569067ae37edcb35d6b6cc40f29
./tooling/Test-AzdComponentDrift.ps1 -TargetPath <function-checkout>
```

All eight hook files and the unchanged report-webapp component match their
locks. Permission evidence hashes are refreshed for changed source only. The
permission requirements and known inventory gaps are unchanged; manifest data
does not authorize a permission grant.

## Proof boundaries

Offline tests use stubs/tripwires for cloud mutations and module downloads.
They are source/contract evidence, not proof of live Azure behavior. Existing
source/package/module integrity, resource-ID/tag checks, deployment timeout,
single-submission and unconfirmed-package preservation contracts remain in place.

No Azure login, deployment, grant, report operation, cleanup, merge or release
was performed for this change. The private native harness was not run or edited.
The prior B1 PowerShell 7.6.6/.NET 10.0.12 full-source/default-module evidence
remains historical for its recorded source and exact lab scope; see
[Function runtime validation](function-runtime-validation.md). Broad Function
execution, actual assessment/report access, audience and existing-target
migration gates remain open.

## Offline result (2026-10-18)

Final full-suite run on PowerShell 7.6.6 / Pester 6.2.0: **112 passed,
0 failed, 2 skipped** in 36.08 seconds. The skips are existing Windows-only
batch-launcher cases on this Linux executor. All 29 actual-entrypoint guard
cases passed, including the final pre-trigger state-change check. All PowerShell
files parsed successfully and `git diff --check` passed. Independent source,
provenance and test-coverage review found no blocking defects.

## Reproduce offline checks

From the Function checkout, using PowerShell 7.6.6 and Pester 6.2.0. Set
`POWERSHELL_TELEMETRY_OPTOUT=1` and `DOTNET_CLI_TELEMETRY_OPTOUT=1` in the
launching process environment before starting PowerShell; child test processes
inherit these official opt-outs. Then run:

```powershell
Import-Module Pester -RequiredVersion 6.2.0 -Force
Invoke-Pester ./tests -CI
$errors = @()
Get-ChildItem . -Recurse -File -Include *.ps1,*.psm1 | ForEach-Object {
  $fileErrors = $null
  [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$fileErrors) | Out-Null
  $errors += @($fileErrors)
}
if ($errors.Count) { throw ($errors | Out-String) }
```

`TargetGuardEntrypoints.Tests.ps1` executes the production entrypoints in isolated
subprocesses with copied source and real guard/token helpers. ZIP cases cover
wrong tenant/subscription, stale cached Enabled/current Disabled, missing state,
failed metadata query, missing/blank expected tenant, explicit/environment tenant
success with a different global default, and Disabled state after packaging.
The real Setup path captures the actual Exchange token argument splat and deploy
argument splat, including wrong-tenant token rejection before Exchange writes.
Actual preup tests prove a mismatch cannot create a missing group. Direct
validation failures cannot reach token/key/trigger operations. Existing
packaging/module-tamper and deployment-timeout fixtures remain separate.

The canonical backlog schema check and rendered view check pass without changing
historical backlog evidence. The rendered view's original claim timestamp uses
America/Los_Angeles; the render check was run with that timezone. Permission
schema validation and evidence hashes pass, and the permission manifest's
semantic content is identical to the frozen base after excluding evidence
hashes. `ComponentIntegrity.Tests.ps1` retains exact vendor/evidence hash checks
in ordinary repository CI.
