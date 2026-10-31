# Shared enums and checked errors

**ASTRA-ENUM-ERROR-CONTRACT-1 · 2026-10-04 · Proposed detailed contract.**
This is the single normative proposal for this checkpoint. [ADR 0087](../decisions/0087-shared-enum-and-error-foundations.md)
records its status; the review table
contains recommended decisions. No source syntax, production type, ABI or runtime
below is implemented by this delivery. Every Astra code block is **proposed**,
including blocks that reuse already supported scalar/record/buffer syntax.

## Authority and boundary

The user approved nominal payload-bearing tagged unions, shared enum/error value
machinery, explicit handling plus concise keyword propagation (A+C), and checked
ordinary errors before source async. The individual rules below are recommended
for review, not already approved by that direction or by model PASS.

The unexecuted A1-R3-EXPLICIT draft's explicit-matching-only first usable async
surface is superseded. Its packet bytes, the accepted R3 lifecycle model and
reports, and CALLABLE/V01–V03 implementation remain unchanged. R3 supplies
lifecycle obligations, not the final error-value surface. Native-kernel-first
Linux policy remains approved; no kernel/liburing version, provider experiment
or new runtime dependency is selected here.

The bounded return path is useful ENUM-1 → ENUM-OWN-1 (owning/parameterized
composition) → ERROR-1 → revised ASYNC-1 with A+C → ASYNC-IO-1. Scope and exits
make those dependencies concrete. General recursive ADTs, persistent stored
borrows, arbitrary owning records/containers, owned text, closures, reflection,
pattern guards/or-patterns, defer/finally, unwinder interoperability and broad
foreign aggregates are excluded from this initial sequence. Later extensions
must add their own storage, lifetime and independent-verifier witnesses to these
same authorities, rather than replace the rules with a second type system.

## Current-source audit

Audit baseline: `a7cb205b6ac9b4341455f0798f4af041206de134`, tree
`0280bac728f0debdcc9113743b63e245ce0393fb`. Packet excerpts were navigation;
the following findings use the current repository files and applicable decisions.
No executable compiler probe was needed: restrictions are explicit in the
dispatch, admission and transport authorities. Probe count is zero; no compiler
build/run, native test, CAD run or kernel probe supplies this audit.

| Exact source authority / symbols | Delivered restriction | Required bounded addition |
| --- | --- | --- |
| [token](../../bootstrap/syntax/token.vala), `TokenKind`; [lexer](../../bootstrap/syntax/lexer.vala); [parser](../../bootstrap/syntax/parser.vala), `parse`, `parse_statement`, `parse_type_suffix`, `parse_field_access` | Top-level const, struct/class and native functions; statements have no enum/match/throw/catch/try/capture/async dispatch. Dot syntax is currently field/member lookup. The Vala enums/errordomains in compiler code are implementation facilities. | Enum declaration/constructor/pattern nodes and explicit type-qualified variant lookup. ERROR-1 alone adds error operations. No reservation of tokens in this checkpoint. |
| [types](../../bootstrap/semantic/types.vala), `TypeKind`, `BuiltinTypes`, `SemanticType`, `GenericArgumentTypes`, `TypeSubstitution`; [symbols](../../bootstrap/semantic/symbols.vala), `NativeInstanceSymbol`; [analyzer](../../bootstrap/semantic/analyzer.vala), `named_types`, `ValueScope`, `resolve_type`, `check_argument`, `check_arguments` | int/i32 canonicalize together; structs and exact applications are nominal. No sum type. Value/type lookup authorities are distinct. | Immutable enum-definition tokens, exact variant/field tokens and application arguments; one shared substituted field graph. |
| [copyability](../../bootstrap/semantic/copyability.vala), `CopyabilityAuthority.value_copy`, `visit` | Scalars/vectors and complete nonempty acyclic records; exact lexical plain-copy premises; owning categories excluded. Copyability has no Eq/zero implication. | Visit every variant's declared payload graph; an empty payload is allowed inside a nonempty enum. Preserve record rules. |
| [record producers](../../bootstrap/semantic/semantic-struct-values.vala), `CheckedStructProducer`, `CheckedStructSnapshot`, `CheckedStructCallResult`; [contract](../../bootstrap/semantic/struct-value-contract.vala), `StructValueContract`, `StructLeafOrder` | Bounded snapshots/call results are not general aggregate expressions. Native records cross declaration-ordered leaf channels. [Structs](../language/structs.md) still reject owned fields; general result-member projection is absent. | A bounded sum producer/value category with explicit active alternatives; do not pretend existing scalar or unconditional record-leaf transport suffices. |
| [generic structs](../../bootstrap/semantic/semantic-generic-structs.vala), `GenericStructSymbol.application`, `GenericStructApplicationType.matches`; [generic functions](../../bootstrap/semantic/semantic-generics.vala); [inference](../../bootstrap/semantic/generic-call-inference.vala) | Plain T is copied; generic record fields need that proof. Ownable T is direct Resource/Class transfer, with no plain T local, generic owned-T local or borrowed T. SliceType is neither plain copied T nor direct Ownable. | ENUM-OWN-1's enum-scoped array payload premise and applied enum storage, checked at definition time. Do not change all existing T to move-by-default. |
| [elements](../../bootstrap/semantic/buffer-elements.vala), `GenericSliceObligations`, `BufferElementTypes`; [buffer checker](../../bootstrap/semantic/semantic-buffers.vala); [owned arrays](../language/generic-owned-arrays.md) | Direct T[] signatures supply COPY/STORAGE/ZERO/DESTRUCTION premises. 34 primitive/vector/mask identities and eligible records; no owning elements. Ownership is a contract on SliceType, not a second canonical slice identity. | Reuse these four obligations for a declared `owned T[]` enum payload. This does not admit enum elements into zero-filled buffers. |
| [semantic flow](../../bootstrap/semantic/generic-ownership-flow.vala), `GenericOwnershipFlow`; [owner states](../../bootstrap/semantic/ownership-state.vala), `OwnershipState`; [CFG](../../bootstrap/cfg/cfg-builder.vala), `lower_arguments`, `lower_call`, `capture_before_transfer`; [CFG flow](../../bootstrap/cfg/ownership-flow.vala), `OwnershipFlow.analyze` | Written-order capture; semantic source unavailable at capture. `CfgPendingOwnedArgument` is physically disarmed by the joint `CfgOwnedCallTransferCommit` immediately before invocation. Current normal-exit cleanup has no recoverable abort edge. | Distinguish reservation from committed movement; abort edges restore only reservations and dispose staged fresh owners. New sum/error edges need independent flow/cleanup proofs. |
| [CFG verifier](../../bootstrap/cfg/cfg-verifier.vala), `verify_pending_interval`; [SSA builder](../../bootstrap/ssa/ssa-builder.vala), buffer capture/commit handling; [SSA flow](../../bootstrap/ssa/ssa-buffer-flow.vala); [borrow regions](../../bootstrap/semantic/lexical-region.vala) | Pending intervals currently require eventual call commit; no cleanup/rearm or exit before commit. Buffer capture reads the pair; commit disarms its source. No persistent view into an owner. | A verified abort terminal for each reservation; bounded payload borrow intervals; exactly one sum/result consumer. Existing fatal exits keep their policy. |
| [native mapper](../../bootstrap/nabi/native-type-mapper.vala), `NativeTypeMapper`; [record plans](../../bootstrap/nabi/native-struct-values.vala), `NativeStructValuePlan`; [buffer plans](../../bootstrap/nabi/native-buffer-values.vala), `NativeBufferValuePlan`; [verifier](../../bootstrap/nabi/native-verifier.vala), `NativeAbiVerifier.verify_detached_signature` | Scalars and explicit record/buffer groups, no enum/error carrier. Owned arrays have an exact base/count group. Internal continuations are exact code/environment associations, not source callables/tasks/sums. | Versioned sum-value and fallible-signature capabilities; preserve old signatures and the complete V01–V03 correspondence checks. |
| [allocation policy](../language/allocation-failure.md), [LLVM allocation](../../bootstrap/backend/llvm/llvm-buffer-allocation.vala); [C mapper](../../bootstrap/cabi/cabi-type-mapper.vala) | `new ... else void_call(...)` reports then fatally traps; traps do not unwind caller owners. Native aggregates do not grant C aggregate ABI. | No changes here. Recoverable allocation is Q13's separate extension. Foreign status adaptation needs a separately reviewed explicit adapter. |

[Capabilities](../language/capabilities.md), ADRs [0062](../decisions/0062-native-struct-values.md),
[0078](../decisions/0078-generic-copyable-values.md), [0080](../decisions/0080-generic-owned-runtime-arrays.md),
[0082](../decisions/0082-allocation-failure-actions.md), [0084](../decisions/0084-owned-buffer-exchange.md)
and [0086](../decisions/0086-internal-continuations.md) remain delivered authorities.
Their historical examples/reports are not rewritten to claim these additions.

## Declaration, lookup and validity

Recommend this first grammar. Braces have no closing semicolon. Parentheses are
required for **construction**, even for no-payload variants; declaration `Empty`
and `Empty()` mean the same zero-field shape (prefer `Empty`). One trailing comma
is allowed in enum declarations only. Constructor arguments are positional and
in declaration order; no default/named constructor arguments are added.

```text
enum-decl := enum Name type-parameters? { variant (, variant)* ,? }
variant := Name | Name (payload (, payload)*) | Name ()
payload := owned? type Name
constructor := enum-type . Variant (expression-list?)
match-statement := match (scrutinee) { arm+ }
arm := case enum-type . Variant (binding-list?) : block | else : block
binding-list := positional-list | named-list
positional-list := binding (, binding)*
named-list := field = binding (, field = binding)*
binding := identifier | _
scrutinee := expression | move identifier
```

```astra
enum Colour { Red, Blue }
enum DecodeError {
	InvalidMagic,
	UnsupportedVersion(int version),
	UnexpectedEnd(int offset, int required)
}
enum IOError { Denied(int code), ShortRead(int count) }
enum LoadError { IO(IOError cause), Decode(DecodeError cause) }
enum BufferState { Empty, Ready(owned u8[] bytes), Failed(DecodeError cause) }
```

Enums share the global nominal type namespace with structs/classes/builtins.
Collect definition identities before resolving payloads, as for records. A type
collision, duplicate variant, duplicate payload name within a variant, unknown
payload type, illegal ownership qualifier, by-value cycle or empty enum is an
error. Payload names may repeat across different variants. Initial payloads admit
current scalar/vector/mask/raw-void* copied values, eligible ordinary records,
acyclic nested enums, and concrete owned runtime arrays with existing elements.
Arrays themselves are not plain payload values; `owned` is necessary on the array
payload. Resource/Class payload admission waits for a specific witness and is
not inferred from the buffer witness. `void` is not a field or generic argument.

`DecodeError.UnsupportedVersion(7)` names exactly that variant in exactly that
enum. Names are case-sensitive. No bare variant import or layout-based search.
In a constructor/pattern qualifier, lookup explicitly uses the type authority;
other value/member uses retain their existing resolution. Generic constructors
spell all type arguments initially: `Result<int,DecodeError>.Success(7)`.
Neither result context nor payload layout infers missing arguments. Concrete
`var` can infer the constructed/applied enum. Unresolved generic bodies retain
explicit local types and exact lexical premises. This avoids new inference
machinery as an enum prerequisite; later inference can remove repeated obvious
arguments under its own once-only proof.

A valid initialized enum has a declared active variant and every required
active field initialized with its exact substituted type and transport contract.
Construction evaluates each field once, left to right; publish only after the
complete constructor commits. Inactive fields have no source lifetime and cannot
be read, moved, bound or destroyed. A moved, uninitialized, released or partially
built slot is internal storage state, never a hidden source variant, null case or
default. Conditional initialization/cleanup facts come from CFG ownership proofs;
an independent verifier must reject invented validity bits unsupported by stores.

Empty/uninhabited declarations are unnecessary initially and reject. No implicit
zero/default-first-variant, integer cast, arithmetic, flags, layout conversion,
recursive heap boxing or runtime error allocation is provided. Void success is
a **zero-field Success** in `VoidResult<E>`; absence is an ordinary explicit
variant such as `BufferState.Empty()`, distinct from an unusable moved slot. No
general bottom or Unit type is required.

## Whole values, borrows, construction and replacement

Copyability is derived over **all** alternatives, recursively. Any owning
payload makes the entire enum move-only, including its empty and error cases.
The ordinary enum spelling denotes derived value transport: a move-only enum
local/parameter/result needs no redundant `owned BufferState` or moveonly marker.
Named transfers use `move name`; a fresh enum constructor/call result is consumed
directly by initialization, return or match. Owned array fields still declare
their existing `owned T[]` contract. Calls consuming an existing buffer or enum
require a named move; this proposal does not widen all consuming-call arguments
to arbitrary inline owner producers.

Copyable enums can initialize/replace an exact local, pass/return by value and
provide independent arm snapshots. Move-only enum locals/parameters/results have
whole movement and active cleanup. No partial field extraction from a still-live
named enum is admitted. No outside-match payload access, writable payload
projection, enum methods/properties, owner-bearing struct field, Class field or
collection element admission follows automatically. ENUM-OWN-1 admits only the
explicit enum storage/parameter/result/generic application matrix below.

Normal cleanup traverses active fields in **reverse declaration order**, recursively,
then ends the enum's lifetime. Scope cleanup is reverse successful binding
initialization order. Staging cleanup visits only acquired/committed initialized
fields, in reverse field acquisition order (constructor order equals declaration
order). Moved sources have no cleanup responsibility. A transferred zero-length
buffer is still an ownership contract, though it causes no allocator/free event.

Construction stages fresh owners; named payload moves reserve their source at
the argument position, making it unavailable until the consumer commits or
aborts. All reservations for one constructor commit only after its arguments
succeed. An inner constructor/call that already commits is an external effect
of the enclosing expression: the outer operation does not undo that move. Its
fresh returned aggregate is now staged and must be cleaned if a later outer
argument fails. Fatal termination retains the current non-unwinding policy.

Replacement first identifies/validates an exact initialized destination, then
completes the incoming producer without destroying the old value. On success,
commit incoming named moves, dispose the old active payload, and publish the
complete incoming value. On recoverable failure, discard newly acquired staging
values and cancel uncommitted reservations; the destination remains live at the
handler entry if its scope survives. Leaving that scope subsequently cleans it.
No rollback of earlier I/O, mutation or nested completed calls is promised.
Self-move rejects, even for an empty case. A borrow of the destination/source or
a possibly aliasing invalidation through a containing object rejects; aliasing
copyable self-snapshots are allowed only after complete capture. No public
half-live enum or dynamic owner pin is needed.

## Exhaustive matching and binding

`match (value)` evaluates its scrutinee once. For a copyable enum it captures an
independent whole snapshot. For a named move-only enum it inspects without
consuming. `match (move value)` consumes the named value; matching a fresh owning
constructor/call result consumes the temporary without an artificial name/move.
Exactly one arm is selected by the active variant. Arms never fall through;
ordinary `break` continues to refer only to loops, not match. The matching block
itself adds no control-flow jump spelling.

Require every declared variant exactly once, or an explicit last `else` arm.
Missing cases, duplicate cases, wrong enum/application, duplicate bindings,
unknown payload names, wrong field count and an unreachable fallback after all
explicit cases are errors. `else` intentionally covers current and future
alternatives; an exhaustive explicit list must be revised when a variant is
added. A no-payload pattern is `case Colour.Red():`; constructor/pattern
parentheses consistently make shape visible. Named patterns can reorder fields
but must name **all** of them, using `_` for an ignored field; named/positional
forms cannot mix. Arm local names follow current no-visible-shadowing rules.

| Match kind | Copyable scalar/record/nested enum field | Owned array / move-only nested enum field | End of arm |
| --- | --- | --- | --- |
| Copyable snapshot | Binding is a copy | Impossible in a copyable enum | Independent snapshot/bindings end normally |
| Inspect named move-only value | Binding is a copy | Read-only, nonescaping arm borrow, implicitly derived from payload contract | Borrows end on every arm exit before outer cleanup |
| Consume named/fresh whole value | Binding is a copy | Binding receives full responsibility, derived without repeating owned/move in each pattern | Untransferred bound owners clean normally |

`_` in an inspection reads/drops nothing. In consuming matching, ignored owners
are disposed at arm entry in reverse payload declaration order; remaining
bindings are initialized in declaration order and clean in reverse binding order.
A consuming fallback disposes the entire active payload at arm entry. Consuming
match disarms the source before arm code; the arm cannot move it again. A live
payload borrow blocks retagging, replacement, movement and destruction of its
whole root for the arm's full extent. Scalar snapshots may escape; borrowed
payloads may not escape, return, be stored or cross suspension. Nested enums use
an ordinary **nested match** on a binding, not refutable nested patterns in the
outer arm. This provides nested error policy without a new coverage algebra.

Every recoverable error edge ends exactly the inspection loans whose arm extents
it exits, before cleaning their enclosing owners and entering the handler. A
handler still inside an arm retains that arm's loan; copied scalar/record bindings
carry no loan. ERROR-1 must map each loan to its lexical extent and verify both
its error-exit ordering and the surviving loans, as witnessed by the
R1 correction.

## Parameterized outcomes and transport

Choose ordinary generic enums with existing **plain-copy** T/E premises, plus
one enum-scoped direct-array-payload extension. The proposed declarations are:

```astra
enum Result<T,E> { Success(T value), Error(E error) }
enum VoidResult<E> { Success, Error(E error) }
enum ArrayResult<T,E> { Success(owned T[] value), Error(E error) }
enum Completion<T,E> { Success(T value), Error(E error), Cancelled }
enum VoidCompletion<E> { Success, Error(E error), Cancelled }
enum ArrayCompletion<T,E> { Success(owned T[] value), Error(E error), Cancelled }
```

These are shared enum definitions, not six independent runtime storage systems.
Completion adds one no-payload case. No compiler-private scalar Error(int)
replaces nested nominal error values. Ordinary non-propagating enum definitions
may use a copyable E that is not an error domain; ERROR-1 recognizes the error
role only from a declared fallible operation and its exact outcome bridge.

| Fallible success signature / error | Explicit capture value | Constructor witness | Transport |
| --- | --- | --- | --- |
| `int f() throws DecodeError` | `Result<int,DecodeError>` | `Result<int,DecodeError>.Success(7)` | Copied scalar/error |
| `Header f() throws DecodeError` | `Result<Header,DecodeError>` | `Header h = { version = 1, size = 4 }; Result<Header,DecodeError>.Success(h)` | Copied bounded record snapshot/error |
| `void f() throws DecodeError` | `VoidResult<DecodeError>` | `VoidResult<DecodeError>.Success()` | No success payload; copied error |
| `owned u8[] f() throws DecodeError` | `ArrayResult<u8,DecodeError>` | `owned u8[] b = new u8[4]; ArrayResult<u8,DecodeError>.Success(move b)` | One buffer group on success; whole enum move-only on both cases |

Do **not** write `Result<owned u8[],E>`, `Result<u8[],E>` or instantiate plain
T with a move-only enum. Those do not satisfy the selected premises. Generic
definition checking proves all Result fields copyable without specializing.
For ArrayResult, direct `owned T[]` in the enum declaration establishes
COPY/STORAGE/ZERO/DESTRUCTION on the exact lexical **element T**, in addition
to its ordinary plain-copy premise; E has the ordinary plain-copy premise only.
This is a proposed enum-scoped extension to `GenericSliceObligations`, not a new
public capability or an inference from a favorable caller. Definition-time
legality requires every variant/operation to follow these premises, even unused.

Instantiation validates both plain-copy arguments, then the array element
obligations against the current BUFFER domain; E does not need zero. Canonical
int/i32 still share an argument identity. Application identity is definition
token plus ordered exact canonical arguments, including phantom arguments.
Payload mode is fixed by each definition/field; it need not enter a separate
application-mode key or create `OwnedSliceType`. An otherwise equal-layout
ArrayResult/Result or two nominal error applications remain distinct.

A function signature mentioning `ArrayResult<T,E>` imports that definition's
exact element premises for T; it does not derive new authority from a local.
Bounded owning **applied enum locals** and whole forwarding are added in
ENUM-OWN-1, while direct generic owned-T locals and generic Class/struct owners
remain excluded. For example (proposed):

```astra
ArrayResult<T,E> relay<T,E>(ArrayResult<T,E> input) {
	return move input;
}
ArrayResult<T,DecodeError> produce<T>(int count) {
	owned T[] values = new T[count];
	return ArrayResult<T,DecodeError>.Success(move values);
}
```

Known applied enums substitute every payload and premise; exact T versus U
does not merge in a definition just because one call supplies equal types.
Specialization erases parameters before concrete CFG/layout planning, preserving
nominal/application and per-field transport tokens. Generic constructor type
arguments remain explicit; handlers infer no union of domains from body calls.

The strongest alternative is an enum-scoped generalized value/owner-mode type
parameter admitting `Result<owned u8[],E>`. It removes family names but needs
ownership-qualified argument grammar, mode-aware application keys, unknown
owner-local storage/borrowing and body legality rules beyond the present T
contracts. The chosen family costs explicit `ArrayResult`/`VoidResult` names;
it is sufficient for all required success domains without that larger change.
Later generalized composition may unify surface families only with reviewed
mode premises and compatibility adapters. It is not a hidden prerequisite now.

The future compiler recognizes an **exact compiler-owned outcome operation
contract**, binding success/error/cancel role ordinals to registered definition
tokens and their substituted transport contracts. Spellings alone never confer
control flow: a user enum named Result/Completion has ordinary enum behavior.
Capture materializes the registered enum; try consumes the same semantic
channels directly. This bridge promises semantic parity, not physical ABI identity.

## Initialization, operations and physical plan

All enums require explicit initialization. Copyable/zeroable leaves do not
establish an enum default. `new E[count]` and enum collection elements reject
initially, including payload-free E; BUFFER admission is unchanged. A later
filled-array producer can construct each valid element explicitly, but must
review element copy/storage/destruction and failure cleanup first.

First ENUM-1 equality is only `==`/`!=` on the **same concrete payload-free enum**,
comparing variant identity. Payload enums have no derived equality initially,
even when copyable. No ordering, hashing, arithmetic or integer conversion.
Inactive/padding bytes are never an equality oracle.

Choose bounded **tag plus active payload storage**, normally an addressable
carrier for native sum parameters/results and owning sum locals. Copyable local
cases may scalarize; a bounded sum producer carries selected fields without
requiring universal aggregate SSA. Concrete layouts follow specialization.
Storage is aligned for the largest variant payload: approximately
`align_up(tag_bytes + payload_offset_padding + max_variant_bytes, max_alignment)`;
actual target plans determine offsets, tag width and padding. On GNU LP64 a
buffer payload needs its pointer/count group (typically 16 bytes including
alignment); adding a tag can yield a 24-byte carrier. This is illustrative cost,
not an approved ABI or guaranteed 1-byte discriminant. Copy/tag selection and
cleanup introduce branches; no universal zero-cost claim follows.

| Physical option | Assessment |
| --- | --- |
| Bounded carrier with tag and active union storage; caller-provided result slot | Recommended initial plan. Easy to preserve one initialized active payload and larger record/buffer results. Can cost stack stores/projections versus register leaves. Requires a genuine sum plan/versioned native capability. No heap box. |
| Explicit status plus separate success/error out slots | Strongest fallible-call alternative. Avoids materializing raw Result when try projects immediately; may fit bounded old leaf channels. Extra out storage/pointers and inactive channels require strict initialization/correspondence rules. May be a later layout refinement under the same semantics. |

A universal all-variant aggregate carrier would transport unused payload slots
and invite reading uninitialized data; do not encode it as an ordinary copied
record with unconditional leaves. No boxed/runtime-dictionary workaround.
Old NABI signatures/profiles remain frozen. Future enum-bearing boundaries need
a named **new sum-value capability**, and fallible calls an additional checked
normal/error capability; reserve actual profile numbers only in their approved
implementation orders. Native target layout, C ABI and serialized bytes are
three independent contracts. No stable native tag numbering, repr/packed/niche
policy, serialization or foreign enum admission follows. A future C adapter
must validate foreign tags before construction, reject unknown values or
explicitly preserve them in an ordinary `Unknown(int raw)` data case under its
own policy. No arbitrary foreign bit pattern becomes a valid safe enum.

## Checked ordinary errors, capture and handlers

Initial error domains are nonempty nominal closed enums with copyable scalar,
record and nested copyable enum payloads. This is a bounded first restriction,
not a permanent prohibition on owned errors. Errors have no base class, required
allocation, dynamic type erasure or second storage identity. `throws E` assigns
one exact domain to a native function. Throw expression must have exactly E or
the domain of an applicable enclosing handler. Ordinary enums become errors
through that operation contract, not through the name Error.

```text
fallible-function := owned? result-type Name generics? (parameters?) throws error-type block
throw-statement := throw expression ;
try-expression := try direct-fallible-call
capture-expression := capture direct-fallible-call
handler-statement := try block catch-clause+
catch-clause := catch (error-type identifier) block
```

An unadorned fallible call is a **diagnostic**, including as a statement. It
never silently returns raw Result or chooses extraction from a destination type.
`capture f(args)` evaluates one call and yields the appropriate raw enum above;
it handles that call's error and invokes no lexical handler. Nested arguments
remain independently explicit: `capture f(try g())` can still dispatch g's error.
`try f(args)` evaluates one call, yields success, or dispatches its exact Error.
For void success it is a statement `try check(bytes);` with no fabricated value.
Initially try/capture apply to a direct native named/member fallible call, not
an arbitrary arithmetic expression or every call in a block. Fallible record
success reuses a bounded producer; owned-buffer success retains owning storage.

`try { ... } catch (E err) { ... }` installs lexical destinations; it does not
implicitly annotate calls inside the block. Prefix try exposes which operations
may exit the expression. Dispatch selects the **nearest enclosing handler of
the exact nominal E**, skipping mismatched domains; every crossed scope cleans
before entry. With no such handler, the function must declare the identical E,
or checking fails. Duplicate E catches on one try statement reject. Each catch
handles the entire E value; partial policy is an exhaustive match inside it
with explicit `throw err;` for unwanted alternatives. Bare `throw;` rejects.
The caught binding is read-only copied E in ERROR-1; a local copy can transform
it. A catch does not catch its own rethrow or a new failure in its body: those
go to handlers outside its associated try. Nested handlers therefore have an
unambiguous lexical destination and reverse cleanup order.

Error composition is explicit: `throw LoadError.Decode(err);` wraps a decoded
error. `LoadError.IO(io)` and `LoadError.Decode(decode)` preserve their domains.
Equal variant names/layouts do not convert; no flattening of closed sets or
implicit conversion framework is added. Transformations are ordinary code.
An explicit capture/match may similarly return Success, convert Error or rethrow.
Policy transformations are deliberate behavior changes, not parity witnesses.

The nonthrowing/root rule is static: all checked errors need capture or an exact
lexical handler. Existing `int main()` remains nonthrowing and supplies an
ordinary adapter returning an int on each branch. No implicit termination,
successful return, global pending error or type-erased downcast. A foreign
callback must finish native handling/adaptation before returning to ordinary C;
transparent propagation across arbitrary C frames is unsupported.

The first throws annotation must resolve to a concrete copyable nominal enum
(including a fully proved applied enum). A generic function can declare a known
concrete DecodeError; an unconstrained `throws E` type parameter rejects because
plain-copy alone does not prove a nominal error domain. General abstract error
parameters need a later explicit premise, not specialization-only discovery.

## Error edges and ownership commit points

Use compiler-generated CFG normal/error/cleanup edges. Logical scope cleanup
occurs on ordinary error exit; no dynamic stack-walker/personality runtime is
mandatory. This is not a measurable overhead guarantee. Destructors/automatic
cleanup remain synchronous and non-fallible. Explicit `close` can report a
checked status before ordinary nonthrowing best-effort destruction; a failing
automatic destructor cannot replace a pending first error in this subset.
Fatal assertions, bounds/arithmetic traps, allocation actions and termination
retain existing non-unwinding behavior and cannot be caught by try/catch.

| Trigger | Recommended exact responsibility / commit |
| --- | --- |
| Later argument errors after `move named` was captured | Named source is reserved/unavailable from capture but not yet transferred to callee. Cancel reservation on abort. If local handler preserves the source scope, it is live again; if scope exits, clean it once there. Fresh already-produced owner arguments clean in reverse acquisition order. The callee never runs. |
| All call arguments complete | Commit all named transfers together immediately before invocation; disarm sources. Fresh arguments become callee responsibilities at the same boundary. Current pending-move verifier needs an explicit verified abort exit, not deletion of its interval proof. |
| Callee consumes input, then errors | Input belongs to callee. Callee cleans live input/locals before error return unless transferred onward; caller cannot resurrect its moved source. |
| Constructor fails after earlier fresh payload acquisition | Unpublished initialized prefix cleans in reverse acquisition order. Cancel that constructor's named reservations. A completed inner move/call is not rolled back. |
| Return expression errors with live locals | Capture/propagate error, clean crossed initialized owners in reverse binding order, publish only Error. No success slot may be projected. |
| Replacement's incoming function errors | Its initialized candidate/staging cleans; old destination is still live. Commit/dispose/publish has not occurred. If error exits the destination scope, its normal scope cleanup still runs. |
| Owning success is matched/forwarded/ignored | Consume registered outcome once; transfer selected owner or explicitly discard it with active cleanup. Whole owning Error case still moves even with no active owner. A discarded owning call result is diagnosed; explicit consuming `_` documents disposal. |
| Future owning error is handled/rethrown/ignored | Same single transfer/active cleanup laws. A handler receives responsibility, rethrow/wrap transfers it with visible move, and unused bindings dispose on handler exit. Initial ERROR-1 does not yet admit these error domains. |
| Handler itself fails | Its outside handler/function receives the new error; the handler's original error binding and remaining owners clean on exit. To preserve both errors, explicitly construct a combined nominal error value before throwing it. No hidden second-failure overwrite. |

For example `consume(move a, try later())` reserves a, then evaluates later once.
If later errors into a same-scope handler: `(acquire a, reserve a, later Error,
abort reservation, enter handler)`; a stays live. If later succeeds: `(reserve a,
later Success, commit a→callee, invoke)`; callee owns a. The eager-move alternative
would dispose captured a on the failed-call path and make retry with a impossible.

For `consume_pair(move a, recover_second())`, local recovery inside
recover_second leaves consume_pair's reservation of a intact and unavailable;
its eventual invocation commits a once. If the error escapes and abandons
consume_pair, only that pending consumer and abandoned nested consumers abort.
Restore a only if its owner scope survives; otherwise clean it once. A completed
inner move/call remains committed in either case. Equal scope depths cannot
identify which invocation was abandoned. ERROR-1's semantic/CFG/SSA responsibility
map must associate each reservation and handler continuation with the exact
pending consumer, independently of owner cleanup and lexical loan extent.

Choose joint commit to preserve the current physical boundary; this requires
new reservation/abort facts in semantic/CFG flow, because the current MOVED
lattice alone cannot represent recovery correctly. Nested operations already
committed remain effects under either path.

## Complete synchronous walkthrough

This whole program is proposed and self-contained. Bytes, casts, len, records,
new and named buffer moves reuse current spellings. New enum/match/throws/try/
capture forms and fallible record transport depend on the sequence above.
Allocation in the buffer-producing function remains fatal on OOM.

```astra
enum DecodeError { InvalidMagic, UnsupportedVersion(int version), UnexpectedEnd(int offset, int required) }
enum IOError { Denied(int code), ShortRead(int count) }
enum LoadError { IO(IOError cause), Decode(DecodeError cause) }
struct Header { int version; int size; }
Header validate(u8[] bytes) throws DecodeError {
	if (len(bytes) < 2) { throw DecodeError.UnexpectedEnd(len(bytes), 2); }
	if (bytes[0] != (65 as u8)) { throw DecodeError.InvalidMagic(); }
	int version = bytes[1] as int;
	if (version != 1) { throw DecodeError.UnsupportedVersion(version); }
	Header header = { version = version, size = len(bytes) };
	return header;
}
void check(u8[] bytes) throws DecodeError {
	Header header = try validate(bytes);
}
int decode_code(DecodeError err) {
	match (err) {
		case DecodeError.InvalidMagic(): { return 10; }
		case DecodeError.UnsupportedVersion(version): { return 20 + version; }
		case DecodeError.UnexpectedEnd(offset, required): { return 30 + required - offset; }
	}
}
int inspect(u8[] bytes) {
	var outcome = capture validate(bytes);
	match (outcome) {
		case Result<Header,DecodeError>.Success(header): { return header.size; }
		case Result<Header,DecodeError>.Error(err): { return decode_code(err); }
	}
}
int concise(u8[] bytes) {
	try {
		Header header = try validate(bytes);
		return header.size;
	} catch (DecodeError err) {
		return decode_code(err);
	}
}
Header load_header(u8[] bytes) throws LoadError {
	try { return try validate(bytes); }
	catch (DecodeError err) { throw LoadError.Decode(err); }
}
Header require_version(u8[] bytes) throws DecodeError {
	try { return try validate(bytes); }
	catch (DecodeError err) {
		match (err) {
			case DecodeError.UnsupportedVersion(version): {
				Header fallback = { version = version, size = 0 };
				return fallback;
			}
			else: { throw err; }
		}
	}
}
owned u8[] validated_bytes(int version) throws DecodeError {
	owned u8[] bytes = new u8[2];
	bytes[0] = 65 as u8;
	if (version != 1) { throw DecodeError.UnsupportedVersion(version); }
	bytes[1] = 1 as u8;
	try check(bytes);
	return move bytes;
}
owned u8[] keep_result(int version) throws DecodeError {
	var outcome = capture validated_bytes(version);
	match (move outcome) {
		case ArrayResult<u8,DecodeError>.Success(bytes): { return move bytes; }
		case ArrayResult<u8,DecodeError>.Error(err): { throw err; }
	}
}
owned u8[] concise_result(int version) throws DecodeError {
	return try validated_bytes(version);
}
int main() {
	try {
		owned u8[] first = try keep_result(1);
		owned u8[] second = try concise_result(1);
		if (inspect(first) != concise(first)) { return 1; }
		return (second[1] as int) - 1;
	} catch (DecodeError err) { return decode_code(err); }
}
```

On version=1, one created buffer transfers producer→outcome→arm binding→caller;
the outcome slot has died before caller uses bytes, and no local descriptor
address escaped. Both forms return the same buffer responsibility. On version=2,
the producer cleans its allocated bytes once and transports only copied Error;
the caller never publishes an uninitialized buffer success. `inspect` and
`concise` evaluate validate once and use the same numeric error policy.
`load_header` deliberately transforms the domain; `require_version` deliberately
handles one alternative and rethrows others. Neither is an equivalence witness.

Additional complete small proposed programs exercise the enum boundaries:

```astra
enum Colour { Red, Blue }
enum DecodeError { InvalidMagic, UnsupportedVersion(int version), UnexpectedEnd(int offset, int required) }
enum BufferState { Empty, Ready(owned u8[] bytes), Failed(DecodeError cause) }
int main() {
	Colour first = Colour.Red();
	Colour copied = first;
	owned u8[] input = new u8[1];
	input[0] = 9 as u8;
	BufferState state = BufferState.Ready(move input);
	int observed = 0;
	match (state) {
		case BufferState.Empty(): { observed = 0; }
		case BufferState.Ready(bytes): { observed = bytes[0] as int; }
		case BufferState.Failed(cause): {
			match (cause) {
				case DecodeError.InvalidMagic(): { observed = 1; }
				case DecodeError.UnsupportedVersion(version): { observed = version; }
				case DecodeError.UnexpectedEnd(offset = at, required = need): { observed = need - at; }
			}
		}
	}
	match (move state) {
		case BufferState.Empty(): { return 1; }
		case BufferState.Ready(bytes): { return (bytes[0] as int) - observed; }
		case BufferState.Failed(_): { return 2; }
	}
}
```

The inspection binding bytes is borrowed/read-only and dies at its arm boundary;
the consuming bytes binding owns and cleans at return. Copied Colour is valid
regardless of its use. Ignoring an owning payload is explicit and disposes it:

```astra
enum BufferState { Empty, Ready(owned u8[] bytes), Failed(int code) }
int main() {
	owned u8[] input = new u8[1];
	match (BufferState.Ready(move input)) {
		case BufferState.Empty(): { return 1; }
		case BufferState.Ready(_): { return 0; }
		case BufferState.Failed(code): { return code; }
	}
}
```

Required proposed diagnostics (each independently invalid insertion): omit
UnexpectedEnd from decode_code → missing-arm error; `BufferState b = state`
even when state is Empty → whole-type copy error; `state = BufferState.Empty()`
inside Ready(bytes) inspection → live payload borrow invalidation; `move state`
after consuming match → moved-source error; `Result<u8[],DecodeError>` → plain-T
admission error; `validate(bytes)` without try/capture → unchecked-call error.

## Future async composition and cancellation

The same result families extend to Success, Error(E) and Cancelled. Task remains
a unique consuming observation/lifecycle capability, not a Completion value.
The registered Completion bridge supplies `await` and `try await`; its exact
initial parser/task/start surface belongs to revised ASYNC-1 review. Error E is
the declared ordinary domain, including nested enum values, not a private int.

| Observation | Success | Error(E) | Cancelled |
| --- | --- | --- | --- |
| Explicit `await move child` / await fresh task | Raw Completion; consuming match transfers success owner | Explicit match chooses handle, transform or throw | Explicit policy for independently cancelled child, subject to parent's own monotone cancellation |
| `try await move child` / try await fresh task | Extract/transfer success once | Dispatch nearest exact lexical E handler, otherwise declared E function channel | Enter current task's cancellation exit and scoped cancel/drain state, never ordinary catch(E) |

Recommend that the concise Cancelled default requests cancellation of the current
parent task and preserves that monotone request through its required drain. An
explicit Completion match may choose a fallback for an independently cancelled
child **only when the parent has no cancellation request**. It cannot erase a
parent request, publish parent Success after cancellation or free retained data.
This cancellation policy is a proposed detailed decision, not retroactive Q02
approval. An ordinary E catch never receives Cancelled by accident.

No completion is observable until R3's observed target, payload-release and
applicable command-release facts, registration retirement and queued-reference
retirement are satisfied. Completion availability/semantic tag is not a quiescence
proof. One pending consuming right remains with the waiter until observation,
then result transfer/discard and frame destruction close the join. Parent-only
cancellation, stable frame/environment identity and exact continuation code/
environment associations remain intact; timeout/cancel acknowledgment is never
permission to free. [R3 contract](async-contract.md) retains those authorities.

Here is a complete sequential **virtual** proposed program using only numeric
payloads. Cold task creation/deferred start and consumption on direct await follow
R3; executor/root adaptation is a separately selected async runtime boundary.

```astra
enum DecodeError { InvalidMagic, UnsupportedVersion(int version), UnexpectedEnd(int offset, int required) }
int version(int n) throws DecodeError {
	if (n != 1) { throw DecodeError.UnsupportedVersion(n); }
	return n;
}
async int next(int n) throws DecodeError { return try version(n); }
async int explicit_sequence(int n) throws DecodeError {
	match (await next(n)) {
		case Completion<int,DecodeError>.Success(value): { return value; }
		case Completion<int,DecodeError>.Error(err): { throw err; }
		case Completion<int,DecodeError>.Cancelled(): { return cancelled; }
	}
}
async int concise_sequence(int n) throws DecodeError { return try await next(n); }
```

These agree under the same ordinary-error policy and cancellation-forwarding
policy. A completion already carries release proof; the program does not supply
provider events or establish a kernel result. `return cancelled;` is only an
async cancellation exit, and never an E value or synchronous return spelling.

Concurrent early error has a real extra obligation. The following complete
**async function**, sharing DecodeError/next above, uses abstract virtual API
`start_reserved(executor, child)`: nonconsuming enrollment into an explicit
executor with two admissions already reserved before entry. It cannot fail in
this bounded witness. Executor and Task are dedicated lifecycle contracts, not
generic classes/ordinary enum owners. Real fallible admission requires its own
explicit capture plus join of any already admitted child; no provider/start ABI
is approved by this illustrative API.

```astra
async int concurrent(Executor executor, int n) throws DecodeError {
	var left = next(n);
	var right = next(1);
	start_reserved(executor, left);
	start_reserved(executor, right);
	var first = await move left;
	var second = await move right;
	match (first) {
		case Completion<int,DecodeError>.Success(value): {
			match (second) {
				case Completion<int,DecodeError>.Success(other): { return value + other; }
				case Completion<int,DecodeError>.Error(err): { throw err; }
				case Completion<int,DecodeError>.Cancelled(): { return cancelled; }
			}
		}
		case Completion<int,DecodeError>.Error(err): { throw err; }
		case Completion<int,DecodeError>.Cancelled(): { return cancelled; }
	}
}
```

Both children are joined before first's error is propagated; second's copied
completion can be ignored under this deliberate first-error-wins policy. With
owning results the second completion requires explicit consuming disposal on
first's error arm. Parent cancellation invokes the existing R3 cancellation drain
instead of resuming ordinary catch code. The abbreviated `return try await move
left;` while separately started right is still outstanding **rejects**: the error
edge lacks right's join. A lexical E handler could retain the scope, explicitly
join right, then rethrow; it does not authorize implicit error-scope drain. No
async destructor, nested event-loop pump or detached work is introduced. The
model tests the retirement/observer boundary only; concurrency/start/drain
execution stays with the unchanged R3 model and future implementation.

## Lowering and independent verification responsibilities

Every retained model owns a compact immutable witness of the exact program
identity it verifies, rather than a predecessor graph or generated-name lookup.

| Boundary | Owns after predecessor destruction | Must independently reject |
| --- | --- | --- |
| Syntax → checked semantics | Definition/application/variant/field tokens, complete substituted payload graph, spans, match coverage and explicit call disposition | Duplicate/missing fields/arms, wrong nominal application, unchecked error/copy/move, invalid generic premises |
| Parameterized checked/Core → materialized Core | Exact lexical premises and argument substitutions until erasure; concrete sum shape, transport and producer/use association afterward | Definition legal only at one specialization, same-layout argument substitution, missing element cleanup contract |
| Core → CFG | Exact enum shape; storage lifetimes; staging-prefix and reservation/commit/abort sites; borrow roots; handler/function destination tokens; normal/error cleanup edges | Uninitialized success publication, inactive projection/destruction, alias invalidation, losing or resurrecting staged owner, wrong-domain handler |
| CFG → SSA | Dominating tag test and selected field path, owner groups/disarms and unique result consumers, exact edge/scope correspondences | Copy owning empty enum, projection without matching active proof, duplicate consumption, missing cleanup, orphan reservation or wrong predecessor instance |
| SSA → NABI | Versioned physical carrier/tag/payload layouts, exact nominal/application identity keys, source-ordinal channel groups, normal/error role association, owned base/count and cleanup signatures | Structurally valid plan for another enum/program; wrong active layout/channel type; uninitialized error/success out slot; old profile silently widened |
| NABI → LLVM artifact | Expected carrier/result allocation, full projection base/path/indices, tag/payload stores and dominance/publication order, source→consumer/call→result instance association | LLVM-valid wrong carrier/allocation or nonzero intermediate projection; independent valid tag/plan substituted for wrong use |
| Async integration later | Exact enum/error role bridge plus separate frame/child/provider/queue/right evidence | Cancellation caught as E, outcome publication before retirement, lost pending observation, code/environment mismatch |

V01 requires validating full physical channel/profile groups even in detached
plans; V02 requires the entire projection path, not its final field index; V03
requires the expected allocation/instance, not a same-shaped dominating pointer.
All three principles apply to sums and fallible results. Physical verifier data
may contain immutable copied identity keys and borrowed LLVM handles owned by
the artifact lifetime; retaining the entire checked/Core/CFG/SSA graph is not a
solution. Native and C signature contracts stay separate.

## Model evidence and limits

The [standard-library-only model](../../tools/design/enum-error-contract-1/README.md)
tests proposed identities, initialized active payloads, ownership, matching,
replacement, staging, argument reservations, nested exact handlers and a small
retirement prerequisite. Handwritten owner event counts and independent
state/edge checks cover corruption separately from transition refusals. Explicit
and concise paths agree under the stated same policy and owner effect; deliberate
wrapping/handling is not equated.

Exploration bounds are declared in code before execution: two enum cells, two
owner-binding cells/tokens, up to three variants, nesting depth three, handler
depth two, six transitions and a 20,000-state cap per explored domain. Directed
handler/pair-owner traces exercise additional fixed cells outside the explorer;
there is no claim that all arbitrary programs fit that bound. The small domains
are Decode, BufferState and ArrayResult<u8,Decode>. Depth-bound completion is
reported separately from state-cap incompleteness. Counts and identities are in
the historical validation report.

The R1 validation adds independently
checked selected-field binding/event correspondence, scoped inspection-loan
error exits and exact consumer reservation aborts. These are fixed directed
domains alongside the unchanged explorer bounds. Explicit/concise parity checks
values and owner effects; one source-call evaluation remains a compiler
obligation, not an executed count inferred from a literal in the Python wrapper.
Original evidence and baseline replay remain historical; neither PASS approves
D01–D09 or implements these language features.

The model is not an Astra interpreter/parser, alias analysis, actual allocation,
native cleanup qualification, stack/register cost measurement or universal
soundness proof. Abstract retirement facts assume the unchanged R3 obligations;
they prove no provider behavior. General stored borrows, zero-length allocator
behavior, arbitrary recursion, concurrency, handler filters and target layouts
are outside this finite model. Detailed source and ABI approval remains pending.
