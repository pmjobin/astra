# GitHub CI activation — 2026-11-17

This activation is separate from release qualification. The canonical R1 report
remains byte-exact, SHA-256
`8076a8e808c64097d0d46a58c99509c448c4131f757bdd6a8c854a6096d367b2`.
The starting source was `611da1360aa769b354a9693de5cf543fbfab35ac`, tree
`ed1349bb71fc4d005da358a1b309d34aeaceb0c4`. The inspected remote is
`git@github.com:pmjobin/astra.git`, public repository ID 1440814852. Existing
history, peer work and installed tooling were preserved. Initial branch policy
was inspected; the owner's follow-up explicitly authorizes the protection below.

The owner separately approved public distribution of only the exact
2,388,496-byte bootstrap ELF with SHA-256
`560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`.
Its hash was rechecked before commitment. Static credential-pattern scans found
no matches; embedded home paths identify 31 already-public Astra source files.
Source license and dynamic dependencies were reviewed and documented in
`tools/ci/seeds/`. No C0 oracle, other private input, installer or GitHub Release
was published. Acquisition uses the raw file in immutable seed commit
`f5cb38e4026124a64c93914a0e86b6ad182bbbf7`, with an independent size/hash check.
The public download was fetched and rehashed successfully.

## Completed hosted observations

[PR #1](https://github.com/pmjobin/astra/pull/1) publishes the reviewed activation
branch without modifying main. These first observations are tied to source
commit `46890ceebd4743b93e0d67a8eee0306c63398413`, tree
`be9e7289506109933608f410ca950ce996a3817b`:

| Actual run | Outcome |
| --- | --- |
| [Push smoke 44048246918](https://github.com/pmjobin/astra/actions/runs/44048246918) | PASS: source/trust controls and authenticated Linux seed smoke |
| [PR smoke 44048513808](https://github.com/pmjobin/astra/actions/runs/44048513808) | PASS |
| [Strict nightly 44048246842](https://github.com/pmjobin/astra/actions/runs/44048246842) | FAILURE with recorded BLOCKED inputs/Windows; package jobs skipped |

The Linux runner reported `ImageOS=ubuntu24`,
`ImageVersion=20261111.370.1`, `RUNNER_ARCH=X64`. The smoke used the frozen
27-D **Stage3 O2** ELF produced by Stage2 O2. It built **zero new compiler
generations**. It compiled and linked four fresh O0/O2 arithmetic/owning-C-ABI
programs, executed them with exact exit/output checks, observed five drops
with sum 30, and checked eight type/owner diagnostic/output refusals.
The actual LLVM C API version was [23, 1, 4]. The runner-built original-archive
library had SHA-256
`ad29174faefcf33aa2ea261d73c978a0b64ad72eb1ae223b0890b4574a3351c5`.
This does not establish compiler strict-memory or release qualification.

## Downloaded artifact identities

Artifact ZIPs were actually downloaded, checked against GitHub's digest,
CRC-checked, and hashed locally. Embedded command streams, generated products
and fixture identities were independently checked. Neither the seed ELF nor
the private C0 binary was present in these artifacts.

| Artifact ID | Run | Downloaded ZIP SHA-256 |
| --- | --- | --- |
| 14312073419 — Linux smoke, 119,148 bytes | 44048246918 | `5a795acaba2ce181b021f2c2e38f550dd0eddd77747e650789655836e48fcc63` |
| 14311604519 — source controls, 6,420 bytes | 44048246918 | `747d0b9170641695895e0a84e11571c8e2d1d1e3dfeeb6974c79ea968187ce18` |
| 14312022587 — Windows blockers, 918 bytes | 44048246842 | `f75ac042be9dd317c36511084305f924af51e5f52f10ca2adbf06aa666f08d38` |
| 14311769037 — Linux strict blockers, 798 bytes | 44048246842 | `3e8045d2dc40eeb40c97a11125e07351c4723fe7fa587c0112c89db664776aa0` |

Raw API responses, job logs and artifact inventories are retained under
`~/Workspace/codex/work/astra/runtime/ci-activation-20261117/`; downloaded ZIPs
are under the matching `build/ci-activation-20261117/hosted-artifacts/` leaf.
Artifacts have bounded retention; the committed seed is the durable input.

## Gates and remaining decisions

Both source/trust controls and native seed smoke must pass for a green smoke
workflow. Main was initially unprotected. At the owner's request it now requires
`Source and trust controls` and `Authenticated Linux seed smoke`, both bound to
GitHub Actions app ID 15368, with strict freshness. Admin enforcement is enabled
and force pushes/deletion remain disallowed. Blocked strict/Windows jobs are not
required functional smoke contexts. Push and PR triggers are active
on the branch. Default-branch scheduling/manual availability follows ordinary
PR review/merge; no protection or dispatch policy was bypassed.

Strict nightly records the missing independent rebuilt-C0 oracle/runtime and
immutable 27-C source closure before expensive builds. Their portable
acquisition remains unimplemented and no private input publication is
authorized. Windows ran a real hosted feasibility check and remains BLOCKED
without a native compiler/CRT/seed/installer chain. Its failure does not gate
basic Linux smoke. Nightly consolidation writes PARTIAL and exits 78. The
first run exposed a missing `always()` on its ledger upload; the follow-up
retains that failure artifact while keeping the strict gate red. The temporary
activation push trigger was subsequently removed: strict qualification is now
scheduled/manual only, so ordinary branch pushes no longer launch it.

The original 44048246842 logs were inspected directly. Linux preflight returned
78 after recording the missing independent C0/runtime and frozen source closure.
Windows recorded its five native-port/installer blockers and its PowerShell step
exited **1**, not 78. Consolidation explicitly wrote PARTIAL and returned 78 after
failed prerequisites. LLVM strict memory was not exercised in that run because
preflight stopped first; its prior NOT_PASS remains disclosed. Node.js warnings
were not the causes of those failures.

Routine dependency maintenance updates checkout to v7.0.1
(`3d3c42e5aac5ba805825da76410c181273ba90b1`), upload-artifact to v7.0.2
(`cf430e030ddbb5b0abf93d22962f4752f3646cd9`) and download-artifact to v8.0.2
(`9000827ccba6bdab643e8b6fd33ac0654aef8333`). Official stable release tags were
resolved to these full commits, their signatures verified and `action.yml`
checked for `node24`. The existing attest v3.0.0 pin already uses Node.js 24;
it remains owner-gated and unchanged. `tools/ci/actions.json` records the audit.
The smoke artifact roundtrip exercises checkout/upload/download in hosted CI
and independently verifies the actual native products, fixtures and log hashes.
No Node.js tooling dependency was added to Astra and no attestation was signed.

Release preparation was not dispatched. Rebuilt C0 remains
ACCEPTED_WITH_DISCLOSURE with historical memory NOT_PASS; original C0/1,044
proofs remain missing. Original LLVM 23.1.4 strict memory remains NOT_PASS;
the diagnostic InstCombine rebuild was not adopted. Formal Reference remains
PARTIAL and native Windows remains unqualified. No public release, installer
promotion, code signing, new credential or secret mutation occurred.
