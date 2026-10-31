# 0030 — Borrowed owner parameters

Status: accepted for ASTRA-OBORROW-1, based on accepted MOVE-1
`63eb60dd44ad7a883480948a36298de27f288df0`.

Owned foreign handles need temporary access through native wrappers and C imports
without transferring their lexical cleanup responsibility. Ordinary raw pointer
parameters carry no lifetime promise and cannot safely receive an owner.

The following decisions are frozen for this milestone:

1. `borrowed` is a parameter contract, reserved by both source and VAPI lexers.
2. It is permitted only on `void*` parameters.
3. `borrowed void*` has the ordinary semantic pointer type `void*`.
4. The qualifier describes lifetime and ownership behavior, not physical type.
5. A borrowed parameter acquires no cleanup responsibility.
6. Passing an owner to a borrowed parameter does not move ownership.
7. The owner must be definitely OWNED at argument evaluation.
8. MOVED owners cannot be borrowed, including physically null moved sources.
9. MAYBE_OWNED owners cannot be borrowed.
10. Borrowing leaves ownership state unchanged: OWNED → OWNED.
11. A successfully acquired null-valued owner may still be borrowed.
12. Borrowed parameters are noescape.
13. Noescape means the callee may not make the borrowed address available after
    its dynamic invocation.
14. Retaining, storing for later, returning, or transferring the borrowed pointer
    is forbidden. Its non-owning contract also forbids freeing or destroying it.
15. Borrowed does not mean readonly. Resource mutation and I/O are permitted.
16. Foreign borrowed contracts are trusted binding declarations. A C
    implementation that violates them breaches the foreign interface contract.
17. Native borrowed contracts are statically enforced by Astra.
18. Borrowed parameters may be forwarded directly only to another
    borrowed/noescape parameter. Parentheses do not create an alias.
19. Raw unmanaged `void*` values may be passed to borrowed parameters.
20. Null literals may be passed to borrowed parameters.
21. An owned-producing expression cannot be borrowed inline; its responsibility
    must first enter an owner.
22. Owners have no general implicit conversion to raw `void*`.
23. Borrow adaptation exists only at a compatible borrowed parameter boundary.
24. NABI physical signatures remain unchanged: Native PTR, `scalar-ptr-v1`.
25. C ABI physical signatures remain unchanged: C PTR, `scalar-ptr-v1`.
26. LLVM receives ordinary pointer arguments without runtime borrow machinery.
27. No LLVM noescape/nocapture or other optimization attribute is required or
    emitted by this milestone.
28. Existing native `Struct*` lexical borrowing remains a separate semantic system.

The grammar is `parameter := "borrowed"? type-name identifier` in each independent
frontend. The semantic restriction is exactly `void*`; `int`, `bool`, `Pair`,
`Pair*`, `void`, and other pointer depths reject. Borrowed locals, fields, results,
and `export(C)` borrowed parameters remain unsupported. Owned parameters/results,
call ownership transfer, owner reassignment, Release, native-owned objects and
reference counting are outside this milestone.

`PointerParameterContract { UNMANAGED, BORROWED_NOESCAPE }` is an LLVM-free shared
behavioral authority. ParameterSymbol and native/Core/CFG/SSA parameter objects
carry it independently of SemanticType. C declarations use the same stage
parameter classes, preserving exact identity, name and parameter provenance;
the existing parameter-type arrays remain checked mirrors for existing callers.
CAbiParameter retains the same enum alongside its physical scalar channel.
Cleanup-function parameters stay UNMANAGED under their separate destructive
compiler-owned cleanup contract.

Semantic checking validates each borrowed parameter reference only in pointer
equality/inequality or direct borrowed argument context. Copying into even a raw
local is forbidden, so no general `void*` alias or lifetime dataflow is needed.
Core, CFG and SSA verifiers also reject obviously escaping native parameter uses
in standalone graphs. This restriction deliberately defers persistent aliases.

CheckedOwnedBorrowValue records the exact LocalSymbol, destination ParameterSymbol
and argument span. CoreOwnedBorrowValue maps these to CoreOwnedLocal and
CoreParameter. CFG emits CfgOwnedBorrowInstruction at the argument's left-to-right
evaluation point; its CfgOwnedBorrowValue records the exact owner and parameter.
The verifier requires a unique event and direct use at that exact boundary.
MOVE-1's existing fixpoint validates BORROW without adding a state or changing
cleanup, transfer, or reachability. SSA reads the current owner definition at the
event and maps the argument to that ordinary pointer value. There is no SSA borrow
node, source null definition, cleanup change, token, counter, hidden channel,
retain/release call, or extra storage caused by borrowing.

Foreign calls remain ordered and conservatively effectful. Native fastcc and C
ccc realization remain unchanged. Optimizer capture, readonly, noalias, nonnull
and dereferenceability attributes are deliberately unqualified here.

Future Release, reassignment and owned function boundaries must distinguish
Borrow from Transfer explicitly. Longer-lived borrowed references require an
explicit alias/lifetime design; this parameter contract does not authorize one.
