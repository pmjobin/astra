> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# ADR 0101: Finite exact-Class generic owning bag

Status: **User-approved Option A, implemented and qualified 2026-10-16.**
Milestone `ASTRA-GEN-MEMBER-1A-CLASS-BAG-1`, 2026-10-16.
The explicit decision below preceded compiler semantic edits. The baseline
proves the existing concrete operations; later implementation evidence is
recorded separately. Historical negative fixtures remain unchanged.

## Starting point and measured feasibility

Repository `<historical-private-path>`, branch `astra-lazy-1`, HEAD
`61fab540a891f79ce85f52014353bb68ce4e2b10`, tree
`ea041c2a66ceded1cf643b41da58f8a6a9109b00`, parent
`f431acaa775da1e4c0d3732d790509aeab5248fd`. Tracked worktree and index
were clean. The 17 initial untracked files have individual SHA256/mode/size
records in external `runtime/native-current/gen-member-1a-preflight.json`.
No active hook or hooksPath override was found. Archive ref
`archive/codex-next-20261013` is `fbd2c16f4a86da2a68da1938af18492eef7bb24d`;
the sibling `astra-cad-1` worktree is at
`a1fadc5c052e82ae464268787f617252998c24be`. Neither is an implementation target.
The published predecessor's entire staging folder was preserved by rename to
`runtime/native-published-container-1a-20261015` before new validated intake.

Fresh strict compiler rebuilding and `tests/container-1a/verify.sh regressions`
passed 3 focused plus 21 selected regression registrations, with 123 TAP
subtests. The Q20A execution driver passed 139 commands and 18 unsuppressed
Valgrind runs; the refusal driver passed 296 commands, including six expected
fatal child scenarios. Actual observed `2->3 len=2` growth preserves diagnostic,
message and payload identities and reverse cleanup. The existing second-element
`tests/container-1a/messages.astra` also ran at native/O2 with clean memory checks.
The separate existing numeric/child-owner baseline passed 93 commands and six
memory runs. See fresh baseline details.
Fourteen additional Q11B-D and copyable generic-struct registrations passed
63 TAP subtests. The combined fresh selection is 38 registrations / 186 TAP
subtests, covering Q11A-E without claiming the full registry.

The new pre-approval probe
passed 94 command checks and four unsuppressed memory runs. Its one program
interleaves the two **existing concrete** bags, grows each from 2 to 3 with two
live elements, and inspects both through concrete free functions outside the
bag declaration. Counted embedded NUL and combining UTF-8 survive. Native and
independent `opt -passes=default<O2>` / `llc -O2` outputs agree. A copyable generic
struct/free-function program also passes both routes. Generic Class/member
declarations still reject in the parser; symbolic `T[slots]`, a local concrete
slots descriptor, and an unowned slots field reject during semantic checking.
External indexed-loan escape and later-argument reserve also reject there.

## Choice A: recommended finite source contract

Propose this precise new class declaration form, using the existing type-list
and contextual `where` conventions:

```astra
class Bag<T> where T : ExactHeapClass {
	owned T[slots] entries;
	init() { this.entries = new T[slots]; }
	bool reserve(int requested) { return this.entries.reserve(requested); }
	void append(owned T value) { this.entries.append(move value); }
	int count() { return len(this.entries); }
	int capacity() { return this.entries.capacity; }
}
```

`ExactHeapClass` is a **new proposed contextual constraint identifier**, accepted
only in this finite generic-Class declaration. It is not an existing capability,
new global keyword, user-defined trait, or extension of free-function `Ownable`.
There is exactly one type parameter and one explicit bound. An unbounded generic
Class remains unsupported. The parameter may appear only as this owned slots
field's element, its empty allocation, and the append method's owned parameter.
It cannot occur as an ordinary copied field/value, a result, a generic object
constructor, or another type constructor. The declaration is checked even when
unused; invalid definitions cannot hide until instantiation.

The first admitted bodies are the five direct operation patterns shown above:
one empty initializer, one reserve forwarding return, one append forwarding
statement, one count query, and one capacity query. Names such as `Bag`, `entries`
and the parameter names carry no compiler privilege. Member names may differ;
their source signatures and bodies must prove the same finite patterns. No
arbitrary generic member body, user deinit, additional field, method type
parameter, property, inheritance, virtual dispatch, async or throws is admitted
in the template. Each closed instance gets ordinary generated field cleanup.
This deliberately bounds template checking and independent body reconstruction.

Explicit `Bag<Diagnostic>` and `Bag<Utf8Message>` applications select independent
native Class identities. `new Bag<Diagnostic>()` constructs a normal unique heap
object. A named same-instance owner can move under existing Class rules; its
object address stays stable and the original owner is disarmed. No generic
default construction of T is provided. Concrete element factories remain
`make_diagnostic(...)` and `utf8_message(...)`; append still requires a named
live exact heap owner and `move`.

The bound admits only source-known, nonpolymorphic native Classes with no parent,
foreign identity, or nested owner-slot storage, including through owned children.
Ordinary scalar fields, Q19A snapshots and acyclic exact child owners remain
admitted. Resource, struct, open/generic arguments, subtype families, generic bag
elements and nested slots reject. The Class type alone does not prove heap
origin: every appended object must independently prove its heap acquisition.
Lexical and caller-backed instances of an otherwise eligible Class still reject.
Do not extend unrelated generic free-function/record argument domains, foreign
ABI, lexical generic-Class construction, or generic bag ownership composition
as a side effect of this admission. These are separate future decisions.

### Inspection uses existing concrete call sites

```astra
bool show_diagnostic(Bag<Diagnostic> bag, int index) {
	return render_diagnostic(bag.entries[index]);
}
bool check_message(Bag<Utf8Message> bag, int index, string expected) {
	return message_is(bag.entries[index], expected);
}
```

These are two element-specific inspectors over **one generic collection body**.
They borrow their concrete bag and element synchronously, return copied bools,
and retain neither reference. They introduce no callbacks, returned element,
generic introspection, reflection, or dynamic dispatch. Within `message_is`, the
existing message-bound text view lasts only for that helper. The positive
baseline executes this exact outside-field access shape using Diagnostics and
Messages; specialization must substitute only the exact containing Class identity.

Source anchors are `analyzer.vala`'s `field_context_type` (2824),
`check_field_place` (2910), `check_slots_place` (226), and indexed argument
checking (3986). Both receiver and object-field Places already exist.
`pending_field_borrows`, `check_slot_operand` and `check_member_receiver`
conservatively prohibit possibly aliasing calls or consumption while a captured
element awaits its inspector. Specialization must preserve that field/containing
Class identity. It must not erase the container into T or a pointer-width class.
The new tests must also reject nested later-argument reserve/append, bag moves,
ancestor aliases, persistent element/text escape and wrong-class inspection.

## Stage architecture and proof obligations

The architectural gap is nominal Class/member specialization; Q20A already has
the required concrete storage and loan operations. The implementation must add
explicit definition/instance authorities, rather than reuse plain-copy structs
or mark unresolved T as a Class. The following are required implementation
invariants, **not claims that the proposed verifiers already exist**.

| Stage | Existing source and required extension |
| --- | --- |
| Syntax | `src/syntax/parser.vala:298` rejects Class type parameters; its generic-struct branch permits fields only, while line 376 rejects member type parameters. Add only the bounded Class form above, with the existing contextual where/type-close parsing rules. Preserve generic-member and generic-struct exclusions. Retain exact source spans; substitute type identities through AST/IR structure, never textual find/replace. |
| Checked definitions | `src/semantic/semantic-generic-structs.vala` deliberately separates a type definition from a native instance. Introduce a separate Class definition and parameter token, owned-slots **pattern**, and finite member-operation recipes. Validate parameter visibility, exact bound, field count, complete init, signatures and all five body patterns without any concrete T. Do not construct `OwnerSlotsType(T)`: `types.vala:450` requires a concrete ClassType element. |
| Checked applications | `analyzer.vala:420` currently resolves applications only as structs/enums; `ClassSymbol` currently creates a fresh ordinary nominal type. Add a canonical registry keyed by exact definition identity and exact Class argument identity. Extend construction to accept that canonical ClassType separately from the original name span; do not fabricate source text to create a nominal name. Declare closed Class/receiver/field/member symbols once per key before checking callers. Resolve the slots field to `types.slots_of(concrete_argument)`, and check specialized direct bodies against ordinary constructor, origin and ownership authorities. Register all ordinary element classes first; complete fields/child graphs before final admission, including forward declarations. |
| Origin and binding | Reuse `analyzer.vala:138,186,205,1923,2021`: append propagates a heap requirement through its owning parameter, qualified element/child graphs are validated after registration, and constructor init is definite/exactly once. Methods bind via the instance's member map; ctor and append formals carry that instance's receiver and concrete element cleanup. Same spelling, layout or pointer width grants no authority. |
| Core specialization | Add Core-owned immutable generic Class definition/member/field origin tokens and independent finite operation recipes, plus a canonical instance record and exact materialization maps. `core-generic-structs.vala` supplies an identity pattern, not a copyability contract. Extend `CoreBuilder` and `CoreGenericMonomorphizer` to materialize each declared closed Class and its five members once, remapping receivers/fields/parameters/cleanup and preserving definition spans. Checked's closed lookup symbols do not substitute for Core's reconstruction. Reject forged keys, foreign definitions, mismatched argument/type/receiver or a body that diverges from the admitted operation recipe. |
| Concrete Core | `CoreVerifier.verify_concrete` must see complete closed Classes and ordinary concrete methods, with no open template operation or T in executable bodies. Extend template verification explicitly; do not globally disable `verify_slots_place`'s existing prohibition on generic free-function instances (277). `verify_slots_field` (270), exact owned arguments, initialization and reverse cleanup still rederive Q20A authority. One record cannot claim another instance's field/member map. |
| CFG / ownership flow | `cfg-builder.vala`, `cfg-verifier.vala`, `ownership-flow.vala` receive only concrete classes and operations. Retain exact instance provenance in stage-owned class/member records, revalidate its concrete field/receiver/cleanup mapping, and reject wrong-instance calls or cleanup. Existing owner dataflow supplies move/disarm, definite initialization and the call-scoped indexed-loan boundary. |
| SSA | `ssa-builder.vala`, `ssa-verifier.vala:298` reconstruct exact field/element/heap-cleanup authority, append's current pointer and immediate source disarm, the loan consumer/path, and reverse descriptor drop. Preserve independent concrete instance origin records so swapping same-layout bags cannot manufacture type compatibility. No runtime instance dictionary or origin flag appears. |
| Native | `nabi/native-classes.vala` already proves element ordinal/name/destructor and PTR/I32/I32 channels; extend class plans with independent specialization identity and receiver/member mappings. Native standalone validation must reject a coherent-looking wrong-instance plan, not merely compare an upstream flag. Scalar method results and pointer receivers keep existing direct ABI. No descriptor is exposed as a copied slice or foreign aggregate. |
| LLVM | `llvm-owner-slots.vala:8` checks size 16/alignment 8/offsets 0,8,12 and pointer stride 8; line 25 binds exact element cleanup. `llvm-type-mapper.vala` and ordinary Class lowering emit one layout and direct ctor/method/destructor per instance. Helpers remain keyed by exact concrete element, with actual function/address/instruction bindings. Independently mutate instance dispatch, element destructor, transfer/clear/commit/free, length/capacity and stale release operands, restore and reverify. Never execute corrupted IR. |

Instance keys use definition-token identity plus ordered canonical semantic
arguments. They are not display-name strings or mutable ordinal pairs. Repeated
same-key requests coalesce, while different definitions or arguments cannot.
Emission names may use validated per-program ordinals after identity is fixed;
source-order tests check semantic identity/parity rather than promising identical
ordinal spelling. Each stage owns the provenance it verifies and must survive
retirement of the preceding graph, following the current contract-test pattern.

### Lifetime and physical invariant

For a closed instance K and exact element C, its field owns one descriptor
`(base,len,capacity)` with `0 <= len <= capacity`. Capacity zero corresponds to
null backing; each occupied prefix slot owns one distinct nonnull heap C.
Unoccupied carriers are empty. No other owner aliases the descriptor/backing or
an occupied element right. K's object itself has one ordinary stable Class owner.

Empty init establishes this invariant without allocating. Reserve no-op and
normal rejection preserve it. Growth allocates before mutation; at transfer
index i the replacement prefix owns 0,i), old cleared prefix owns nothing,
and old suffix owns [i,len). Referent and snapshot addresses do not change.
After the complete transfer, commit installs the replacement descriptor and
retires the now-empty old backing exactly once. There is no callback or ordinary
checked failure within that primitive. Append consumes/disarms one exact C
owner and initializes exactly the next live slot. Inspection temporarily borrows
an exact C while retaining K's ownership and excluding mutation until the call
ends. It creates no cleanup right or persistent reference.

Moving K changes the owning carrier, not K's allocation or its field address.
Ordinary destruction drops live elements in reverse insertion order with C's
exact nested cleanup and heap free, then frees backing once. Checked failures
after complete acquisitions use existing Q20A unwind paths. Fatal bounds/full/
nonnull/OOM traps remain expected fatal children without an unwind or leak-free
fatal-path claim. The same inductive proof applies separately to each K; equal
descriptor layouts never allow exchanging their semantic ownership rights.

## Alternatives and implementation acceptance

**B — separately approvable foundation:** retain the same explicit exact-Class
parameter and canonical nominal application keys, but admit only a scalar field,
direct scalar constructor and scalar reader on a phantom-T Class. Demonstrate
two distinct executable instance identities, member binding, stable moves,
native/O2 parity and forged-key/receiver rejections. No T value, owning slots,
growth or element inspection is delivered. Report the requested generic bag
**PARTIAL**; the specific follow-up is closed owning-field/member specialization
plus Q20B two-element growth/loan qualification. This fallback is not authorized
unless the user chooses B.

**C — hold:** retain baseline and proposed design for additional review. No
language-semantic implementation. Preserve the prepared intake/session; publish
only if the user chooses to conclude with a hold report.

A is recommended because the concrete outside-field inspection witness resolves
the immediate lifetime route without introducing a new escape channel. Approval
authorizes implementation of the documented finite specialization architecture;
it is not acceptance of untested stage changes. If independent reconstruction or
physical proof cannot be implemented within this scope, return to the user before
introducing a workaround or enlarging the admitted language.

A must deliver `tests/gen-member-1a/`, a usable example with one Bag declaration,
both instantiations interleaved in one program and each alone, real 2->3 growth,
empty/1/2/3/early/qualified checked-error cases, unchanged payload/owner IDs and
exact reverse cleanup. Run native and independent O2 with exact traces and
unsuppressed Valgrind; qualify source negatives and authentic restored
Checked/Core/CFG/SSA/Native/LLVM mutations. Re-run the targeted Q20A/Q19A/Q11A-E,
Q08/Q10B, generic-copy, numeric buffer/slice/swap and strict-build fence.
The full registry, real liburing, strict LAZY, CAD and hardware remain outside
this milestone. Only complete A can earn PASS for the bag objective.

## Historical fixtures and decision record

No existing negative fixture currently needs alteration for this proposal.
`tests/gen-struct/parse-tests.vala`'s `class Bad<T>{T x;}`,
`tests/app-diag-collection-0/probes/generic-class.astra`, and the GEN-OWN-2A-D
unbounded/owned-field shells still lack the required exact-Class bound and/or
have excluded field forms. Their original rejection coverage and diagnostic
expectations must remain. General generic-method negatives remain invalid.
If implementation identifies any existing path that must change, name that exact
path and obtain separate human consent before editing it. Initial untracked
paths require separate path-specific consent for any change or adoption.

Decision: **A**, explicitly approved in ordinary interactive Codex after the
baseline and this design. The user first replied `A`, then confirmed:
`I approve Option A, the bounded Q11F/Q20B design in docs/decisions/0101-exact-class-generic-bag.md.`
The confirmation specifically authorizes `Bag<T> where T : ExactHeapClass`,
owning slots, the five proposed direct operations, and concrete inspection
helpers; it requires exact identity, unique ownership, deterministic cleanup,
safe growth, loan guarantees, native/O2/negative/verifier/memory qualification,
and no expansion without asking. No historical-fixture change is authorized.

## Implemented stage placement and qualification

Closed nominal Classes and their member signatures are registered during
Checked declaration collection, before caller checking. The same source AST is
checked under each exact argument context; no textual substitution or open
`OwnerSlotsType(T)` is used. CoreBuilder lowers those bodies through its existing
concrete operations. Core independently reconstructs each of the five operation
recipes against its own definition inventory, instance key, field, receiver and
parameter identities. CoreGenericMonomorphizer preserves that inventory and its
existing concrete verification boundary. It does not introduce a second pass
that clones an executable open Class body. This placement keeps lookup concrete
while retaining the independent reconstruction required above.

CFG, SSA and Native copy their instance provenance and independently verify the
closed contracts; ordinary owner/origin/loan machinery remains authoritative.
The LLVM owner-slot implementation and runtime descriptor are unchanged.
[Final qualification records 47 passing
registrations / 217 TAP subtests, both-type native/O2 growth and loan witnesses,
30 unsuppressed memory runs, 50 source negatives and restored stage mutations.
Q11/Q20 remain open outside this finite contract.
