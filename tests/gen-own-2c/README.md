# Direct incoming generic heap Class results

Run `sh tests/gen-own-2c/verify.sh focused` or `regressions` from the real
repository. The recipe checks existing source routing and strict debug,
werror=true, b_pch=false, linux_async=false options, then uses the shared external
build with serial compilation and ccache disabled. It never builds in source.
The selected regression chain includes Q11A/B/C, GEN-OWN-1 results/recursion,
concrete heap factories/results, Q08/Q10B, Core/CFG/SSA/native, virtual async and
property fences. Full historical registry and real Linux/liburing remain outside
this qualification.

The user approved [bounded Q11D](../../docs/gen-own-2c-heap-result-design.md) and
exactly two historical fixture replacements before implementation. One named
exact heap Class owner may enter a synchronous/nonthrowing native generic helper
with one owned T formal, copied scalar neighbors and owned result of the same T.
Exactly one direct `return move incoming` is permitted, outside loops, with no
local owner or Class construction in that result helper and all
reachable normal exits transferring it. A concrete caller acquires directly into
a fresh named owning Class local. Generic owner locals, result forwarding,
inline/nested consuming producers, recursion, second sites, loops, multiple
owners, subtype adaptation, aggregates, generic members and foreign/async/throws
helpers remain excluded. Resource and lexical result rules are preserved; Q11
stays OPEN.

Thirteen source programs exercise explicit/inferred var and explicit owned result
acquisition; pure transfer and a copied int neighbor before or after the owner;
same nominal T in both
actual heap/lexical request orders and real declaration orders; completed loans;
derived/empty/no-deinit cleanup; Q08 children; normal receiving-local retirement;
and subsequent Q11C consuming forwarding. Existing Q11B source/allocator observer
and Q11C pointer observer are reused without editing them.

Every program runs generated native code, independent opt/llc O2, and separately
compiled C entry/pointer instrumentation under both unoptimized and O2 lowering.
The test-only LLVM instrumentation observes actual original constructor,
parameter, returned and receiving pointers. It checks heap/lexical domains from
independently audited signatures and verifies no Class memcpy/memmove, helper
allocation or incorrect candidate channel. The existing private native fastcc
entry is bridged for testing; this does not expose a new source C owning ABI.

Allocator interposition counts real allocations/frees and enforces destructor
obligations. Separate OWN_MEMORY companions use the standard allocator with
unsuppressed Valgrind and exact destructor/operation/pointer traces. Valgrind
bypasses the interposition hooks; free counts are deliberately zero in those
companions. Their evidence is separate from the allocation/free observers.
Omitting the final consumer's free must fail both observer and memory checks;
duplicating it stops at observer exit 98 before a second unsafe host free. The
unchanged valid program is run again after those IR faults. Two argument traps
prove only nonunwinding behavior, never cleanup on SIGILL.

The negative suite pins deterministic diagnostics, exit 1, no stdout/internal
errors and no executable for ownership/loan misuse, result and owner origins,
exact nominal types, destination/producer restrictions, missing/multiple result
sites, loops/cycles and structural exclusions. Six multi-source cycle orders
check declaration-order independence. The two approved old cases remain rejecting
stronger invalid forms, with their original direct behavior tested positively.

The LLVM-free contract binary mutates and restores Checked result origin and
eligibility; symbolic Core result/type/source/acquisition; concrete key/candidate/
return provenance; CFG return capture, ordering, moved read and duplicate caller
acquisition; SSA captured pointer/event, escaped and duplicate cleanup, signature
domain and independently authored pointer/origin graphs; and native origin/Class/
heap bit/candidate plans. Every restored valid graph re-verifies. The independently
authored SSA graph has no call edges or predecessor approval, and omits optional
return-source annotations so the pointer/origin proofs must reconstruct authority.

The first escaped-cleanup probe exposed an SSA gap: consistently replacing
cleanup(null) and its END event with cleanup(returned pointer) was accepted.
Existing pointer evidence and heap-return capture/cleanup guards now close that
gap. Production LLVM/NABI/backend representation remains unchanged.
