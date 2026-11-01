# ASTRA-SELFHOST-LEXER-2

Lexer and source ownership qualified in the selected hosted GNU x86-64 profile.
The public full compiler remains Vala. Parser/AST, semantic analysis and IR/backend
ports, Stage 1 equivalence, foreign-platform qualification and full registry
execution were not performed.

The clean intake was `7edd2fc7f949d568d8cd973ff061554604d1345e`, tree
`03593ab5b25c98d8295ed10c274d058dbce32dcd`. The read-only donor's HEAD and existing
status stayed unchanged at `61d1529956369770fc817563a43b0038b852ab90`.
No donor products or source were modified. Previous target builds remain intact.

## Changes and preservation

Commit `06f7667` moved all 332 files from `bootstrap/vala/src/` directly into
`bootstrap/`, byte/mode exact, and adapted active routing. The full
[relocation map](../../bootstrap/relocation.json) retains original blobs/hashes.
All 330 compiler implementation/template inputs retain their original bytes;
no bootstrap semantic repair was made. `compiler/source/` is unchanged.

Commit `9777249` removed six dependency-reviewed historical output tables,
2,188,400 bytes in total. [Restoration instructions](active-tree.md) identify the
pre-cleanup commit. All 207 document candidates and every example directory have
one external disposition inventory in the report. The remaining 201 document
candidates are retained for context or unresolved replay dependencies. The
[example tour](../../examples/README.md) curates ten projects without deleting
shared qualification fixtures. The synthetic frozen-profile test now creates
its actual `src/unit` fixture directory; its frozen source/expectations remain
unchanged, and all 15 profile controls pass.

Seven historical release receipts referenced by `tools/release/candidate.py`
were already absent at intake. The audit verifies the exact missing set remains
unchanged; no successful historical release replay is claimed. Both large
release registry tables and all available explicit release inputs were retained.
No removed table is read by the audited current runners or install manifests.

The new [scanner API](../../compiler/syntax/README.md) retains source identity,
spans, exact/generated spellings, counted decoded payloads and comment trivia.
It preserves the existing 92 token kinds, ASCII identifiers, numeric boundaries,
maximal munch, Unicode validation/escape errors, first-error precedence and
independent forks. Its algorithms execute in Astra. A narrow Vala adapter uses
the unchanged reference scanner and exact extracted decoder class.

## Current evidence

- Strict new-path production C0 build; compiler SHA-256
  `b3509c00315900eb81d0e54fbc756e762d467ffcd225116d9a78d06a461eb6f4`.
  [Seed metadata](../../bootstrap/seed.lock.json) binds source, generated inputs,
  flags, linked dependencies and libraries, and references the previous seed.
- O0/O2 exact differential batch results on 2,127 real Astra sources, 448 bounded
  generated inputs and 18 hand-authored cases. Independent checks include every
  keyword and suffix boundary, maximal munch, numeric and Unicode/NUL behavior,
  error precedence, and offset-mapped whitespace/comment transformations.
- Fork continuation for every corpus input; explicit independent error state,
  empty fork trivia, repeatable EOF/failure, generated spelling, token/trivia
  survival and same-versus-distinct source checks. Four O0/O2 Valgrind executions
  report zero errors and all heap blocks freed.
- Existing source component passes 63 encoding/byte cases, eight path cases per
  profile, span identity/coverage and six memory checks with the rebuilt C0.
- Opaque foreign-unit continuity passes 108 commands. Layout-cache lifetime
  passes O0/O2 import/rebind routes, malformed layout rejection and deterministic
  retained-cache negatives. Independent verifier boundaries were not modified.
- All 9,564 inherited registrations and 1,089 test-call templates preserve their
  full argument/expected-result/timeout/serial contracts after explicit routing
  normalization. One new lexer registration and compiler-selectable target are
  added. Catalog comparison is not registry execution.
- Full read-only formatting: 4,468 sources, zero changes, 192.27 seconds. The later
  preservation recipe and final component edits pass the ten-source targeted
  check. All 452 exclusions, including five Windows command scripts, match their
  hashes. Twelve formatter guards pass with the pinned tools.

The production Ninja log records a 138.293-second build span. The final scanner
attempt records 6.910 seconds compiling changed O0/O2 products, 4.603 seconds of
scanner/behavior execution and 1.317 seconds of Valgrind. Matching oracle/runtime
products were reused. These phases overlap other work; they are not total campaign
elapsed time. Setup, editing, cleanup and early development were not individually
timed. Runtime records retain earlier attempts, command costs and final identities.

## Failure history and limits

Development failures included unsupported enum field/property storage and raw
string fields, missing explicit strong clones before shared-field borrowing,
and a borrowed-text forwarding result rejected by SSA verification. The final
API uses existing scalar storage, typed methods, owned messages, explicit clones
and static diagnostic selection. No compiler exception or pointer cast was added.
The first build request preceded completion of C0. A preliminary formatter-guard
run used the unqualified PATH formatter; the pinned rerun passed.

A new hand case incorrectly counted a 21-byte literal as 22; its expectation was
corrected without changing historical goldens. Differential tests found and fixed
backspace diagnostic escaping and missing `dot`/`mac` keyword entries. New explicit
keyword expectations cover that omission. An early token-table extraction omitted
the two digit-bearing enum names and was corrected before successful builds.
Initial development log names were reused before the durable runner existed;
the transcript and this failure inventory preserve those outcomes, while later
attempts retain separate artifacts. No uninterrupted-green-run claim is made.

The initial deletion approval review rejected the tables as potentially historical
record loss. Byte/mode comparison against committed Git objects and the packet's
explicit recoverable-cleanup authority resolved that rejection on retry. Historical
outcomes remain recoverable and their narratives retain their original scope.

The publisher's path-filtered patch exceeded its automatic patch cap even though
the rename-aware patch is smaller. Report evidence therefore contains ordered,
lossless `patch-01.txt`, `patch-02.txt` parts; concatenate them in that order.
`summary.json` records the full patch hash and reconstructed final tree. A separate
index application at the exact intake base verified that reconstruction. Initial
publication is retained through the installed report-amendment facility.
