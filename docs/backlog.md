# Backlog: nathanmcnulty/azd-maester-functionapp

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-maester-functionapp
- **Source revision:** `edd46eb043b632aa41e97e3d16c7bdb09e7a4d5c`
- **Captured:** 2026-10-04
- **Items:** 6

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
- **Status:** proposed
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

- _none_

**Review and authorization note:**

Review MFUNC-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-002: Qualify Function App execution and optional report-webapp lifecycle

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** azure-deployment
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Shared pilots are already vendored; host-specific execution and report access still need independently bound evidence.

**Scope:**

- scripts/Invoke-FunctionValidation.ps1
- docs/
- infra/
- tests/TargetContext.Tests.ps1

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

**Evidence:**

- _none_

**Review and authorization note:**

Review MFUNC-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
