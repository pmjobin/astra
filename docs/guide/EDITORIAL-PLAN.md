# A reader's path through the Astra Guide

Editorial plan for the 28-A2 R2 pilot. This is a plan for teaching the Guide,
not a replacement for the Language Reference or a claim of book completeness.
Only Getting started, Values and Records are being rewritten in this pilot.
The other chapters below are mapped for later work, not silently rewritten.

## The reader and the promise

Write for a programmer who can use a terminal and has written functions in
C, C++, C#, Java or Python. Do not assume familiarity with Astra's ownership
rules, compiler construction or the project's milestone names. Explain a new
term at the point where it helps the reader make a decision.

The reader should finish with a small readings application they understand well
enough to change. Begin with five known measurements: 2, 4, 6, 8 and 10. Establish
the expected count of five and total of thirty before discussing code. Move from
a calculation to a loop, then to records and focused functions. Later, replace
generated readings with stored data and finally with the existing bounded file
input. Ownership becomes necessary when the program acquires storage; foreign
interfaces become necessary when it reads and reports data.

The [Rust Book](https://doc.rust-lang.org/book/) is a benchmark for explaining
ideas through use, making errors teachable and giving the reader a next step.
Its prose, distinctive examples and chapter layouts are not templates for this
book. Astra's existing readings application supplies our subject and constraints.

## A project that already has an executable destination

The current [application](application.md) has three explicit source inputs:
[the model](../../tests/books/app-model.astra),
[the entry point](../../tests/books/app-main.astra) and
[the C provider](../../tests/books/app-report.c). Its checked input file contains
the five readings above. Its actual stdout is `readings: count=5 total=30` plus
a newline. The current application fixture deliberately exits 42; malformed or
missing input exits 64 without a report. Those existing bytes and expectations
remain regression controls. A later application rewrite can reconsider that
sentinel only with an intentional, separately tested change.

The pilot's new opening examples use exit 0 for success and need no text-I/O
provider. Their terminal messages come from the shell, not an invented Astra
printing function. The first exercise deliberately produces a runtime check
failure, so the reader can distinguish it from a compile error. Later lessons
introduce actual text and C-provider dependencies when they are useful.

The initial baseline has 39 book cases and 42 source fixtures. A genuine later
R1 delivery replay, completed before any pilot edits, re-executed those cases
with both O0/O2 compiler hosts and O0/O2 targets, along with grammar, boundary,
ABI, ownership, physical and documentation checks. New pilot examples must
receive their own native evidence. A proposed exercise in the table below is
future work unless it appears in the tested pilot fixtures.

## The complete chapter map

This table accounts for all thirteen existing Guide files, including the front
matter and glossary. Its order is the proposed learning trajectory. The existing
chapter registry and navigation order are retained for this narrow pilot; moving
the later chapters belongs to a subsequent editorial decision.

| Existing chapter | Prerequisite and reader outcome | Project step and current executable anchor | Missing teaching work or next exercise |
| --- | --- | --- | --- |
| [Front matter](README.md) | Terminal familiarity. Understand what the book will build and what development environment it requires. | Introduce the five readings and point directly to the opening lesson. | Keep release history and proof mechanics in the Reference and editorial records. Explain the different return conventions in older examples without making them the opening lesson. |
| [Getting a first program running](getting-started.md) | Front matter. Compile, link and run a complete program; distinguish its result from the compiler's result. | Check the known total, using the present native compiler and C linker. The original `hello` case remains a small regression control. | Pilot: make environment selection reproducible; give a visible shell result, an expected failing check, a compile error and a tested exercise. A distributable installation remains an explicit tooling gap. |
| [Values, decisions and progress](values.md) | A working executable. Predict local values, conditions and loop progress; choose an exact numeric type. | Generate the same five readings and accumulate count/total. Existing `values`, `numeric-contract` and `evaluation-order` fixtures establish arithmetic and evaluation boundaries. | Pilot: show a short iteration trace and a tested filtering exercise. Separate the main lesson from optional numeric edge and effect-order experiments. Do not introduce refused `for` or comparison-chain forms as executable shortcuts. |
| [Records and small calculations](records.md) | Typed locals, conditions and loops. Name related data, call a function, predict independent copies and read one concrete generic call. | Give a reading a value and weight; compute through a `Sample` helper. The existing `records` fixture observes an unchanged original after modifying its copy. | Pilot: explain declaration, construction, field shorthand and parameter labels separately. Test a changed-weight exercise and a common call mistake. Explain that scalar record copying does not grant ownership copying. |
| [Objects, owners and observers](objects.md) | Records and functions. Choose object identity when values alone do not describe the problem; trace one acquisition through inspection and consumption. | Use the existing `owners` example first. `ownership-defaults` and its independent C observer check retirement and an anchored borrow; `shared` and `weak-expiry` distinguish a live handle from an observer. | Future rewrite: one lifetime diagram and a prediction exercise before shared/weak machinery. Explain default parameter/result channels in context. Add an exercise whose incorrect answer would cause two consumptions, and explain the actual diagnostic without exposing compiler internals as a prerequisite. |
| [Text, failures and useful diagnostics](text-errors.md) | Functions and a basic owner/borrow model. Decide which failures are recoverable and identify who owns a message. | `errors` validates a reading; `formatting` builds and checks text; `call-abort` observes cleanup when a later argument throws. | Future rewrite: begin with a rejected reading and a useful explanation. Introduce selected libraries/providers before their use. Distinguish a borrowed text view, an owned message and stdout. Make byte length, allocation during reservation and fatal bounds failures concrete exercises. |
| [Sequences without hidden costs](sequences.md) | Loops and borrowing; error vocabulary for invalid bounds. Choose between a range, fixed storage, an owning array and a borrowed view. | Replace generated scalar readings with the tested `collections` data: 2, 4, 6, 8 and 10. `lazy`, `range-edges` and `numeric-pipeline` cover deferred work, endpoints and a scalar floating reduction. | Future rewrite: begin with storage and indexed access, then introduce ranges and lazy work. Add empty-input and changed-stride exercises. Teach immediate view consumption before discussing unsupported retained view locals. Keep allocation and deferred execution distinct. |
| [Generic functions and matching](generics-match.md) | Concrete functions, records and basic ownership. Generalize a small operation and represent a reading or a problem explicitly. | `generic-contract` instantiates constrained addition at two exact integer types; `matching` handles nested alternatives. | Future rewrite: motivate a second concrete type before adding a type parameter. Make the incompatible `bool` call and a missing match case repairable exercises. Explain owning payloads separately from the copied scalar example. Preserve the finite specialization boundary. |
| [Calling native C code](ffi.md) | Functions, text views and explicit lifetimes. Connect a declaration to a real provider and understand its trust boundary. | The existing provider loads a bounded file and reports a counted UTF-8 label. Its C implementation checks bytes, count, input bounds and file closure. | Future rewrite: draw the argument/result boundary and compile the provider in small steps. Explain that a declaration supplies no implementation. Add a wrong-provider/link exercise and a counted-string exercise; do not imply general typed-pointer, varargs or aggregate ABI support. |
| [A multi-file readings application](application.md) | Sequences, records, errors and the concrete C boundary. Assemble explicit inputs into a working file-processing tool. | Preserve the tested `application` case: five values, count five, total thirty, with separate malformed/missing-file executions. | Future rewrite: build the model before the entry point and provider; show the full source list and environment input. Add an empty-file exercise and a bounded-data variation with fresh tests. Explain namespaces as naming, not automatic package discovery. Revisit exit 42 deliberately rather than silently. |
| [Documentation, tooling and migration](tooling.md) | A working application. Inspect an API, reproduce a test and make one intentional source change. | Existing API extraction, safe rendering, exact source fences and the book runner provide working tools. | Future rewrite: show a small edit/test/read cycle before qualification recipes. Explain how to select external manifests and recover from a missing prerequisite. Move detailed campaign mechanics to contributor documentation. Installation, package discovery and editor onboarding remain 28-C work. |
| [Hosted and freestanding calculations](profiles.md) | Knowledge of the application's actual dependencies. Explain why a fixed calculation can need less runtime support. | `fixed` is linked both conventionally and through the tested Linux x86-64 syscall startup; owning collections require their allocator. | Future rewrite: compare imported symbols from two small programs and ask the reader to predict the changed link requirement. Avoid equating “no heap here” with qualified firmware or arbitrary targets. Keep performance measurements in the separately authorized 28-B lane. |
| [Glossary, index and edition history](glossary.md) | Any chapter. Find a term, return to its first useful example and distinguish an edition from a release. | Current Reference/API links and complete-book HTML provide the navigation base. | Future work: add first-use Guide links, a short “what to build next” route and a terminology consistency pass. Retain historical exceptions and formal completeness limits in a clearly identified edition note. Do not make that note the first lesson. |

## How ownership should enter the story

The first three chapters need only ordinary scalar values and copied records.
Use assignment to establish a concrete prediction: changing the copy leaves
the original alone. Do not call this a general rule for every Astra type.

Next introduce one class whose identity matters, one owner and one borrowing
function. Ask who is responsible after each statement before adding `move`.
Only after the reader can trace acquisition, borrowing and consumption should
the book add shared ownership, weak observation, stored borrows and failure-path
cleanup. The existing independent destructor and call-order observers are useful
evidence, but the narrative should first explain the behavior they observe.

Sequence lessons can then distinguish the storage owner from a view into it.
Text lessons apply the same question to borrowed counted bytes and owned
messages. Generic and foreign interfaces must retain those distinctions; neither
a type parameter nor a C declaration makes a lifetime promise true by itself.

## A repeatable lesson and review method

Give each lesson a question the reader can answer by running the program. State
the expected data and result, show complete source, explain the new decisions,
then change one thing. A negative example should identify its stage, a stable
diagnostic phrase and the reason for the repair. A runtime failure is a different
event from a compilation refusal.

Exercises should require a prediction before execution and provide a tested
answer. For the pilot, use a failed total check, a filtered reading and a changed
weight. Keep commands usable from an existing checkout and put outputs in an
explicit external build directory. Explain missing development artifacts as a
current limitation; never fill that gap with an imaginary installer or CLI.

Full Astra/C code fences must match registered fixture bytes exactly. Existing
experiments that no longer belong in the main explanation may be explicit
source-download links, provided the book checks still require their publication
and the generated download is byte-exact. This keeps all 39 baseline cases
without forcing the opening chapters to reproduce a regression catalogue.
Source fences retain their original mismatch and unknown-example refusals.

After the first draft, make one deliberate technical/editorial critique. Test
at least these misunderstandings: “returning a number prints it,” “a typed small
integer promotes automatically,” and “a record assignment aliases its source.”
Also check that the prose distinguishes a parameter label from a field name.
Record concrete revisions, actual model use and measurable usage separately
from judgments about readability. No external novice study is implied by a
single author's review.

## Source authority and remaining work

The starting point was the exact source tree
`779a76dd245b14623b1e94a6d75ea7359ac9459b` at commit
`750c1338239bdb9e7bd66a5e11925efa2e4711fd`, including all thirteen Guide files,
the chapter registry and the example manifest. The relevant Reference chapters
cover profiles, lexical rules, types, expressions, control, declarations,
records, generics and ABI. Direct source checks include
[conditions and initializers](../../compiler/semantic/statements.astra),
[numeric expressions](../../compiler/semantic/expressions.astra),
[record identity and construction](../../compiler/semantic/recover-record.astra),
[loop verification](../../compiler/semantic/recover-loops.astra) and the separate
[integer emitter](../../compiler/backend/llvm/recover-integer-emit.astra) and
[integer verifier](../../compiler/backend/llvm/recover-integer-check.astra).
Native execution decides what is usable in these lessons; a syntax node alone
does not establish executable support.

Beyond the chapter-specific gaps, the Guide still needs a coherent installation
story, a fuller input-validation narrative, namespace/module teaching, richer
ownership exercises, a practical testing workflow and reader feedback. Those
are planned editorial or tooling work, not newly implemented language features.
The original Reference's 222 missing direct source-unit witnesses and its
comprehensive G1–G4 obligations remain separate and PARTIAL. The 256 generic
instance and 8,000,000 SSA ceilings, E25-A-v1 ABI and independent verification
boundaries stay unchanged. A successful pilot would justify a decision about
another bounded editorial batch; it would not establish release readiness,
public deployment or a produced print edition.
