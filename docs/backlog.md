# Backlog: nathanmcnulty/azd-maester-functionapp

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-maester-functionapp
- **Source revision:** `ed8668d84ed2ccd66bba94c1298916ca285ca64d`
- **Captured:** 2026-10-07
- **Items:** 8

## MFUNC-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md

**Evidence:**

- Reconciled later reviewed metadata tip 6d20764649a80a720cd4d234119e571333c4dd91 against freshly fetched origin/main edd46eb043b632aa41e97e3d16c7bdb09e7a4d5c. Current main adds reviewed source fixes from pull request&lpar;s&rpar; &num;16, &num;17, &num;19 and &num;21; no dirty canonical bytes or unrelated branch history were copied.
- Current repository issues and pull requests were read on 2026-10-04&colon; none are open. Items MFUNC-002, MFUNC-003 remain proposed because their component, host-specific live, or shared azd-maester issue gates are not satisfied by source merges alone; completed issue-backed fixes retain exact issue and pull-request evidence.
- Full current-source offline Pester validation passed 42/42 tests with zero failures. Canonical backlog schema and generated-Markdown checks also passed; no Azure, Graph, deployment, report publication or other live operation was performed.

**Review and authorization note:**

Review MFUNC-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-004: Reconcile active module packaging and function-validation fixes

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The report captured on 2026-10-03 is closed after the reviewed fix merged; this record preserves the original trigger and validation boundary.

**Scope:**

- scripts/ModulePackaging.psm1
- scripts/FunctionValidation.Core.psm1
- tests/Packaging.Tests.ps1
- tests/FunctionValidation.Tests.ps1
- docs/backlog.json
- docs/backlog.md
- BACKLOG.md

**Acceptance:**

- Obtain current owner outcome and exact integrated revision before proposing another fix.
- Validate package contents, pinned module availability and function job evidence with the existing focused tests.
- Do not stage, revert or duplicate the active dirty work; record whether follow-up is still required.

**Validation:**

- git status --short
- git worktree list --porcelain
- Read the active owner handoff and current diff; run no live function validation from this discovery task.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- scripts/Deploy-FunctionCode.ps1
- scripts/Invoke-FunctionValidation.ps1
- https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/issues/11
- https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/issues/9

**Evidence:**

- Current owner outcome is integrated&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/pull/13 closed packaging issue &num;11 at 7cb3ce3143fd376f1382c8d562f1f87390458189, and https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/pull/14 closed validation issue &num;9 at current main b1ad59802ef9f952ac024e0fd2dcfdae328cd643.
- Current-head packaging installs the locked modules before ZIP creation and stops on failure&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/blob/b1ad59802ef9f952ac024e0fd2dcfdae328cd643/scripts/Deploy-FunctionCode.ps1&num;L83-L104; validation requires the current request terminal receipt&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/blob/b1ad59802ef9f952ac024e0fd2dcfdae328cd643/scripts/FunctionValidation.Core.psm1&num;L3-L21
- Focused current-main tests passed 14/14 locally on 2026-10-03&colon; tests/PackageFailure.Tests.ps1, tests/FunctionValidation.Tests.ps1 and tests/ValidationReceipt.Tests.ps1. No live function or provider operation was invoked.
- Exact current-main validation passed&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/actions/runs/37146917170/job/111272674031
- Live evidence gap preserved&colon; PR &num;14 claims no live Function invocation, Graph run, HTML delivery or queue/admin host acceptance; those remain integration evidence boundaries.
- GitHub issue &num;11 is closed by merged pull request &num;13; current origin/main edd46eb043b632aa41e97e3d16c7bdb09e7a4d5c contains the reviewed fix. Source closure does not claim a new live deployment, report publication, or human-visible result.

**Review and authorization note:**

Review MFUNC-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-006: Pin exact bundled and managed Function dependency versions

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The report captured on 2026-10-03 is closed after the reviewed fix merged; this record preserves the original trigger and validation boundary.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/issues/12

**Evidence:**

- GitHub issue &num;12 is closed by merged pull request &num;14; current origin/main edd46eb043b632aa41e97e3d16c7bdb09e7a4d5c contains the reviewed fix. Source closure does not claim a new live deployment, report publication, or human-visible result.

**Review and authorization note:**

Review MFUNC-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-005: Function runner uploads a success-looking report when Maester execution fails

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The report captured on 2026-10-03 is closed after the reviewed fix merged; this record preserves the original trigger and validation boundary.

**Scope:**

- Paths and trigger cited in the linked issue
- Focused offline regression tests
- docs/
- docs/backlog.json
- docs/backlog.md
- BACKLOG.md

**Acceptance:**

- Classify the report as still reproducible, already fixed, superseded or requiring live evidence; record the exact current revision.
- For a reproducible defect, demonstrate the linked trigger with an offline regression and apply the smallest fix preserving tenant/target/ownership and failure semantics.
- For a feature, produce a bounded design with compatibility, optional permissions, acceptance and rollout gates before implementation; no live mutation or automatic issue closure.

**Validation:**

- Read the issue body and current source/PRs; capture the exact reproduction and existing registered offline validation command.
- Use deterministic fixtures for the described trigger and negative boundary; retain current-source results. Do not rerun production or tenant operations to reproduce it.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/issues/10
- README.md

**Evidence:**

- Merged fix&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/pull/13 closed issue &num;10 at 7cb3ce3143fd376f1382c8d562f1f87390458189; the fix is present on current main b1ad59802ef9f952ac024e0fd2dcfdae328cd643.
- Current-head runner throws on Maester failure or missing genuine output, fails required publication, writes success only after completion and rethrows after attempting a failed receipt&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/blob/b1ad59802ef9f952ac024e0fd2dcfdae328cd643/src/MaesterTimerTrigger/run.ps1&num;L428-L507
- Deterministic regression coverage proves thrown invocation, missing report, genuine findings and failed publication behavior&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/blob/b1ad59802ef9f952ac024e0fd2dcfdae328cd643/tests/RunnerFailure.Tests.ps1&num;L43-L88
- Exact current-main validation passed&colon; https&colon;//github.com/nathanmcnulty/azd-maester-functionapp/actions/runs/37146917170/job/111272674031
- Live evidence gap preserved&colon; no live Function invocation, Graph run, HTML delivery or queue/admin host acceptance is claimed by this reconciliation.
- GitHub issue &num;10 is closed by merged pull request &num;13; current origin/main edd46eb043b632aa41e97e3d16c7bdb09e7a4d5c contains the reviewed fix. Source closure does not claim a new live deployment, report publication, or human-visible result.

**Review and authorization note:**

Review MFUNC-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-003: Reconcile shared hook/webapp versions and host permission deltas

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Existing adoption must be updated through hashes and host-specific validation rather than blindly reinstalling components.

**Scope:**

- azd-components.lock.json
- azd-permissions.json
- scripts/
- infra/
- docs/

**Acceptance:**

- Compare lock pins with canonical manifests and current-source drift before proposing an update.
- Run target-context negative cases and compare minimal versus optional-feature permissions.
- Keep Maester execution and reporting host-specific; record exact source hashes and candidate/pilot status.

**Validation:**

- Invoke-Pester ./tests/TargetContext.Tests.ps1 -CI
- Read and compare lock hashes with canonical reference source; do not overwrite drift.

**Dependencies:**

- _none_

**Components:**

- maester-azd-hooks
- maester-report-webapp

**Sources:**

- README.md
- azd-components.lock.json

**Evidence:**

- Adopted pilot maester-azd-hooks 0.1.6 from immutable azd-reference revision a09cac311aac7362f56d2a31833ed90ce5812649. All eight managed targets match the component manifest and lock; only Maester-UpWizard.psm1 changed from 0.1.5, to require a non-empty GUID before persisting the optional Web App group Object ID.
- Preserved maester-report-webapp 0.1.1 at immutable revision 79f0608c672639aae0f0ed96d160b1eb17cfc08f with exact vendored hash 4b12708c76489f3f20e031fdafc706a3062276ef4a83fda7f5109f4cbd902972.
- Added a schema-valid partial permission manifest with exactly 24 source-proven declarations&colon; eight Minimal runtime roles, eleven additional default Extended roles, four deployment-operator scopes, and optional Mail.Send. Working and raw-index comparisons returned 8/19/20/4 permissions with no evidence findings; comparisonComplete remains false and explicit gaps preserve unmodeled Azure RBAC, optional feature, operator and cleanup authority.
- The 0.1.6 permission helper is byte-identical to 0.1.5 at SHA-256 e43b6e4ce60c9adef30355cc126519e5f754c01630c94fca9d85c04aebde3548; this adoption adds no declared scope or grant and claims no effective tenant permission.
- Offline validation passed&colon; TargetContext 5/5, full host suite 42/42, PowerShell parse 29 files with zero errors, Bicep compilation to valid JSON SHA-256 8820a75098c4e6c46eb97e574324f67dbd18b72ddbcf6f96d2c11c769a97cebc, canonical permission comparison tests 9/9, component/lock drift checks, backlog schema, generated Markdown and diff checks.
- No Azure, Graph, deployment, report publication or live host operation was performed. Host-specific live execution, report access and cleanup remain under item 002 and are unchanged.

**Review and authorization note:**

Review MFUNC-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-002: Qualify Function App execution and optional report-webapp lifecycle

- **Kind:** verification
- **Priority:** P1
- **Status:** in-progress
- **Wave:** 2
- **Authorization:** azure-deployment
- **Blocker:** _none_
- **Claim owner:** codex/root
- **Claim worktree:** C&colon;/azd-reconciliation-20261016/function-runtime-review
- **Claim base revision:** `d817c055e9ebc42c7c2ba79053a0188671e29338`
- **Claim started:** 10/15/2026 20&colon;59&colon;34

**Problem:**

Shared pilots are already vendored; host-specific execution and report access still need independently bound evidence.

**Scope:**

- scripts/Invoke-FunctionValidation.ps1
- docs/
- infra/
- tests/TargetContext.Tests.ps1
- scripts/Deploy-FunctionCode.ps1
- tests/PackageFailure.Tests.ps1

**Acceptance:**

- Record exact Maester/runtime/component revisions and host execution output under the selected tenant.
- Validate optional webapp identity, report publishing, Easy Auth and feature-specific permission delta.
- Disabled web hosting works independently; cleanup preserves adopted objects and records exact owned resources.

**Validation:**

- Invoke-Pester ./tests/TargetContext.Tests.ps1 -CI
- After separate authorization use ./scripts/Invoke-FunctionValidation.ps1 against the exact owned host; retain report access and cleanup evidence.

**Dependencies:**

- _none_

**Components:**

- maester-azd-hooks
- maester-report-webapp

**Sources:**

- README.md
- scripts/Invoke-FunctionValidation.ps1
- docs/function-runtime-validation.md

**Evidence:**

- 2026-10-16 partial native runtime qualification at d817c055e9ebc42c7c2ba79053a0188671e29338&colon; both FC1/B1 ARM deployments succeeded; FC1 executed PowerShell 7.6.5/.NET 10.0.11, loaded the five locked modules including Maester 2.2.0/Pester 6.2.0 and denied anonymous probe access. Both assessment triggers were disabled. B1 Kudu deployment remained incomplete after CLI timeout; no duplicate ZIP was submitted, and its runtime remains unproven. Exact owned resource group, two storage role assignments and two managed-identity principals were verified absent. Deployment code now stops after one unconfirmed submission and preserves the exact ZIP; regression tests cover timeout, generic failure and confirmed-success cleanup. Full collection/report/viewer lifecycle acceptance remains open; see docs/function-runtime-validation.md.
- 2026-10-16 source baseline follow-up&colon; CI asserts/logs PowerShell 7.6+, explicitly imports/logs Pester 6.2.0 in the test process, and the validation module now requires PowerShell 7.6. Expanded the existing entry-point test to inspect actual AST version requirements on owned scripts/modules and worker scripts. All 74 offline tests pass on PowerShell 7.6.6/Pester 6.2.0; source parsing and permission evidence hashes/schema pass. This does not change the native trial revision or close the B1, collection/report, permissions or existing-target preservation gates.
- 2026-10-16 fresh B1 isolation at c8cfc7957ffee23538289587e82f6c07d334fd6b&colon; ARM/configuration/disabled-trigger readback passed. One 1,740-byte module-free runtime ZIP reached concrete Kudu status 1 &lpar;Building and Deploying&rpar; but remained incomplete at the ten-minute observation limit; no worker execution is proven. No module ZIP, duplicate upload or assessment was submitted. The CLI returned nonzero; temporary and concrete Kudu records were preserved separately. Owned group absence, exact storage-role ARM 404, managed-identity Graph 404 and unchanged CLI default were verified after deliberate teardown. B1 remains unproven; diagnose the deployment/startup boundary before another identical fixture. See docs/function-runtime-validation.md.

**Review and authorization note:**

Review MFUNC-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-007: Implement optional Caddy Container App report viewer

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 4
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The shared viewer design is complete, but this standalone Function runner has no Caddy provider implementation.

**Scope:**

- infra/
- scripts/
- docs/
- azd-permissions.json

**Acceptance:**

- Add exact -IncludeContainerWebApp mapping, default-off and exclusive with both other viewer flags, including legacy -IncludeWebApp; preserve existing hooks and deployment-validation behavior.
- Use only an immutable signed image/SBOM and reviewed versioned azd-reference component pin; publish a private bounded HTML projection plus manifest with ETag/conditional pointer, BlobDataContributor only where required, and viewer managed identity read-only.
- Bound Caddy paths, fixed loopback GET/HEAD routes with no shared report volume, size/poll/LKG/atomic switch, HTTPS and native tenant/audience group authorization; reject missing/overage groups, foreign tenant, forged headers and host bypass. Record owned rollback/deletion receipts and validate with offline fixtures before authorized lab writes.
- Use a dedicated viewer-projection container with immutable HTML/manifest versions and an ordered ETag-conditional latest pointer. Assume all app containers can use attached identities; expose no archive, Graph or resource-write privilege to the viewer.
- Before feature completion, pass the design native gates in the authorized lab with concrete tenant/subscription/group/test users&colon; allowed and denied report/asset/host access, exact report bytes, concurrency/staleness, provider-specific rotation/cold start, rollback and ownership-aware cleanup. Preserve failed evidence; no live success claim from fixtures.

**Validation:**

- Run the existing standalone validation workflow and new offline native fixtures; fixtures do not prove live auth, provider acceptance or report receipt.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-maester/blob/main/docs/report-viewer-design.md
- https&colon;//github.com/nathanmcnulty/azd-maester/issues/5

**Evidence:**

- _none_

**Review and authorization note:**

Review MFUNC-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-008: Implement optional Static Web Apps Standard report viewer

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 4
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The shared viewer design is complete, but this standalone Function runner has no Static Web Apps provider implementation.

**Scope:**

- infra/
- scripts/
- docs/
- azd-permissions.json

**Acceptance:**

- Add exact -IncludeStaticWebApp mapping, default-off and exclusive with both other viewer flags, including legacy -IncludeWebApp; preserve existing hooks and deployment-validation behavior.
- Use Standard/custom tenant issuer and a reviewed Report.Reader role-source function/claim mapping with fail-closed missing, invalid and overage claim behavior; do not add tenant-wide Graph reads.
- Keep end-user UAMI/FIC distinct from the high-trust deployment-token publisher; bind fixed safe HTML, auth config, hash, revocation/reset and owned teardown receipts. Validate offline before authorized lab writes.
- Qualify the documented preview/support posture of function-based role assignment. Keep site-deployment authority and token access out of Maester runners&colon; a separate trusted publisher must bind fixed auth/function config hashes and reject report-supplied config or code.
- Before feature completion, pass the design native gates in the authorized lab with concrete tenant/subscription/group/test users&colon; allowed and denied report/asset/host access, exact report bytes, concurrency/staleness, provider-specific rotation/cold start, rollback and ownership-aware cleanup. Preserve failed evidence; no live success claim from fixtures.

**Validation:**

- Run the existing standalone validation workflow and new offline native fixtures; no deployment or delivery claim is made.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-maester/blob/main/docs/report-viewer-design.md
- https&colon;//github.com/nathanmcnulty/azd-maester/issues/4

**Evidence:**

- _none_

**Review and authorization note:**

Review MFUNC-008 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
