# Internal generated continuations

CALLABLE-1 adds a compiler-only, closed SSA continuation region. Source async,
closures, Task scheduling and provider quiescence remain pending. The region is
the first bounded executable seam for generated lowering; source CFG and source
types do not acquire a callable type.

## Representation selected before implementation

| Responsibility | Representation / authority |
| --- | --- |
| Logical descriptor | Region-local unique owner ordinal, exact family and environment instance |
| Generated operations | Exact weak SSA body identities for step and cancel-drain; family-specific generated destroy entry |
| Environment | Nominal contract leaf, concrete scalar or existing copyable record field graph, optional concrete owned buffer |
| Invocation | Non-reentrant begin/call/end witness; sequential step invocation may repeat |
| Ownership | Create/initialize/publish, whole-descriptor move, one destroy; metadata copying never duplicates a runtime owner |
| Retention | Distinct bounded retain/release witnesses checked before move or destruction |
| Native plan | Independently owned identities, declared memory fields, channel leaves and operation schedule |
| Physical boundary | Internal fastcc wrappers and a four-pointer descriptor (step, cancel-drain, destroy, environment) |

A source callable type would broaden generic, borrow and ABI admission. Passing
two erased pointers would lose the association this milestone must verify. A
closed generated SSA region instead admits typed operands through existing SSA
dominance and value boundaries, owns all its normal-path cleanup, and keeps the
internal owner and invocation carriers separate from source values. This first
region has a sequential schedule; it does not model arbitrary executor graphs.

Record environment storage follows declared fields recursively, never register
return leaves. Entry wrappers snapshot state, pass existing native value channels
to the exact generated body, then store its complete result. Buffer state remains
an owner and is passed to the body only through an existing synchronous borrowed
slice contract. Descriptor movement changes the carrier, never environment bytes.

The verifier establishes local bounded-use retirement, not kernel quiescence.
ASYNC-1 must establish its separate parent cancellation and observed publication
obligations before ending future executor/provider retention witnesses. No raw
source destroy operation or mutable `safe_to_free` predicate is exposed.
