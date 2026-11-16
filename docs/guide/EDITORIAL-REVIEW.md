# Reader-first editorial pilot: review and evidence

This review covers only `ASTRA-RELEASE-28A2-R2-READER-FIRST-EDITORIAL-PILOT`.
The complete Guide plan and three revised opening chapters are the editorial
experiment. Its scoped editorial and executable checks passed. Final qualification
and publication identity are recorded in the delivered report.
The earlier **28-A2-R1 remains PARTIAL**. This work does not complete the formal
Reference milestone, authorize 28-B performance work or produce a release.

## Reader and standard of review

The reader can already program but is new to Astra. They should be able to
predict an example, build it in the qualified development environment, explain
its result, and repair one common mistake without first learning the compiler's
internal milestones. The official [Rust Book](https://doc.rust-lang.org/book/)
served as a benchmark for sequencing, complete examples and explanation; its
expression and distinctive examples were not copied. The five readings project
comes from Astra's existing application fixture.

The reviewer was the same `gpt-6-astra` agent in a separate deliberate pass.
This is a technical-editorial self-review, not independent human feedback or a
novice usability study. Each conceptual check below was examined separately
against exact fixtures, current Reference contracts and executable evidence.
No claim of measured learning improvement follows from the rubric.

Use this rubric for the next reader trial: can the reader state the goal before
reading syntax; reproduce setup without guessing a compiler command; distinguish
compile errors, runtime failure and successful data; explain each new concept;
predict a variation; find and run its complete answer? Score each question 0
(absent), 1 (present but requires unstated knowledge), or 2 (explicit and
reproducible). These scores describe an editorial judgment, not a percentage of
language or formal milestone completeness.

## Before, first draft and deliberate revision

The comparison baseline is commit
`750c1338239bdb9e7bd66a5e11925efa2e4711fd`. Its opening chapters were correct but
dense: Getting started had 314 whitespace-delimited words including code,
Values 780 and Records 367. Length itself was not the defect; the chapters
compressed decisions that a new reader needed to see unfold.

| Chapter | Baseline friction | First draft | Change made during critique |
| --- | --- | --- | --- |
| Getting started | An exit-42 program and instructions to select authenticated paths assumed environment knowledge before the first run. | A sum with ordinary success, visible shell output, a verified environment helper and separate compilation/runtime failures. | Added a complete O2 repeat, stated Python's prerequisite, and grouped the expected runtime failure behind successful compile/link steps so a failed build cannot fall through to an old executable. |
| Values | One first example combined filtering, 8-bit wrap, a range test and a conditional sentinel; large edge experiments interrupted the loop story. | One loop over the same five readings, an iteration table, a filtered exercise and an explicit numeric conversion. | Replaced “repeat the recipe with changes” with complete commands for the filter, rejection and repair; kept the progress step outside the conditional. |
| Records | A nominal type, shorthand, copying and generic syntax appeared together in one short example. | The readings became weighted samples, with explicit checks on both original and copy; the generic identity was still embedded too early. | Removed generics from the main project, used a concrete named call, and moved the controlled generic preview after the completed exercise. The preview retains the original fixture and captures its documented exit 42 explicitly. |

The preserved first-draft bytes and dated critique are in the report's
`runtime/books28a2-r2-draft1` evidence. The reviewer did not retroactively label
the first draft as the revised result. Original fixtures remain byte-exact and
still execute; optional edge experiments now have complete source downloads.
The book adapter counts a real fixture download as publication while retaining
strict byte comparison for every inline Astra program. Hostile-input controls
exclude code-span, fenced, external and fragment lookalikes from that count.

The baseline rubric was 1/0/1/1/0/0 (goal/setup/outcome/concepts/prediction/answer).
The revised text earns 2/1/2/2/2/2 by the same self-review: setup remains 1 because
an ordinary clone still needs externally qualified compiler products and the
exact LLVM capsule. This is an honest limit, not an installer delivered by prose.
The external prerequisites are named before the commands. The helper checks their
identities, refuses changes, and leaves existing environment files intact.

## Three conceptual checks, with observed counterexamples

| Potential misunderstanding | Reader-facing repair | Source-grounded check |
| --- | --- | --- |
| “A compiler exit, my program's result, and printed output are the same thing.” | Getting started distinguishes a successful compile/run, a valid program whose check returns 1, and a source error. It identifies the visible sentence as shell `printf`; the Astra programs have empty stdout. | `pilot-total` returns 0; `pilot-total-failure` returns 1; `negative-type` fails compilation with the exact Boolean/integer diagnostic. The O2 repeat and published shell blocks check actual outcomes. The original exit-42 case remains a separate control. |
| “A loop advances automatically, and integer types promote whenever their values fit.” | Values traces all five iterations and puts advancement outside the filtering branch. It separates contextual literals from already typed operands. | `pilot-loop` checks count 5/total 30; `pilot-filter` checks 4/24. `negative-numeric-mix` refuses `u8 + int`; `pilot-conversion` uses `as int`, checks data 42 and returns 0. `negative-literal` still refuses 256 in `u8`. |
| “A copied record aliases the original, and a field name is also an argument label.” | Records observes both copies, explains scalar value copying, and separates field `=` from parameter `:`. The ownership qualification appears beside the copying claim. | `pilot-records` checks original weighted value 6 and copied value 12; `pilot-weight` changes only the loop's last weight and expects total 40. `weighted(sample: original)` succeeds; `negative-label` rejects an undeclared label. The optional generic's concrete `int` call grants no permission to copy owners. |

The grounding is the existing native implementation and tests, with Reference
links for [profiles](../reference/profiles.md), [numbers](../reference/types.md),
[control](../reference/control.md), [record values](../reference/values.md),
[expressions](../reference/expressions.md) and [generics](../reference/generics.md).
The [editorial plan](EDITORIAL-PLAN.md) records the selected source witnesses and
maps every existing Guide chapter. No new parser-only construct is presented as
native executable behavior. No new allocation, exception, text-I/O or ownership
rule was introduced.

## Validation and preservation

The final report binds source and recipe hashes to raw commands, outputs,
diagnostics, timing and memory summaries. Tests are not inferred from a successful
process exit alone. The published shell verifier executes the exact 13 marked
blocks in one `/bin/sh -eu` session; it checks messages, diagnostics and absence
of rejected object outputs. The two setup controls reject an altered manifest
and an existing destination without replacing that destination.

The initial focused campaign passed seven added cases and four selected rejection
cases on both O0/O2 hosts and both O0/O2 targets. The records and changed-weight
fixtures were then simplified during critique. A subsequent full native attempt
was interrupted with signal 15 before its final receipt; the cause was not
established and no full-run PASS is claimed for it. Its raw streams are retained.
Final qualification uses three disjoint explicit selections, 6 + 6 + 34 cases,
covering the complete 46-case manifest in all four host/target profiles. Complete
receipts from those groups qualify the revised bytes; the older focused result
does not. All three final groups completed with their expected outcomes.

| Final observation | Result and scope |
| --- | --- |
| Native examples | 46 cases × 4 host/target combinations = 184 profiles, from disjoint 6/6/34-case runs. Includes all original 39 cases and all seven additions. Exact exits/stdout, stable rejection diagnostics, untouched refusal sentinels and LLVM verification were checked. |
| Consolidated regressions | 29 suites passed, including current ABI, ownership, 46 physical mutations, source-owner memory and API/docs extraction. The O0/O2 API bytes agree and reproduce the final site. |
| Strict memory | 894 recorded streams across final native and regression checks: every observed process has zero errors and zero bytes/blocks at exit, with default suppressions disabled and all leak kinds selected. Historical C0 NOT_PASS is a separate, unchanged disposition. |
| Reproducible reader commands | All 13 published shell blocks and both setup refusal controls passed. These are exact shell bytes from the three chapters; their shell replay uses the O0 host, while the native suite supplies the complete O0/O2 host/target matrix. |
| HTML and rendering | 15 renderer controls; 1,906 local links; deterministic complete-book/API output. Seven actual browser screenshots inspected, including the pilot chapters, plus JavaScript, keyboard, responsive and print-style checks. |
| Recorded execution | 3,271 final command records were independently rehashed and inspected. The earlier mandatory predecessor replay and interrupted attempt are retained separately and are not added to this count. |

To reproduce the native coverage, use `tests/books/run.py` with the manifest,
product/toolchain/link arguments in [Tooling](tooling.md), selecting no cases for
one complete run or the disjoint groups retained in the report. Each command
uses fresh external build/runtime leaves. `tests/books/tutorial.py --runtime`
executes the marked reader commands; `tests/books/render.py --runtime` checks
the adapter; `tests/books/regression.py --qualification --qualification-sha256`
replays the exact preserved 29-suite plans. The report contains the actual full
argument vectors, source/tool identities, raw outputs and portable evidence.

The adapter retains all 30 registered Guide/Reference chapters, all 66 rule
entries and all original 42 fixture files/39 cases; seven fixtures/cases are
added. The 13-source guarded formatter check is scoped to this work. The final
renderer and browser checks cover complete HTML, exact source downloads, API
links, disabled JavaScript, keyboard navigation, mobile width and print styles.
No PDF or public website publication is claimed.

Before editing, the exact submission, predecessor R1 submission/report, 81 Git
blob witnesses, selected read-only source snapshots and all eight evidence
transport parts were authenticated. The predecessor had no qualifying later
G8 for its canonical report SHA. The committed `tests/books/delivery.py` was
therefore executed against report
`bf2dd95fb38e7e126919bc4adc2badb4d8cbe2a5e1ef6340f96c9d12c582b962`.
Its actual run started at 2026-11-16 20:01:13 UTC, after that report's publication
at 18:39:24 UTC, and ended at 20:58:54 UTC. Independent inspection of 4,175 command
records and 904 strict memory streams qualified that separate later G8 before
any pilot edit. Its receipt does not rewrite the immutable prepublication audit:
that audit's G8 remains PENDING and R1's formal engineering status remains PARTIAL.

Preserve these qualifications in any retelling: the missing 222 direct source-unit
witness obligation and comprehensive G1–G4 remain open; original C0/1044 raw
proofs were lost; rebuilt C0 is ACCEPTED_WITH_DISCLOSURE; strict all-kinds C0
memory remains NOT_PASS. E25-A-v1, the exact public C ABI, ownership/borrowing,
256 generic and 8M SSA ceilings and independent verification boundaries are
unchanged. The protected 451 paths, 6,622 donor files, peer work, Git settings,
hooks and installed `$pm-next` workflow remain protected. This pilot cannot
turn any of those historical exceptions into a PASS.

## Actual model use and cost-effectiveness

Session metadata records **`gpt-6-astra`, reasoning effort `max`** for the outline,
chapter draft and deliberate review/revision. There was no model switch, lower
model substitution or delegated editor. “Max” here names the recorded reasoning
setting; the submission ZIP did not select it or grant access.

Two retained server-counter checkpoints bracket drafting, fixture/test work and
review; they are not an isolated measurement of prose generation. The first,
at 21:04:05 UTC, follows intake, the mandatory predecessor replay, source reading
and the outline. The second follows the revised chapters and tutorial verifier.
Their delta is 2,924,877 input tokens, including 2,859,520 cached input tokens,
and 28,303 output tokens, including 10,545 reasoning tokens. Repeated context
is counted repeatedly. The cumulative totals are not unique words read, and
reasoning is not added a second time to output. Raw checkpoints and command
wall/CPU/RSS measurements are included; overlapping parent/child timings are
not summed into an invented task CPU or peak-memory number. No billing data or
comparable lower-effort editorial run was available, so no dollar saving or
model superiority is claimed.

The mandatory predecessor replay alone took about 57 minutes 42 seconds. That
is authentication and execution cost, separate from the value of the three
chapters. The first part of this session also spent too much context on large
evidence inventories. This review does not hide that overhead or recommend
repeating it as an editorial method. After authentication, summaries and exact
receipt references are sufficient; high-effort reasoning belongs in teaching
sequence, semantic distinctions and a deliberate revision.

Recommendation: evaluate this pilot with an actual new reader, then authorize
at most the next two or three chapters if its trajectory works. Keep Max for
the whole-book outline, ownership explanations and the editorial critique;
run the existing deterministic tests as ordinary engineering work. Do not pay
for a full-book rewrite yet. There is no measured basis to claim a cheaper
model would give equivalent prose, and no evidence that more tokens alone would
resolve installation friction or the formal Reference witness deficit.

The next useful decision is whether to continue with objects and errors/text,
following the dependency map, and separately whether to fund the tooling/setup
work under its own authorization. The other ten Guide chapters remain mapped
but unrevised. The Guide is not yet a complete reader-tested book.
