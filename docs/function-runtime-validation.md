# PowerShell 7.6 native runtime validation

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
