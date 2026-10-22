# azd-maester-functionapp

Deploys a production-style Maester automation solution on Azure with:

- Azure Function App (PowerShell 7.6, Flex Consumption FC1 by default, timer-triggered)
- Managed identity + Graph permissions
- Storage-backed report history (`archive`) and latest pointer (`latest/latest.html`)
- Optional App Service + Easy Auth portal in WebApp mode

## Quickstart (recommended)

Requires PowerShell 7.6 or later. Offline repository tests use Pester 6.2 or later.

From the repository root in PowerShell 7.6+, install and explicitly select the
same test dependency as CI:

```powershell
Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force
Import-Module Pester -RequiredVersion 6.2.0 -Force
Invoke-Pester -Path ./tests -CI
```

After `azd init -t nathanmcnulty/azd-maester-functionapp`, run from the template root:

`azd up`

First bootstrap the dedicated tenant-owned setup client with an authorized administrator,
then review the exact postprovision access plan before approving it. See
[setup identity and consent migration](docs/setup-consent-migration.md).
Direct setup scripts default to plan-only; `azd up` explicitly requests an interactive
review. Choosing a capability does not approve its permission changes.

## Versioning and shared components

This template uses the stable Maester module `2.3.0`. Shared azd hooks,
permission setup, and the optional report web app are vendored from
`nathanmcnulty/azd-reference` and recorded in `azd-components.lock.json`.

The original multi-variant catalog remains available at
[`nathanmcnulty/azd-maester`](https://github.com/nathanmcnulty/azd-maester) while
the migration is being completed.

During interactive `azd up`, the preprovision wizard prompts for:

- Include Web App / Exchange / Teams / Azure
- Security group object ID (required when Web App is enabled)
- Azure RBAC scopes (when Azure is enabled)
- Full assessment [Y/n] (Yes/Enter: Full27; No: Minimal8; legacy Extended19 remains explicit)
- Separate default-off Mail.Send and ReportSettings.ReadWrite.All capabilities
- Optional mail recipient and the previously bootstrapped setup-client ID/account

For non-interactive runs (`azd up --no-prompt`), if `AZURE_RESOURCE_GROUP` is set, `preup` creates it automatically when missing.

## Advanced options (optional)

You can optionally enable additional data collection/connectivity for Maester by enabling one or more include options in the `azd up` wizard.

- `IncludeExchange`
  - Bundles the SHA-256 verified `ExchangeOnlineManagement` module in the deployment package.
  - Grants the Function App managed identity the Exchange app permission required for app-only Exchange Online access.
  - Creates/links an Exchange service principal for the managed identity and assigns the Exchange RBAC role `View-Only Configuration` after explicit aggregate-plan approval.
- `IncludeTeams`
  - Bundles the SHA-256 verified `MicrosoftTeams` module in the deployment package.
  - Assigns the Entra directory role `Teams Reader` to the Function App managed identity.
- `IncludeAzure`
  - Grants Azure RBAC `Reader` to the Function App managed identity at one or more scopes.
  - Scopes can be management groups and/or subscriptions.

### Permission behavior

- Azure RBAC, Entra directory roles, Exchange assignments, and Microsoft Graph app-role assignments are separate authorities.
- Some environments already have the required Microsoft Graph permissions consented and assigned. If Graph consent has not been completed previously, the deployment may require a **Global Administrator or Privileged Role Administrator**. See the selected profile and permission sections for solution-specific details.
- Unreadable, incomplete or ambiguous access inventory stops setup before writes.
- Apply rebuilds the aggregate delta and requires the exact reviewed plan hash; changed access or targets require a new review.
- The setup app is bootstrapped and admin-consented separately; it never grants its own consent.
- Toggling an option from `Yes` to `No` in a later `azd up` run is additive only and does **not** revoke prior assignments.
- Revocation/best-effort cleanup runs on `azd down` (predown hook).

What this does:

- runs preprovision checks/auth + interactive wizard
- provisions infra and runs postprovision setup + validation hooks

## Modes

- **Quick**: Function App + Storage
- **WebApp**: Quick + Web App (Entra auth restricted by security group)

For a manual postprovision retry after a successful provision, run
`./scripts/Setup-PostDeploy.ps1 -EnvironmentName <selected-environment> -SubscriptionId <selected-subscription> -TenantId <expected-tenant> -ResourceGroupName <deployed-resource-group>`.
Setup reads that environment's exact `functionAppName`, `functionAppPrincipalId`, `STORAGE_ACCOUNT_NAME` and optional
`WEB_APP_NAME` and `WEB_APP_ENABLED` deployment outputs; a false enablement output skips Easy Auth even
when other Web Apps exist in the resource group. Missing or mismatched targets
stop setup before role assignments or Easy Auth changes. The default invocation
returns a plan without deploying code; use the documented reviewed apply flow. The postprovision
summary uses the Function App and optional Web App's exact hosting plan IDs.

Setup, direct ZIP deployment, and direct validation require the expected tenant
via `-TenantId` or `AZURE_TENANT_ID`. They check fresh ARM subscription metadata
for the exact selected subscription, tenant, and `Enabled` state; cached CLI
account state is insufficient. ZIP deployment rechecks after packaging. See
[fresh target guards and migration](docs/fresh-target-validation.md).

Defaults:

- `PERMISSION_PROFILE=Full` for interactive Yes/Enter; No selects Minimal; stored Extended remains legacy
- `WEB_APP_SKU=F1`
- resource group pattern: `rg-<environment>-<location>` (override with `AZURE_RESOURCE_GROUP`)

## Operations

- Remove environment + Azure resources (includes predown cleanup):
  `azd down -e <env> --force --purge`
- Optionally remove local azd env:
  `azd env remove <env> --force`

### Cleanup details

`azd down` runs `scripts/Run-AzdPreDown.ps1`, which performs best-effort cleanup for tenant/scope-level assignments created by advanced options, including:

- Teams directory role assignments (`Teams Reader`) created by this environment
- Azure RBAC role assignments created by this environment (at selected scopes)
- Exchange Online permissions/assignments created by this environment (best-effort)

The generated setup summary in `outputs/<env>-setup-summary.md` includes tracked assignment IDs used for cleanup.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Azure Functions (Flex Consumption FC1 by default)                │
│   ┌────────────────────────────────────────────────────────┐     │
│   │ Function App (PowerShell 7.6, Linux)                   │     │
│   │ Timer trigger: Sunday midnight UTC                     │     │
│   │ MI: System-Assigned                                    │     │
│   └──────┬─────────────────────────────────────────────────┘     │
│          │                                                       │
└──────────┼───────────────────────────────────────────────────────┘
           │
    ┌──────┼──────────────────────────────────────────────┐
    │      ▼                                              │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
    │  │ Graph    │  │ Storage  │  │ Web App  │ optional  │
    │  │ + EXO    │  │ archive/ │  │ Easy Auth│           │
    │  │ + Teams  │  │ latest/  │  │ portal   │           │
    │  └──────────┘  └──────────┘  └──────────┘           │
    └─────────────────────────────────────────────────────┘
```

## Script map

- azd hooks: `scripts/Run-AzdPreUp.ps1`, `scripts/Run-AzdPreProvision.ps1`, `scripts/Run-AzdPostProvision.ps1`, `scripts/Run-AzdPreDown.ps1`
- Internal setup/validation: `scripts/Setup-PostDeploy.ps1`, `scripts/Invoke-FunctionValidation.ps1`
- Function deployment: `scripts/Deploy-FunctionCode.ps1`

### Bind a manual validation request

`Invoke-FunctionValidation.ps1` requires an explicit request file and a new durable
receipt path. The earlier implicit-GUID/admin-key invocation is disabled. The
controller sends one OAuth message to the existing `maester-validation` queue;
it neither creates the queue nor grants access. The sender needs **Storage Queue
Data Message Sender** on that queue, plus the read access required to verify the
exact site, deployment package and validation evidence. App settings are read
only in memory to establish the actual host queue account independently from
report storage. They are never included in controller output or receipts.

Prepare a private schema-2 request containing exactly `schemaVersion`, `context`,
`binding` and `packagePath`. `packagePath` identifies the reviewed local ZIP.
`context` contains `schemaVersion` (2), a fresh canonical `validationId`,
`siteName`, `storageAccountName`, `queueStorageAccountName`, `sourceSha256`,
`configurationSha256`, `packageSha256`, `activeDeploymentId`, `tenantId`,
`workloadIdentityId`, `runtimeVersion` (`7.6`) and `deadlineUtc` (UTC round-trip
timestamp). `sourceSha256` is the hash of the ZIP's generated
`validation-source.json`, which inventories every packaged file. The external
build manifest records this hash and the containing ZIP hash without a circular
dependency. Compute the configuration hash with
`Get-MaesterValidationConfigurationDigest` using the reviewed effective settings.

`binding` contains exactly `subscriptionId`, `resourceGroupName`,
`operatorObjectId`, `packageETag`, `selectorETag`, `transport` (`QueueStorage`),
`queueName` (`maester-validation`) and `queueEncoding` (`base64`). The deployment
ID and strong ETags must come from a verified capture/deployment receipt for the
same site and ZIP. The controller verifies the site's Flex deployment storage
binding, selector and package ETags before submission. Review scheduled/queue
concurrency, assessment side effects, containment and restart procedures before
running this command:

```powershell
./scripts/Invoke-FunctionValidation.ps1 @target `
  -RequestPath C:/private/validation-request.json `
  -ReceiptPath C:/private/validation-intent.json -PassThru
```

The controller flushes a new intent and submission checkpoint before the single
enqueue attempt. A lost response or HTTP error never causes another enqueue.
Use the same command with `-ReconcileOnly` to read that request's immutable claim
and terminal evidence, including when the exact app has stopped. Reconciliation
does not retrieve invocation keys, enqueue, restart the app or extend the saved
deadline. Preserve partial files and uncertain request identities.

The Function verifies its complete package inventory, settings, runtime and
workload identity, then conditionally creates a one-use claim before assessment
side effects. Duplicate delivery cannot rerun the assessment or overwrite its
terminal receipt. Queue acceptance, message expiry, a client timeout and an app's
control-plane `Stopped` state do not establish invocation completion. An absent
terminal receipt remains `Unresolved`; the controller does not perform app stop
or claim cancellation. Native containment still requires separate qualification.

For the optional postprovision validation hook, supply both
`FUNCTION_VALIDATION_REQUEST_PATH` and `FUNCTION_VALIDATION_RECEIPT_PATH` in
addition to `VALIDATE_FUNCTION_ON_PROVISION=true`. Source and offline test success
alone do not establish deployed runtime or assessment acceptance.

### Inspect a package before deployment

Build a ZIP without Azure authentication or deployment:

```powershell
./scripts/Build-FunctionPackage.ps1 -OutputPath C:/packages/maester.zip
```

The output directory must already exist. The builder refuses to overwrite the
ZIP or its adjacent `.manifest.json`. It verifies the selected module archives
against `runtime-packages.lock.json`, disables managed dependencies in the staged
content, and records source and component hashes, package pins, every ZIP file
hash, and the final ZIP hash. Entries use fixed timestamps and sorted paths;
repeat builds use the same PowerShell/.NET versions for byte comparison.
Use `-PackageDirectory` for previously downloaded locked archives, or let the
builder download them from PowerShell Gallery. Optional Exchange and Teams
modules must be selected when building.

After reviewing the artifact and approving the Azure change, deploy those exact
bytes with the expected tenant and subscription:

```powershell
./scripts/Deploy-FunctionCode.ps1 -TenantId $tenant -SubscriptionId $subscription `
  -ResourceGroupName $group -FunctionAppName $function `
  -PackagePath C:/packages/maester.zip -ExpectedPackageSha256 $reviewedSha256
```

Prepared packages remain available after success or an uncertain result. A
deployment timeout requires reconciling the existing remote deployment before
another submission. Packaging does not change the Function host runtime,
permissions, schedule, or validate an assessment.

## Runtime behavior

- Weekly schedule (Sunday midnight UTC). To run at a different time or frequency, edit the `schedule` value in `src/MaesterTimerTrigger/function.json` (e.g. `"0 30 6 * * 1"` for Monday 6:30 UTC), then re-deploy the function code.
- Default plan: FC1 (Flex Consumption) — serverless, pay-per-execution, 30-minute timeout. Alternatively set `FUNCTION_APP_PLAN` to `B1` (App Service Basic). Both supported plans use a 30-minute function timeout.
- All plans bundle exact modules from `runtime-packages.lock.json`; `scripts/Deploy-FunctionCode.ps1` verifies package SHA-256 before zip deployment. Managed dependencies are disabled. Update the lock only after reviewing and testing the exact new packages.
- The Azure Functions extension bundle is constrained to the available 4.32.0 release; the Functions host obtains this platform bundle from Microsoft's CDN.
- Runner script: `src/MaesterTimerTrigger/run.ps1`
- The 2.3.0 health gate distinguishes policy findings from runtime/permission/engine errors; a nonempty HTML file alone cannot satisfy success. See [release provenance and validation boundaries](docs/maester-230-upgrade.md).
- On-demand validation invokes `src/MaesterValidationTrigger` with a new request ID and waits for its private `validation/<request ID>.json` completion receipt. A timeout, failed invocation, or missing receipt fails validation; a scheduled run or a fresh `latest.html` cannot satisfy it.
- Outputs:
  - `archive/maester-report-<timestamp>.html.gz`
  - `latest/latest.html`
- In WebApp mode, latest report is published to Web App `index.html`
- Optional Entra auth via app registration is configured only after reviewed-plan approval. Existing Microsoft Graph consent and app-role assignments are reused; if they are not already present, the first run may require a **Global Administrator or Privileged Role Administrator**.
- The exact selected setup operator receives `Storage Blob Data Reader` only after its missing assignment is reviewed in the aggregate plan
- Blob soft delete is enabled for 1 day, with blob versioning disabled
- Archive uploads are gzip compressed and written directly to Cool tier
- Lifecycle policy moves `archive` blobs to Cold tier after 180 days and deletes after 365 days
- Key resources are tagged and protected with `CanNotDelete` locks by default
- Function App identity uses `Website Contributor` (least privilege for web content publish) on the optional Web App

## Security recommendations

This solution is reasonably secure, but there are additional controls you may choose to implement based on your organization requirements:

- **Storage private networking:** Use Private Endpoint + storage firewall rules to restrict data plane access to approved networks only.
- **Function App networking:** Use VNet integration and private endpoints for network isolation.
- **Web App private networking:** Use App Service Private Endpoint and access restrictions if your organization requires private-only ingress.
- **Centralized logging:** Send resource logs/metrics to a central Log Analytics workspace (or SIEM) for audit and incident response.
- **Conditional Access:** Apply tenant-wide baseline Conditional Access policies for user sign-in controls (MFA, device/risk posture).

## Reference docs

- Azure Developer CLI overview: https://learn.microsoft.com/azure/developer/azure-developer-cli/
- azd templates: https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-templates
- azd hooks/extensibility: https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-extensibility
- Manage azd environment variables: https://learn.microsoft.com/azure/developer/azure-developer-cli/manage-environment-variables
- Azure Functions hosting options: https://learn.microsoft.com/azure/azure-functions/functions-scale
- Azure Functions PowerShell guide: https://learn.microsoft.com/azure/azure-functions/functions-reference-powershell
- Azure Functions module bundling: https://learn.microsoft.com/azure/azure-functions/functions-reference-powershell#dependency-management
- App Service custom domain: https://learn.microsoft.com/azure/app-service/app-service-web-tutorial-custom-domain

Configuration drift remains disabled: the runner isolates inherited drift input
from the ordinary assessment. See [drift isolation and remaining gates](docs/drift-isolation.md)
(MFUNC-009 and MFUNC-010).
