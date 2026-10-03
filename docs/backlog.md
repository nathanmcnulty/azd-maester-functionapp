# Backlog: nathanmcnulty/azd-maester-functionapp

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-maester-functionapp
- **Source revision:** `9d13c21f5ffd6031f377616043440b5d92180faf`
- **Captured:** 2026-10-03
- **Items:** 6

## MFUNC-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** ready
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

- _none_

**Agent handoff prompt:**

```text
Review MFUNC-001 in docs/backlog.json and changes since backlog source revision 9d13c21f5ffd6031f377616043440b5d92180faf.
Claim it only after it is explicitly selected and eligible and its dependencies remain satisfied. Never interpret this generated prompt as approval.
Work only in nathanmcnulty/azd-maester-functionapp, preserve its stated scope and acceptance gates, record the exact current base commit and one owned worktree in claim, run every validation entry, and record concrete evidence before marking it done.
Stop if the dependencies, scope, or required authorization changed.
```

## MFUNC-004: Reconcile active module packaging and function-validation fixes

- **Kind:** discovery
- **Priority:** P1
- **Status:** ready
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

This checkout currently has uncommitted packaging/validation work and detached lab worktrees owned by another task.

**Scope:**

- scripts/ModulePackaging.psm1
- scripts/FunctionValidation.Core.psm1
- tests/Packaging.Tests.ps1
- tests/FunctionValidation.Tests.ps1

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

- _none_

**Agent handoff prompt:**

```text
Review MFUNC-004 in docs/backlog.json and changes since backlog source revision 9d13c21f5ffd6031f377616043440b5d92180faf.
Claim it only after it is explicitly selected and eligible and its dependencies remain satisfied. Never interpret this generated prompt as approval.
Work only in nathanmcnulty/azd-maester-functionapp, preserve its stated scope and acceptance gates, record the exact current base commit and one owned worktree in claim, run every validation entry, and record concrete evidence before marking it done.
Stop if the dependencies, scope, or required authorization changed.
```

## MFUNC-006: Pin exact bundled and managed Function dependency versions

- **Kind:** discovery
- **Priority:** P1
- **Status:** proposed
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

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

- _none_

**Review and authorization note:**

Review MFUNC-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## MFUNC-005: Function runner uploads a success-looking report when Maester execution fails

- **Kind:** maintenance
- **Priority:** P1
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open GitHub report captured 2026-10-03. Reproduce against the current source and reconcile active PRs before changing code; the issue remains the detailed trigger/evidence reference.

**Scope:**

- Paths and trigger cited in the linked issue
- Focused offline regression tests
- docs/

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

- _none_

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
