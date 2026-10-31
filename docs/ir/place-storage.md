# Local storage and Places

A value is the result of computation. A Place is authoritative storage containing
a value. Reading a local does not turn its declaration or storage into a value:
an explicit load reads its Place. This semantic distinction makes no decision
about an address, LLVM alloca, stack slot, register, or physical memory.
See [ADR 0009](../decisions/0009-place-storage.md).

## Current language

```astra
int mutate(int x) {
	int y = x + 1;
	y = y * 2;
	return y;
}
```

Initialized `int`, `bool`, and `void*` locals exist. An initializer and every assignment RHS
must have exactly the local's semantic type; no conversions occur. `void` locals
and unknown types fail semantic checking. `int x;` fails parsing. Assignment is
a statement: `return x = 3;`, `a = b = 4;`, and assignment in an argument or
initializer are not supported expressions. Calls are also unimplemented.

The function body, each conditional arm, and each while body have lexical value scopes. Each
declaration's type and name are checked before its initializer; the new symbol
is published only after the initializer succeeds. Earlier visible locals and
parameters can be read. Later locals and self-initializer references are unknown.
No local may shadow a currently visible local or parameter. Siblings can have
same-spelling locals with distinct identities; branch and loop locals do not escape.
General shadowing remains undecided, and standalone block statements are absent.
Different functions have independent locals.

Only locals are assignment targets. A parameter assignment reports that it is
unsupported in this subset, without deciding future parameter mutability.
Known function/type names are not assignable; an absent name is an unknown
assignment target. The target is resolved before the RHS is checked.

## Identity across stages

| Stage | Declaration/storage authority | Read | Fresh initialization | Replacement |
| --- | --- | --- | --- | --- |
| Checked | `LocalSymbol` in `CheckedFunction.locals` | `CheckedLocalReferenceExpression(local)` | `CheckedLocalDeclaration(local, initializer)` | `CheckedAssignment(target, expression)` |
| Core | `CoreLocalPlace : CorePlace` in `CoreFunction.locals` | `CoreLoadValue(source)` | `CoreInitialize(target, value)` | `CoreStore(target, value)` |
| CFG | `CfgLocalPlace : CfgPlace` in `CfgFunction.locals` | `CfgLoadValue(source)` | `CfgInitialize(target, value)` | `CfgStore(target, value)` |

Each declaration has its own object identity, copied name, semantic type,
declaration/name spans, and deterministic function-local ordinal equal to its
declaration-array position. A Place has a type and provenance; a load is a
separate typed value whose result type comes directly from its source Place.
Initialize/Store consume values and retain direct Place targets. Values and
Places have separate base classes.

Core construction establishes its own locals before translating statements.
Temporary `direct_hash`/`direct_equal` maps translate exact `LocalSymbol` objects.
CFG construction verifies Core, then creates each function's CFG locals and
maps exact Core local objects. Maps are discarded with the builders; matching
names or ordinal numbers never establish downstream binding. Parameter symbols
and parameter values stay separate and never silently become local Places.

Arrays define containing-function authority without parent reference cycles.
Types and source files/spans are legitimate shared authorities. No completed Core
node requires checked symbols or syntax nodes; no completed CFG node requires
Core nodes. No Place contains layout, alignment, offsets, addresses, or backend
handles. ASTRA-SSA-1 eliminates current int/bool/void* local Places in a distinct
downstream representation. Future addressable/resource-bearing Places may need
other processing; physical memory realization remains undecided.

## Source order, instructions, and terminators

Core preserves `Initialize`, `Store`, `If`, and `Return` in its structured statement
array. A declaration evaluates its initializer then initializes fresh storage.
Assignment evaluates its RHS, including any local loads, then replaces the
target's stored value. Initialize and Store are distinct even though current
int/bool values have no ownership operations.

CFG accumulates Initialize/Store in the pending block's ordered instruction array.
A Return completes that block with a separate return terminator. Later statements
start a disconnected pending block. An empty body or trailing instructions close
with FunctionEnd; a final Return creates no extra block. Block construction
reserves identity and completes it once with a terminator and instruction array;
terminators cannot be inserted as instructions. Conditional arms use explicit
branches to a reserved join when they fall through. Successors belong only to
terminators. Both arm stores and a join load retain the same outer Place; sibling
local declarations retain different Places despite identical spelling. Bool
initialization/store/load uses this same machinery without integer special cases.
See the [conditional inventory](conditional-control-flow.md) and
[mutable-join golden](../../tests/branch/fixtures/choose.cfg).

For `int f() { int x = 1; return x; x = 2; return x; }`:

```text
block #0 reachable
	initialize local-place #0 = integer 1
	return load local-place #0
block #1 unreachable
	store local-place #0 = integer 2
	return load local-place #0
```

This abbreviated view is recorded exactly in the
[post-return CFG golden](../../tests/place/fixtures/post-return.cfg).
The unreachable store and return survive. There are no unreachable warnings,
implicit edges, dead-store elimination, load forwarding, or SSA temporaries.
Instructions do not affect reachability or the existing empty-int completion
diagnostic. A reachable FunctionEnd in a non-void function is still a flow error,
including when the block contains storage instructions.

## Verification and lifetime

Both verifiers check unique local containment, ordinals, supported non-void
Place types, exact containing-function ownership for every load/initialize/store,
load result types, write value types, and exactly one initialization per local.
They reject foreign or identical-looking impostor Places with deterministic
structural paths. Constructors derive load types from Places, so an inconsistent
load result type cannot be built through the normal API. Synthetic write tests
reject void values, and declaration tests reject void, unknown, or inconsistent
canonical type identities.

Core additionally checks initialization before loads and ordinary stores in its
structured lexical statement order, including preserved post-return statements.
It checks the initializer before marking the target available, catching self-loads;
leaving a branch removes that branch's declarations from availability. Unique
initialization counting remains separate from scope availability. This does not
analyze reachability or dominance. CFG counts initializations across all blocks,
including unreachable ones; it does not use block order to infer definite
assignment. Mandatory source initializers and lexical visibility establish the
current guarantee without a general definite-assignment analysis.

Weak-reference tests release syntax/tokens, the checked model, LocalSymbols,
ParameterSymbols, and the type-universe container before using Core. The CFG
test also releases Core functions, local Places, parameters, initialization,
store, and load nodes. The surviving stage still verifies, dumps, and preserves
exact bindings and provenance; CFG also remains reachable and flow-checkable.
Releasing the final stage releases the remaining source/type authorities.

Both standalone structural executables build the nodes/verifier/dumper with
only shared source and semantic type/operator authority. The CFG executable
also builds reachability/flow checking. Neither needs upstream models or LLVM.
The existing `ldd`/`nm` firewall includes both targets and keeps the LLVM smoke
executable as a negative control.

## Representative dumps and literal regression

The [mutate source](../../tests/place/fixtures/mutate.astra) has these checked
bindings (the complete [semantic golden](../../tests/place/fixtures/mutate.semantics)
also shows the parameter/local declaration tables):

```text
(local-init #0 "y" : int (binary + : int (parameter-ref #0 "x" : int) (integer 1 : int)))
(assign (local-ref #0 "y" : int) (binary * : int (local-ref #0 "y" : int) (integer 2 : int)))
(return (local-ref #0 "y" : int))
```

The [Core golden](../../tests/place/fixtures/mutate.core) makes every read explicit:

```text
(store
	(local-place #0 : int)
	(binary * : int
		(load : int
			(local-place #0 : int)
		)
		(integer 2 : int)
	)
)
```

The [CFG golden](../../tests/place/fixtures/mutate.cfg) contains a single reachable
block with Initialize then Store as instructions and Return as its terminator.
Its loads refer to the one CFG-owned local Place. Empty local tables are omitted
in dumps, preserving existing programs' golden output. All IDs are scoped to the
containing function; no pointer addresses are printed.

The [huge local source](../../tests/place/fixtures/huge-local.astra) initializes
`x` from `000` followed by 1,000 nines. SCALAR-1 preserves all 1,003 digits in
syntax and rejects the out-of-range magnitude in every semantic CLI mode before
Core construction. Lifetime tests instead use valid INT_MAX with 1,003 decimal
digits (leading zeroes). They follow returned Core/CFG loads to the exact Place
and prove numeric AstraIntValue, type, spelling, and location survive upstream
destruction. See [scalar semantics](../language/scalars.md). Loads read storage; they do not
duplicate or fold the initializer's literal into the returned computation.

## Scalar promotion boundary

With while loops, an outer Place is shared across the preheader, condition,
body stores, and exit loads. There is no Place clone per iteration. A body-local
has one declaration-site Place whose initialization executes on every body
visit, even though the Place belongs to the containing function. Promotion
uses real reaching definitions and ordinary header block arguments. The
initialization-dominance restriction prevents body-local Places from receiving
values at outer headers; nested headers within their valid region may receive
parameters normally. See [cyclic control flow](cyclic-control-flow.md).

ASTRA-SSA-1 adds `--dump-ssa` and extends `--check` through SSA verification.
After CFG flow validation, reachable scalar locals and fields of non-address-taken
structs are promotable because their storage cannot be aliased and they carry
no ownership/resource behavior. Addressable fields instead retain explicit memory. Initialize/Store
establish current SSA values; Load resolves to the reaching definition. The
Place itself disappears, and divergent definitions meet through block
parameters supplied by predecessor terminators. No storage operation survives for those promoted Places. See [the SSA inventory](ssa.md) and
[ADR 0011](../decisions/0011-ssa-block-arguments.md).

Core and CFG retain all existing storage distinctions, including unreachable
source operations. Valid integer constants carry immutable AstraIntValue into
SSA; SourceSpan separately preserves spelling after CFG destruction. Branch-local
placement respects initialization dominance; sibling locals never merge by name.
Unused merges within that availability region remain, without liveness pruning.

Erasing Initialize versus Store is valid only for these resource-free promoted
scalars. Address-taken struct fields now preserve both operations in SSA memory.
Future owned/destructible or foreign-resource Places
may need ownership before or during promotion, partial promotion, or another
ordering. This milestone does not freeze that pipeline. No dependency, physical
storage realization, or LLVM lowering is added.

## Compiler-generated CFG Places

SHORTCIRCUIT-1 adds CfgTemporaryPlace alongside CfgLocalPlace. Its function-owned
`temporaries` array uses independent deterministic ordinals; type and span do not
merge identities. It has no LocalSymbol or invented source name. The generated
use is bool and requires exactly one Initialize, with matching stores and loads.
These Places bridge expression control flow before SSA, are always scalar and
promotable, and disappear through the same algorithm as source locals.
A while condition enters a dedicated evaluation region so its fresh temporary
initialization does not demand a value at the original header. See
[expression control flow](expression-control-flow.md).

## Raw-pointer locals and addressability

A raw void* or Struct* is a value, not authoritative storage and not the address of its own
Place. CoreLocalPlace/CoreInitialize/CoreLoadValue/CoreStore and ordinary CFG
local Places handle it without pointer-specific storage classes. Null is an
explicit pointer value. Copying/storing/destroying these unmanaged values performs
no retain/release/free or other pointee cleanup.

Pointer locals fully promote in straight-line, branch, null-merge, and loop-carried
cases. No address-of, ref/out, dereference, or capture can expose their storage.
A foreign C call may affect foreign storage but cannot receive an Astra local's
address through current language semantics. Native Struct* calls can receive
a struct borrow and mutate its fields; those fields do not promote. Future
escaping references or ownership must revisit eligibility; PTR alone grants
no alias optimization. See [raw pointers](../language/raw-pointers.md).

## Aggregate bases and scalar field projections

STRUCT-1 extends ordinary local Places to StructType aggregate bases and adds
CoreFieldPlace/CfgFieldPlace, canonically owned by the containing function.
Each projection retains the exact base and stage-owned field identity. Bases
have no directly loadable value and receive no aggregate Initialize or Store.
Complete, written-order scalar field initialization establishes initialized
aggregate storage. Scalar field Loads and Stores use the existing operations.

[Field Places](field-places.md) document canonicalization, verification, acyclic
ownership, and stage lifetime. Promotion includes scalar locals, eligible
field projections ordered by local/field ordinal, then temporaries. Aggregate
bases, address-taken fields, and indirect fields are excluded. Scalarization
itself adds no physical layout or aggregate ABI channel. Addressable storage
uses the separate bounded SSA memory model.

## TPTR-1 addressability

LocalSymbol, CoreLocalPlace, and CfgLocalPlace explicitly record address_taken.
Any valid address borrow, including a stored lexical borrow, marks its struct
base for the whole checked function.
Every direct field of that base is ineligible for scalar promotion; exact
CoreIndirectFieldPlace/CfgIndirectFieldPlace projections are also ineligible.
Pointer locals remain eligible. SSA translates retained storage to
SsaAddressableStruct with direct/indirect memory Places and ordered
Initialize/Load/Store. See [addressable storage](addressable-storage.md) for
aliasing, verifier, effect-order, and lifetime contracts.
