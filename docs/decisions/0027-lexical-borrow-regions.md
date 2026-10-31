# 0027: Lexical borrow regions

Status: accepted for ASTRA-BORROW-1.

## Context

[TPTR-1](0026-typed-struct-pointers.md) established exact nullable Struct* values,
addressable local aggregates, aliasing field Places, and native call borrows.
Its physical representation already supports storing pointer values. The missing
proof is that a stored local borrow cannot outlive its source storage.

BORROW-1 chooses lexical lifetime bounds rather than flow-sensitive pointee-origin
inference. The latter could accept more programs, but requires tracking stored
values through branches and loops. Lexical pointer-local requirements permit
ordinary SSA merges after checking each store independently. No new runtime or
IR representation is needed.

## Decision

1. Struct* remains a nullable, non-owning raw typed pointer. Multiple mutable
   pointers may alias; lifetime safety does not imply exclusive access.
2. BorrowProvenance is static semantic information, not a new runtime pointer
   representation. A borrow is pointer provenance plus a proven lifetime bound.
3. Every checked lexical block owns one exact LexicalRegion identity. The function
   body is the invocation root; nested blocks form a parent-linked lexical tree.
4. A local struct's borrow region is its lexical local-storage lifetime. Storage
   becomes usable only after its complete initializer; ordinary name visibility
   proves the start. It ends at the lexical scope boundary.
5. Native Struct* parameters are valid for the complete receiving invocation.
   Their provenance is the function-body region, including when copied inward.
6. Literal null has NULL provenance, with no finite pointee-lifetime requirement.
   It satisfies every destination region without inventing a lexical null region.
7. A typed-pointer local requires all values stored into it to be borrow-valid
   for that local's own lexical storage region.
8. Initialization and assignment require exact pointer type identity, then proof
   that the source provenance outlives the destination local's region.
9. Pointer-local reads advertise REGION(local.lexical_region), even if a more
   precise origin could guarantee longer validity or the local only stores null.
10. This local summary supports transitive copies without retaining the original
    pointee-origin object at every subsequent storage boundary. Conservative
    rejections are intentional; there is no general lifetime dataflow inference.
11. Borrow checking is semantic. Core/CFG/SSA trust a successfully checked program
    and do not re-run lifetime reasoning or retain its region graph.
12. `&struct-local` becomes a general typed-pointer expression. Safe local stores,
    equality, parenthesized addresses, and native arguments are valid. Address-of
    fields, scalars, pointers, and temporaries remains unsupported.
13. Typed-pointer function returns remain prohibited. They need explicit
    return-lifetime contracts, not an exception to this proof.
14. Typed pointers remain prohibited in struct fields; aggregate lifetime
    relationships are outside this milestone.
15. C imports, C exports, and VAPI remain typed-pointer-free. The native typed
    pointer cannot convert into a C-compatible void*.
16. Together with the absence of global/captured pointer storage and casts, these
    restrictions leave no route for a local borrow to escape the active native
    invocation/lifetime graph. Transitive calls and bounded recursion preserve
    the caller's live storage until callees unwind.
17. A borrow owns nothing. No runtime retain/release, cleanup, borrow counter,
    hidden validity bit, region ID, or stack-lifetime check is emitted.
18. Taking an aggregate address anywhere in the checked function prevents scalar
    promotion of all its fields for that function, including unreachable uses.
19. The pointer local itself remains an ordinary promotable scalar pointer value.
    Existing AddressOf, pointer block parameters, memory operations, LLVM ptr
    phis, and null traps suffice. NABI PTR/scalar-ptr-v1 and CABI are unchanged.
20. Future ownership, heap-managed values, escaping references, and return
    contracts may generalize this lexical model, but must preserve its soundness
    and explicitly extend the lifetime contract before adding escape routes.

## Identity, ordering, and ownership

The analyzer allocates regions in deterministic source preorder, restarting at
zero for each native function. It visits the then body before the else body and
a loop body when it checks the loop. Ordinals are debug labels, never equality
or ancestry authority. Scope depth, line ranges, and brace counts play no role.

`source.outlives(destination)` walks from destination through its parents and
compares exact object identity at each step. Equality or any ancestor succeeds;
unrelated roots and siblings fail. Complexity is linear in lexical nesting depth.

Checked blocks strongly own their regions through the checked function's block
tree. LocalSymbols and native ParameterSymbols strongly retain their own regions.
A queried BorrowProvenance retains its region and named source Symbol for
inspection/diagnostics. Regions have only a GLib.WeakRef parent and no child,
symbol, block, or function backlink. There is no strong-reference cycle. A
detached region may outlive its parent; the parent getter then returns null,
and queries cannot invent ancestry. Checked graph destruction before Core is
explicitly qualified, as are detached local and provenance destruction.

There is no pre-existing standalone semantic verifier. Analyzer checks provide
source diagnostics; checked pointer initialization/assignment constructors also
assert the outlives invariant. Region ownership, producer provenance, and tree
identity are directly tested. `SemanticDump.format(program, true)` optionally
shows regions, local ownership, and pointer requirements. Default semantic and
downstream dumps stay unchanged; debug ordinals are not a serialization contract.

## Consequences and limits

Same-scope late assignment is safe even when the pointer was declared first:
both storages end together, and the pointee is visible at assignment. Outer to
inner stores are safe. Inner to outer stores fail before Core, including loops,
unreachable branches, and copies from an inner pointer that currently holds an
outer address. Literal null can always replace a pointer value.

Loop-local pointers and pointees end together on iteration completion, continue,
or break. Backend entry-block allocas may physically last for the whole frame;
semantic region checking prevents source access after the lexical lifetime ends.
Repeated body initialization retains its existing source control-flow position.

No TPTR physical redesign, new external dependency, alias exclusivity, pointer
arithmetic, address-of extension, ownership, heap allocation, or destructor is
part of this decision. See [language rules](../language/borrows.md) and
qualification.
