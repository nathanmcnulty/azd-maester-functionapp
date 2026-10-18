# PowerShell 7.6 native runtime validation

Current status (2026-10-18): the latest `sub-mvp` B1 trial at
`3cd4c621cec3fafdc4a580bbb703f636a127f985` validated production-source package
startup, imported all five default locked modules and verified both triggers' host-reported
disabled state. Live collection, report/viewer access and existing-environment
preservation remain open. Earlier trials below retain their original source and
subscription provenance.

The 2026-10-16 commercial-lab trial used reviewed source
`d817c055e9ebc42c7c2ba79053a0188671e29338` and its exact checked-in ARM template.
Both deployments disabled the optional report web app and resource locks.

| Plan | Azure configuration | Worker evidence |
| --- | --- | --- |
| FC1 | Deployment succeeded; `functionAppConfig.runtime` is PowerShell 7.6 | Executed PowerShell 7.6.5 / .NET 10.0.11 on 64-bit Linux; imported all five exact locked modules; reported Maester 2.2.0 and Pester 6.2.0; anonymous HTTP access returned 401 |
| B1 | Deployment succeeded; `PowerShell\|7.6`, always-on enabled | Unproven: Kudu retained an incomplete deployment after the CLI stopped waiting; no second ZIP was submitted |

The instrumented package preserved every maintained `src` file and added only a
key-protected HTTP probe. Its SHA-256 was
`1C19136CB7A734D32D2C6CBCB89F47DF6F2EFA5702BCD55CAFB2266761039DD4`.
Both Maester triggers were disabled before upload and remained disabled inside
the successful worker. No assessment, Graph permission grant or report delivery
was performed. This does not prove a complete Maester collection or upgrade of
an existing environment.

B1's pending attempt was deliberately cancelled through owned-resource teardown;
it is not evidence that PowerShell 7.6 fails on B1. The exact test resource group,
two storage-scoped role assignments and two managed-identity service principals
were verified absent. Failed probe and deployment diagnostics remain preserved
privately; B1 execution and the broader MFUNC-002 lifecycle gates remain open.

## Unconfirmed package deployment

`Deploy-FunctionCode.ps1` submits a package once. A nonzero CLI result can leave
an active server deployment, so it does not automatically re-upload the ZIP.
The error identifies the preserved package. Inspect the existing deployment's
actual result before submitting another package; a client timeout is not a
terminal service result. Confirmed success retains normal temporary-file cleanup.

## Fresh B1 isolation attempt

A second disposable B1 trial used clean source
`c8cfc7957ffee23538289587e82f6c07d334fd6b` with the same ARM template and
maintained worker files as the first trial. Infrastructure succeeded and readback
confirmed B1, Linux, `PowerShell|7.6`, always-on, HTTPS, disabled SCM basic
authentication and both assessment triggers disabled.

Only a 1,740-byte package containing the current host/profile/requirements files
and a nonce-bound, function-key-protected HTTP probe was uploaded. Its SHA-256 was
`3A09816CE7D82EA607D974784CF353C6D801FD53550BC9711AC1EF5C0869E7CF`.
No module package or assessment was submitted. Kudu progressed to a concrete
`az_cli_functions` deployment in status 1, "Building and Deploying", with
`complete=false`; its log stopped at "Running deployment command". It remained
nonterminal at the ten-minute observation limit. The CLI returned nonzero, and
Kudu listed both a temporary upload record and the concrete deployment record.
Neither record was treated as successful, and no ZIP was resubmitted.

This narrows the unresolved boundary to B1 deployment/startup handling before
module loading can be tested. It does not prove runtime incompatibility. B1
execution remains unproven; another identical fixture should not be the next
step without a concrete platform/deployment diagnosis.

The fixture was deliberately removed after preserving the pending deployment.
Fresh readback verified the resource group absent, its exact storage role
assignment absent (ARM 404), its managed-identity service principal absent
(Graph 404), and the operator's default subscription unchanged. No credentials
were written to the evidence files.

## Deployment boundary diagnosis (2026-10-18)

Read-only inspection of the installed Azure CLI 2.90 implementation and retained
receipts narrowed the next investigation. The B1 receipt's `az_cli_functions`
deployer matches the generic `/api/zipdeploy` route. It does not support the
previous working hypothesis that the Flex `/api/publish` helper handled this
attempt. CLI selection checks the live app's `properties.sku` for
`flexconsumption`; Linux hosting alone does not select that helper. A direct
readback of the old app's SKU was not preserved, so the next attempt must record
that field instead of inferring the route solely from template configuration.

In the inspected generic implementation, `--timeout 300` limits polling trials;
ZIP submission and status HTTP requests have no request-level timeout. An
individual request can therefore outlive that nominal deadline. The retained
nonterminal receive/build receipts identify an unresolved deployment boundary;
they do not establish the precise remote cause or a PowerShell incompatibility.

Before another upload, use a new disposable `sub-mvp` target, verify B1 SKU,
`PowerShell|7.6`, absent/null `functionAppConfig` and disabled assessment triggers,
and place a process deadline around the single submission. Preserve the ZIP,
CLI result and exact Kudu receipt/log. A client process deadline still does not
prove the server operation ended: observe its status or deliberately tear down
and verify the owned resources before another submission. Do not repeat the
same unbounded fixture or change hosting plans based on this diagnosis alone.
No new deployment or source-code fix was performed for this diagnosis; B1 worker
execution and MFUNC-002 lifecycle acceptance remain open.

## Client deployment deadline

`Deploy-FunctionCode.ps1` adds `-DeploymentTimeoutSeconds` (default 600) around
one Azure CLI submission. It keeps the CLI's `--timeout 300` and separately
bounds the local process and output collection time. A deadline failure attempts to
terminate the local process tree and reports unconfirmed completion; it never
submits a replacement package. The uniquely named ZIP is preserved on failure
and removed only after confirmed CLI success.

This local process bound does not cancel or qualify Azure's server-side
deployment. Inspect the exact Kudu operation, or deliberately tear down and
verify the owned fixture, before another upload. Subprocess fixtures validate
client behavior only; B1 runtime execution remains unproven.

The Windows MSI launcher uses its bundled Python executable directly, preserving
arguments such as resource-group names containing parentheses. Other batch
launchers reject shell-expansion characters in arguments before invocation.

## MVP B1 minimal runtime evidence (2026-10-18)

A fresh, explicitly selected `sub-mvp` trial used clean source
`ca8f87c99214eca91b1ccbe423ce8247cca42d56`. Before every cloud write, the private
harness rechecked the approved subscription and tenant, Enabled state, operator
and unchanged CLI default. Infrastructure readback confirmed the owned Linux B1
plan, `PowerShell|7.6`, always-on, HTTPS, disabled SCM basic authentication and
both maintained assessment-trigger settings set to `true`.

One 1,402-byte HTTP-only ZIP was submitted, SHA-256
`7B7B7A4E7B69227D7D4425691612EC053506B38B75C8E123E7D4094D1F2CD9B7`.
It retained the current profile and requirements bytes but omitted the host's
extension bundle, assessment functions and modules. The client exited zero and
one concrete Kudu receipt reached status 4 with `complete=true`. Authenticated
Kudu inventory reads needed more than the initial 20-second limit: a bounded
60-second diagnostic returned an empty inventory in 23.4 seconds before upload.
Those initial read failures occurred before upload intent; no package was
submitted until the baseline read succeeded, and no duplicate ZIP was uploaded.

The protected HTTP probe returned 200 and matched the exact source, nonce and
stage, PowerShell >=7.6, .NET >=10, Linux x64 and an empty module inventory.
Anonymous access returned 401. However, both dotted trigger-setting values were
absent from the worker response despite successful control-plane readback.
The full probe contract therefore remained **not qualified**. Four bounded
probe attempts were used; the remaining attempts were abandoned. This proves
minimal B1 worker execution, not host-level assessment disabling, production
host/extension loading, locked-module execution or the broader MFUNC-002
collection/report/viewer lifecycle.

At the end of this minimal trial, host trigger disabling still needed independent
verification before qualifying full production source. Worker setting exposure
was unresolved; control-plane flags alone were insufficient. Do not weaken the probe to
accept missing values. No assessment, Graph permission grant or report delivery ran.
The owned group was removed; fresh checks verified group absence, the exact
storage role's ARM 404, managed identity's Graph 404 and unchanged CLI default.
Historical trials retain their original subscription provenance.

## B1 production source, locked modules and host state (2026-10-18)

A separately reviewed trial used fresh owned `sub-mvp` resources and clean source
`3cd4c621cec3fafdc4a580bbb703f636a127f985`. Every cloud write rechecked the
approved subscription, tenant, Enabled state, operator and unchanged CLI default.
The same owned B1/Linux/PowerShell 7.6 app was used for two distinct, independently
reviewed phases, each with one journaled ZIP submission and one concrete Kudu
receipt. Both reached status 4 with `complete=true`; no phase resubmitted its ZIP.

The first phase restored the exact production host, including its pinned
extension bundle, profile, requirements and both trigger bindings, with inert
assessment bodies. After startup, protected host metadata GETs for exactly
`MaesterTimerTrigger` and `MaesterValidationTrigger` returned each expected name
and Boolean `isDisabled=true`; unauthenticated access returned 401. The runtime
probe also returned 200 with the exact source/nonce/stage and denied anonymous
access. Qualification succeeded on the third bounded attempt. This directly
checks host-reported state rather than inferring it from worker environment
variables. The earlier Tiny trial remains not qualified; why its worker omitted
the dotted settings remains unproven. The host API contract is represented by
its [pinned response model](https://github.com/Azure/azure-functions-host/blob/60c277e2c28bc074947602bcfa13ed29e4811bdf/src/WebJobs.Script.WebHost/Models/FunctionMetadataResponse.cs).

Only after that proof and another independent review, the second phase uploaded
the full production source plus the five default locked modules and a protected
runtime probe. All seven maintained `src` files were preserved byte-for-byte.
Five freshly downloaded NUPKGs matched the source lock; their 725 extracted files
matched the package. The complete 734-file ZIP was 21,402,842 bytes, SHA-256
`03DBABFE7524C35F2BACAA704BEBF1688833EA154F92F3D7AD730BEEFA9CE564`.

The third bounded probe attempt executed PowerShell 7.6.6 / .NET 10.0.12 on Linux
x64 and imported exactly Az.Accounts 5.5.3, Microsoft.Graph.Authentication 2.41.0,
Maester 2.2.0, Pester 6.2.0 and DnsClient-PS 1.2.1. It matched the source/nonce/stage,
returned protected HTTP 200 and anonymous 401, and again read both exact host
functions as disabled with unauthenticated metadata access denied. The first two
attempts did not qualify during startup; successful ZIP deployment alone was
never used as runtime proof.

These results qualify B1 production-source startup, locked-module loading and
host-reported disabling at the recorded revision. Validation submitted no
assessment invocation, queue message, Graph grant or report operation. It does
not establish a completed Maester collection, delivery/viewer access, all
historical invocation behavior or an upgrade of an existing environment.
Afterward, fresh checks verified the owned group absent, exact storage role ARM
404, managed identity Graph 404 and unchanged CLI default. MFUNC-002 remains open
for the collection, report/viewer and preservation lifecycle gates.
