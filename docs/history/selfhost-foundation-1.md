# ASTRA-SELFHOST-FOUNDATION-1

Foundation and first component qualified within the tested hosted GNU x86-64
profile. The full compiler is still the Vala bootstrap. Full post-migration
registry, foreign-platform qualification and self-hosted bootstrap equivalence
were not performed.

The target starts at `e17eee6dddfe0a287cfca01c1822ee3bd08eb799`. Its Git history,
remote and project initialization remain intact. The donor stays at
`61d1529956369770fc817563a43b0038b852ab90`, including its pre-existing untracked
work. The repaired ancestor is `88eca9e953ec418994ac5b4a2ee97db7d7a354bc`;
the intervening rename changed routing/documentation, not compiler semantics.

The exact handoff was validated before extraction; its read-only binder produced
a submission pinned to the target's actual initial HEAD. Installed `pm-next`
intake accepted that exact submission. No donor hash was substituted for the target
base, no integration was replaced, and no public push occurred.

## Preservation and layout

The private self-contained history bundle restores 102 original refs, 551 unique
old/new reflog commit roots and 24,701 reachable objects. An independent restored
repository passed strict fsck, ref/object/tree comparisons and independence checks.
Its SHA-256 is in `bootstrap/provenance.json`; raw config, hooks, reflog text and
17 untracked donor files are retained separately in private local-state storage.
External tools and old builds remain protected in place. This archives locally
available history; it does not fetch unavailable remote objects.

The final inventory accounts for all 6,622 donor entries: 5,629 unchanged,
386 moved byte-exact, 382 adapted and 225 external-only. Each record binds original
and destination modes, Git blobs and SHA-256, plus adaptation commit and reason.
The full inventory is split into report evidence; its hash is in public provenance.
Raw historical receipts and donor-local workflow state remain private. Historical
frozen challenges still require their original private context and are not claimed
as current target passes.

Compiler sources move to `bootstrap/vala/src`; public Astra libraries stay in
`lib/astra`; runtime C/headers and foreign bindings have one canonical home in
`lib/runtime` and `lib/bindings`. Installed API paths stay stable. License/notices
remain intact. Path adaptations preserve test expectations and fixture bytes.
Six frozen helper scripts accidentally adapted in the routing commit were restored
byte-exact in `a98179c`; their exclusion hashes were never changed.

## Seed and component

`bootstrap/seed.lock.json` binds the new C0, all 330 unchanged compiler implementation
files, generated inputs, linked host dependencies, strict build flags and the
96-file consumer library inventory. C0 SHA-256 is
`bd0f446909476c33ed7d616de9b63c01364a104b4c33e3d785f482b897f5ac01`.
The inherited RC2 banner is historical, not a new qualification. Production
configuration/build access traces show no donor or historical build-root reads;
this is access-trace evidence, not a filesystem-denial sandbox claim. Paired tests
intentionally use the preserved corrected reference compiler as their second oracle.

The new Astra implementation owns source bytes, computes line starts and locations,
validates encoding, retains spans, normalizes paths, sorts/rejects duplicate paths
and renders diagnostics. See `compiler/source/README.md` for the exact contracts,
explicit API differences and unported SourceSet collection policy.

The user approved a narrow compiler extension if needed for shared identity.
Existing call-scoped `shared_borrow` plus typed borrowed native Class equality
already implements the contract without consuming or acquiring operands. No compiler
semantic change, weak-reference extension, pointer cast or source-specific exception
was introduced. Focused tests and documentation are isolated in `77a3190`.

## Current evidence

| Check | Observed result |
| --- | --- |
| New strict production build | C0 built from target paths with fatal Vala warnings, strict C and C warnings as errors. |
| Corrected-reference comparison | 66 exact observations on identical inputs: parse, diagnostics, semantic/Core/CFG/SSA/NABI/CABI, LLVM and O0/O2 execution. |
| Layout lifetime | O0/O2 positive routes, wrong-layout rejection and deterministic retained-cache negative exit 97. |
| Foreign units | `OPAQUE_FOREIGN_UNIQUE_C_PASS`, 108 commands, separate producer/consumer and artifact-only import. |
| API-B2 | `API_B2_LINUX_SDK_PASS`, 228 commands, native/SDK/GI and memory checks; current regression mode, no historical freeze credit. |
| Shared identity | O0/O2 aliases/clones/distinct equal payloads/nulls; six negative type/lifetime cases; exact destructor counts and zero-error Valgrind. Core comparison contains two borrows and no acquire/clone/consume. |
| Shared verifier | Both TAP tests pass; existing Checked/Core/CFG/SSA/native/LLVM authority mutations and new invalid Class-comparison mutations are rejected. |
| Source component | 63 byte/encoding cases including three existing fixtures and 40 fixed-seed generated cases; every offset compared with Vala and independent arithmetic at O0/O2. |
| Paths/spans | Eight path cases per profile; same-instance and cloned handles, distinct equal-content sources, valid coverage, cross-source/reversed rejection, creator-lifetime escape and bounds errors. Vala assertion refusal checked separately. |
| Component cleanup | Six O0/O2 source/span/path Valgrind runs: zero errors; definite/indirect/possible leaks treated as failures. |
| Daily workflow | Explicit compiler-selectable script and Meson target pass; C0 digest unchanged after target execution. |
| Formatting/catalog | 4,459 sources checked read-only, including 452 protected entries; 12 formatter guard tests. All 1,087 existing Meson test-call templates retain arguments, expectations, timeouts and serial constraints after explicit path mapping. |

Earlier failed development attempts are retained in evidence: an incorrect owning
collection sort trapped and was corrected to respect `take` removal; requesting the
new Meson target before graph regeneration failed; and the detached verifier under
the production-wide fatal-warning option stopped on unused helper methods. The
verifier passed in a separate build using the documented ordinary helper warning
policy; production C0 remains strict. An initial formatter invocation selected an
unqualified system tool; the unchanged pinned tools passed the guards and full check.

## Cost and next port

Measured archive/restore: 9.69 s; initial configuration: 34.77 s; production compile:
151.31 s; separate verifier build: 151.87 s; final verifier rebuild/run: 42.45 s;
paired command sum: 6.89 s; final component command sum: 8.39 s; focused Meson graph
regeneration/component run: 29.38 s; full format check: 175.20 s. These observations
overlap and are not a wall-time total. Mapping, exploratory port work, some selected
tests and reporting lack complete phase timing and remain unmeasured. No old build
cache supplied production objects; repeated final target execution reused the exact
unchanged C0. No full registry or blanket detached-helper rebuild was launched.

Next port the lexer against the owned source/span API, retaining the separate Vala
oracle and bounded independent expectations. Then port parser/diagnostic integration;
semantic analysis, IR, ABI and backend follow later. SourceSet IDs need a separate
source-management requirement and are not needed for the identity contract.
