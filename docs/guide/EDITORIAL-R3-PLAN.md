# Full Guide editorial plan — 28-A2-R3

This is one complete-book campaign from R2 commit
`5f3e8bd4e7b4ceaa38c0bddc18fc32bf17d94cdf`. The unlaunched two-chapter R3
draft produced no edits. R2's plan and review remain historical records, including
their now-superseded recommendation to stop after another small batch.

## Learning dependencies and first introductions

Keep all 13 stable source routes. Change the reading order once: put Text/Errors
immediately after Objects, and Profiles after Application and Tooling. Preserve
the opening three lessons' outcomes and their seven fixture files byte-for-byte.
The complete-book review permits one narrow setup clarification in Getting
started: explicitly enable the error-stopping shell used by all tested recipes.

| Lesson | What the reader brings | New decision and observable result |
| --- | --- | --- |
| Front matter | Programming and a terminal | What will be built; exact existing development prerequisites |
| Getting started | Arithmetic | Compile, link, run; distinguish exit status from printed text |
| Values | One checked sum | Progress and filtering; five readings total 30, or four total 24 |
| Records | Typed locals and functions | Copy a scalar record; weight ten twice for total 40 |
| Objects | Copy versus identity | Acquire, borrow, consume; five objects retire exactly once; then owning fields and weak observation |
| Text/Errors | Cleanup responsibility | Validate a reading, catch a recoverable error, borrow text while backing lives, explicitly materialize a message |
| Sequences | Owners and bounded inputs | Choose fixed storage, an owning array, an immediate slice or a lazy plan; traverse the same five values |
| Generics/Matching | Concrete calculations | Justify two numeric instantiations and cover every copied alternative |
| FFI | Text lifetime and borrowed data | Match an actual C implementation to scalar/counted declarations; observe missing-provider failure |
| Application | Storage, summary records and C | Build all three files, read valid/invalid/missing data, extend the model with a tested filter |
| Tooling | A working application | Inspect its API, select one test, interpret input mismatch, repeat an edit/check cycle |
| Profiles | Actual application dependencies | Separate per-file syntax from link/runtime choices; execute a fixed calculation without libc |
| Glossary | The whole journey | Find first-use explanations and precise rules; choose a bounded next project |

## Frictions found in the live manuscript

The later chapters are useful semantic notes but rarely offer complete exercise
answers. Several shell blocks run exit-42 programs directly under an error-stopping
shell. Text dependencies are described without a reproducible link command.
Generic prose assumes the reader ran an optional early generic. The final program
has no empty-input or modification exercise. Tooling references unset variables
and asks a beginner to run the entire qualification campaign. Profiles explains a
startup hidden inside a test runner instead of giving a runnable recipe. Most
chapters end in qualification exclusions rather than a learning transition.

Resolve these in the manuscript, not just in this plan. New examples continue
2, 4, 6, 8, 10 and use exit 0 for their own checks; historical fixtures keep
their exact exit-42 behavior. Keep all original 46 case records and 49 published
source fixtures. Existing fixtures remain available as clearly identified further
experiments, without making the main text an inventory of regression tests.

## Implementation and review checkpoints

Draft ownership/text and focused native tests; draft data/generics/FFI/application
and focused tests; finish tooling/profiles/front matter/glossary. Read the complete
manuscript again, make substantive revisions, then independently check the prose
against current Reference, library and fixture sources. Record concrete corrections
in a separate R3 review. No novice-reader study is claimed.

Every displayed full Astra/C program must match a registered fixture. All reader
shell fences must carry a tutorial identity and run verbatim in one retained
shell environment with checked outputs. Add exact execution checks and fresh-output
refusal checks to the native runner while preserving its memory, LLVM and sentinel
controls. Final qualification covers every old and new case in all four host/target
combinations, the 29 current regression suites, deterministic HTML and actual
browser inspection. Only completed current results establish acceptance.

The compiler, normative Reference, ABI, LLVM 23.1.4, workflow, protected sources,
donors and peer work stay outside the edit set. Formal R1 PARTIAL/222 source
witnesses and the owner C0 disclosures remain separate. The current host reports
`gpt-6-astra` / `max`; mechanical work uses ordinary tools. Counters measure the
whole observed interval, not an isolated writing bill.
