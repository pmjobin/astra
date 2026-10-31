# Architecture invariants

## Owned buffer exchange: OWN-SWAP-1

- Both operands name live initialized owning buffer storage with exact canonical type and cleanup contracts.
- Resolve and validate left, then right, once; protect the first slot and containing object during later evaluation.
- Capture both complete pointer/count groups before any store; no fallible or source-observable effect interrupts the region.
- Snapshot components cannot escape as extra owners; neither field is exposed in an empty state.
- Both slots invalidate dependent borrows, including conservative containing-object aliases.
- Same-slot aliasing is valid after both evaluations; no allocation disjointness or thread atomicity is promised.
- Allocation identities move; declared cleanup ranks, scopes and containing ObjectStorage do not.
- Generic definitions require exact lexical elements and existing signature premises; all remapping completes before CFG.
- Copied plans and physical bindings preserve exact correspondence without retaining executable predecessor graphs.

## Copyable record elements: STRUCT-ELEM-1

- Canonical ArrayType/SliceType identity is separate from ownership and element eligibility.
- Each stage supplies its own complete recursive field graph to shared copy/zero/storage authorities; caches do not outlive a query.
- Indexed roots compose with ordinary recursive FieldPlaces and preserve exact bound/view association.
- Fixed entries complete in written order; no source array view exists before complete initialization.
- Whole-record producers snapshot all leaves before destination writes; live destinations/receivers protect their backing owner through later evaluation.
- Completed lifetime-neutral snapshots can precede an owner transfer without retaining an array address.
- Record memory uses ordinary natural layout, never aggregate-v7 channel concatenation or source-visible padding semantics.
- Independent struct-elements-v11 plans retain nominal element shape and transfer/borrow responsibility without upstream graphs.
- Physical stride/alignment/offset and zero representation are target-qualified; size arithmetic is checked before allocation/address formation.
- Owned arrays still have one allocation, one PTR/count owner and no element callbacks. Fixed/borrowed use acquires no allocator dependency.
- Concrete generic storage does not widen generic-function capabilities, C ABI, text borrowing or nontrivial lifetime domains.

## Caller information: DIAG-1

- Only explicit native parameter annotations authorize call completion; callable names grant nothing.
- Declaration contracts own kind, exact optional target ordinal and source provenance; semantic-to-Core validation independently checks forged contracts.
- Source syntax already preserves full written expression spans, including parentheses; capture copies owned source bytes into independently owned TextBytes.
- K..N positional calls synthesize only the omitted suffix and preserve ordinary explicit argument evaluation, borrow and ownership proof staging.
- Generic inference observes the same supported written arguments. Definition-site metadata precedes specialization and never changes instance keys.
- Checked calls have full signatures/arguments. Declaration metadata erases before executable Core; no caller evaluator or new ABI/entry profile exists.
- File/expression parameters stay bounded borrowed strings, with no caller-sensitive static-result strengthening.
- The assertion library and selected provider are ordinary source/C interfaces. No name-based backend attributes or autolinking exist.
- Fatal providers do not unwind native owners or an ARGS snapshot. Normal cleanup and disposal retain their original order.
- Captured paths and snippets are explicit privacy/data costs; pooling uses complete bytes/counts without global name interning.

## Immutable text: TEXT-1

- One canonical StringType is distinct from pointers, mutable slices and aggregates.
- Contents are immutable; mutable local bindings copy/rebind descriptors without owners.
- Bytes and explicit count survive embedded zero; scalar UTF-8 validity is locale-independent.
- Plain/explicit native parameters borrow noescape; results require verified STATIC_TEXT.
- Origin equations track per-write backing provenance through joins/loops, never current callers.
- Complete StringType groups preserve base/count correspondence; no raw base projection exists.
- Every stage checks its own payload membership, shape, contracts and return origins.
- TextBytes has no upstream graph or source backlink; verifier origin graphs are temporary.
- text-v9 is independent native physical authority; text-free profiles and CABI remain unchanged.
- Private literal pooling keys full count/content and uses separate deterministic module ordinals.
- Runtime equality reads bounded content after both operands evaluate; zero length dereferences nothing.
- Generated text needs no allocator, RC/GC, Unicode tables or external text runtime.
- Generic admission, fields/collections/properties and C/I/O boundaries are not broadened.

See [ADR 0073](../decisions/0073-immutable-utf8-text.md) and [text IR](../ir/text-values.md).

## Exact compile-time constants: CONST-1

- A named constant is an exact scalar or TEXT-1 immutable text value, never a Place, runtime immutable binding or owner.
- Inferred constants supply no context; explicit constants supply ordinary initializer context. References retain exact types.
- Ordinary operator/conversion authorities remain the only type capability tables.
- Constant expressions exclude calls, memory, allocation, moves and runtime binding reads.
- Both lazy operands are statically checked and contribute dependencies; only required values are evaluated.
- Global dependency traversal is iterative, deterministic, cycle-safe and memoized; local visibility remains lexical.
- Integer results wrap at every operation, and float results round nearest/even at every operation without host float authority.
- Required traps diagnose only in constant contexts; existing ordinary runtime behavior is preserved.
- Fixed-array extents share the evaluator, resolve to mathematical integer values in 1..1024, and never remain symbolic.
- Constant declarations/references erase before executable Core, with no runtime initialization; TEXT-1 may retain private literal bytes.
- Stage verifiers remain independent after checked symbols, syntax and evaluators die.
- No library names become intrinsic or constexpr; symbolic constants and function CTFE remain excluded.

See [ADR 0072](../decisions/0072-compile-time-constants.md) and
[constant evaluation](constant-evaluation.md).

## Opt-in base library: BASELIB-1

- Library algorithms and predicates are ordinary Astra source; hosted math is ordinary VAPI.
- No library names, helper prefix, failure hook or C math names receive compiler special treatment.
- No implicit sources, providers, library search, header parsing or autolinking exist.
- Global source lookup and duplicate diagnostics give neither user nor library definitions precedence.
- Existing capability domains/non-implications, exact inference, transactional ownership, explicit moves and inline-owner rejection are unchanged.
- Selection propagates the first NaN and chooses the first ordered tie; clamp validates ordered bounds and preserves an in-range value.
- Assertions are eager and always-on. Non-returning, non-unwinding failure is a static provider contract, not a new IR effect or spelling-based noreturn attribute.
- Trap and hosted providers are explicit, mutually exclusive strong definitions; there is no registry or weak override.
- Pure helpers emit no external support; trap-only composition has no hosted dependency on the qualified target.
- Hosted equality/math retain exact CABI-FP channels, target gates and conservative foreign effects.
- Named-library CLI input has a narrow validated grammar and joins object input in one ordered, repeatable argv stream.
- No parser, semantic, Core, CFG, SSA, NABI, CABI or LLVM implementation changes are required.

See [ADR 0071](../decisions/0071-base-library-foundation.md).

## Generic call inference: GEN-INFER-1

- Ordinary name resolution selects exactly one generic function before inference; overloads remain absent.
- Omitted type arguments may be inferred only from direct T and legal owned T argument positions.
- Inference is local to arguments, never return, assignment, local declaration, property or expected-call context.
- Plain participating expressions are typed without the callee's inferred target type; literals retain standalone defaults.
- No implicit numeric conversion, promotion, subtype search or ownership transformation helps inference succeed.
- Named ownership transfer remains explicit with move, including outer Ownable parameters.
- Inspection and failed calls do not commit owner moves; validated argument proofs retain source order and short-circuit choices.
- Observations track exact callee TypeParameterSymbol identity, candidate identity, argument index and span.
- Repeated observations must agree exactly after existing semantic canonicalization; int/i32 is one identity.
- Nominal types never unify by layout, representation or spelling; signedness and floating width remain distinct.
- Every declared generic parameter must be determined; capabilities validate candidates and never generate them.
- GenericArgumentTypes and GenericCapabilityAuthority retain the existing plain-copy/Ownable domains and non-implication rules.
- Exact outer type-parameter identities may propagate when the equivalent explicit application is already legal.
- Distinct outer A and B never unify based on possible future substitutions. The resolved §75 policy supersedes concrete-only inference.
- Nested structural inference, partial explicit lists, generic borrowing and generic owned buffers remain deferred.
- Explicit and inferred calls have identical Checked generic representations and canonical GenericInstance identities.
- Inference observations and expression caches die in semantic checking; no authoritative provenance enters Core.
- Parameterized Core may retain existing outer type tokens, but never inference variables or equations.
- No runtime dictionaries, witnesses, type descriptors, reflection, dispatch or allocation implement inference.
- Source paths are diagnostic provenance, not inference or specialization identity; instance deduplication is global.
- No ABI, monomorphization, storage, FMA, performance or production dependency policy changes.

See [ADR 0070](../decisions/0070-generic-call-inference.md).

## Default native parameter borrowing (PARAM-BORROW-1)

- Plain native exact Resource/HandleType and ClassType parameters borrow by default.
- Plain SliceType parameters remain bounded non-owning views.
- Plain scalar/vector/mask parameters remain values; copyable structs remain COPY_VALUE.
- Borrowing is a parameter/lifetime contract, never a new semantic type.
- Plain and explicit borrowed forms canonicalize to the same BORROWED_NOESCAPE before Core.
- Downstream stages do not know whether source spelled `borrowed`.
- `owned T` remains explicit transfer; named owners still require `move`.
- A borrow never acquires cleanup, ownership or a reference count.
- A borrow never implies readonly, noalias or mutable exclusivity.
- A borrow cannot outlive its owner; it remains live through the permitted call region.
- Overlap rejects consuming or invalidating the same ownership capability while borrowed.
- Two bounded borrowed arguments may alias; completed borrows permit later ownership operations.
- Native defaults never change C/VAPI/CEXPORT ownership metadata or generic Ownable transport.
- Borrow is distinct from future weak-reference or shared-ownership semantics.

[ADR 0068](../decisions/0068-default-parameter-borrowing.md) intentionally supersedes
plain native Resource UNMANAGED inputs and the old Class same-call transfer exception.

## Local inference: INFER-1

- `var` is a reserved keyword with one local declaration grammar, independent of type lookup.
- `var` is local compile-time inference, not a dynamic type. An initializer is mandatory.
- The initializer is checked without a declaration target type and supplies one exact result.
- Inference never adds an implicit conversion; integer and unsuffixed real defaults are unchanged.
- f/F and d/D suffixes retain exact NUM-CONV-1 precision and rounding.
- Exact canonical and nominal semantic identities survive inference; equal layouts do not unify types.
- Ownership is separate from type identity. An owning buffer still has canonical SliceType.
- Exact fresh/returned responsibility may become an inferred owner local using existing storage contracts.
- Named-owner transfer remains explicit with `move`. Inference never silently copies or moves an owner.
- Inference never invents a persistent borrowed alias or weakens existing lifetime/noescape checks.
- Unresolved type parameters cannot become inferred machine locals; exact generic call arguments may separately be inferred.
- Inference is erased at Checked local construction. Core, CFG, SSA, NABI, CABI and LLVM have no VarType or inference operation.
- Declaration and name spans remain useful after source/syntax and Checked destruction.
- Explicit local typing remains first-class; API boundaries, fields, properties and results remain explicit.
- There is no runtime type metadata, ABI profile, performance policy or production dependency for inference.
- CONST-1 separately defines exact compile-time `const`; runtime immutable bindings remain unresolved. PARAM-BORROW-1 defines parameter defaults.

See [ADR 0067](../decisions/0067-local-var-inference.md).

## NUM-CONV-1 scalar numeric invariants

- Scalar numeric conversion is explicit; no implicit numeric promotion is introduced.
- Integer→floating rounds once directly to its destination, nearest/ties-even.
- Every current integer→f64 conversion is exact: current integers have at most 32 bits and binary64 has 53-bit precision.
- Floating→integer mathematically truncates toward zero before range validation.
- NaN, either infinity and out-of-range truncated integers trap without unwinding.
- Floating→integer never relies on out-of-domain LLVM fptosi/fptoui behavior.
- These integer↔floating conversions neither saturate nor wrap; existing integer→integer ICONV modulo behavior remains unchanged.
- Signedness is semantic. IntegerType is the sole integer range/width authority.
- Each numeric conversion evaluates its source once and preserves effect/trap order.
- CFG/SSA guard results prove the exact destination interval; conversion requires a dominating proof.
- `f`/`F` selects f32 and `d`/`D` selects f64 before decimal rounding.
- A suffix determines literal semantic precision; it is not a later cast and overrides context.
- Unsuffixed defaults and existing contextual literal behavior remain unchanged.
- Decimal constants round once directly to their selected semantic format.
- Literal parsing is locale independent and does not use host FP parsing as semantic authority.
- No suffix survives as runtime or IR conversion metadata; source spans serve diagnostics only.
- Scalar conversions require no heap, mandatory runtime helper, libm or new ABI profile.
- Generic Numeric, vectors/masks, aggregates, bool, pointers and array element conversions are not expanded.
- Machine instructions realize language semantics; they do not define them.

See [ADR 0066](../decisions/0066-explicit-numeric-conversions.md).

## Owned runtime arrays and concrete replacement (BUFFER-1)

- `T[]` is a borrowed runtime-sized view. `owned T[]` adds unique cleanup
  responsibility over the same canonical SliceType; ownership is a contract.
- `new T[count]` creates one unique owner and zero-initializes every element.
  Eligibility separately requires concrete fixed storage, trivial destruction,
  a defined zero and ordinary copyability; GEN1_PLAIN_COPY is not its authority.
- Length is exact int/i32 and immutable within an allocation. Empty allocation
  canonicalizes to null base plus zero length without calling the allocator.
  Negative count, checked byte-size overflow and nonempty failure trap.
- Named owners are move-only. Transfer never copies element storage. One owner
  identity governs both base and length; complete null/zero physical disarm does
  not make a semantically MOVED source usable.
- A borrowed slice never owns or frees its base. Compatible slice parameters
  implicitly borrow without allocation or copying; mutations remain visible.
  Views cannot outlive owners. Stored owner-derived views and observable overlap
  with move, replacement or destruction reject under existing noescape policy.
- Buffer indexing reuses Slice bounds and writable element Places. Bounds
  validation precedes element address use and load/store. No new readonly/noalias
  guarantee is assumed.
- Owned buffer cleanup is deterministic RAII under the existing ownership lattice
  and lexical ordering. Explicit release remains intentional early destruction.
- Assignment to a live mutable concrete Resource or buffer local/parameter is
  RAII replacement. Incoming production and capture precede source commit, old
  cleanup and complete destination storage. RHS traps leave the old owner intact.
- MOVED/RELEASED assignment is rearm with no old cleanup. Live replacement is
  OWNED → OWNED with one old cleanup. Self-move rejects. ClassType/ObjectStorage
  assignment and unresolved generic ownership are not generalized.
- Owned buffer fields definitely initialize in explicit init. Allocation, moved
  named owners and direct exact factory results may initialize/replace fields.
  Receiver validation precedes incoming production or named-source consumption.
- Resource and buffer fields share one reverse declaration-order cleanup sequence.
  User deinit sees live fields; normal return cleans the final current contents.
  Deinit methods/scalar setters may replace fields. Field move-out/release remains
  rejected, and traps do not unwind or clean partial construction.
- OBJ-RET constructs pairs in final ObjectStorage. Object/GEN-OWN forwarding
  preserves object address, buffer base, length and responsibility; final owner
  destruction cleans current fields once.
- Native owner boundaries transport complete PTR/I32 groups without element copy.
  Borrowed slice-v5 and owned buffer-v8 are distinct contracts even where channels
  coincide. Native v0–v7 remain frozen; CABI/VAPI arrays are not introduced.
- Core allocation is target-neutral and independent of libc. Each stage verifies
  its own element, group, lifetime and cleanup contracts after upstream destruction.
  SSA uses ordinary pointer/integer Values plus bounded metadata; LLVM return
  carriers never become universal aggregate SSA Values.
- Allocator/deallocator identity is static physical policy. No per-buffer runtime
  pointer, active bit, heap header, refcount or capacity word is needed.
- Hosted x86-64 Linux allocation is one realization of `new`, not its semantic
  definition. Unsupported allocator targets fail closed. Buffer-free programs
  acquire no allocator dependency, heap requirement or buffer runtime machinery.
- The qualified allocator's alignment bounds LLVM element alignment. Optimizing
  allocation calls must retain observable failure traps and zero initialization.
- Custom allocators/arenas, freestanding allocation, resizing/capacity, struct or
  RAII elements, aggregate Move, generic owned buffers and future `var` inference
  require later architecture. No production compiler dependency is added here.

See [ADR 0065](../decisions/0065-owned-runtime-arrays.md),
[buffer IR](../ir/owned-runtime-arrays.md) and
qualification.

## Generic-function invariants (GEN-1)

- Generic definition and lexical TypeParameter identities are compiler-owned semantic identities.
- A definition is checked once, including when unused. Concrete instantiation never legalizes an invalid generic operation.
- GEN1_PLAIN_COPY is the implicit bounded baseline capability; eligible arguments are lifetime-neutral ordinary copy values, independent of physical representation.
- Instance identity is exact definition plus ordered canonical semantic type arguments. int/i32 deduplicates; signed/unsigned and phantom same-ABI instances remain distinct.
- One deterministic compilation registry serves all native callable kinds and registers concrete signature placeholders before bodies. Direct and mutual recursion reuse those identities.
- Core monomorphization substitutes exact types and identity maps, never source text or names.
- Every instance receives fresh parameter/local/Place/block/owner/storage identities; non-generic Function/Method/Property/accessor/Field/cleanup targets remain exact.
- Generic calls substitute their explicit type arguments and bind to canonical concrete instances. Full explicit arguments are mandatory; no inference or defaults exist.
- Generic definitions have parameterized checked/Core representations and no CFG, SSA, NABI or LLVM representation.
- Concrete instances become ordinary CoreFunctions before CFG. CFG's input firewall rejects generic definitions, calls and unresolved types; CFG/SSA/NABI/LLVM contain no TypeParameterType.
- Each substituted signature uses existing NABI channels/profile requirements and accepted effective-profile subsumption. A definition has no maximum or generic-specific profile.
- Generic argument lists never become runtime operands. No metadata, boxing, dictionary, witness or dispatcher is introduced.
- Checked graphs can die before specialization; generic Core graphs can die before CFG; every later stage owns its needs independently.
- Semantic representation sharing is deferred. Future code sharing may optimize physical bodies without collapsing semantic instance identity.
- Generic classes/members, user-defined capability constraints, generic ownership, handle/object/slice/typed-pointer arguments, interfaces and generic C ABI require separate milestones.

See [ADR 0056](../decisions/0056-semantic-generic-functions.md),
[generic IR](../ir/generics.md) and qualification.

## Computed property invariants (PROP-1)

- A property is a semantic accessor member, not a field or storage Place.
- Property reads invoke one exact getter; property writes invoke one exact setter.
- Getter/setter identities belong to one exact PropertySymbol and survive stage translation.
- Accessors reuse native callable infrastructure without becoming ordinary methods.
- Fields, methods and properties share one member namespace; class lifecycle names remain reserved.
- One getter is required. An optional setter has one explicit ordinary immutable parameter of exactly the property type. No implicit `value` exists.
- Property values follow the plain native method parameter/result intersection, with handle values explicitly deferred to a later ownership/borrowing property milestone.
- Property accesses are conservatively effectful. Getters may mutate; setters may perform arbitrary ordinary callable effects.
- Actual struct property use may make that particular instance addressable. Declaration alone does not make other instances addressable.
- Class properties retain nullable-reference safety and alias coherence. Setter validation precedes RHS evaluation.
- `this.property` uses the existing live receiver. Constructor `this` cannot access properties; destructor `this` may.
- Structural initialization initializes fields only and never treats properties as setter targets.
- There is no compiler-generated property backing field or other property storage.
- Vector property lanes are value extraction, never lane Places or assignment targets.
- Getter/setter lowering uses existing PTR plus ordinary value channels. F64 uses exact binary64 and fp64-v6.
- Physical accessors do not redefine properties as methods or fields. No new NABI type/profile exists.
- No accessor purity, readonly, readnone, noalias or nonnull attribute is inferred by Astra.
- No automatic/static/virtual property, runtime property table, reflection, notification or GObject adapter exists.
- Future interface/virtual properties must extend exact property/accessor identities; stored/automatic properties must explicitly introduce storage semantics.

See [ADR 0055](../decisions/0055-native-computed-properties.md),
[property IR](../ir/properties.md) and qualification.

[ADR 0053](../decisions/0053-owned-object-results.md) freezes owned ClassType results with caller-provided storage. The result-specific invariants below refine earlier milestone result restrictions; the exact ClassType and shared ownership framework remain unchanged.

## Transferable lexical object ownership

- ObjectStorage identity and physical layout are independent of ownership mode.
- Unqualified construction retains fixed cleanup, alias copying and rebinding.
- Transferability is explicit through `owned`, a binding/call contract, not a ClassType variant.
- A fresh owned lexical object begins with exactly one transferable responsibility.
- Move transfers responsibility for exact storage and the same DestructorSymbol; it never copies or relocates bytes.
- A moved source is unusable. Physical null disarms cleanup but is not semantic MOVED authority.
- Owned local initializers are fresh-only; owner reassignment, rearm, release and local move destinations are unsupported.
- Persistent aliases from owners reject; temporary borrowed views may alias owners and never consume them.
- An earlier borrow cannot overlap a later same-owner transfer into that call; two borrows may still alias.
- Captured field/method bases and input-derived views cannot be used after a consumer may end their lifetime.
- Object and Resource responsibilities share OWN/MOVE/OWNBOUND state, control flow and lexical ordering.
- Semantic move occurs at capture; physical transfer commits only after all arguments succeed, immediately before invocation.
- A pre-call trap does not commit; traps at either side never unwind cleanup.
- A non-forwarded owned parameter cleans on normal exit; a forwarded parameter does not also destroy its object.
- Exactly one normal path remains responsible, including conditional transfer and null cleanup.
- Root locals clean before parameters; parameters clean in reverse declaration order across both ownership domains.
- Classes without deinit retain semantic lifetime ownership without a destructor call.
- Owned ClassType parameters are nullable and mutable through fields/methods; their binding remains immutable.
- Owned ClassType maps to existing PTR. Physical ABI authority never supplies semantic ownership rules.
- No NativeOwnedObject, new NABI profile, runtime ownership flag, ownership header, refcount or GC exists.
- Ownership implies neither noalias, nonnull nor readonly; no byval or sret is added.
- Consuming calls need no heap. Caller stack allocation may outlive the semantic object lifetime.
- Owned object results use the caller-storage/escape contract in ADR 0053; borrowed/unqualified results remain unsupported.

[ADR 0052](../decisions/0052-transferable-object-ownership.md) freezes these rules.

## Borrowed object parameters

- One borrowed object parameter receives one exact ClassType reference value.
- The existing BORROWED_NOESCAPE parameter contract is separate from ClassType identity.
- Native ClassType parameters default to BORROWED_NOESCAPE; explicit borrowed is equivalent and owned transfers.
- Borrowing never transfers ObjectStorage ownership or destructor responsibility.
- Borrowing never duplicates cleanup responsibility or extends lexical storage lifetime.
- ClassType nullability survives the call; borrowed object parameters may be null.
- Borrowed object parameters may mutate the referenced object and alias each other.
- Parameter bindings retain ordinary immutability independently of referent mutation.
- Borrowed object parameters are noescape, using function-region lexical authority.
- Local copies and forwarding retain exact ClassType and conservative lexical provenance.
- Null has no ObjectStorage provenance and creates no dummy object.
- Explicit nullable borrowed parameters remain distinct from implicit nonnull receivers.
- Field and method access reuse ordinary reference-null guards and exact member identities.
- Reference copies remain pointer-like value copies, with no object aggregate argument.
- ObjectStorage remains explicit caller-owned storage with its original cleanup rank.
- A borrowed parameter creates no callee ObjectStorage or object cleanup slot.
- Exact ClassType identity and parameter contracts survive Core/CFG/SSA stage destruction.
- Only validated NABI parameter planning erases borrowed ClassType to PTR.
- Equal physical PTR representations never collapse distinct semantic types/contracts.
- No NativeObjectType or new NABI profile is necessary; existing vector-v4/slice-v5 coexist.
- Owned Resource boundaries keep their existing evaluation and delayed commit authority.
- Borrowed ClassType emits no new LLVM nonnull/noalias/readonly/byval/sret attributes.
- No runtime borrow token, type tag, descriptor or lifecycle metadata crosses the call.
- Object lifecycle stays attached to original ObjectStorage regardless of reference calls.
- Borrowed/unqualified object results and CABI/VAPI object boundaries remain unsupported.
- Owned object boundaries extend this exact reference and storage model under ADR 0052; owned results use the bounded caller-storage contract in ADR 0053.

[ADR 0051](../decisions/0051-borrowed-object-boundaries.md) freezes these rules.

## Native object lifecycle

- Object lifecycle belongs to ObjectStorage identity, not ClassType reference identity.
- Reference copies never duplicate cleanup responsibility.
- Reference rebinding never moves cleanup responsibility or changes its target/rank.
- Ordinary reference nulling never cancels fixed cleanup responsibility.
- Constructors initialize exact caller-owned lexical storage, without allocating or returning it.
- Constructor `this` is an exact nonnull INITIALIZING receiver, distinct from a fully live reference.
- Constructor `this` cannot escape, be rebound or invoke ordinary instance methods.
- Every receiver field is initialized exactly once on every reachable successful constructor path.
- A field cannot be read before definite initialization on all reachable incoming paths.
- Definite sets intersect and possible sets union at joins; maybe-double initialization rejects.
- Field initialization is explicit Initialize and is unsupported inside constructor loops.
- Constructor success is normal body fallthrough; explicit constructor return rejects.
- An object becomes live only after normal constructor completion or complete brace initialization.
- Destructor cleanup activates only after successful construction; a trapping construction never activates it.
- Destructors receive exact fully initialized live ObjectStorage and observe final field state.
- Destructors run once per responsibility at normal lexical lifetime end, never because a reference binding dies.
- Source cannot explicitly invoke a destructor or take it as a value.
- Object and Resource cleanup share one lexical LIFO ordering authority.
- Object rank is stable construction/declaration rank; Resource rearm retains its existing owner-slot rank.
- Return values and transfer state are evaluated/preserved before cleanup.
- Break, continue and loop backedge cleanup follow exact exited lexical scopes.
- Every successful loop construction has a fresh lifetime and matching cleanup before reuse.
- Constructor/destructor locals use the same lexical cleanup rules as other callables.
- Traps do not unwind; a destructor trap stops subsequent cleanup.
- No runtime cleanup stack, registration, active flag or object lifecycle header is required.
- Constructor/destructor identities survive each stage without becoming ordinary Method identities.
- Lifecycle receivers use existing PTR first; both physical results are void.
- Existing native parameter contracts and effective v0-v5 profiles are reused; no new channel/profile exists.
- Calls are effectful; source destructor timing cannot move earlier merely because references are dead.
- Empty objects retain the existing identity anchor without lifecycle metadata.
- No heap, refcount, GC, vtable, RTTI or ClassType C/VAPI boundary is added.
- Transferable owners extend this ObjectStorage lifecycle authority; escaping/heap references remain deferred.

[ADR 0050](../decisions/0050-native-object-lifecycle.md) freezes these rules.

## Native object identity

- A class declares nominal object identity; ClassType is a reference, not an aggregate.
- ClassType remains distinct from StructType and TypedPointerType regardless of shape.
- Object storage and reference bindings have separate compiler identities.
- Every executed construction creates fresh lexical storage identity.
- Complete field initialization evaluates in written order before publishing a reference.
- Reference copying and assignment never copy object storage or fields.
- Equality is exact identity; equal-state distinct objects remain unequal.
- Class references are nullable; null is not an object identity.
- Null field reads/writes and method calls trap explicitly.
- Field-base validity precedes RHS effects; receiver validity precedes explicit arguments.
- Object backing storage is always explicit memory and never a whole-object SSA value.
- Reference locals may promote to scalar SSA definitions and branch/loop block arguments.
- Object fields remain exact mutable Places and explicit memory operations.
- Multiple references may alias one object; no exclusivity or noalias follows.
- Object reference lifetime uses existing lexical borrow-region authority.
- Fixed storage lifetime is lexical and independent of ordinary reference rebinding.
- Destruction targets exact storage identity; an owner capability may transfer responsibility for that identity.
- Class methods reuse MethodSymbol, ReceiverSymbol and the existing direct-call architecture.
- Incoming `this` remains exact, mutable, non-owning, nonnull and non-rebindable.
- Object method dispatch is exact/static, including direct and mutual recursion.
- Receiver PTR does not make ClassType a TypedPointerType or add an explicit ABI channel.
- Empty objects retain distinct identity; the backend uses a private nonzero byte anchor.
- No heap, allocator, GC, refcount, vtable/vptr, RTTI or object descriptor exists in OBJ-1.
- Class references cross native boundaries as plain/explicit borrowed or explicit owned parameters, or owned results; C/VAPI and borrowed/unqualified object results remain unsupported.
- Lifecycle and transferable ownership extend this identity model; escaping boundaries remain deferred.

[ADR 0049](../decisions/0049-native-object-identity.md) freezes these rules.

## Native struct methods

- A method belongs to one exact StructSymbol/StructType or ClassSymbol/ClassType and has one exact MethodSymbol.
- Fields, methods and properties share a deterministic namespace; collisions and overloads reject.
- Member identities/signatures exist before any method body is checked.
- Every method has one exact implicit receiver identity, separate from explicit parameters.
- ReceiverType denotes exact mutable, non-owning, nonnull authoritative instance storage.
- The receiver is not a source typed-pointer parameter, assignable local or transferable owner.
- Explicit `this` is a method/lifecycle/accessor receiver; unqualified field lookup is absent.
- `this.field` is a Place access with exact field identity and explicit Load/Store semantics.
- Invocation never copies or rebinds the receiver.
- For structs, method use makes only the particular direct-local receiver addressable.
- Existing address-taken storage handles that classification for its whole relevant lifetime.
- Declaring methods alone does not make any struct instance addressable.
- Nonreceiver struct instances remain scalarizable, including instances of types with methods.
- Direct fields, typed-pointer aliases and methods observe one coherent storage authority.
- Receiver input storage already exists in the caller; no callee receiver alloca or shadow fields exist.
- Receiver evaluation precedes ordered explicit argument evaluation.
- Calls reuse native signature, effect, borrow, ownership capture and transfer-commit contracts.
- Borrowed slices remain one logical argument; owned results remain ordinary owned producers.
- Dispatch is exact and static, including recursion and mutual references.
- Method identities survive each stage independently of predecessor symbols and physical names.
- Receiver physically lowers through existing PTR only after exact semantic resolution.
- Receiver PTR is physically first; explicit groups/results retain v0-v5 rules, without a new profile.
- Receiver nonnull semantics do not weaken ordinary nullable Struct* field traps.
- Receiver aliasing is legal; no exclusivity, noalias or readonly assumption follows.
- Methods are internal fastcc symbols and cannot be C exports or program entries.
- No vtable, RTTI, runtime method descriptor or GObject machinery exists.
- Methods establish neither class/object identity nor allocation, constructors or destructors.
- OBJ-1 native classes reuse this exact member/receiver/direct-call foundation.
- Typed-pointer method receivers, virtual properties, inheritance and interfaces remain deferred.

[ADR 0048](../decisions/0048-native-struct-methods.md) freezes these rules.

## Bounded borrowed slices

- A slice is one bounded borrowed view value, distinct from arrays and pointers.
- SliceType identity is exact element identity; int/i32 slices alias exactly.
- Runtime extent belongs to SliceValue, never SliceType.
- Slices are non-nullable; emptiness is zero length with valid provenance.
- Construction is explicit bounded borrowing of direct fixed-array local storage.
- No decay, source element pointers, byte stride or pointer arithmetic is exposed.
- Existing lexical region rules govern initialized slice locals and copies/rebinding.
- Mutable aliases and overlapping subranges are permitted and coherent with arrays.
- Array and slice indexing produce writable Places; vector indexing produces Values.
- Similar bracket syntax never overrides Place/Value authority.
- Subrange start then count each evaluate once before range validation.
- Require `0 <= start <= N` and `0 <= count <= N - start`, without overflowing sums.
- Empty end subranges are valid and require no one-past typed object pointer.
- Indexing captures one whole view before evaluating its exact mathematical index.
- Runtime-length bounds precede every physical element address and memory operation.
- Invalid assignment bounds precede and suppress RHS effects.
- Vector slice elements remain whole vector Loads/Stores; no LanePlace exists.
- Slice locals promote as one logical SSA value across branches and loops.
- Physical pointer/length realization never redefines source semantics or pairing.
- Arrays remain explicit non-value storage and acquire no whole-value operations.
- `len` is the common array/slice length operation, with exact int results.
- Fixed-array sources are bounded by 1024 and BUFFER-1 owning sources by INT_MAX;
  future sources exceeding INT_MAX require explicit size-type review.
- Borrowed SliceValue has no cleanup responsibility, equality, nullability,
  unchecked access or runtime library. Buffer ownership is a separate contract.
- SLICE-BOUND-1 permits explicit native borrowed-slice parameters under slice-v5;
  BUFFER-1 also permits implicit borrowed parameters. Borrowed slice results and
  C/VAPI boundaries remain unsupported; owned results use buffer-v8.
- Future native, foreign, readonly, subslicing or address-taking extensions must
  preserve exact SliceType identity, extent, coherent value flow and lifetimes.

[ADR 0046](../decisions/0046-bounded-borrowed-slices.md) freezes these rules.

## Fixed local arrays

- Fixed arrays are storage aggregates, distinct from vectors, pointers and slices.
- ArrayType identity is exact element identity plus compile-time length; int/i32 alias.
- Array indexing produces a writable Place; vector lane indexing produces a Value.
- Similar bracket syntax does not confer similar storage authority.
- Array indices are exact mathematical integer ordinals, independent of element type.
- Invalid indices reject/trap before physical address formation or memory access.
- No invalid source index becomes backend out-of-bounds memory behavior.
- Each index executes once; bounds validation precedes assignment RHS evaluation.
- Complete exact-typed initialization executes left-to-right before local visibility.
- Array locals have one explicit contiguous storage object through Astra SSA.
- Arrays have no whole-value SSA form or synthetic per-element Astra locals.
- Backend SROA does not change Astra storage semantics.
- Numeric vector array elements load/store as whole vector values.
- Arrays create no vector LanePlace; nested extraction remains non-writable.
- Contiguity is semantic at the ascending element-object level.
- Byte stride, sizeof, numeric alignment, address arithmetic and endianness stay unexposed.
- Eligible concrete record elements compose ordinary recursive field storage.
  Direct bool/mask, pointer, Resource and nested fixed-array elements remain
  deferred; record fields follow their separately qualified leaf domain.
- Arrays never decay; array/element address-of and array pointers are unsupported.
- Array parameters/results and C/VAPI representations do not exist in ARRAY-1.
- Slices explicitly borrow indexed contiguous storage using existing lexical lifetimes.

[ADR 0045](../decisions/0045-fixed-local-arrays.md) freezes these rules.

## Typed vector memory

- Every supported numeric VectorType is a typed-pointer pointee; bool-vector
  memory remains unsupported because its object representation is unfrozen.
- Vector pointer identity includes exact element type and shape despite LLVM
  opaque ptr. int/i32 vector pointers alias semantically; signedness does not.
- Whole-vector dereference uses ordinary DereferencePlace, Load and Store.
  Vector memory introduces no vector-specific Place or instruction hierarchy.
- A vector loaded from memory remains one Astra value and one SSA vector value.
  A vector store consumes one whole value; no semantic lane scalarization occurs.
- Address-of makes storage identity observable. Address-taken vectors become
  explicit memory for their checked lifetime; unaffected vectors remain promotable.
- No authoritative promoted vector copy competes with an addressable object.
  Direct, indirect and native-call accesses remain coherent across aliases.
- Mutable pointer aliases require no exclusivity; existing lexical borrows prove
  same/ancestor-region lifetime, including vector-pointer parameters.
- Lane extraction stays a value operation when its source came from memory.
  `(*p)[k]` loads a whole vector then extracts; it creates no LanePlace.
  `(*p)[k]=x` remains invalid; `*p=insert(*p,k,x)` stores a whole updated vector.
- Integer vector memory preserves exact lane bits and signedness. F32 vector
  memory preserves binary32 values and adds no arithmetic rounding point.
- Ordinary vector loads/stores make no source atomicity, volatile visibility,
  synchronization, or concurrent tearing promise.
- Physical splitting or scalarization by the backend does not scalarize Astra
  semantics and need not produce a single hardware vector instruction.
- Non-null typed vector pointers denote suitably aligned live exact objects.
  Initialized local addresses and compatible native forwarding guarantee alignment.
- Numeric alignment comes from backend/target layout, not source semantics or a
  frontend payload-width calculation. No hardcoded 16-byte rule is permitted.
- Null guards precede vector accesses and use existing physical-final-block
  authority for branch, loop-backedge and short-circuit phis.
- Vector pointers use existing native PTR. Vector pointees alone create no
  vector ABI channel and cannot select vector-v4; actual by-value vectors do.
- C vector-pointer/ABI, arbitrary or unaligned addresses, pointer arithmetic and
  indexing, pointer-backed slices and bool array storage remain deferred.
  STRUCT-AGG-1 separately permits native struct vector fields.
- Vector memory extends DPTR-1, including ownership-independent evaluation and
  LLVM-free type/borrow/Core/CFG/SSA/NABI authority, without a parallel subsystem.

See [ADR 0044](../decisions/0044-vector-memory.md) and
qualification.

## General typed data pointers and scalar memory

- Exact pointee identity is semantic authority. LLVM opaque ptr cannot erase
  Astra typed-pointer distinctions upstream.
- Existing Struct* and integer/f32 T* use one canonical TypedPointerType.
  `int*` and `i32*` are one type; differing exact pointees remain distinct.
- Raw void* is a separate opaque type, not TypedPointerType(void).
- Typed pointers are nullable, non-owning, trivially copied, and potentially
  aliasing. Borrow provenance proves lifetime, not exclusivity or readonly access.
- Address-of exposes authoritative storage identity, not a numeric conversion.
  Current construction is limited to initialized direct supported local types.
- Address-taken integer/f32 locals remain memory-backed throughout the checked
  lifetime. Non-address-taken locals remain promotable.
- Direct and indirect accesses, including native-call mutation, remain coherent.
  No stale promoted pointee value may compete with addressable memory.
- Pointer values may remain SSA-promotable even when their pointees are memory-backed.
- Dereference produces a Place; reading explicitly loads it and writing explicitly
  stores through it. Vector lane extraction produces a value and remains nonassignable.
- A dereference base evaluates exactly once. Scalar dereference assignment
  evaluates base, RHS, then guarded store. Existing struct-field order is preserved.
- Null dereference traps before physical access and does not unwind. Every LLVM
  access through a typed runtime pointer is confined to its non-null path.
- Dynamic guards preserve the existing final physical block authority for phis.
- The exact pointee supplies the load/store type. Integer signedness changes
  interpretation, not object width.
- Plain f32 memory preserves binary32 bits and creates no arithmetic rounding point,
  fast-math permission, or numeric conversion.
- B1 transport leaves bool memory representation unfrozen; bool* stays unsupported.
- Resource* slot mutation and nested pointers require separate
  explicit semantics and remain unsupported.
- A well-formed non-null T* denotes a suitably aligned live object of exact T.
  Direct local construction and compatible native forwarding maintain this invariant.
- No source pointer arithmetic, indexing, increment/decrement, casts, typed/void
  conversions, or pointer/integer conversions weaken that contract.
- Native typed-pointer parameters use existing PTR, after exact call typing.
  Profile selection remains unchanged; no DPTR channel or version exists.
- Typed-pointer results need return-lifetime contracts; C/VAPI typed pointers need
  explicit foreign scalar/layout decisions. Both remain deferred.
- No stable numeric alignment, layout, endianness, or pointer width is introduced;
  neither sizeof/alignof nor volatile, atomic, or unaligned primitives exist.
- Core/CFG/SSA own their Places/storage and immutable exact types. Provenance
  snapshots retain checked proof information without checked graph backlinks.
- The type, borrow, Core, CFG, SSA, and NABI layers remain LLVM-free.
- Numeric vector memory extends this same typed-pointer/DereferencePlace
  architecture. Future unaligned access must preserve the aligned-object contract.

See [ADR 0043](../decisions/0043-typed-data-pointers.md) and
qualification.

## Exact bitwise and shift operations

- Integer bit operations use exact fixed-width bit patterns and preserve width,
  signedness and semantic type; vector lanes share the scalar authority.
- Bool/mask `& | ^` are eager boolean value operations with left-to-right
  evaluation. They do not imply integer conversions. `!` is complement.
- `&&`/`||` remain scalar short-circuit control flow.
- Signed left shift retains low bits with no C-like overflow UB.
- Signed right shift is arithmetic and equals floor division by powers of two;
  unsigned right shift is logical and zero-fills.
- Counts are semantic mathematical integers of any scalar IntegerType.
  Invalid counts trap without unwinding; counts are never masked or UB.
- No invalid count may reach an LLVM shift instruction.
- Physical count normalization is backend-only, never an Astra conversion.
- Vector counts are scalar in BIT-1. Vector bit/shift operations remain one
  semantic operation and one SSA operation/result, without LanePlace or memory.
- Potentially trapping shifts preserve value/count evaluation order and actual
  final physical predecessors for phis after LLVM guards.
- LLVM bit/shift instructions realize language semantics; machine selection
  and vector legalization do not define those semantics.
- Future rotates, masked counts, per-lane shifts, bitcasts, fixed point,
  compound assignment requires an explicit semantic addition.

See [ADR 0042](../decisions/0042-bitwise-and-shift-semantics.md) and
qualification.

## Exact vector dot/MAC operations

- Integer products use source mathematical integer values, never source-width
  truncated products reinterpreted in a wider accumulator.
- Integer dot/MAC reduce the exact sum, plus MAC's accumulator, into an explicit
  modulo accumulator domain at least as wide as the source element.
- Source signedness controls operand widening independently of destination.
- Destination signedness interprets final accumulator bits and MAC's input C.
- Integer wrapping reduction grouping and corresponding pair permutation are
  unobservable. This permission does not apply to arbitrary expression trees.
- F32 reduction grouping and contribution ordering are observable.
- F32 dot starts at exact positive zero; F32 MAC starts at its supplied f32 c.
- Every F32 product uses exact scalar binary32 multiplication and rounds before
  accumulation. Every scalar accumulator addition rounds independently.
- F32 dot/MAC accumulate in ascending lane ordinal order. MAC is non-fused;
  no FMA contraction, fast math or result-changing reassociation is permitted.
- Integer and F32 dot intentionally expose different optimization freedoms.
- Each dot/MAC remains one Astra semantic operation and one SSA instruction
  with two whole vector operands and one scalar result.
- CFG preserves c/a/b evaluation order without synthesizing reduction loops.
- Backend scalarization does not imply Astra semantic scalarization.
- Backend-private widened vector types never expand source VectorType legality.
- Dot/MAC introduces no LanePlace, new NABI profile or C vector ABI.
- Specialized machine dot instructions are usable only when their exact results
  match Astra; hidden intermediate saturation, reordered F32 accumulation or
  result-changing fusion are invalid.
- Future grouped/mixed/saturating/fused dot families, widening multiply,
  rotates and per-lane shifts require separate explicit semantic additions.

See [ADR 0041](../decisions/0041-vector-dot-products.md),
[dot/MAC IR](../ir/vector-dot.md), and qualification.

## Exact vector DSP operations

- Saturating arithmetic is explicit and never changes ordinary wrapping `+`, `-` or `as`.
- Scalar integer saturation is the authority for every integer vector lane.
- Saturating conversion clamps the source mathematical integer to the destination representable interval before encoding.
- Saturating conversion is distinct from ICONV wrapping conversion; there is no public scalar saturating cast yet.
- Widening is low/high ordinal half-selection followed by ICONV conversion, within existing VectorType bounds.
- Source signedness, not destination signedness, controls physical extension.
- Pack-wrap uses ICONV modulo semantics, including nonadjacent widths and cross-sign destinations.
- Pack-sat uses the reusable exact saturating-conversion rule for all signedness combinations.
- Pack output contains first-source lanes followed by second-source lanes, independent of machine byte order.
- Interleave is structural and performs no numerical operation or rounding.
- Interleave copies selected f32 values, preserving signed zero, subnormal, infinity and NaN behavior.
- Every vector DSP primitive remains one Astra semantic value operation.
- Every vector DSP primitive remains one Astra SSA vector operation/result, including branch/loop transport.
- No DSP primitive implies lane storage identity or a LanePlace.
- No DSP primitive implies source vector memory, addressability or alignment.
- LLVM saturation, conversion and permutation operations are physical realizations; exact expansion/legalization is allowed.
- Machine SIMD instruction availability never defines source legality; NABI vector-v4 remains sufficient and CABI/VAPI do not change.
- Dot/MAC explicitly defines product/accumulator widths, signedness, overflow, ordering and rounding in ADR 0041; future families must do likewise.

See [ADR 0040](../decisions/0040-vector-dsp-foundations.md),
[DSP IR](../ir/vector-dsp.md), and qualification.

## VEC-LANE-1 component value invariants

- A lane can be observed without becoming authoritative storage.
- Constant extraction returns an exact scalar value, never a Place.
- Insertion creates a new vector; whole-vector assignment is the only vector-local mutation mechanism.
- Splat evaluates its scalar source exactly once, with no implicit broadcast elsewhere.
- Shuffle evaluates one vector source exactly once and preserves its exact type/shape.
- Shuffle selectors are immutable compile-time semantic ordinals; duplicates are valid.
- Select evaluates mask, true vector and false vector in order, including both data operands.
- Select is one vector semantic operation and never short-circuit CFG control flow.
- No dynamic vector indexing or lane Place exists.
- F32 primitives copy exact selected values without arithmetic or extra rounding points.
- Primitives remain whole-vector SSA operations, with ordinary branch/loop promotion.
- LLVM extractelement/insertelement/shufflevector/select are implementation mechanisms.
- Backend legalization can scalarize execution without scalarizing Astra semantics.
- NABI vector-v4 remains sufficient; body primitives do not change signature profiles.
- Writable swizzles/lane storage cannot reinterpret these value primitives as prior Places.
- Future writable indexing should initially consider whole-vector load/insert/store.
- Vector memory/addressability uses whole-vector storage without lane storage projection.

[ADR 0038](../decisions/0038-vector-lane-primitives.md) freezes these rules.

## VEC-1 short-vector invariants

- A short vector is one Astra semantic value and one Astra SSA value.
- Exact scalar element identity and exact lane count form its type identity.
- `int<N>` and `i32<N>` share the same canonical VectorType.
- Vector lane semantics come from the existing exact scalar authorities.
- Numeric vector comparison produces `bool<N>`, distinct from scalar bool.
- Scalar control flow requires explicit all/any mask reduction.
- Construction evaluates lane expressions left-to-right before exposing the local.
- Scalar broadcast and element/shape conversion are never implicit.
- Vectors are not arrays and promise neither a hardware SIMD register nor one instruction.
- Target legalization may split or scalarize a vector without changing its semantics.
- LLVM vectors are physical realization, never upstream type or semantic authority.
- Astra SSA does not proactively scalarize a vector into independent semantic lanes.
- Vector locals use whole-value promotable Places and cannot become addressable in VEC-1.
- No lane Place exists merely because a vector has lanes. STRUCT-AGG-1 permits
  whole-vector native struct fields, including masks; bool-vector pointers/arrays
  remain deferred.
- Integer lanes inherit INTS-1 wrapping and signedness rules; vector div/rem remains deferred.
- F32 lanes inherit F32-1 including subnormals, signed zero, NaNs, exact rounding, and no contraction.
- No vector fast-math permission exists.
- NativeAbiType distinguishes scalar and vector channels; NABI preserves signedness before LLVM.
- One direct native vector channel does not promise a hardware register or memory layout.
- Vector-v4 extends existing program-wide profile selection; old no-vector goldens remain stable.
- C ABI vector semantics remain unspecified and unsupported.
- Concrete VectorTypes work as ordinary exact GEN-1 generic-function type arguments, independently of const generics.

[ADR 0037](../decisions/0037-short-vectors.md) freezes these rules.

## OWNBOUND-1 native ownership invariants

- Native ownership transfer is semantic call-contract information, separate from value type and machine channels.
- Ownership-qualified Resource boundaries require exact nominal Resource identity and stable cleanup authority; owned object parameters retain exact ClassType/native destructor authority.
- Owned native parameters enter source execution definitely OWNED, including null arguments.
- Existing owners cross owned parameter boundaries only through explicit move; borrowed and unmanaged values cannot transfer responsibility.
- Argument ownership state follows Astra's left-to-right evaluation order.
- Source semantic moved-state begins at capture; physical nulling commits after all argument evaluation immediately before the call.
- No later argument may read, borrow or move an already semantically moved owner.
- Pending transfers retain exact source, evaluated value, destination parameter and cleanup; no lexical cleanup or exit may intervene before commit.
- Successful invocation transfers one responsibility per owned parameter, with no observable partial commit.
- Owned parameter cleanup is lexical: root locals first, then owned parameters in reverse declaration order; nested owners clean before root owners.
- An owned result transfers exactly one responsibility to the caller through explicit return move or owned-null return; objects also permit direct result construction and forwarding.
- Return move captures and disarms its source before lexical cleanup; no lexical result-owner slot is introduced.
- Native owned results require immediate, exact, exactly-once acquisition, Resource rearm, or direct owned-object result forwarding; discard and unmanaged capture reject.
- Existing ownership possibility sets and loop/termination precision remain the state authority; SSA carries no state lattice.
- NABI transports all Resource qualifiers through ordinary PTR under scalar-ptr-v1; physical erasure cannot relax upstream contract/type correctness.
- LLVM uses ordinary ptr and fastcc without ownership tokens, flags, destructor arguments, descriptors or refcounts.
- C ownership exports, owned void* boundaries, direct ownership chaining, aggregate ownership and generic ownership require later decisions.

[ADR 0034](../decisions/0034-owned-native-boundaries.md) freezes these rules.

## RESOURCE-1 nominal resource invariants

- Resource identity is semantic, nominal and exact; PTR equivalence never implies type equivalence.
- Cleanup responsibility, nominal type and pointer representation are independent dimensions.
- A handle type owns one exact stable cleanup contract; every owned binding uses it.
- Unmanaged handles own nothing and may copy; borrowed handles own nothing and may not escape.
- Qualifiers never create distinct pointer machine types or runtime lifetime metadata.
- Every current handle admits null; ownership state remains independent of pointer nullness.
- Distinct nominal types may share a physical cleanup function while retaining distinct types through SSA.
- VAPI handles enter the ordinary type namespace before all function signature/body resolution.
- VAPI syntax and prior-stage descriptors never remain downstream type authority.
- Exact HandleType tokens have no upstream backlinks; each IR stage owns its contract descriptor.
- Native and C ABI transport handles through existing PTR after exact semantic validation.
- No runtime tag, descriptor, destructor pointer, allocation or pointer/integer conversion is introduced.
- Nominal cleanup authority supplies both sides of owned native parameter/result transfer under OWNBOUND-1.
- Existing anonymous owned void* local contracts remain valid; native ownership boundaries require nominal types.

[ADR 0033](../decisions/0033-nominal-resource-handles.md) freezes these rules.

These are review constraints. Future milestones must preserve them or propose
an explicit architectural decision before changing them.

| ID | Enforceable invariant |
| --- | --- |
| ASTRA-I1 | No frontend/semantic architecture is defined in terms of generated C. |
| ASTRA-I2 | No Astra-native type is implicitly a GObject. |
| ASTRA-I3 | Foreign ABI operations are explicit semantic boundaries. |
| ASTRA-I4 | Raw LLVM handles remain below `src/backend/llvm/`; frontend/semantic/Core/CFG/SSA/NABI/CABI interfaces must not expose them. |
| ASTRA-I5 | Ownership is represented from language semantics, not pointer shape. |
| ASTRA-I6 | Authoritative storage is distinct from computed values. A computed value is not storage authority. |
| ASTRA-I7 | The language core has no mandatory desktop/runtime dependency: OS, GLib, GObject, GC, heap, threads, reflection, or heavyweight unwinder. |
| ASTRA-I8 | Compiler/runtime costs are pay-for-use where semantics permit. |
| ASTRA-I9 | Unsupported ABI/ownership semantics fail explicitly rather than approximating exact contracts. |
| ASTRA-I10 | Vala and frozen LLVM-v2 have no architectural veto over Astra. |
| ASTRA-I11 | The checked semantic model is distinct from syntax, with compiler-owned canonical types and direct symbol references. Source/syntax remain authoritative for spelling and provenance. |
| ASTRA-I12 | Core IR contains semantic computation with Core-owned identities, not syntax or machine representation. Its semantic types and source provenance survive independently of checked/syntax models. |
| ASTRA-I13 | Physical lowering may consume Core IR; Core IR must never depend on a machine backend. |
| ASTRA-I14 | CFG consumes verified Core and owns its downstream function/parameter/Place/block/instruction/value identities independently of Core and LLVM. |
| ASTRA-I15 | CFG edge authority is encoded by Astra terminators, never inferred from source order or backend block structure. Every completed block has exactly one terminator. |
| ASTRA-I16 | Reachability and flow validity are distinct from structural Core/CFG validity. Unreachable source structure is preserved during CFG construction; function-completion source diagnostics belong to control-flow validation. |
| ASTRA-I17 | Reading mutable storage requires an explicit semantic load from a Place to a value in Core and CFG. |
| ASTRA-I18 | Storage mutation targets an explicit, containing-function Place through exact compiler identity. |
| ASTRA-I19 | Initialization of fresh storage remains distinguishable from replacement of stored state until a downstream stage proves the distinction irrelevant. |
| ASTRA-I20 | Place identity is compiler storage authority, not a backend pointer. Each downstream representation owns its Places; translation never reconstructs identity from strings. |
| ASTRA-I21 | Bool semantic identity and truth payloads are independent of physical representation. Conditions consume bool values without implicit integer truthiness. |
| ASTRA-I22 | Structured conditionals remain structured through Core IR. CFG lowering alone introduces explicit branch targets and joins. |
| ASTRA-I23 | Core/CFG control-flow joins do not duplicate authoritative Places. Stores in either arm and loads after a join retain the exact same outer Place. |
| ASTRA-I24 | Reachability derives solely from terminator successors and entry identity, never block/source ordering or constant-condition evaluation during construction. |
| ASTRA-I25 | CFG branches and target blocks are Astra compiler structures, not LLVM identities. No SSA or physical representation is implied by a join. |
| ASTRA-I26 | SSA owns its function/block/value identities independently of CFG and backend registers; only shared semantic integer values, types, operators, and provenance remain authoritative upstream. |
| ASTRA-I27 | SSA joins use ordered block parameters with incoming arguments carried by predecessor terminators. Block parameters never maintain an independent predecessor-edge authority. |
| ASTRA-I28 | A promoted Place ceases to exist as SSA storage; its reaching values become explicit dataflow, without Load/Initialize/Store machinery. |
| ASTRA-I29 | Every reachable local load must have a reaching definition. Missing definitions are internal errors; undefined or arbitrary scalar values are never fabricated as repairs. |
| ASTRA-I30 | CFG remains the source-preserving authority for unreachable structured code. SSA projects graph-reachable blocks only, without constant-condition evaluation. |
| ASTRA-I31 | SSA may erase semantic storage distinctions only after proving the type/Place eligible. Current int/bool/void* promotion does not freeze future ownership, resource, or addressable-storage processing. |
| ASTRA-I32 | SSA value/block-argument numbering and edge argument ordering are deterministic and independent of source spelling or hash iteration. |
| ASTRA-I33 | Resolved call targets are exact function identities; downstream builders translate them to their own program-owned functions without name lookup. |
| ASTRA-I34 | Programs own functions; body-bearing stages' functions own bodies. Non-owning call references never create self/mutual recursion ownership cycles; expired or foreign callees are invalid. NABI owns signatures without bodies or call edges. |
| ASTRA-I35 | Current expression operands and call arguments evaluate left-to-right. Calls execute after their arguments and are conservatively effectful. |
| ASTRA-I36 | Semantic function signatures remain distinct from physical/native ABI signatures. Semantic calls imply no calling convention or first-class function values. |
| ASTRA-I37 | CFG calls are ordered instructions, never successor edges. Reachability never traverses callees. |
| ASTRA-I38 | Call results are Values, never Places. CFG enforces unique preceding definitions on every incoming path; SSA enforces unique dominating definitions. Discarded non-void results do not remove calls. |
| ASTRA-I39 | Astra defines scalar meaning; Vala/C/host/LLVM behavior is never language authority. |
| ASTRA-I40 | `int` is signed with exactly 32 bits of value representation on every target, range -2147483648 through 2147483647. |
| ASTRA-I41 | Ordinary int add/subtract/multiply/negate wrap deterministically modulo 2^32 in every build mode; no helper relies on overflowing signed host arithmetic. |
| ASTRA-I42 | Division truncates toward zero; remainder follows that quotient. Zero divisors are explicit runtime traps. INT_MIN/-1 is INT_MIN; INT_MIN%-1 is zero. |
| ASTRA-I43 | Integer comparisons use signed ordering and exact value equality. |
| ASTRA-I44 | SourceFile/SourceSpan owns spelling/provenance; immutable AstraIntegerValue owns exact typed integer numeric meaning. |
| ASTRA-I45 | Semantic analysis rejects out-of-range literals before checked constants/Core. Direct signed literal formation admits parenthesized INT_MIN without a positive 2147483648 value. |
| ASTRA-I46 | Core, CFG, and SSA retain valid semantic integer values and never re-parse source text for numeric meaning; upstream constant nodes may die. |
| ASTRA-I47 | Bool is exactly false/true, with symbolic semantic authority and no integer encoding/coercion. |
| ASTRA-I48 | Concrete scalar semantics alone do not prescribe an ABI or layout. NABI separately defines physical channels without choosing C ABI, bool memory width, or LLVM representation. |
| ASTRA-I49 | Potential arithmetic traps obey the accepted left-to-right order relative to calls and expression regions. CFG evaluation results require unique preceding definitions on every incoming path and never act as Places. |
| ASTRA-I50 | Semantic scalar identity and native physical scalar identity are distinct. Completed native signatures retain no SemanticType objects. |
| ASTRA-I51 | NativeTypeMapper is the single compiler-owned semantic-to-native scalar mapping authority. SemanticType exposes no physical conversion API. |
| ASTRA-I52 | Native int transport is I32: exactly 32 bits with Astra's signed two's-complement meaning. |
| ASTRA-I53 | Native bool transport is B1: canonical false/true, without a bool memory-layout or machine-carrier promise. Wider realization may not introduce additional bool values. |
| ASTRA-I54 | Void never becomes a transported native value; a void signature has no result channel. |
| ASTRA-I55 | Each source scalar parameter has exactly one direct native channel in source order; a scalar return has one direct result. Scalar v0 has no hidden channels. |
| ASTRA-I56 | Astra-native signatures are compiler-owned and distinct from C/VAPI signatures; scalar-v0 is internal/unstable with no external or separate-compilation compatibility promise. |
| ASTRA-I57 | Native ABI planning is a signature sidecar and never duplicates SSA bodies. SSA remains the authority for values, instructions, control flow, calls, block arguments, and effect order. |
| ASTRA-I58 | NativeFunction is independent physical compiler identity, with native-internal linkage intent. A source/debug name is not stable linker spelling or a mangling scheme. |
| ASTRA-I59 | Native functions/signatures are complete before call validation, using an exact temporary SsaFunction-to-NativeFunction map with no downstream name lookup or retained call edges. |
| ASTRA-I60 | NativeAbiProgram and its physical signatures remain verifiable, dumpable, and provenance-capable after all upstream stages and semantic types die; weak program owners introduce no cycles. |
| ASTRA-I61 | Register/stack placement, wider carriers, and machine calling conventions belong to backend/target realization, not native signature semantics. |
| ASTRA-I62 | All body lowering preserves wrapping, signed comparisons/division/remainder, explicit zero-divisor traps, INT_MIN/-1 and INT_MIN%-1 results, and previously frozen evaluation/effect order. |
| ASTRA-I63 | LLVM is downstream physical lowering, never Astra semantic authority; it consumes verified SSA and verified NABI with validated ordinal/signature/call correspondence. |
| ASTRA-I64 | NABI supplies LLVM function-channel types. SSA values use NativeTypeMapper before the centralized LLVM mapper; I32/B1/absent result realize as i32/i1/void. |
| ASTRA-I65 | LLVM functions are declared before bodies and mapped by exact SSA/native identity. Current definitions/calls use internal fastcc with deterministic backend-local names, without public ABI stability. |
| ASTRA-I66 | Astra block arguments may lower to LLVM phis without phi becoming Astra SSA semantics. Incoming values use the exact physical edge predecessor. |
| ASTRA-I67 | Backend-created blocks may refine physical control flow without changing Astra CFG/SSA. Distinct parallel edges preserve distinct arguments through physical edge splitting. |
| ASTRA-I68 | Wrapping Astra arithmetic never receives LLVM nsw/nuw assumptions. |
| ASTRA-I69 | Raw signed LLVM division/remainder executes only where Astra and LLVM semantics coincide: neither zero divisors nor INT_MIN/-1 may reach it. |
| ASTRA-I70 | Zero-divisor behavior is an explicit intrinsic trap followed by unreachable, never LLVM undefined behavior. Special division/remainder paths supply INT_MIN/zero. |
| ASTRA-I71 | Physical instruction/effect/trap order follows stored SSA order; no backend source-tree re-walking or speculative trap movement is permitted. |
| ASTRA-I72 | LLVM verification is mandatory before module acceptance/dumping. No optimization pass is required or run to repair generated semantics. |
| ASTRA-I73 | The LLVM artifact owns its module/context and retains no upstream graph, semantic type, or source provenance; builders and correspondence maps have construction-only lifetimes. |
| ASTRA-I74 | Upstream compiler layers remain buildable/testable without LLVM linkage; astrac and LLVM backend tests deliberately link qualified LLVM 22. |
| ASTRA-I75 | A source entry remains an ordinary Astra-native function with native-internal linkage and unchanged call semantics. Source entry selection retains exact compiler identity downstream. |
| ASTRA-I76 | Platform process entry is synthesized only at the backend boundary; the launch ABI does not redefine native ABI or establish user C interoperability. |
| ASTRA-I77 | Host target configuration exists only downstream of verified LLVM lowering. Target data layout never becomes semantic type authority. |
| ASTRA-I78 | Object emission preserves Astra scalar and call semantics, uses target-machine code generation without an explicit Astra optimizer pipeline, and owns no upstream graph. |
| ASTRA-I79 | Executable linking is a driver/platform operation with argv, never semantic lowering or shell interpolation. Publication occurs only after successful linking and preserves prior output on failure. |
| ASTRA-I80 | Runtime traps have no normal result or continuation even when their process manifestation is target dependent. |
| ASTRA-I81 | Upstream layers remain independent of LLVM target-machine machinery. Modules, target machines/data, objects, and executables have separately qualified lifetimes. |
| ASTRA-I82 | Structured loops remain structured through checked semantics and Core. CFG alone introduces header/body/exit blocks and backedges. |
| ASTRA-I83 | A while condition requires bool and executes before every attempted iteration, retaining established left-to-right call/trap order. |
| ASTRA-I84 | CFG cycles arise exclusively through terminator-owned successor edges. A backedge is an ordinary branch edge, not a separate semantic graph. |
| ASTRA-I85 | Cyclic CFG/SSA topology must not imply cyclic strong ownership. Function arrays own blocks; successor references expire safely without retaining blocks. |
| ASTRA-I86 | Loop-carried scalar state uses ordinary SSA block arguments and matching predecessor edge arguments, in deterministic local order. |
| ASTRA-I87 | Reachability, dominance/frontiers, promotion, verification, and dumping are graph-general and terminate on cycles without source-specific loop handling. |
| ASTRA-I88 | Loop-local storage acquires no value outside its initialization-dominated region. Missing definitions never cause invented undef/poison or arbitrary values. |
| ASTRA-I89 | LLVM loop phis realize Astra block arguments; incoming predecessors are actual physical end blocks, including trap-split backedges. |
| ASTRA-I90 | Loop correctness requires no optimizer, new runtime support, or NABI change. Constant conditions retain both CFG edges until a separate analysis proves otherwise. |
| ASTRA-I91 | Semantic analysis resolves each loop-control target once; unlabeled break/continue select the innermost active loop independently of non-loop scopes. |
| ASTRA-I92 | Loop targets are exact compiler objects. Function-local source-preorder ordinals aid inspection but never replace identity. |
| ASTRA-I93 | Checked-to-Core and Core-to-CFG loop-control lowering use temporary exact identity maps, never source-nesting reconstruction. |
| ASTRA-I94 | Structured while statements own loop targets; transfers hold safely expiring non-owning references without ownership cycles. |
| ASTRA-I95 | Core retains explicit Break/Continue and independent loop targets; verification rejects expired/foreign/reused targets without CFG reachability. |
| ASTRA-I96 | Break lowers to ordinary Branch(resolved exit); continue lowers to ordinary Branch(resolved header), reevaluating the condition. No separate CFG edge authority exists. |
| ASTRA-I97 | Source after unconditional loop transfer remains represented but unreachable, including calls and stores; projection alone removes disconnected CFG blocks. |
| ASTRA-I98 | Multiple backedges and exit edges participate in ordinary predecessor/dominance/frontier/SSA construction with exact current edge values. |
| ASTRA-I99 | Loop-local values never acquire fictitious definitions to satisfy break/continue edges outside their initialization-dominated availability. |
| ASTRA-I100 | Backend physical splitting changes phi predecessor realization, never semantic loop-control identity or transfer/effect order. |
| ASTRA-I101 | Short-circuit boolean operations are control-flow expressions with distinct checked/Core identity, never eager binary arithmetic. |
| ASTRA-I102 | Both logical operands and the result require exact bool; the left always evaluates before the short-circuit decision. |
| ASTRA-I103 | AND evaluates its RHS only on true; OR only on false. Required calls/traps retain evaluation order. |
| ASTRA-I104 | Static semantic checking visits both operands independently of runtime suppression, including names and integer ranges. |
| ASTRA-I105 | Compiler-generated CFG Places have independent exact identity, ownership, and ordinals; they never masquerade as source locals. |
| ASTRA-I106 | Pre-SSA expression-control-flow results may use initialized temporary Places, which disappear through generic scalar promotion. |
| ASTRA-I107 | Short-circuit joins use ordinary SSA block arguments discovered by definitions/frontiers/renaming; no logical SSA operation or manual merge exists. |
| ASTRA-I108 | Block parameters follow ascending source-local ordinals then temporary ordinals; debug origin is not promotion identity. |
| ASTRA-I109 | Every logical operator enters a dedicated evaluation region. Its loop-condition temporary is freshly initialized, never fictitious loop-carried state. |
| ASTRA-I110 | Missing expression-join values never cause invented undef, poison, arbitrary bools, or liveness/pruned-SSA workarounds. |
| ASTRA-I111 | LLVM control flow and phis realize logical expressions; eager source-logical and/or does not. RHS phi predecessors use actual physical end blocks. |
| ASTRA-I112 | Continue always re-enters the full while condition from the resolved original header; break still selects the exact exit. |
| ASTRA-I113 | Constant-valued logical left operands retain their structure and both CFG edges; no constant or branch folding occurs in this milestone. |
| ASTRA-I114 | Expression graph expansion retains weak successor ownership, stage independence, unchanged NABI signatures, and LLVM-free upstream firewalls. |
| ASTRA-I115 | Foreign C declarations are explicit compatibility-boundary objects with no Astra body. |
| ASTRA-I116 | A C target remains distinct from a native target through semantic, Core, CFG, SSA, physical ABI, and LLVM identities; call lookup occurs once. |
| ASTRA-I117 | NABI is native-only and never becomes C ABI authority. CABI is separate foreign physical signature authority without semantic type objects or bodies. |
| ASTRA-I118 | C ABI I32 is a distinct physical identity from native I32; native B1 does not model C `_Bool`, and foreign bool rejects. |
| ASTRA-I119 | Native functions/calls remain internal fastcc when C interoperability exists. C imports are external declarations with exact symbols and C convention. |
| ASTRA-I120 | Astra left-to-right expression/effect order applies before crossing the C boundary. Foreign calls are conservatively effectful non-terminators with no successor edges. |
| ASTRA-I121 | Foreign declarations at every IR stage are program-owned; weak calls and temporary exact maps preserve independent stage lifetime. |
| ASTRA-I122 | CABI is complete after SSA destruction, and LLVM retains no SSA/NABI/CABI or source provenance after lowering. |
| ASTRA-I123 | External symbol availability is a link-time concern distinct from source and ABI validity. Check/dump modes do not link. |
| ASTRA-I124 | User object order and literal argv paths survive host linking; failure preserves final output and cleans compiler temporaries. |
| ASTRA-I125 | Executable entry requires a defined native int main(); an imported main never becomes the wrapper target. |
| ASTRA-I126 | VAPI is declaration input for this same boundary, never a separate ABI domain. Foreign metadata never redefines native semantics. |
| ASTRA-I127 | Exporting a function never changes its native Astra identity, body representation, linkage, or calling convention. |
| ASTRA-I128 | Astra calls to exported functions, including self/mutual recursion, use native identity directly and bypass wrappers. |
| ASTRA-I129 | C callers enter exported Astra code only through explicit external/ccc wrappers; implementations remain internal/fastcc. |
| ASTRA-I130 | Export wrappers are physical adapters, not Astra functions; no checked/Core/CFG/SSA wrapper body exists. |
| ASTRA-I131 | NABI owns internal signatures; CABI owns wrapper contracts. Equal-width payloads do not collapse ABI domains. |
| ASTRA-I132 | Stage-owned export metadata weakly targets exact stage-owned native functions; temporary maps preserve independent lifetimes. |
| ASTRA-I133 | CABI exports own copied native ordinals and physical signatures, retaining no SSA/NABI identities. |
| ASTRA-I134 | CABI owns one explicit external-symbol domain and rejects collisions across C imports and exports before LLVM names can be renamed. |
| ASTRA-I135 | Export status cannot replace native executable-entry selection; exported main conflicts with the separate process wrapper. |
| ASTRA-I136 | C import/export coexist without redefining Astra scalar, evaluation-order, short-circuit, loop, or trap semantics. |
| ASTRA-I137 | Export wrappers only adapt/forward arguments, call the exact native target fastcc, and return; representation identity never permits their removal. |
| ASTRA-I138 | VAPI declarations normalize into the same CFunctionSymbol identity as source extern(C); source extern remains a first-class supported path. |
| ASTRA-I139 | Declaration provenance supplies diagnostics and never determines downstream call semantics or physical ABI. |
| ASTRA-I140 | VAPI syntax/tokens never become Core/CFG/SSA identity; span-backed input records can die after semantic collection. |
| ASTRA-I141 | All supplied VAPI files are collected and validated before native body checking; declaration order never controls call resolution. |
| ASTRA-I142 | One callable namespace rejects duplicates across native/exported definitions, source externs, and every VAPI input, including repeated paths. |
| ASTRA-I143 | Import ordering is source externs first, then CLI VAPI file order and lexical declaration order; export ordering remains independent. |
| ASTRA-I144 | CABI remains the physical authority for VAPI-derived imports; completed standalone CABI needs no VAPI source classes. |
| ASTRA-I145 | VAPI never changes NABI, which remains native-only, or introduces an origin-specific backend call path. |
| ASTRA-I146 | VAPI files never implicitly provide link inputs; declaration validity remains distinct from link-time symbol availability. |
| ASTRA-I147 | Future VAPI metadata must enrich the normalized foreign model rather than fork semantic identity, IR, or ABI machinery. |
| ASTRA-I148 | Astra callable identity and C external-symbol identity are separate authorities; cname never creates another Astra callable. |
| ASTRA-I149 | VAPI metadata normalizes into immutable origin-independent CForeignMetadata before semantic collection; source externs share its defaults. |
| ASTRA-I150 | Downstream IR never depends on VAPI attribute syntax, token identities, or declaration origin. |
| ASTRA-I151 | Header names are descriptive integration metadata, never C parser/preprocessor input, existence requirements, or implicit linker inputs. |
| ASTRA-I152 | Header metadata never changes CABI channels, foreign effects, Astra evaluation order, or LLVM code generation. |
| ASTRA-I153 | C external-symbol uniqueness belongs to CABI and is independent of semantic Astra callable-name uniqueness. |
| ASTRA-I154 | LLVM receives physical external symbols from CABI, never from Astra source-call spelling; exact target maps retain call authority. |
| ASTRA-I155 | Normalized foreign metadata lives on imported declarations, survives each stage independently, and never enriches native NABI. |
| ASTRA-I156 | C exports retain source-name external-symbol policy with no export alias or header annotations. |
| ASTRA-I157 | Unknown or duplicate VAPI metadata keys fail explicitly; future pointer/ownership metadata must enrich the existing normalized foreign model. |
| ASTRA-I158 | Raw-pointer semantic identity is independent of machine pointer width; the backend target/data layout determines physical width. |
| ASTRA-I159 | void* is a value, not authoritative storage or the address of its containing Place. |
| ASTRA-I160 | An unmanaged raw pointer does not own its pointee; ownership-qualified bindings carry separate explicit cleanup responsibility. |
| ASTRA-I161 | Null is a contextual pointer literal, never Astra integer zero; absent specific pointer context it defaults to void*. |
| ASTRA-I162 | Pointer equality compares address identity directly and never requires pointer-to-integer conversion; ordering/truthiness/arithmetic are unsupported. |
| ASTRA-I163 | Raw-pointer locals remain promotable while Astra cannot expose their storage address; passing a foreign pointer does not expose an Astra Place. |
| ASTRA-I164 | Native PTR and C ABI PTR are separate physical-domain identities; profile selection is independent and scalar-v0 remains frozen. |
| ASTRA-I165 | LLVM ptr is a backend realization, not Astra pointer semantics or an ownership/nullability guarantee. |
| ASTRA-I166 | C metadata/aliases stay orthogonal to pointer semantics; header metadata never becomes pointer-layout authority. |
| ASTRA-I167 | Future address-of/ref/out/dereference/capture and ownership features must explicitly revisit aliasing and promotion eligibility. |
| ASTRA-I168 | Nullable void* does not freeze future typed-pointer nullability or null-conversion policy. |
| ASTRA-I169 | Pointer C exports retain explicit external/ccc wrappers around native internal/fastcc implementations, with independently validated ABI channels. |
| ASTRA-I170 | Aggregate storage and computed aggregate values are distinct concepts; STRUCT-1 introduces only storage. |
| ASTRA-I171 | A field Place derives storage authority recursively from one exact aggregate base Place; detached scalar copies cannot replace it. |
| ASTRA-I172 | Field identity is compiler-owned and independent of spelling, declaration ordinal, source offsets, and physical offsets. |
| ASTRA-I173 | Physical aggregate layout is not required merely to reason about field storage. |
| ASTRA-I174 | Complete named field initialization follows written initializer order, independently of declaration field order. |
| ASTRA-I175 | A struct local is invisible until its entire initializer finishes; complete named initialization or whole-copy initialization initializes every leaf exactly once. |
| ASTRA-I176 | Scalar/vector leaf FieldPlaces may promote independently when storage is not addressable or aliased. Whole-struct copy preserves promotion by snapshotting concrete leaves before writing destination leaves. |
| ASTRA-I177 | Aggregate base Places are not promotion candidates or SSA values in STRUCT-1. |
| ASTRA-I178 | Field scalarization does not define or freeze future native struct representation or layout. |
| ASTRA-I179 | NABI and CABI remain scalar/pointer-only until aggregate channels are explicitly designed; VAPI adds no struct authority. |
| ASTRA-I180 | Typed pointers and address-of consume exact storage/field authority rather than reconstruct fields from names or LLVM layout. |
| ASTRA-I181 | Struct/field descriptors are stage-owned; shared nominal StructType retains no symbol/syntax backlink; canonical projections have acyclic ownership. |
| ASTRA-I182 | Addressability is semantic storage authority, not merely backend placement; valid borrows mark it conservatively for the whole checked function. |
| ASTRA-I183 | Taking an aggregate local address prevents independent scalar promotion of every field of that aggregate. |
| ASTRA-I184 | Direct and indirect field Places may alias the same authoritative storage; typed pointer parameters may alias each other. |
| ASTRA-I185 | Aliasable storage remains explicit ordered memory through SSA; calls do not justify cached or forwarded field loads. |
| ASTRA-I186 | SSA governs values, while mutable memory need not itself become SSA. |
| ASTRA-I187 | Indirect field access binds exact pointee and field identity, never byte offsets. |
| ASTRA-I188 | A native typed pointer borrow, including lexically stored values, cannot outlive its source storage under the current non-escaping language subset. |
| ASTRA-I189 | Typed pointers are nullable and non-owning; no return, field, cast, capture, global, or foreign destination can currently retain a local borrow. |
| ASTRA-I190 | Null indirect reads/writes trap deterministically; assignment RHS effects precede the target null check. |
| ASTRA-I191 | Native PTR transports addresses without erasing upstream semantic pointee identity or adding alias/nullability guarantees. |
| ASTRA-I192 | Native Struct* and C void* remain distinct semantic/ABI contracts even when LLVM realizes both as ptr. |
| ASTRA-I193 | Physical struct layout is backend-private and target-dependent; no language size, alignment, padding, or offset is promised. |
| ASTRA-I194 | Non-addressable structs remain fully scalarizable even alongside addressable structs; pointer local values remain promotable. |
| ASTRA-I195 | Future escaping pointers, address-of fields, native aggregate ownership, and C structs must explicitly revisit promotion, aliasing, and lifetime rules. |
| ASTRA-I196 | A borrow is non-owning pointer provenance plus a proven lifetime bound; it owns nothing. |
| ASTRA-I197 | Exact LexicalRegion object identity is semantic lifetime authority; deterministic source-preorder ordinals are debugging only. |
| ASTRA-I198 | Every checked block owns one region; checked block containment owns the tree, with expiring GLib.WeakRef parent links and no ownership cycles. |
| ASTRA-I199 | A local becomes visible only after initialization and ends at its lexical scope boundary; same-scope late borrows need no declaration-order lifetime restriction. |
| ASTRA-I200 | Every value stored into a typed-pointer local must have exact pointer type and provenance that outlives that local's lexical region. |
| ASTRA-I201 | Outlives is same object or lexical ancestry; same-scope and enclosing to nested stores pass, and nested to enclosing stores fail before Core. |
| ASTRA-I202 | Pointer-local reads conservatively guarantee only their own lexical region; downstream copies need not retain original pointee-origin objects. |
| ASTRA-I203 | Native typed-pointer parameters are borrow-valid for the complete current invocation, including transitive calls and bounded recursion. |
| ASTRA-I204 | Literal null has no pointee-lifetime requirement; a read of a null-initialized pointer local still uses its local region summary. |
| ASTRA-I205 | AddressOf provenance is the exact visible pointee local's region; general address expressions do not broaden the supported addressable storage kinds. |
| ASTRA-I206 | Borrow checking ends before Core; Core/CFG/SSA/LLVM contain no lifetime graph, runtime region metadata, hidden validity bits, or borrow checks. |
| ASTRA-I207 | Lifetime safety and alias exclusivity are separate; multiple mutable typed pointers may alias in BORROW-1. |
| ASTRA-I208 | Address-taken aggregate fields remain memory-backed while pointer locals themselves remain ordinary promotable scalar SSA values. |
| ASTRA-I209 | Branch/null merges and loop pointer backedges use ordinary pointer SSA after each semantic store proves its destination lifetime requirement. |
| ASTRA-I210 | Future escaping references, typed-pointer returns/fields, native aggregate ownership, heap values, and foreign channels must explicitly extend the lifetime contract rather than bypass it. |
| ASTRA-I211 | Ownership responsibility is distinct from raw pointer value/address identity; owned locals retain canonical void* representation. |
| ASTRA-I212 | An owned foreign result cannot silently enter raw storage, discard, argument, or return contexts; fresh acquisition/rearm requires a direct annotated foreign producer. |
| ASTRA-I213 | Every accepted OWN-1 acquisition creates exactly one lexical obligation, including a returned null. Local visibility follows initializer completion. |
| ASTRA-I214 | Lexical cleanup visits each owner once on every normal exit from its lifetime, in reverse lexical owner-slot order and inner-to-outer scope order; moved/released pointers no-op. |
| ASTRA-I215 | Return expressions evaluate completely before cleanup; the computed value returns afterward. |
| ASTRA-I216 | Break and continue clean exactly the scopes they exit; loop-body fallthrough cleans before its backedge and branch-local cleanup occurs only on entered paths. |
| ASTRA-I217 | Null ownership cleanup performs no foreign call. Astra traps and non-returning foreign calls do not unwind owned resources in OWN-1. |
| ASTRA-I218 | Cleanup obligations, acquisition, transfer, release and rearm events are explicit compiler semantics; they are never inferred from LLVM calls or represented by a target runtime destructor stack. |
| ASTRA-I219 | Cleanup functions are physical C ABI contracts, not Astra source callables; CABI owns their exact symbol, signature, and identity. |
| ASTRA-I220 | Cleanup contracts intern before downstream mapping; each stage uses exact mapped identity, and cleanup symbols cannot collide with ordinary C imports/exports. |
| ASTRA-I221 | Owner scalar Places may promote while ordered, effectful, resultless SSA Cleanup instructions retain responsibility semantics. No ownership-state phi is needed in OWN-1. |
| ASTRA-I222 | Ownership and borrowing are orthogonal. Checked lexical regions normalize to existing CoreBlock scopes without introducing another lifetime tree. |
| ASTRA-I223 | Cleanup null guards update the same physical LLVM continuation authority used by traps; phi predecessors must name actual post-cleanup blocks. |
| ASTRA-I224 | Transfer and explicit Release semantics must change responsibility explicitly rather than suppressing cleanup heuristically. OWN-1 adds no owned parameters/results, heap, refcounting, or native destructors. |
| ASTRA-I225 | A move requires a definitely OWNED exact void* local and transfers its exact cleanup identity to a fresh owner. |
| ASTRA-I226 | MOVED, RELEASED and mixed-state owners cannot be read by source, including null comparison and another move; definitely disarmed slots may rearm. |
| ASTRA-I227 | Semantic responsibility and pointer nullness are independent; an actual-null owned value can transfer or release. |
| ASTRA-I228 | Reachable CFG predecessors determine ownership joins; loop inputs require a finite deterministic fixpoint. |
| ASTRA-I229 | Compiler cleanup consumes any active ownership state and ends its lifetime; duplicate cleanup and declaration reinitialization reject internally. |
| ASTRA-I230 | Transfer keeps lexical cleanup sites and clears the physical source pointer at the transfer point. |
| ASTRA-I231 | Ownership flow validation finishes before SSA; transfer normalizes to destination=old-source and source=typed-null; release normalizes to cleanup(current) and current=typed-null; rearm defines current=producer-result. |
| ASTRA-I232 | Conditional source values need only ordinary pointer phis; no runtime armed flag or cleanup-contract phi exists. |
| ASTRA-I233 | Move assignment, contract-changing rebinds and owned function boundaries must explicitly extend stable-slot responsibility semantics; borrow analysis remains separate. |



LOOPCTRL-1 additionally proves [exact loop targets](../decisions/0018-loop-control-targets.md),
multiple predecessor merges, post-transfer source preservation, and independent
checked/Core target reclamation. NABI and generic SSA/LLVM production code remain
unchanged.

LOOP-1 additionally exercises [cyclic control flow](../ir/cyclic-control-flow.md),
source/standalone lifetime probes, nested SSA, and physical backedge predecessors.
The generic promotion/frontier algorithms and NABI/LLVM/EXEC production code
remain unchanged; CFG and SSA target ownership use expiring WeakRef references.

For ASTRA-LOOP-1, review raw handles under the backend, LLVM-free source/syntax/
semantic/Core/CFG/SSA/NABI/CABI interfaces and test linkage, verified physical body
lowering, host-only target configuration, private launch entry, and transactional
driver linking without a target runtime. Semantic types must have no
layout/ABI/LLVM conversion APIs. Integer constants retain AstraIntValue numeric
authority and exact provenance; only semantic literal formation parses digits.
Name references bind to exact parameter or local symbols. Signature collection precedes body checking; locals become visible only
after their initializer is checked. See
[ADR 0006](../decisions/0006-semantic-model.md). Core construction consumes checked
authority through temporary identity maps, retains ordered structured
computation without optimization, and introduces no CFG/SSA or ownership
operations. See [ADR 0007](../decisions/0007-core-ir.md).
CFG translates this structured computation without optimization, preserving
disconnected post-return blocks and distinct explicit return/function-end
terminators. Reachability follows terminator successors from the explicit entry;
only reachable non-void function ends receive completion diagnostics. Branch and
ConditionalBranch are the new successor-bearing terminators. Every CoreIf has an
explicit join, even if both arms return. CFG adds no constant folding or SSA.
See [ADR 0008](../decisions/0008-explicit-cfg.md) and
[ADR 0010](../decisions/0010-conditional-control-flow.md).
Local storage uses distinct Core/CFG Places, explicit loads, and separate
Initialize/Store operations. CFG instructions precede the separate mandatory
terminator and do not define successors. No physical storage or ownership is
introduced. See [ADR 0009](../decisions/0009-place-storage.md).

SSA consumes flow-valid reachable CFG through temporary identity maps. Placement
uses iterated dominance frontiers within a local initialization's dominated
region, preserving branch-local availability without liveness. Renaming uses
definition stacks over the dominator tree. Current expressions flatten without
eliminating operations. CALL-1 freezes left-to-right operand and argument
evaluation, preserving ordered calls.
Initialize versus Store disappears only for promoted, resource-free int/bool/void*
values. See [ADR 0011](../decisions/0011-ssa-block-arguments.md).

Frontend tests retain the syntax, span, and diagnostic checks. Semantic tests
check canonical types, symbol identity, separate checked structure, deterministic
diagnostics/dumps, signed literal formation, and oversized literal rejection
with exact syntax spelling retained. Core tests check typed
construction, exact Core bindings, provenance/lifetime independence, deterministic
dumps, and malformed-IR rejection through internal errors. CFG tests add
terminators, reachability, completion diagnostics, stage distinctions, independent
identity/lifetime, and malformed graphs. Local tests cover initialization order,
exact identity mapping, foreign Places, and post-return mutation. Branch tests
cover bool typing, lexical scope identities, shared storage through joins,
full/partial return paths, nested edges against ordinal ordering, and lifetime
independence of conditionals and sibling Places. Standalone
Core, CFG, and SSA targets exclude their upstream models. SSA tests add
dominance/frontier queries, scalar joins and flattened computation, malformed
edge arguments/definitions, unreachable projection, and independent SSA lifetime.
Linkage/backend-symbol checks cover frontend/mid-level, standalone, scalar
reference/pipeline executables when host tools are available. Separate positive
checks require qualified LLVM 22 linkage for the driver and backend tests.
The separate CHARTER-1 tests still verify LLVM construction/linkage and
valid/invalid module behavior. All implementation is independently authored.
These checks establish only the [implemented semantics](../language/semantics.md)
and [structured Core](../ir/core-ir.md) with [explicit control flow](../ir/cfg.md)
and [scalar SSA](../ir/ssa.md),
including the executable scalar reference semantics. EXEC-1 additionally
qualifies native machine behavior without freezing bool memory layout or a
stable target machine ABI.

[ADR 0012](../decisions/0012-direct-call-semantics.md) freezes direct-call
identity, evaluation order, and GLib WeakRef ownership. Standalone malformed
call tests, forward/self/mutual lifetime tests, and order/join goldens enforce
these contracts independently of physical lowering.

[ADR 0013](../decisions/0013-scalar-semantics.md) freezes the signed 32-bit scalar
contract and numeric authority boundary. Reference tests exercise every current
arithmetic operation, boundary wrapping, zero-divisor outcomes, and INT_MIN/-1;
optimized UB-trapping builds check that signed host overflow is not the oracle.
CONST-1 adds bounded semantic scalar evaluation; general compile-time execution
remains excluded. Standalone malformed tests retain valid
AstraIntValue payloads while exercising constructible type/identity errors.
Trap/call fixtures preserve evaluation order and stage independence.

[ADR 0014](../decisions/0014-native-scalar-abi.md) freezes the
[native scalar v0 physical contract](../abi/native-scalar-v0.md). NABI tests
cover declaration/call mappings, same-spelled distinct identities, forward and
recursive calls, malformed signatures and compatibility errors, and body-independent
dumps. Weak references prove destruction of syntax, checked models, Core, CFG,
SSA, and all semantic types before verifying/dumping the sidecar. Standalone
NABI compiles without any upstream representation or semantic authority, using
only shared source provenance/diagnostics. Its verifier and dumper enforce
physical structure independently of construction-time SSA-call validation.

[ADR 0015](../decisions/0015-llvm-scalar-lowering.md) adds verified LLVM scalar
lowering. Structural backend tests inspect signed predicates, absent wrapping
flags, call identity/conventions, exact phi incoming values, and trap-safe raw
operation paths. Synthetic parallel edges and post-division predecessors guard
the representational boundary. Weak references prove full upstream destruction
before LLVM verification/printing. Body lowering adds no optimization pipeline.

[ADR 0016](../decisions/0016-host-native-execution.md) adds host-native object
emission and executable publication. Structural tests prove external/default-CC
wrapper versus internal/fastcc source main and recursive-call identity.
Runtime tests qualify scalars against AstraIntValue, traps as non-returning,
bool channels, branches/SSA joins, calls, and recursion. Lifetime tests destroy
upstream graphs before emission, LLVM resources before linking, and object
temporaries before execution. Driver tests enforce entry-stage separation,
argv-safe paths, link error authority, output preservation, and cleanup.

TPTR-1 standalone Core/CFG/SSA tests add exact typed pointers, addressable
aggregate authorities, direct/indirect field Places, AddressOf, and ordered
memory operations. Malformed-IR cases check identities, initialization and
pointer-use dominance, and promotion barriers. LLVM and native execution tests
qualify null traps, RHS-first writes, actual split phi predecessors, aliases,
mixed storage, recursive borrows, and artifact independence. SSA memory remains
LLVM-free. See qualification.

BORROW-1 adds region tree/provenance/expiry tests, conservative copy and scope
escape diagnostics, stored pointer phis and memory promotion checks, and native
execution through branches, loops, transitive calls, and recursion. See
qualification.

OWN-1 adds standalone malformed-contract/owner/instruction checks, exact stage
lifetime checks, cleanup-stack exit/order checks, complete scalar pointer promotion,
CABI interning/collision checks, LLVM guard/predecessor checks, and observable
static-resource runtime qualification. See OWN-1 evidence.

## MOVE-1 ownership invariants

- Responsibility has explicit OWNED/MOVED/MAYBE_OWNED flow state. Transfer never
  duplicates it and requires a definitely OWNED exact source.
- MOVED and MAYBE_OWNED owners cannot be source operands, even in null comparisons.
- Pointer nullness is independent of responsibility. A producer can successfully
  produce an owned null value, and that value can still transfer ownership.
- Transfer inherits exact cleanup identity, defines the destination with the old
  pointer and clears the physical source. No cleanup-contract phi is needed.
- Lexical cleanup remains present for moved owners and accepts all reachable responsibility sets. Source nulling makes its old cleanup a physical no-op. Dynamic duplicate
  cleanup and duplicate declaration acquisition are internal errors.
- Joins use only reachable CFG predecessors. Terminating arms do not contribute
  to continuations; loops require a deterministic finite fixpoint.
- Ownership validation completes before SSA/LLVM. Ordinary pointer phis carry
  conditional values; no runtime ownership-state flag or stack exists.
- Borrowed Struct* lifetimes and ownership transfer are distinct systems. Neither
  changes the other's state lattice, addressability or scope authority.
- Traps remain non-unwinding. Future move assignment, contract changes and owned function boundaries must
  explicitly define their responsibility transitions.

Standalone ownership-flow and Core/CFG/SSA tests enforce these boundaries. Stage
lifetime tests reclaim transfer objects, CFG snapshots and exact contracts before
later IR/backend use. See MOVE-1 evidence.

## OBORROW-1 parameter invariants

- Borrowing responsibility is not transferring responsibility. Borrow requires
  definitely OWNED and leaves state unchanged, including for a null-valued owner.
- An owner exposes its pointer temporarily only at a canonical borrowed/noescape
  parameter boundary. Ordinary unmanaged void* parameters cannot receive owners.
- A borrowed parameter owns nothing. Noescape forbids persistent aliases and
  transfer; non-owning use also forbids destruction. It does not imply readonly.
- Native noescape contracts are compiler-enforced. Foreign contracts are trusted
  binding declarations: the borrowed address cannot escape the dynamic call.
- Direct borrowed forwarding is permitted; borrowed locals, results, fields,
  C exports and general void* lifetime inference remain unsupported.
- Borrow contracts are semantic/behavioral, separate from type equality and
  physical channel identity. Native/C PTR and scalar-ptr-v1 stay unchanged.
- Explicit owner views survive through CFG validation, then normalize to the
  current SSA pointer. LLVM carries no token, runtime flag, retain/release,
  extra storage, source clearing or required optimizer borrow attributes.
- Borrowing never modifies cleanup identity, ordinal, scope or suppression.
- Struct* lexical borrowing and owned-void* parameter borrowing stay separate.
- Future owned parameters/results must distinguish Borrow, Transfer and Release.
  Reassignment and longer-lived references must define their own interactions.

Standalone verifiers, ownership flow, lifetime tests, ABI differentials and
runtime cleanup traces qualify these rules; see OBORROW-1 evidence.

## RELEASE-1 invariants

- Release explicitly discharges responsibility without transferring it or creating
  another owner. It requires an exact definitely OWNED void* local.
- MOVED and RELEASED are distinct concrete outcomes. An OWNED null resource is not
  RELEASED. Pointer nullness never defines semantic responsibility.
- RELEASED owners are unusable by source, including comparison, borrow, move and
  another release, until successful rearming. Definitely disarmed slots permit
  same-contract direct-producer rearming under REARM-1.
- Release clears the physical owner pointer to null. Existing lexical cleanup
  stays present and safely no-ops after release.
- Ownership joins are sets of reachable concrete responsibility states, with
  union as join. Reachable CFG predecessors determine joins, not syntax alone.
- Ownership loops converge over a finite lattice. A released backedge invalidates
  possible repeated source consumption; fresh body owners retain dynamic lifetimes.
- Compiler cleanup is valid in every active ownership flow state, including
  states that reject source use.
- Release may shorten lifetime and intentionally change physical destruction
  order; its cleanup effect stays at the statement position.
- Borrow and release remain separate: OWNED → OWNED versus OWNED → RELEASED.
  Move transfers responsibility; release ends it without a recipient.
- No runtime ownership-state tag is required. SSA uses existing cleanup plus a
  null reaching definition, and physical joins use ordinary pointer phis.
- Cleanup CABI identity, pointer channels, native ABI and VAPI metadata remain
  unchanged. LLVM cleanup guards retain exact physical continuation authority.
- Rearming occurs only from statically proven disarmed states and preserves
  the exact cleanup contract and lexical rank under ADR 0032. Owned function boundaries must
  define responsibility transfer and cannot reinterpret this milestone's meaning.

[ADR 0031](../decisions/0031-explicit-release.md) freezes these rules;
RELEASE-1 evidence qualifies them.

## Legacy producer-specific owned void* REARM-1 invariants

BUFFER-1 supersedes the disarm-first restriction below for concrete Resource
and buffer locals/parameters; their assignment is RAII replacement as specified
above. This historical contract remains applicable to producer-specific owned void*.

- An owned binding is one stable lexical cleanup slot, which may be armed,
  disarmed and rearmed over its lifetime with at most one active responsibility.
- Rearming requires definitely_disarmed: OWNED is absent from every reachable
  possibility. MOVED, RELEASED and their union qualify; any OWNED possibility fails.
- Rearm never implicitly releases. Its direct foreign owned-result producer
  acquires exactly one new responsibility after successful return, including null.
- Every slot has one exact stable cleanup contract. Rearm cannot change it;
  distinct producers may share that exact normalized contract.
- Every slot has one stable lexical cleanup rank. Rearm creates no new obligation,
  owner ordinal or cleanup entry and never changes rank. Automatic destruction is
  reverse lexical owner-slot order, with explicit release at its source position.
- Semantic responsibility, never pointer nullness, authorizes rearming. SSA replaces
  the current null pointer definition with the producer result; a construction
  verifier checks nullness through ordinary pointer phis, including loop cycles.
- The owned producer result has one immediate acquire/rearm consumer and cannot be
  discarded, copied or exposed between call and transfer.
- Ownership fixpoints track responsibility only, without dynamic destruction order.
  Safe discharge cycles converge; OWNED backedges reject before SSA.
- No runtime armed/disarmed flag, generation, cleanup priority, contract pointer,
  new ABI channel, alloca or LLVM primitive exists.
- Future move assignment, owned function boundaries and cleanup-contract-polymorphic
  ownership must explicitly extend these rules. Physical PTR identity cannot infer
  a responsibility transfer, replacement policy or cleanup contract.

[ADR 0032](../decisions/0032-owner-rearming.md) and
REARM-1 evidence define and qualify these refinements.

## INTS-1 invariants

- Integer width and signedness are immutable semantic language authority,
  independent of host C, target registers, ABI channels, and LLVM types.
- Six canonical IntegerType identities exist per type universe. `int` and `i32`
  are the same object, displayed canonically as int; bool is separate.
- Decimal literals remain contextual values until final integer typing. Without
  stronger context they default to int. Contextualization is not conversion.
- Typed operands retain identity. Arithmetic and comparisons require exactly
  matching integer types; there is no implicit width/sign change.
- Addition, subtraction, multiplication, and signed negation wrap modulo 2^N.
- Signed division truncates toward zero and remainder follows the dividend.
  MIN/-1 is explicitly defined as MIN and remainder zero, independent of LLVM UB.
- Unsigned quotient, remainder, and ordering use unsigned mathematical values.
  Unsigned unary minus rejects. Every zero divisor explicitly traps.
- Equal bit patterns do not imply equal typed integer values.
- Core/CFG/SSA retain exact type and bits after upstream destruction, without
  reparsing decimal source spelling or using a width-specific value class.
- SSA block parameters and promoted Places retain width/sign before physical
  lowering; addressable fields retain exact scalar width without a layout promise.
- NABI preserves signed channel distinctions even where LLVM widths coincide.
  Signature-only v2 selection preserves existing v0/v1 profiles and dumps.
- LLVM integer width realizes language semantics and does not define them.
  Wrapping operations never carry nsw/nuw. Signed raw division cannot execute
  with a zero divisor or MIN/-1; unsigned division has only the zero guard.
- Arithmetic splits preserve the existing actual-final-LLVM-block authority
  used by branch, loop-backedge, and short-circuit phi predecessors.
- New narrow/unsigned C ABI channels are explicitly deferred; no C extension,
  layout, typedef, or transport claim follows from an LLVM integer type.
- Integer breadth does not alter ownership, borrowed/owned native contracts,
  Resource identity, Places, addressability, or scalarization architecture.
- Future short vectors can use these exact scalar IntegerTypes as elements
  instead of introducing a parallel numeric authority.

[ADR 0035](../decisions/0035-exact-width-integers.md) records the design and
INTS-1 qualification records the evidence.

## Exact binary32 authority

- F32Type is an Astra semantic identity, distinct from integer/bool/pointer
  identities. LLVM float is only its backend realization.
- Every f32 arithmetic operation rounds to binary32 nearest/ties-even.
  No excess precision, reassociation permission, fast math, or implicit FMA exists.
- Signed zero and subnormals are preserved; infinity and NaN are valid values.
  Float division by zero has IEEE results and never inherits integer zero traps.
- NaN comparisons are explicit: inequality is true; equality and all relational
  predicates are false if either operand is NaN. Payload/sign/signaling
  construction are not stable language-visible data.
- Decimal source literals convert directly and exactly to correctly rounded
  binary32. Locale, host float/double parsing, and LLVM decimal parsing supply no
  semantic authority. Syntax provenance is never reparsed downstream.
- Checked/Core/CFG/SSA constants retain immutable uint32 bits and canonical type
  after upstream destruction. The LLVM boundary constructs constants by bitcast.
- No implicit numeric conversion, float truthiness or remainder exists. F64-1
  adds only explicit f32↔f64 floating casts.
- Existing Places, field storage, SSA, ownership, and physical predecessor
  authorities remain shared. Float memory adds no struct layout promise.
- Native F32 is independent physical-channel authority. Signature-only v3
  selection takes precedence while old profile dumps stay unchanged.
- Native f32 support alone does not qualify C float. CABI-FP-1 independently
  qualifies C float under scalar-fp-v2 without changing the native contract.
- Native f32 execution must preserve binary32 precision and subnormals, or reject
  the target configuration. Astra never enables FTZ/DAZ. Foreign code must restore
  the required default environment; rounding changes and flags are not Astra state.
- Future short-vector f32 lanes must reuse this exact scalar authority.

[ADR 0036](../decisions/0036-binary32-semantics.md) and
F32-1 qualification record rationale and evidence.

## Owned native object result invariants (OBJ-RET-1)

- An owned object result does not imply heap allocation; caller storage preserves freestanding use.
- Fresh results construct directly in caller-provided ObjectStorage, never a callee-local returned-object slot.
- Result construction neither copies nor relocates object bytes; object identity is the supplied candidate identity.
- The returned owner PTR identifies exact result storage and may be null, the candidate, or forwarded ancestor storage.
- Caller cleanup follows the returned capability and never the candidate unconditionally.
- Unused candidate bytes have no semantic object lifetime and no cleanup or runtime active flag.
- Moving an owned parameter through a result preserves identity and disarms its source before remaining cleanup.
- Callee-local ObjectStorage cannot escape by direct move or through a potentially forwarding result call.
- Fixed and borrowed references, including receivers, cannot manufacture owned results.
- Nullable OWNED and MOVED remain different states in the existing ownership possibility authority.
- Object and Resource result transfers share OWNBOUND concepts and cleanup authority; object provenance remains explicit.
- Constructor receivers operate on exact target storage; constructors themselves still return void.
- Returned object lifecycle belongs to the receiving owner, with no callee result cleanup.
- Result arguments, transfer commit, construction, remaining cleanup and physical return retain their specified order.
- Traps do not unwind and expose no successfully returned owner.
- Result storage is a compiler-private physical input, ordered before receiver and explicit parameters.
- Owned ClassType results use existing PTR channels and existing NABI profiles, including vector-v4 and slice-v5.
- No object header, storage-kind tag, allocator tag, destructor pointer, result descriptor or speculative pointer attribute is introduced.
- Heap allocation should be introduced only for lifetimes caller/ancestor storage cannot represent, and must preserve this owned-result contract.

## Exact floating scalar invariants (F64-1)

- f32 means exactly IEEE binary32; f64 means exactly IEEE binary64. Floating width
  is semantic and never target-selected.
- Decimal literals convert directly to their contextual format. Decimal-to-f64
  never passes through f32. Without stronger context, decimal literals remain f32.
- Conversion is compiler-owned, exact and locale-independent. Host strtod/scanf,
  host casts and LLVM floating parsing are not semantic authorities.
- F32/F64 share one closed BinaryFloatFormat/BinaryFloatValue foundation. Existing
  F32 semantics and unchanged golden dumps must survive every internal extension.
- Every ordinary operation rounds independently at its format under nearest/even.
  No reassociation, fast-math assumption or implicit fused arithmetic is permitted.
- Signed zero, subnormals, infinities and NaN comparison semantics are required.
  NaN payload/sign/signaling construction remain unspecified source data.
- f32 and f64 do not implicitly convert. Explicit f32→f64 widens exactly;
  f64→f32 narrows nearest/ties-even with IEEE overflow/underflow and signed zeros.
- NUM-CONV-1 defines explicit concrete scalar integer↔float conversion; its
  truncation/trap and nearest/ties-even rules are stated above.
- F64 remains one scalar semantic/SSA value, with explicit conversion kinds and
  complete exact type/bits/provenance after upstream stage destruction.
- Ordinary f32 scalar storage predicates admit f64 for fields, typed pointers,
  arrays and slices. Loads/stores introduce no arithmetic rounding point.
- Native by-value f64 uses F64 in fp64-v6. F64 pointees/elements do not turn PTR
  or SLICE(PTR,I32) into F64 channels. Frozen v0–v5 profiles remain unchanged.
- Scalar f64 does not add f64 vectors, DSP or dot/MAC. CABI-FP-1 separately
  qualifies C floating channels; explicit FMA and other target qualification
  remain separate campaigns.
- The qualified execution environment retains nearest/even, masked exceptions and
  IEEE subnormals. Foreign changes must be restored and cannot redefine semantics.

[ADR 0054](../decisions/0054-exact-binary64.md), [floating IR](../ir/floating-values.md)
and F64 qualification record authority and evidence.

## Explicit generic capability invariants (GEN-CAP-1)

- Generic capability authority is semantic and explicit. A parameter knows only
  its declared capabilities plus the unchanged GEN1_PLAIN_COPY baseline.
- Eventual instances cannot grant operations or missing forwarding evidence.
  Parametric checking never enumerates the current or future concrete universe.
- Requirements attach to exact parameter identities and compiler-owned symbols
  in a distinct capability namespace. Source ordering is deterministic.
- No implication exists: Ordered does not grant Eq; Numeric grants neither Eq
  nor Ordered. Parametric calls use exact explicit requirement subsets.
- One compiler-owned concrete capability matrix governs satisfaction everywhere.
  Every call validates all requirements, including phantom parameters, before
  an instance placeholder is created.
- Eq authorizes only ==/!= with scalar bool result; Ordered only scalar ordering;
  Numeric only same-type binary +,-,*,/; Bitwise only &,|,^,~; Shift requires an
  exact constrained value and ordinary concrete scalar integer count.
- Cross-T/U operands remain invalid. Generic literals never contextualize to T.
  Capabilities do not grant members, casts, null, addressing, indexing or ownership.
- Explicit capability operations survive only in checked and parameterized Core.
  Core retains immutable stage-neutral identities without checked symbol backlinks.
- Monomorphization resolves them to ordinary concrete Core operations, without
  analyzer re-entry, source rechecking or instance-based operation discovery.
- CFG/SSA/NABI/LLVM never see capability operations, types or runtime evidence.
- Concrete operators preserve wrapping, division/traps, IEEE behavior, strict
  rounding/non-contraction, signedness and BIT count guards. Numeric availability
  and shape do not impose one uniform arithmetic law across int/f32/f64.
- Satisfaction creates no witness, dictionary, descriptor, boxing or runtime helper.
  Instance keys remain exact definition identity plus ordered concrete arguments.
- No NABI profile is added and no CABI/VAPI capability boundary is introduced.
- Vectors remain plain-copy generic arguments with no named capabilities because
  their equality results/operator sets are nonuniform. Associated outputs remain
  future work; no vector capability names are frozen.
- Generic ownership, Copy/Move, generic classes/members, user-defined/interface
  capabilities and witness semantics remain separate future campaigns, which must
  extend exact requirement identities and explicit checking.

[ADR 0057](../decisions/0057-explicit-generic-capabilities.md),
[language](../language/generic-capabilities.md) and
[IR](../ir/generic-capabilities.md) define the bounded contract.

## Recursive native struct storage (STRUCT-AGG-1)

- A native struct may contain concrete native struct storage and supported vectors.
  Classes retain their prior field policy; lifecycle semantics are not broadened.
- A struct-valued field is a storage subobject Place, never automatically a Value.
- FieldPlace composes recursively over another Place. Exact base and field identities,
  never textual paths or physical offsets, establish nested storage identity.
- Intermediate struct fields are not loaded to access child fields.
- Nested initializers target storage directly in written order, require recursive
  completeness and never synthesize aggregate temporaries, copies or memcpy.
- STRUCT-COPY-1 adds whole-struct assignment/copy as Place-to-Place operations;
  native/C aggregate ABI remains a separate feature.
- A vector leaf contains one whole VectorValue; lane reads extract Values and
  vector field support does not introduce LanePlace.
- Nested structs and vectors do not force memory. Existing SSA promotion handles
  eligible leaves independently, without whole Inner/Outer SSA values.
- Addressability remains rooted in the existing local-wide storage policy. Only
  an affected local pays for memory; recursive address lowering uses the same Places.
- By-value StructType graphs are acyclic. Semantic/Core identity checks reject
  recursive layouts before LLVM, and standalone downstream verifiers defend that rule.
- LLVM/DataLayout owns physical offsets and alignment, which are not semantic identity.
- No generic aggregate representation, runtime metadata, heap allocation, ownership
  semantics, pointer category, dependency or NABI profile is introduced here.
- GEN-STRUCT-1 uses ADR 0059 and reuses ordinary aggregate machinery after Core materialization.

## Generic native structs (GEN-STRUCT-1)

- A generic struct is a semantic type constructor, never a concrete struct or
  physical layout. Its definition owns exact compiler-generated identity.
- Struct parameters reuse `TypeParameterSymbol`, `TypeParameterType` and
  `CoreTypeParameter`. GEN1_PLAIN_COPY remains the argument authority; no struct
  where clause or second parameter system exists.
- Instance identity is the exact definition plus ordered canonical semantic
  argument identities. `int`/`i32` canonicalize before lookup; signed/unsigned,
  different definitions and phantom arguments remain significant even when
  physical layouts match. Size, alignment, spelling, NABI and LLVM never enter keys.
- Generic fields have exact origin identities. Each instance creates fresh
  ordinary concrete field identities with immutable origin association. Projection
  specialization maps those identities directly and never resolves names again.
- One Core generic instantiation context owns separate function and struct
  registries and uses the existing exact type-substitution authority. Applications
  extend that authority; parameterized pointers, slices and arrays do not.
- Concrete instances are demand-driven, including transitive nested dependencies,
  and globally deduplicated. Unused definitions are checked but emit no instance.
- First request under deterministic root, FIFO function and field traversal sets
  struct instance order. Hash tables perform lookup only. Requesters retain exact
  callable or instance identity; labels are diagnostic text only.
- Struct placeholders register before resolving fields. Re-entry while
  MATERIALIZING through a by-value field rejects an infinite layout; failed
  instances never become COMPLETE. Function placeholder recursion remains valid.
- Parameterized applications and generic field projections exist only above Core
  concretization. Materialization runs without the checked graph and produces
  ordinary CoreStructs before CFG; immutable origin tokens need no definition body.
- Concrete generic instances reuse recursive FieldPlace and direct-storage
  initializer trees. STRUCT-COPY-1 adds whole storage copy without an aggregate
  temporary, whole-aggregate SSA Value or frontend memcpy/memmove.
- Generic origin never forces memory. Ordinary recursive leaf promotion and
  selective root addressability govern scalar, vector and nested fields alike.
  A vector field remains one whole-vector leaf, with no LanePlace.
- Fully concrete generic Struct* uses existing typed-pointer identity and PTR
  semantics, null traps, aliasing and recursive memory projection. Parameterized
  generic Struct* remains deferred; pointer return-lifetime policy is unchanged.
- GEN-COPY-1 admits concrete generic instances as GEN1_PLAIN_COPY arguments
  exactly when the shared structural copy/value-storage proof succeeds. Generic
  origin and physical layout alone provide no proof. Public Copy/Move and generic
  ownership remain separate language decisions.
- CFG, SSA, NABI and LLVM contain no unresolved generic aggregate representation
  and require no generic-definition graph. Concrete physical layout follows the
  existing backend policy; layout measurements are evidence, never type authority.
- No runtime descriptor, hidden type arguments, dictionary, witness, box, heap
  allocation, production dependency or NABI type/profile is introduced. Whole
  aggregate native/C ABI and class embedded aggregate fields remain unsupported.
- Future generic ownership, classes, methods and interfaces must extend these
  exact definition, parameter, application and field identities.

[ADR 0059](../decisions/0059-generic-native-structs.md),
[language](../language/generic-structs.md) and
[IR](../ir/generic-structs.md) define this boundary.

## Generic ownership (GEN-OWN-1)

- Generic ownership is semantic and statically specialized. Ownable is a
  compile-time capability for explicit owned-binding semantics, distinct from
  future aggregate Copy/Move.
- Ownable promises neither ordinary copyability nor value/operator capabilities.
  No value capability implies Ownable, and combinations on the same T are deferred.
- Existing parameters remain PLAIN_COPY unless explicitly Ownable. OWNABLE T
  never implicitly carries GEN1_PLAIN_COPY; plain T value transport is unavailable.
- `owned T` requires exact Ownable authority. Generic owner state is validated
  before concrete specialization; instantiation cannot legalize a double move.
- Generic ownership contracts survive only through parameterized Core. Independent
  Core verification requires no Checked graph, proof object or source rechecking.
- One monomorphizer converts owned T to the existing concrete ownership domain.
  Resource and Class ownership remain separate and need not share a physical ABI.
- Generic definitions have no NABI. CFG/SSA/NABI/LLVM never see generic ownership.
- No runtime witness, dictionary, type descriptor, cleanup helper, destructor
  function pointer, owner header, type switch, box or heap allocation is introduced.
- Transfers preserve exact Resource and ObjectStorage identity. Returning an
  incoming generic owner transfers its original responsibility and storage.
- ClassType results retain caller-provided candidate storage. Generic source
  semantics do not expose that mechanism, and Resource results never acquire it.
- Generic owned local construction, fields and properties do not exist in this
  milestone. Callee-local owned object storage still cannot escape.
- Left-to-right semantic capture, OWNBOUND physical commit, exact cleanup order,
  nullable ownership and non-unwinding traps remain unchanged.
- Public Copy/Move, generic owned fields, borrowed T,
  parameterized Struct*, generic methods/classes and interfaces must extend these
  exact identities and contracts in separate campaigns.

See [ADR 0060](../decisions/0060-generic-ownership.md) and
[generic ownership](../ir/generic-ownership.md).

## Whole struct copy (STRUCT-COPY-1)

- Whole native struct copy is a Place-to-Place semantic operation, never a
  general aggregate expression Value. Both Places require exact nominal type
  identity; equal layout never suffices.
- One stage-neutral semantic Copyability authority recurses through exact field
  types. StructType is copyable iff every field is copyable. Semantic meaning is
  independent of size, alignment, LLVM type, memcpy eligibility or generic origin.
- Concrete generic StructTypes follow the ordinary rule. Parameterized aggregate
  copying remains deferred, including in checked-once generic definitions.
- Copy initializes a fresh local exactly once or replaces already initialized
  storage. It preserves source usability and performs no ownership transfer.
- Destination validation precedes source validation; every source leaf snapshots
  before any destination mutation. Null source traps cause no partial update.
  Self-copy and aliasing require no noalias assumption or runtime temporary.
- Nested fields recurse through declaration-order field identity. Vectors are
  atomic whole-vector leaves, with no LanePlace. Floating bits and void* pointer
  identities copy without conversion or arithmetic.
- Copy does not force addressability. Scalarized copies remain leaf-oriented;
  memory copies reuse ordinary recursive Place addressing and leaf loads/stores.
- Core independently verifies its own field graph after Checked destruction.
  Core→CFG eliminates whole copy before SSA; no aggregate SSA Value or phi exists.
- No frontend memcpy/memmove, copy helper, heap, descriptor or reflection exists.
  Optimizer instruction selection is evidence, never language authority.
- Local copy semantics are independent of future native/C aggregate ABI and
  aggregate generic transport. Struct* remains PTR; NABI profiles are unchanged.
- GEN-COPY-1 connects ordinary Copyability to GEN1_PLAIN_COPY admission with
  complete nonempty value-storage graphs and exact scoped symbolic premises.
  Function/struct arguments share this authority; no public Copy token is required.
- Ownable remains ownership-specific and is not reinterpreted as Move. Source
  Copy/Move, aggregate Move and owning aggregate fields remain deferred. Current
  overwrite semantics apply only to recursively copyable lifecycle-free fields.

See [ADR 0061](../decisions/0061-whole-struct-copy.md),
[language](../language/struct-copy.md) and [IR](../ir/struct-copy.md).

## Native struct value boundaries (STRUCT-ABI-1)

- Copyable concrete structs are native function boundary values with exact nominal
  identity and COPY_VALUE semantics. Layout equivalence never grants compatibility.
- CopyabilityAuthority is the sole recursive eligibility authority, independent of
  size, padding, ownership guesses, LLVM or ABI channel availability.
- Native transport uses recursive semantic leaf channels in the identical order
  used by STRUCT-COPY. StructLeafOrder owns that walk; CoreStructLeaves binds exact
  Core field paths. Vector fields remain one whole leaf.
- Parameter storage is independent of caller storage, acquired completely before
  body execution, and read-only. Caller source storage remains usable.
- Struct arguments snapshot completely at their source-language argument position.
  Later argument effects cannot change an earlier argument's captured value.
- Struct results snapshot completely before cleanup and source lifetime ends.
  They have value identity and no alias to their source storage.
- Bounded Place/call producers and four exact consumers do not imply a universal
  Checked/Core StructValue or arbitrary aggregate expressions/properties.
- Astra CFG/SSA remain leaf-oriented. Multi-leaf call results have one bounded
  result identity over ordinary leaf definitions; there is no aggregate Value,
  block argument or phi. Forwarding needs no storage round trip.
- Concrete generic-origin structs follow ordinary rules after materialization.
  Parameterized Box<T> source signatures stay deferred. GEN-COPY-1 admits
  eligible record arguments to direct T and known Box<T> copy operations.
- Padding is not semantic struct value state and produces no ABI channel.
  Field bits obey their existing integer, bool, F32/F64, vector or PTR semantics.
- aggregate-v7 subsumes frozen v0–v6. Body-only struct use and Struct* do not
  independently select v7. Physical transport does not define semantic identity.
- Native copyable structs use no default hidden pointer, sret or byval. LLVM may
  use aggregate Values solely as physical return carriers at call boundaries.
  Backend carriers are not Astra semantic/Core/CFG/SSA StructValues or storage.
- Explicit addressability still permits memory-backed destinations. Scalarized
  boundaries require no alloca, memcpy/memmove, heap or runtime descriptor.
- CABI/VAPI, property value policy, receivers, Resource/Class ownership and object
  result-storage contracts remain separate. Generic Copy/Move, aggregate Move and
  owned aggregate fields are not implied by native aggregate transport.

See [ADR 0062](../decisions/0062-native-struct-values.md),
[language](../language/struct-values.md), [IR](../ir/struct-values.md), and
[aggregate-v7](../abi/native-aggregates-v7.md).


## Exact C floating-point invariants (CABI-FP-1)

- Astra f32 has one binary32 semantic identity; f64 has one binary64 semantic identity.
- C float/double are foreign realizations of those types, never new Astra semantic types.
- CABI and NABI are independent physical boundaries, even when LLVM types coincide.
- Native scalar-fp-v3 and fp64-v6 do not define the C calling convention.
- C scalar-fp-v2 does not define native f32/f64 or aggregate-v7 transport.
- C floating transport performs no semantic numeric conversion or integer ABI bitcast.
- Boundary-only calls preserve exact binary32/binary64 bits, including quiet NaN payloads; foreign arithmetic has no payload guarantee.
- C boundaries introduce no implicit f32↔f64 or integer↔floating promotion.
- VAPI float/double resolves to ordinary f32/f64 plus ForeignAbi.C, with retained source provenance and no downstream VAPI type.
- Any foreign floating signature selects scalar-fp-v2, including unused declarations; native/body-only floats do not.
- Earlier scalar CABI profiles reject F32/F64 and remain frozen; scalar-fp-v2 preserves their accepted integer/pointer/cleanup contracts.
- Foreign calls stay conservatively effectful; both widths obey ordinary left-to-right argument and trap order.
- C floating support implies neither float*/double*, slices over C memory nor C aggregate support.
- Target C float/double compatibility must be explicitly qualified and fail closed for unqualified targets.
- Process arguments and entry signatures are orthogonal to scalar C floating transport and remain unchanged.
- No runtime conversion helper, allocator or new production dependency is required.

See [ADR 0063](../decisions/0063-c-floating-point.md) and [C floating ABI](../abi/c-fp-v2.md).

## Persistent Resource fields: OWN-FIELD-1

- Persistent Resource responsibility may live in an explicit owned native class field.
- Ownership is an exact field contract, not a new Resource type identity.
- Every owned field is definitely initialized before its object becomes live.
- A constructed field remains an initialized ownership slot throughout the live object lifetime, including user deinit.
- Non-consuming field use borrows temporarily and never duplicates cleanup responsibility.
- A pending field borrow cannot overlap a potentially aliasing containing-object capability in the same call or a later argument call.
- Named Resource owners transfer into fields explicitly and become MOVED.
- Receiver validity precedes incoming evaluation and consumption.
- Replacement captures the new owner, releases the old owner, then commits the new handle; producer traps leave the old field untouched.
- Normal object destruction performs deterministic automatic field cleanup.
- User deinit runs first with live mutable fields and may replace them through ordinary direct/member/setter paths.
- Automatic cleanup releases the current final contents in reverse declaration order.
- A trap does not unwind or roll back construction, replacement, or destruction.
- Object owner transfer moves transitive cleanup responsibility without moving individual field handles.
- Object result construction/forwarding preserves final candidate storage, exact object identity and field contents.
- Null Resource owners require no release call or active bit; null object owners require no field cleanup.
- No move-out, explicit release-to-empty, or persistent MOVED field state exists.
- Owned ClassType fields await a separate storage-provenance solution.
- Owned struct fields await aggregate Move and do not weaken STRUCT-COPY/STRUCT-ABI.
- No heap, refcount, ownership header, destructor pointer, field-active bitmap or runtime cleanup table is required.

See [ADR 0064](../decisions/0064-owned-resource-fields.md).

## Source composition: SOURCES-1

- An Astra program may contain multiple source files. Files and directories are
  organizational units, not semantic modules or automatic namespaces.
- Every supplied native source contributes to one global native declaration
  universe. Duplicate names reject globally under the existing name rules.
- Every source is parsed independently. Source text is never concatenated.
- Every syntax node and declaration retains its exact SourceFile identity and
  byte span; line and column computation starts independently in each file.
- Native visibility and legality do not depend on CLI file order or forward
  declaration spelling. Names and signatures are collected before body checking.
- Canonical normalized-path and byte order stabilizes existing per-kind queues,
  diagnostics, ordinals and emission. It does not define runtime execution order.
- Cross-file references select exact symbols before Core. File paths never
  replace semantic symbol identity or trigger downstream re-resolution.
- Generic instances are canonical across the entire source set. Caller/file
  identity is not a specialization key, ABI channel or nominal type identity.
- File boundaries do not change ownership, borrowing, object storage, struct
  copying, cleanup, Resource metadata or foreign visibility contracts.
- One compilation emits one program/module/output. There is no per-file Astra
  link, runtime registry, filename table, initialization table or added dependency.
- SourceSet and syntax trees may die after checking. Provenance objects own no
  syntax graph; existing stage lifetime and independent-verifier rules continue.
- Modules, imports, packages, separate compilation, stable module ABI, caches,
  manifests and standard-library organization remain distinct future decisions.

See [ADR 0069](../decisions/0069-multi-source-compilation.md).

For annotated C text imports, both explicit UTF8_I32 metadata and the exact
BORROWED_NOESCAPE StringType parameter must survive every stage. The CABI plan
owns group roles, signed count width and physical/logical ordering independently
of NABI. An import cannot silently gain text results, export role, pointer
attributes or purity. Scalar parameters beside text retain their original C
admission rules. See [ADR 0074](../decisions/0074-borrowed-c-text-and-output.md).

## Generic copyable values (GEN-COPY-1)

[ADR 0078](../decisions/0078-generic-copyable-values.md) connects the existing
plain-copy contract to eligible record values and exact constructed arguments.
One shared structural proof supplies concrete admission and scoped symbolic
premises. Definitions remain checked once; bounded transport materializes into
existing scalar/vector or struct-copy/producer operations before concrete Core.
Record parameters use independent read-only storage; call arguments capture all
leaves before later effects. Named record-valued initializer entries accept
bounded producers in written order for ordinary and generic enclosing records.
No ownership, operator, zero, public Copy syntax, ABI profile or runtime machinery
is implied. Exact nominal keys, canonical applications and deterministic budgets
govern completion. See [transport IR](../ir/generic-copyable-values.md).

## Generic borrowed slices (GEN-SLICE-1)

[ADR 0079](../decisions/0079-generic-borrowed-slices.md) permits exactly direct T[]
formals and compatible local views. Signature-derived exact element obligations
are shared by semantic and parameterized-Core checking; copying and storage use
existing independent authorities. One-layer inference retains complete checked
views and transactional effects. Materialization produces ordinary concrete
slices, bounds associations, backing origins and record snapshots before CFG.
Collections remain borrowed, values remain copied, and existing instance keys,
limits, ABI profiles, overlap checks, target gates and lifetime rules remain intact.
The installed fill/swap library is explicitly selected ordinary source without a
provider or compiler name reservation.


## Sealed lifetime-query cache

The empty-origin query cache belongs to one sealed lifetime graph. Its key includes
the node, path, descendant flag and exclusions. Publish a hit only after all
reachable projections and grounding checks succeed; failed queries are never
cached. The 65,536-entry cap limits reuse, not semantic admission. Each public
result array remains fresh, and graph identities cannot share cached facts.
The independent lifetime-model controls cover warmed projections, exclusions,
cycles, input origins, graph isolation and mutation of returned arrays.

## Validation ordering and field lookup

Foreign-call guards inspect target terminators only after establishing program
ownership and a present, complete entry block. Malformed calls remain the
responsibility of each independent ownership/completeness verifier.

Field-context resolution resolves a receiver once per projection step and shares
that resolved type with imported-property lookup. Deep ordinary record chains
must not repeat the same recursive traversal or gain depth/name special cases.
Nominal identity, property access rules and existing cache lifetimes remain intact.
