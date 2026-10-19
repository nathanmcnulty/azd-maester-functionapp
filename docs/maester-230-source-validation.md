# Function Maester 2.3.0 source qualification

This record covers the source-only successor to reviewed draft #32 at
`9e65d43bec1d271211e5af8fd7947e6d48e34902`. It does not extend the older
[native Function evidence](function-runtime-validation.md) to Maester 2.3.0.

## Reviewed inputs

- Canonical Reference #133: commit `15625809704898465f370d488d6b2f88978e3cbd`,
  source tree `67ac37e329d0d914646c048073eba9b72cbf9cfc`; hooks 2.0.0 and
  delegated coordinator 1.0.0. Every vendored byte is checked against the lock.
- Official Maester 2.3.0 package SHA-256
  `95F720822D04271F5E15F4665BC017111DC72E17B97E5D0525CB4EC2FF5BD0B0`;
  source commit `7413c42d3fcc724dfea94d2726e690ddd364d914`.
- Existing exact Graph Authentication 2.41.0 and Pester 6.2.0 package locks.
  The maintained installer verified and extracted all three official packages
  from local evidence. No package or module download was needed for this run.

## Offline results (2026-10-19)

- PowerShell 7.6.6 / Pester 6.2.0 repository suite: **199 passed, 0 failed,
  2 skipped**. The skips are the pre-existing Windows batch-launcher cases on
  Linux. No assessment test was excluded to conceal errors.
- All PowerShell scripts, modules and data manifests parse successfully.
- `git diff --check` passes.
- Official Bicep 0.42.1 compiles `infra/main.bicep`. Recursively ignoring only
  generated compiler metadata, output is identical to checked-in `main.json`.
  Infrastructure source and compiled deployment template were not rewritten.
- `tests/Invoke-Maester230Compatibility.ps1` runs the production configuration,
  invocation and pure health gate against the actual hash-verified modules.
  It confirms the 519 bundled test-file inventory, accepts a real policy finding
  (1 pass, 1 finding, 1 explicit skip, 2 upstream-default NotRun cases), and
  rejects runtime I/O failure, setup failure and a skipped required core case.
  Pester engine errors remain visible in JUnit. All transport/authentication/
  installation/mail tripwires record **0 attempts**.

The same compatibility check is wired into CI after exact-package verification.
This record describes local results; CI for a future published commit must be
checked separately.

## Preserved and strengthened boundaries

The real Function setup caller still uses exact deployment outputs, ownership,
resource kinds, the selected subscription/tenant and fresh Enabled-state checks.
It now returns a hashed aggregate read-only plan by default. A stale approval or
failed Exchange inventory prevents all access writes, receipts and ZIP deployment.
Selected Exchange token acquisition stays tenant-bound before any role write;
legacy skip preferences cannot bypass that boundary. The independent ZIP and
validation entrypoints retain their own fresh target checks.
The post-ZIP wrapper does not reopen Graph or infer Teams readiness from unrelated
application roles; setup responses explicitly leave propagation unverified. An
offline subprocess regression covers the real helper reset, plan-only early
return, no polling/reconnection, and visible optional native-validation failure.

Runtime stays managed identity only. The bundled health module has no setup or
permission-grant capability. The existing request/invocation-bound validation
receipt is retained; a successful receipt now follows strict assessment health
and the existing required publication boundaries. Genuine policy findings remain
valid assessment results. Runtime, permission and engine errors do not become
false success simply because HTML exists.

## Remaining gates

No Azure authentication, setup-app creation or bootstrap, admin consent, access
assignment, infrastructure deployment, ZIP submission, native invocation, mail,
merge or release was performed. Effective Graph/workload access, license/API
coverage, refreshed managed-identity tokens, propagation, native FC1/B1 behavior,
mail delivery and report access remain separate authorized validation gates.
Existing broader grants are preserved and disclosed, including their possible
mail/report-privacy consequences. See [the migration](setup-consent-migration.md)
and [release/coverage notes](maester-230-upgrade.md).
