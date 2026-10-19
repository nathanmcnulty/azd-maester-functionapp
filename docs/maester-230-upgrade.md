# Maester 2.3.0 source upgrade

This change pairs the stable **2.3.0** package and its bundled test suite with the
reviewed, vendored Full/Minimal permission manifest. It does not grant consent,
register applications, deploy resources, send mail, or certify a native Function assessment.

## Release and byte provenance

- Official [release 2.3.0](https://github.com/maester365/maester/releases/tag/2.3.0),
  source commit `7413c42d3fcc724dfea94d2726e690ddd364d914`
- [PowerShell Gallery 2.3.0](https://www.powershellgallery.com/packages/Maester/2.3.0)
  `.nupkg` SHA-256 `95F720822D04271F5E15F4665BC017111DC72E17B97E5D0525CB4EC2FF5BD0B0`
- Bundled `maester-tests`: 519 test files and 524 total files; package config
  version `2026.10.06.1`. Every test file matches the release commit byte-for-byte.
  The packaged config updates its release/version fields.
- Package dependencies remain compatible with the existing reviewed Graph
  Authentication 2.41.0 and Pester 6.2.0 pins. Other module pins are unchanged.
- The upstream module manifest still declares PowerShell 5.1 as its own minimum.
  The host deliberately retains its stricter PowerShell 7.6/.NET 10 contract.

No floating `latest`, main-branch tests, `Update-MaesterTests`, or preview package
is introduced. Package verification happens before import. Hashes establish byte
integrity; they are not independent publisher signatures.

## Explicit compatibility changes

The maintained runner selects **exactly** Maester 2.3.0, and the strict assessment
result parser accepts that version only. Old 2.2.0 results, future 2.3.1/3.0.0
results, and preview labels cannot satisfy the assessment-health gate. The
Function validation request/receipt correlation remains unchanged; a Succeeded
receipt is now written only after the health gate and required publication.
Package, runner, result fixture and health-gate pins changed together.

The strict ErrorRecord, JUnit, core-test path/identity, count and report-hash
checks are adapted from the reviewed Container health gate. Existing Function
trigger request/invocation correlation and failure propagation remain. Policy findings may
be valid assessment outcomes; runtime/permission/engine errors are not silently
converted to compliant findings. HTML existence or job success is insufficient.

`tests/Invoke-Maester230Compatibility.ps1` uses the actual locked Maester 2.3.0 and
Pester 6.2.0, two bundled test wrappers with offline policy adapters, and the
production invocation/configuration/health blocks. It checks:

- A real policy assertion result is accepted, with exactly 1 pass, 1 finding,
  1 explicit skip and 2 visible upstream-default exclusions
- A runtime I/O error, setup failure and missing/skipped core test are rejected
- Actual Pester engine errors remain recorded in JUnit
- Inherited drift input is isolated and restored
- No HTTP, workload authentication, installation or output-message tripwire fires

This is real-package compatibility with synthetic inputs, not an assessment of
all 519 test files against a tenant. The full bundled suite remains installed.
Preview and LongRunning retain upstream opt-in defaults; AD needs explicit host
connection. No exclusion is based on a permission-error string.

## Permissions and coverage

The vendored `Maester-GraphPermissions.json` defines Full27, unchanged Minimal8,
and explicit legacy Extended19. Full uses the 25 release-matched read roles plus
Policy.Read.DeviceConfiguration and Sites.Read.All, supported by the actual
application-authenticated endpoints. Sites.Read.All also permits reading
content across all site collections; its broader consequence is in the consent
plan metadata and must be reviewed. Mail.Send and report-privacy writes remain
separate capabilities.

Graph app roles do not authorize Exchange, Teams, Azure or other workloads by
themselves. Full is a reviewed stable Graph baseline, not a guarantee every test
runs. Licenses, API support, service connections, report privacy and the explicit
unverified API dependencies in the manifest remain coverage limits. Choosing
Minimal retains the suite and visible gaps. Existing grants are not revoked.
Grant readback alone does not prove refreshed managed-identity tokens.

One explicit gap is `GET directory/onPremisesSynchronization`: Microsoft's
[v1.0](https://learn.microsoft.com/en-us/graph/api/onpremisesdirectorysynchronization-get?view=graph-rest-1.0)
and [beta](https://learn.microsoft.com/en-us/graph/api/onpremisesdirectorysynchronization-get?view=graph-rest-beta)
contracts mark application access unsupported, despite the upstream application
read role existing. Stable Maester soft/hard-matching and object-identifier
checks use those endpoints. The baseline role remains; app-only support remains
unverified. Existing report-privacy write grants can also enable upstream MOERA
setting changes even when the selected profile adds no new write role.

## Native acceptance and module maintenance

Native validation remains a separate, explicitly authorized gate: inspect actual
host/module receipts, effective workload permissions, full assessment accounting,
per-workload gaps, report delivery/access and retention/rollback. Existing 2.2.0
native receipts remain historical evidence and have not been relabeled as 2.3.0.

The later PowerShell-module maintenance proposal is to add a source-only updater
that checks official stable Gallery versions, downloads exact package bytes,
refreshes provenance, reviews API/permission deltas, and opens a draft with full
compatibility tests. It must never silently update runtime permissions, grant
consent, deploy, or treat Dependabot as covering PowerShell Gallery packages.
That automation is not implemented by this change.

## Function-specific validation boundary

The existing [native Function qualification](function-runtime-validation.md) and
[fresh-target evidence](fresh-target-validation.md) remain historical evidence for
their recorded commits and package versions. They are not 2.3.0 native evidence.
The source change retains FC1/B1 support, native ZIP deployment guards, bounded
subprocess handling, exact submitted-ZIP preservation on uncertain completion,
and private request-correlated validation receipts. Full 2.3.0 workload, mail,
report access, and platform acceptance require a separate authorized native run.

Configuration drift stays disabled. Its pre-discovery exclusion and inherited
input isolation predate this upgrade and prevent unapproved input consumption;
no new permission-error or failing-test exclusion is added. Preview and
LongRunning remain the upstream defaults. This is no claim that all tests ran.

Archive publication remains best-effort as before. Latest-Blob publication,
configured Web App publication, and the private validation receipt have their
existing failure behavior. Mail uses upstream Maester delivery and is not
independently verified. A recipient alone never authorizes a new Mail.Send grant;
an existing Mail.Send grant can still permit configured upstream mail. Likewise,
existing ReportSettings.ReadWrite.All can enable upstream report-privacy changes
although the selected profile requests no new write role. The plan preserves and
shows existing access rather than silently revoking it.
