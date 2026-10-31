# 0047 — Native borrowed slice parameters

Status: implemented for ASTRA-SLICE-BOUND-1, extending accepted ASTRA-SLICE-1
commit `fe9ac2ba55850ce29243ae84e651505c7ba1e50f`.

## Decision

1. Native slice parameters require explicit `borrowed`.
2. Unqualified SliceType native parameters remain unsupported.
3. Owned SliceType parameters are invalid.
4. Borrowed slice parameters are explicit noescape contracts.
5. The callee receives one semantic SliceValue.
6. That value retains its exact SliceType element identity.
7. Borrowing does not mean readonly.
8. The callee may mutate elements through SliceElementPlace.
9. Borrowing does not imply exclusivity.
10. Multiple slice parameters may overlap.
11. The caller retains its slice and backing storage after the call.
12. Passing a slice performs no ownership transition.
13. Arrays never implicitly decay to borrowed slice parameters.
14. Explicit `slice(array)` remains required when borrowing an array.
15. Direct subrange slice expressions may be passed.
16. Argument evaluation remains left-to-right.
17. A failing construction/range check prevents evaluation of later arguments.
18. One semantic slice parameter lowers to one grouped native slice parameter.
19. Its physical components are ordered: base PTR, then length I32.
20. Both components remain grouped as one NABI parameter.
21. Physical component expansion never splits the semantic parameter.
22. I32 represents length because SliceType length is currently semantic `int`.
23. The physical base may be null if and only if the length is zero; an empty
    view need not have a null base.
24. Nonempty slices carry a valid, suitably aligned base for their exact element
    type and sufficient live contiguous storage for the supplied length.
25. Native Astra calls are trusted to pass well-formed SliceValues.
26. No runtime slice-validation descriptor is introduced.
27. Callee indexing performs ordinary slice bounds checks.
28. After successful bounds checking, no separate base null check is required.
29. Borrow provenance is compile-time information only.
30. No runtime lifetime token exists.
31. No noalias assumption is valid.
32. No readonly assumption is valid.
33. No nonnull assumption is valid: empty slices may have a null base.
34. Slice parameters may be copied into local SliceValues.
35. They may be forwarded to compatible borrowed-slice native parameters.
36. Slice results remain unsupported because result lifetime relationships
    cannot yet be expressed.
37. Slice NABI is compiler-owned, without a stable external ABI promise.
38. C/VAPI slice boundaries remain unsupported, including C exports.
39. Future slice results must extend this semantic model, not reinterpret slices
    as raw pointer/count pairs.

## Semantic and lifetime authority

`borrowed T[] s` has exact value type `SliceType<T>` and separately has
`PointerParameterContract.BORROWED_NOESCAPE`. No BorrowedSliceType exists.
FunctionSymbol retains the parameter's type, contract, identity, source spans,
and function lexical region. `int[]` and `i32[]` share identity; `i8[]` and
`u8[]`, or `i16<4>[]` and `i16<8>[]`, do not. Runtime lengths and source array
extents do not participate in callable identity.

The existing BorrowProvenance authority assigns incoming slices the function
region. Local copies obey existing same-region/descendant rules, including the
conservative region of a stored local read. Core, CFG and SSA retain exact
parameter identity and contract; element places can carry immutable PARAMETER
provenance snapshots with region zero. Upstream symbols and region trees do not
survive as backlinks. Forwarding and recursion reuse the same view and perform
no reconstruction in semantic IR.

The caller's existing lexical proof makes an argument live during the call.
The callee cannot retain that authority after return. Current bans on slice
results, fields, arrays of slices, globals and foreign boundaries structurally
close the escape paths. These bans implement the current contract; they do not
define its entire meaning. Any future storage/result capability must consult
BORROWED_NOESCAPE and specify lifetime relationships before permitting escape.
Handle borrowing retains its existing stricter equality/direct-forwarding rules.

Slice results would require a signature relation such as “result borrows from
parameter A” or “result borrows caller-owned storage.” Neither inference from
the return expression nor a physical pointer/count result establishes that
relation. Results, including attempted borrowed results, remain rejected.

## Evaluation and owned boundaries

Each argument is evaluated completely before the next. Subrange construction
evaluates start, count, then validation; invalid start still permits count's
effects, while an invalid range suppresses the next argument and invocation.
CFG captures the whole view before later effects. A slice parameter uses this
same capture when indexing; the old borrowed-handle capture shortcut does not
apply to slice values.

OWNBOUND-1 remains authoritative: `move owner` captures a pending transfer and
makes the owner semantically moved at that argument position. Physical transfer
commit remains after all argument evaluations and immediately before the call.
Thus a later slice operand cannot borrow an already-moved owner. If construction
traps, no transfer commit, callee entry or lexical cleanup executes. Traps remain
non-unwinding. CFG verification rejects an unevaluated constructor or length
expression inserted into an owned call after transfer commit.

Extracting base and length from an already-evaluated SliceValue introduces no
new source evaluation point and no ownership event.

## NABI and backend alternatives

NativeSliceType extends the existing NativeAbiType hierarchy and stores ordered
base/length channel kinds. NativeParameter retains one ordinal, name and span
for that group. The physical sidecar contains no semantic types, borrow regions,
element descriptors, call bodies, or runtime ownership data. Parameter mapping
requires a supported SliceType and BORROWED_NOESCAPE; general direct-value and
result mapping continue rejecting slices. Compatibility validation checks exact
semantic slice identity before comparing the physically identical groups.

`slice-v5` extends the existing program-wide profile selection. Any native slice
parameter selects it, regardless of declaration order. It permits all existing
scalar/PTR/vector channels. Programs without slice parameters retain their
previous profile and dumps; body-only slices select no new profile. Earlier
profiles reject slice groups, and every profile rejects slice results.

LLVM expands the groups when declaring a function and emitting its calls.
Entry code reconstructs the existing `{ ptr, i32 }` value from each adjacent
pair. Ordinary SSA binding, aggregate phis, bounds guards, aligned scalar/vector
memory and final physical predecessor tracking then apply unchanged. Slice
arguments extract both components from the same already-bound value. No slice
alloca, lifetime token, runtime helper, attribute contract or hidden parameter
is introduced.

Independent semantic pointer/count parameters were rejected because they lose
the exact SliceType, parameter identity and paired-value invariant. Passing an
LLVM aggregate as one physical argument was rejected because this boundary
explicitly calls for PTR/I32 expansion. A generic aggregate ABI framework would
add policy with no additional supported channel; the slice-specific group is
the focused extension to the existing NABI architecture.

See [native slice ABI](../abi/native-slices-v5.md),
[language](../language/slices.md), [IR](../ir/slice-values.md), and
validation.
