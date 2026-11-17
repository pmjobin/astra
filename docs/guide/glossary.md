# Glossary, index and edition history

You began with a sum and finished with a file-processing program. Use this index
when revisiting a decision: why a parameter borrows, why a view must be consumed
immediately, why a missing provider is a link problem, or why an error does not
behave like a trap. Each first link returns to a teaching example; the Reference
link gives the more precise implemented boundary.

## Find the idea again

| Term | Meaning and reading route |
| --- | --- |
| Acquisition | Establishing an owner's cleanup responsibility from a checked producer; [objects](objects.md#acquire-inspect-then-hand-over), [Reference](../reference/ownership.md) |
| ABI | Agreement about arguments, results and their physical calling representation; [C boundary](ffi.md#a-declaration-needs-an-implementation), [Reference](../reference/abi.md) |
| Borrow | Access while backing remains alive, without acquiring its cleanup responsibility; [owner and borrower](objects.md), [Reference](../reference/ownership.md#borrowing-arrays-and-failure) |
| Capture | A value or admitted backing relationship retained for later lazy work; [deferred calculation](sequences.md#delay-a-calculation-until-it-is-consumed), [Reference](../reference/collections.md) |
| Cleanup | Retiring the responsibility on an admitted scope/return/error path; [ownership](objects.md), [errors](../reference/errors.md) |
| Counted string | Validated UTF-8 bytes with a byte count, which may include NUL; [byte-count exercise](ffi.md#exercise-count-bytes-including-nul), [Reference](../reference/text.md) |
| Exact type | A checked type identity; already typed numbers do not silently become another numeric domain; [values](values.md#choose-a-numeric-domain-deliberately), [Reference](../reference/types.md) |
| Exhaustive match | A match covering all required alternatives of its input type; [matching](generics-match.md#exhaustiveness-is-part-of-the-calculation), [Reference](../reference/values.md) |
| Extent | Number of elements in fixed storage or a runtime array/view; [sequences](sequences.md), [Reference](../reference/collections.md) |
| Instance | A checked concrete specialization of a generic declaration; [generics](generics-match.md#constraints-at-concrete-calls), [Reference](../reference/generics.md) |
| Materialization | Producing actual fixed or owning storage from a sequence; [storage choices](sequences.md), [Reference](../reference/collections.md) |
| Move | Transferring ownership responsibility and invalidating the old owning use; [move versus copy](objects.md#a-move-is-not-a-copy), [Reference](../reference/ownership.md) |
| Namespace | A scope for declaration names, not automatic package discovery; [application model](application.md#keep-the-calculation-independent-of-i-o), [Reference](../reference/declarations.md) |
| Nominal record | A value type identified by its declaration, not just its field layout; [records](records.md#describe-a-value-then-construct-one), [Reference](../reference/values.md) |
| Owned message | An object retaining text backing that can be borrowed while it lives; [text](text-errors.md#keep-message-backing-alive), [Reference](../reference/text.md) |
| Profile | A per-source language selection, or a separately stated runtime/target scope; [profiles](profiles.md), [Reference](../reference/profiles.md) |
| Provider | The actual external implementation of imported functions; [FFI](ffi.md), [Reference](../reference/abi.md) |
| Recoverable error | A declared error channel handled by a catch or propagated through a compatible contract; [validation](text-errors.md), [Reference](../reference/errors.md) |
| Shared owner | A strong handle that keeps an admitted payload alive; [sharing](objects.md#sharing-when-two-parts-must-keep-an-object-alive), [Reference](../reference/shared.md) |
| Slice | An admitted immediate borrowed view of part of live named array storage; [views](sequences.md#a-view-is-not-an-independently-stored-owner), [Reference](../reference/collections.md) |
| Test sentinel | A deliberately chosen value, such as the original application's exit 42; [application status](application.md#coordinate-the-boundaries-in-the-entry-point) |
| Trap | Fatal termination for a runtime failure, with no general recoverable unwind promise; [errors](text-errors.md#keep-message-backing-alive), [Reference](../reference/errors.md#recoverable-versus-fatal) |
| Weak observer | A managed handle that does not keep the payload alive; upgrade may return null; [expiry](objects.md#observing-expiry), [Reference](../reference/shared.md) |

The complete-book HTML also supports ordinary browser Find without a search
service. Read an individual chapter for navigation, or use the complete book
for an uninterrupted read and print preview. Both come from the same Markdown.

## What to build next

Start with a variation you can predict. The application chapter supplies a full
calibration-filter answer, so it is a useful comparison point. You could next
summarize a selected interval, count zero values separately, or compute minimum
and maximum with an explicit empty-input policy. Before implementing one, write
down results for the original five readings, an empty file and a single reading.
Those are project suggestions, not claims that unshown solutions have been tested.

Keep the bounded provider unchanged while exploring the model. That isolates
the calculation from file parsing and makes mistakes easier to locate. If you
later change the C boundary, review the provider's real byte, count and lifetime
contract, then give that change its own tests. A successful link alone cannot
establish those promises.

## Edition 28-A2 changes

This development Guide builds on the three R2 opening lessons and continues
through ownership, errors/text, sequences, generics/matching, actual C integration,
the complete application, tooling and runtime choices. The source examples,
exercise answers and local book renderer have explicit tests. Editorial review
is an author's critical review, not an observed novice-reader study.

Guide completion is distinct from the formal Reference's acceptance ledger.
Milestone 28-A2-R1 remains PARTIAL: its G1–G4 and 222 direct source-unit witnesses
are still open. Passing the Guide's examples does not prove complete grammar
or every language/profile combination. Consult [Limits](../reference/limits.md)
for that boundary. Canonical source is Markdown; generated HTML stays outside Git.

## History that remains visible

The original C0 executable and 1,044 historical raw proofs remain missing;
27-B remains PARTIAL. The owner accepted the authenticated rebuilt-C0 provenance
substitution WITH DISCLOSURE. Its historical strict all-kinds process-memory
status remains NOT_PASS, separately from current tests. The
[release exception ledger](../release-exceptions.md) preserves these facts.

Later work covers performance comparisons, installation/developer experience,
release qualification and professional print production. This Guide does not
announce a release, public website, designed PDF or manufactured book. Those
limits do not prevent using the checked development examples to learn and build.
