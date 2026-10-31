# Structural generic ownership and typed native units

Status: APPROVED by the user in the native Codex interaction on 2026-10-20
("Approve."), covering sections 1–3 as proposed. Implementation and G0–G8
qualification remain separate obligations.

This proposal addresses F01, F05 and the necessary callable portion of F11.
It does not declare any new capability implemented or qualified. The existing
RC1 objects, source, receipts and compiler fingerprint remain historical artifacts.

## 1. Substitution and lifetime contract

A closed nominal instance is identified by its defining module/declaration,
ordered type arguments and storage/semantic policies. A closed method additionally
includes its own ordered arguments. Parameter names and display strings are not
identity. Resolve type expressions recursively using the existing substitution
authority; derive each field and member from the declaration. Slots are ordinary
field storage, with no required field count or recognized member bodies.

Proposed interpretation of `owned T` in a generic declaration:

| Substituted type | Storage and transport |
| --- | --- |
| Scalar or recursively copyable record | Ordinary inline copied value; `owned` adds no allocation/cleanup; `move` in the template copies and does not invalidate this copyable binding |
| Owning record | Inline move-only value with all recursive owner obligations; transfer disarms the original storage |
| Native Class, including a closed generic Class | Unique owner with the original allocator/destructor provenance; a persistent child requires admissible independently owned storage |
| Resource or an already supported explicit Shared/Weak handle | Its existing explicit transfer, clone and cleanup contract |

This is a substitution rule for a type-parameter-bearing occurrence. It does not
make concrete `owned int` declarations legal, broaden the existing `Ownable`
capability to scalars, or implicitly clone an owner. An explicit `where T: Ownable`
continues to require Ownable. A bare T value position requires copyability;
owning records retain their established explicit-move value rule, and bare
Class/Resource references do not become owning fields by inference.

`borrowed T` parameters observe the substituted value without taking cleanup.
For scalars/copyable records the implementation may pass an ordinary value copy.
For owning records/objects the loan includes the recursively observed storage and
cannot escape, overlap invalidation, or survive unsafe suspension.

Example proposed source, deliberately using the same declaration for values and
owners:

```astra
class Box<T> {
	private int generation;
	private owned T payload;
	init(owned T value) {
		this.generation = 0;
		this.payload = move value;
	}
	property borrowed T view {
		get { return this.payload; }
	}
}

int main() {
	var number = new Box<int>(42);
	var child = new Child();
	var object = new Box<Child>(move child);
	return inspect(object.view) + number.view;
}
```

`Child` and `inspect(borrowed Child)` are ordinary client declarations. A
copyable `view` returns a copy; an owning `view` is a receiver-bounded observation,
including a read-only owning-record projection. The getter never extracts an
owner. Checked computed value getters keep their declared effects. Mutation is
excluded while a related loan is active. Unqualified properties returning owners
remain invalid unless they have a distinct valid ownership/result contract.

Each field has definite initialization and moved state. A checked construction
failure destroys exactly the initialized fields in reverse declaration order.
Replacement captures the incoming value before retiring the old one. Field
extraction requires a complete place/flow proof: no field hole may be exposed to
an alias, callback, checked failure or suspension. This proposal adds no unchecked
`take` primitive. Map removal can instead transfer a complete owning entry.

Ordinary direct methods, independent method parameters, properties, checked
effects and closed native interface implementations follow the same substituted
contracts. An async operation captures an explicit owned environment/argument;
no automatic capture syntax or escaping receiver borrow is added.

## 2. Typed callables and the checked/async module ABI

Keep the current Fn/Closure/CheckedClosure forms. Permit existing `owned` and
`borrowed` qualifiers in their signature type arguments to describe a channel
explicitly; bare result/argument types retain ordinary copied/value semantics.
The closure environment remains one explicitly transferred heap owner and may
be a closed generic Class. No automatic retain or erased void-pointer payload
semantics are introduced.

```astra
Stats inspect_checked(borrowed Box<Stats> environment,
	borrowed Input input) throws Error {
	// Ordinary typed analysis, with an actual checked failure path.
}

// Exact target signature, including the nominated Error identity:
// CheckedClosure<Box<Stats>,Error,Stats,borrowed Input>
// Owned results use, for example, CheckedClosure<Env,Error,owned Output,Input>.
```

The comment describes a signature, not an implementation stub. `closure_bind`,
`checked_closure_bind` and `closure_invoke` preserve exact channel qualifiers.
The environment stays borrowed through each call and remains reusable after a
caught error. Aggregate values use native record plans; owned results carry their
complete cleanup/provenance. Owned arguments require explicit transfer.

Keep native fastcc calls and the current separate checked success/exception
channels. Serialize the declared error bound, unique exception-root origin,
success carrier/initialization and cleanup plan, parameter groups, receiver and
borrow relationships. The imported declaration must independently reconstruct
and verify these facts. A scalar sentinel never replaces an exception.

An exported async declaration calls the producer's cold-task factory. The factory
retains the captures; its task points to producer-owned resume and destroy
functions using the existing executor protocol. Consumers do not reconstruct
producer control flow or frame code. Metadata carries the provider/runtime ABI,
typed success/error/cancellation and capture ownership contracts, frame layout
fingerprint, and exact factory/resume/destroy symbol contracts. Opaque private
frame state is validated in the producer; no executable frame states are shipped
as consumer source. Cancellation/retirement still waits for descendants and
provider users. A graph uses one nominated Error root and one explicitly linked
compatible executor/helper set; virtual and Linux profiles stay separate.

Example ordinary public command structure (signatures only):

```astra
async Stats analyze(owned Box<Input> input) throws Error {
	await delay_ticks(1);
	// Resume and analyze the retained input using ordinary Astra code.
}
```

This extends the development module ABI, with no promise of cross-version
binary compatibility. It does not change foreign C/COM/GObject contracts.

## 3. Native-unit schema and compatibility

Use `astra-native-module/2` with schema
`gnu-x86_64-lp64-typed-units/3`. Keep exact compiler-binary, runtime-ABI, target
triple and data-layout pinning, canonical unique-field KeyFile serialization,
content digests and existing native objects. Old format/schema imports fail with
an explicit rebuild diagnostic; nothing rewrites old artifacts.

Add canonical direct dependency records:

```ini
[dependency Foundation]
interface=foundation.asti
interface_sha256=<exact SHA-256 of the complete interface>
object_sha256=<exact SHA-256 of its relocatable object>
abi_identity=<provider ABI identity>
```

Paths are safe basenames resolved beside the referring interface. A relocated
artifact tree stages the graph's interfaces/objects together. No current-directory,
network or source-tree fallback occurs. Explicit imports remain public entry
points; recursively load their declared dependencies before dependent declarations.
Deduplicate a diamond by exact module/provider/artifact identity and link each
object once. Conflicting origins for the same module, cycles, missing/corrupt
dependencies and unsafe paths reject before native emission.

The receipt and ABI identity include the dependency contract. A producer-only
implementation change requires new object/interface receipts and a rebuild of
dependent metadata; old artifact trees keep their old behavior. Hashes check
integrity, not an untrusted author's authority.

Types and callable entries carry complete declarative nominal, visibility,
type-argument, field/layout, initialization/cleanup, allocation, dispatch/property,
checked and task contracts. Imported declarations are validation scaffolding,
never substitute implementations. No serialized producer algorithm, IR, bitcode
or executable AST is distributed. Private layout facts do not grant source access.

Existing `--native-export` selects qualified closed types with recursively parsed
argument tuples, for example `Foundation.Map<int,Foundation.Entry>` or
`Foundation.Box<Foundation.Box<int>>`. A method selector adds its own tuple:
`Foundation.Map<int,Foundation.Entry>::convert<Foundation.Summary>`.
Each selected member is compiled by its producer. A consumer cannot instantiate
an unexported producer body. Consumer-owned templates may specialize over imported
nominal arguments. Nominal dependencies must have a declared provider/export.

Apply deterministic bounds to resource use, not witness shapes: initially 256
units, dependency depth 64, type-expression depth 128 and 16,384 closed instances
per compilation, with a diagnostic naming the limit and instantiation chain.
Finite source graphs and three-or-more-argument declarations are ordinary cases.
Infinitely sized inline recursion and expanding specialization cycles receive
separate diagnostics. Validate boundary behavior and adjust an implementation
budget only with recorded evidence, without silently narrowing accepted shapes.

## Decision and qualification

The requested single decision covers sections 1–3 together. Approval authorizes
implementing this contract; it grants no automatic G0–G8 PASS. Intentional changes
to historical negative fixtures require a separate exact-path/case consent batch.
No such fixture changes are proposed in this checkpoint.

Independent verifiers must retain and check substituted types, field/method
identities, ownership masks, callable effects, native dispatch and task plans
after upstream graphs are gone. Each supported fast path must have a legal,
equivalent ordinary path. Final acceptance remains the supplied G0–G8 contract,
including the opaque transitive application, structural transformations, memory
checks and fresh full applicable registry.
